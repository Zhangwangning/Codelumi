import SwiftUI
import WidgetKit
import UIKit

// MARK: ============================================================================
// 「已取」+「统计」（2026-10-14 由原「浏览」页拆分，主人定稿四标签信息架构）
//
// 原「浏览」一个页面装三层内容（总览 / 已取列表 / 统计分析），拆成两个标签页：
//   · **PickedUpView（已取）**：取完的回执列表 —— 对账、回看、批量管理；
//   · **StatsTabView（统计）**：总览三格 + 取件习惯分析五张卡 —— 只看数据。
// 组件（StatCard / StatTriple / 图表）留在 StatsView.swift 不动。
// 数字全部来自 `PickupStats`（口径集中在那一个文件里，本页只负责画）。
// ============================================================================

// MARK: - 已取页状态

final class HistoryModel: ObservableObject {
    @Published var path = NavigationPath()

    // MARK: 重计算缓存（2026-11-17 流畅度）

    /// `orderedList` 的记忆化（与待取页 `displayed` 同一套做法）。
    ///
    /// 「已取」这条链是 `list → searchedList(过滤) → orderedList(排序)
    /// → visibleList(裁条数)`，四层全是计算属性，而 `visibleList` 在 body 里被
    /// 读很多次（空态、统计卡、分组、每一行、分栏右栏回退）。
    /// 每读一次就把 50 条记录重新过滤 + 重排一遍。
    ///
    /// 放 model 而不是 view 的 `@State`：body 求值期间写 state 会触发
    /// 「Modifying state during view update」，而且必然引起又一轮重算。
    private var orderedCache: (key: String, value: [PickupRecord])?

    func cachedOrdered(_ key: String, build: () -> [PickupRecord]) -> [PickupRecord] {
        if let cache = orderedCache, cache.key == key { return cache.value }
        let value = build()
        orderedCache = (key, value)
        return value
    }
    /// 刚复制成功的取件码（非 nil 时页面底部弹「已复制 xxx」）
    @Published var copiedCode: String?

    // MARK: 批量编辑
    @Published var isEditing = false
    @Published var selection: Set<UUID> = []

    /// 搜索词（2026-11-16 主人：已取页也要能搜，与待取页同一套）。
    /// 搜的是**全部已取记录**，不受免费版条数上限影响 —— 上限只裁"显示多少条"，
    /// 不裁"能搜到哪条"（主人原话：「可以搜索所有已完成取件的快递信息」）。
    @Published var query = ""

    /// 分组 / 排序方式（2026-11-16 主人：分组按钮从待取页也搬到本页）。
    ///
    /// 🔴 独立存一个键 —— 与待取页**各记各的**。两页的记录集合不同，
    /// 在一页选了「按快递公司」不该把另一页也带跑。
    private static let sortKey = PickupStorage.listSortKey + ".history"

    @Published var sort: PickupSortMode {
        didSet {
            PickupStorage.sharedDefaults.set(sort.rawValue, forKey: Self.sortKey)
            UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
        }
    }

    /// 排序方向翻转时 +1（同值重新赋值不触发 didSet，靠它强制重算）
    @Published private(set) var orderRevision = 0

    func bumpOrderRevision() {
        orderRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 「清空已取件记录」的确认态（2026-11-16 从待取页迁移过来）。
    /// 🔴 数据只在本机，删了 App 内**没有任何办法恢复**（没有云端备份、没有回收站），
    ///    所以这个动作必须先问一次（2026-11-01 主人要求）。
    @Published var confirmClearPicked = false

    init() {
        let saved = PickupStorage.sharedDefaults.string(forKey: Self.sortKey)
            ?? UserDefaults.standard.string(forKey: Self.sortKey)
        sort = saved.flatMap(PickupSortMode.migrated) ?? .newest
    }

    /// 非 nil 时弹出分享预览面板（长按菜单「分享卡片」传单条）。
    /// 🔴 面板由**页面**承载：挂进长按浮层会在菜单收起时一起被销毁（见 CardMenu.swift）。
    @Published var shareRecords: [PickupRecord]?

    private var copyTask: Task<Void, Never>?

    // MARK: 单条删除（2026-11-11 内测反馈）
    //
    // 已取页此前只有「选择 → 批量删除」一条路，长按菜单里没有删除项，
    // 用户想删一条只能先进编辑模式 —— 反馈为「已取页面无法进行删除」。
    // 现在长按菜单直接给「删除记录」，并给 4 秒撤销条（与待取页同口径）。
    /// 🔴 2026-11-16：改成数组 —— 一张卡多个取件码时，删除与撤销都要按**整组**走。
    @Published var deleteUndoRecords: [PickupRecord] = []
    @Published var showDeleteUndo = false
    private var deleteUndoTask: Task<Void, Never>?

    /// 删除并给出撤销机会（单条 / 整组通用）。
    func delete(_ records: [PickupRecord], in store: PickupStore) {
        guard !records.isEmpty else { return }
        withAnimation(.snappy) { store.deleteMany(records) }
        deleteUndoRecords = records
        withAnimation(.snappy) { showDeleteUndo = true }
        deleteUndoTask?.cancel()
        deleteUndoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showDeleteUndo = false }
        }
    }

    /// 保留单条调用点（截图脚手架 / 单码卡），内部转到批量版。
    func delete(_ record: PickupRecord, in store: PickupStore) {
        delete([record], in: store)
    }

    /// 撤销刚才的删除：必须 `insert` 回整表，`restore` 找不到已摘掉的记录。
    func undoDelete(in store: PickupStore) {
        deleteUndoTask?.cancel()
        if !deleteUndoRecords.isEmpty {
            withAnimation(.snappy) { store.insert(deleteUndoRecords) }
        }
        deleteUndoRecords = []
        withAnimation(.snappy) { showDeleteUndo = false }
    }

    func copy(_ record: PickupRecord) {
        UIPasteboard.general.string = record.code
        // 与待取页同口径：复制后必须给回执（2026-10-25 主人要求）
        withAnimation(.snappy) { copiedCode = record.code }
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { copiedCode = nil } }
        }
    }

    /// 一张卡多个码：复制时按行拼全部码（与待取页 `HistoryModel` 同口径）。
    func copy(_ records: [PickupRecord]) {
        guard let first = records.first else { return }
        guard records.count > 1 else { copy(first); return }
        UIPasteboard.general.string = records.map(\.code).joined(separator: "\n")
        withAnimation(.snappy) { copiedCode = "\(records.count) 个取件码" }
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { copiedCode = nil } }
        }
    }

    /// 进入 / 退出编辑模式。退出时顺手清空选择。
    func setEditing(_ active: Bool) {
        isEditing = active
        if !active { selection.removeAll() }
    }

    func toggleSelection(_ record: PickupRecord) {
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
    }

    /// 一张卡多个码：整组一起选 / 一起取消，避免半张卡被选中（2026-11-16）。
    func toggleSelection(_ records: [PickupRecord]) {
        let ids = Set(records.map(\.id))
        if ids.isSubset(of: selection) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    /// 当前范围下是否全部选中（用于「全选 / 全不选」文案与状态）
    func isAllSelected(of items: [PickupRecord]) -> Bool {
        !items.isEmpty && items.allSatisfy { selection.contains($0.id) }
    }

    /// 全选 / 全不选（只针对当前范围的可见列表）
    func selectAll(of items: [PickupRecord]) {
        if isAllSelected(of: items) {
            items.forEach { selection.remove($0.id) }
        } else {
            items.forEach { selection.insert($0.id) }
        }
    }
}

// MARK: ============================================================================
// 已取页（取完的回执库）
// ============================================================================

struct PickedUpView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = HistoryModel()
    /// 长按菜单（自绘，替代系统 contextMenu —— 见 CardMenu.swift 的说明）
    @StateObject private var cardMenu = CardMenuState()

    private var list: [PickupRecord] {
        store.pickedUpRecords
    }

    /// 搜索命中后的全表。**先搜再裁条数** —— 免费版上限只限制"屏幕上显示几条"，
    /// 不能限制"能搜到哪条"（主人：可以搜索所有已完成取件的快递信息）。
    private var searchedList: [PickupRecord] {
        store.filtered(list, query: model.query)
    }

    /// 按分组方式排好的整表（2026-11-16 与待取页 `displayed` 同一套口径）。
    /// 注意先排再裁条数：选「最早收到」时该显示最旧的那 N 条，而不是最新的 N 条。
    private var orderedList: [PickupRecord] {
        model.cachedOrdered(orderedCacheKey) { computedOrderedList() }
    }

    /// 缓存判据：数据版本 + 检索词 + 排序 + 可见上限 + 自定义驿站/驿站组内容。
    /// 🔴 驿站点用 hashValue 不用 count —— 改名时数量不变，用 count 会一直命中旧结果。
    private var orderedCacheKey: String {
        "\(store.revision)|\(model.query)|\(model.sort.rawValue)|"
            + "\(store.visibleLimit)|"
            + "\(StationDirectory.shared.customNames.hashValue)|"
            + "\(StationGroupStore.all().hashValue)"
    }

    private func computedOrderedList() -> [PickupRecord] {
        // 🔴 2026-11-23：与待取页、桌面小组件、灵动岛、锁屏卡**同一个函数**。
        //    时间键是 `receivedAt`（同一条再收到会刷新），组内永远按取件码升序。
        PickupSortLogic.sort(searchedList, mode: model.sort.logic)
    }

    /// 搜索态**不裁条数**：主人 2026-11-16「可以搜索所有已完成取件的快递信息」。
    /// 免费版 4 条上限只管常规列表显示几条；搜索时全部命中都列出来，
    /// 详情另由 `detailLocked` 锁住 —— 与待取页 `displayed` 同一套口径。
    private var visibleList: [PickupRecord] {
        guard model.query.trimmingCharacters(in: .whitespaces).isEmpty else { return orderedList }
        return Array(orderedList.prefix(store.visibleLimit))
    }

    private var hiddenCount: Int {
        // 搜索态本来就把命中结果全铺开了，再说「还有 N 条」是自相矛盾
        guard model.query.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        return max(0, searchedList.count - store.visibleLimit)
    }

    /// 「一张卡片多个取件码」开启时，需要真正画出来的记录（每组只留代表）。
    /// 与待取页同一套 `PickupRecordGrouping`，两页口径必须完全一致。
    private var visibleRecordIDs: Set<UUID> {
        PickupRecordGrouping.representativeIDs(visibleList)
    }

    private func rows(_ items: [PickupRecord]) -> [PickupRecord] {
        items.filter { visibleRecordIDs.contains($0.id) }
    }

    private var groups: [(group: DayGroup, items: [PickupRecord])] {
        store.grouped(visibleList)
    }

    /// 「按快递公司」的归类桶（组头 = 卡片主名口径的承运方，件数多的在前）。
    /// 口径与待取页 `companyGroups` 一致：`courier ?? company`，驿站不进分组名。
    private var companyGroups: [(company: String, items: [PickupRecord])] {
        var buckets: [(company: String, items: [PickupRecord])] = []
        for record in visibleList {
            let name = groupingName(for: record)
            if let index = buckets.firstIndex(where: { $0.company == name }) {
                buckets[index].items.append(record)
            } else {
                buckets.append((name, [record]))
            }
        }
        for index in buckets.indices {
            buckets[index].items.sort { PickupSortLogic.tieBreak($0, $1) }
        }
        buckets.sort {
            $0.company == "其他" ? false
                : $1.company == "其他" ? true
                : $0.items.count > $1.items.count
        }
        return buckets
    }

    /// 「按快递驿站」的归类桶，取舍同上。
    private var stationGroups: [(station: String, items: [PickupRecord])] {
        var buckets: [(station: String, items: [PickupRecord])] = []
        for record in visibleList {
            let name = stationName(for: record)
            if let index = buckets.firstIndex(where: { $0.station == name }) {
                buckets[index].items.append(record)
            } else {
                buckets.append((name, [record]))
            }
        }
        for index in buckets.indices {
            buckets[index].items.sort { PickupSortLogic.tieBreak($0, $1) }
        }
        buckets.sort {
            $0.station == "未标注驿站" ? false
                : $1.station == "未标注驿站" ? true
                : ($0.items.count == $1.items.count
                    ? $0.station < $1.station
                    : $0.items.count > $1.items.count)
        }
        return buckets
    }

    private func stationName(for record: PickupRecord) -> String {
        // 与待取页 / 桌面小组件同一门函数（走单一解析入口）
        return PickupSortLogic.stationName(of: record)
    }

    /// 归类名 —— 与待取页、卡片主名三方同源，组头与卡片不会打架。
    private func groupingName(for record: PickupRecord) -> String {
        let courier = record.courier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !courier.isEmpty { return courier }
        return record.company.isEmpty ? "其他" : record.company
    }

    /// 编辑态里真正会被分享 / 删除的那些（按当前显示顺序，与「分享 N」同源）。
    private var selectedRecords: [PickupRecord] {
        visibleList.filter { model.selection.contains($0.id) }
    }

    // MARK: 顶部统计摘要卡（2026-11-15 主人）

    /// 底部菜单栏是否还显示「统计」。
    ///
    /// 🔴 关掉之后统计**没有入口**了（底栏只剩 待取 / 已取 / 设置），
    ///    所以这里补一张简要卡 —— 统计信息不该因为少一个标签页就消失。
    ///    与设置页读写同一个 App Group 键，开关一动立即生效（`@AppStorage` 跨页同步）。
    @AppStorage(TabBarPrefs.showsStatsKey,
                store: PickupStorage.groupStore)
    private var showsStats = true

    /// 累计已取 —— 本页的**全部**已取记录（不受可见条数上限约束）。
    private var pickedTotal: Int { list.count }

    /// 本周已取。时间口径统一走 `pickupMoment`（`pickedUpAt ?? receivedAt`），
    /// 与统计页同一套 —— 老数据没记 `pickedUpAt` 也不会漏掉。
    private var pickedThisWeek: Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return list.filter { week.contains($0.pickupMoment) }.count
    }

    /// 本月已取（口径同上）
    private var pickedThisMonth: Int {
        guard let month = Calendar.current.dateInterval(of: .month, for: Date()) else { return 0 }
        return list.filter { month.contains($0.pickupMoment) }.count
    }

    /// 截图脚手架覆盖值：`SHOW_STATS=0` 强制「已关统计」的样子，`1` 强制「还开着」。
    /// simctl 点不了设置里的开关，验收两态只能靠它。仅调试构建存在。
    @State private var statsOverride: Bool?

    /// 顶部统计卡到底出不出。
    ///
    /// 三档判定，顺序不能换：
    ///   ① 截图脚手架（仅调试）优先；
    ///   ② **非 Pro 一律不出** —— 非 Pro 的统计页本来就在（见 `RootView.showsStats`），
    ///      再补一张卡等于同一份数据在两个地方；
    ///   ③ 其余跟随设置里的开关。
    private var showsStatsCard: Bool {
        if let statsOverride { return !statsOverride }
        guard EntitlementSnapshot.licensedPro else { return false }
        return !showsStats
    }

    /// 宽屏（iPhone Duo 展开态）判定 —— 与待取页同一口径。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 分栏右栏当前显示的记录 id；nil = 还没点过 → 回落第一条（见 `splitDetailRecord`）。
    @State private var splitSelection: PickupRecord.ID?
    /// 当前页可用宽度（只量不改布局）
    @State private var paneWidth: CGFloat = 0

    /// 通知点击待打开的记录 id（2026-10-25）
    @StateObject private var notificationRouter = NotificationRouter.shared

    /// 当前打开侧滑的行（自绘侧滑，2026-10-25）
    @State private var openSwipeRow: UUID?
    /// 排序面板（自己画的 popover，与待取页同一个 `SortMenuPanel`）
    @State private var showSortPanel = false

    var body: some View {
        // 📱 2026-10-25：宽屏走平行视图（左列表 / 右详情），常规 iPhone 仍单栈。
        Group {
            // 与待取页同口径：按实际宽度分栏（iPad mini 竖屏 744pt 不分栏）。
            if PadLayout.usesSplit, paneWidth >= PadLayout.splitMinWidth {
                splitLayout
            } else {
                stackedLayout
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: AlludePaneWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(AlludePaneWidthKey.self) { paneWidth = $0 }
        // 长按景深：整个界面轻微后退（模糊 + 缩放），被按的卡片由浮层里的「替身」接管。
        .blur(radius: cardMenu.openID == nil ? 0 : CardMenuMetrics.backgroundBlur)
        .scaleEffect(cardMenu.openID == nil ? 1 : CardMenuMetrics.backgroundScale)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: cardMenu.openID)
        .overlay { cardMenuLayer }
        // 通知点击 → 打开对应记录的详情（2026-10-25）
        .onAppear {
            // 截图脚手架（仅调试构建）：`SHOW_STATS=0` 拍"统计已关"那张，
            // `SHOW_STATS=1` 拍"统计还开着"（顶部不该有卡）那张。
            if let raw = ProcessInfo.processInfo.environment["SHOW_STATS"] {
                statsOverride = (raw != "0")
            }
            consumeNotificationTarget()
        }
        .onChange(of: notificationRouter.pendingRecordID) { _, _ in consumeNotificationTarget() }
    }

    /// 与待取页同口径：只认属于本页（已取集合）的 id，谁匹配谁清空。
    private func consumeNotificationTarget() {
        guard let id = notificationRouter.pendingRecordID,
              let record = store.pickedUpRecords.first(where: { $0.id == id }) else { return }
        notificationRouter.pendingRecordID = nil
        if PadLayout.usesSplit, horizontalSizeClass == .regular {
            splitSelection = record.id
        } else {
            model.path.append(record)
        }
    }

    /// 单栈布局（常规 iPhone）：与历史版本完全一致。
    private var stackedLayout: some View {
        NavigationStack(path: $model.path) {
            listPane
                .navigationDestination(for: PickupRecord.self) { record in
                    RecordDetailView(record: record)
                }
        }
    }

    /// 平行视图（宽屏）：左列表 / 右详情 —— 与待取页同一口径：
    /// 右栏**常驻详情**、不 push（无返回箭头）；未选中时默认显示第一条；
    /// 列宽左右等分（主人 2026-10-25 已否掉「按铰链中轴分列」）。
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            listPane
                // 左右等分（与待取页同口径；主人已否掉中轴方案）
                .navigationSplitViewColumnWidth(min: 400, ideal: PadLayout.splitColumnIdeal, max: 600)
        } detail: {
            if detailLocked {
                // 分栏右栏是常驻区域，没有"点击"可拦 —— 不换成占位就等于白送详情
                ProLockedSplitPlaceholder { showPaywall = true }
            } else if let record = splitDetailRecord {
                // 与待取页同口径：绑定 id，避免编辑草稿串到下一条（2026-10-25 审查修）
                RecordDetailView(record: record)
                    .id(record.id)
            } else {
                SplitDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        // 与待取页同口径：导航栏透明，露出列底色（上色压不住系统材质，2026-11-15 实测）
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// 分栏右栏要显示的记录：选中的那条优先，没选中就显示第一条（同待取页口径）。
    private var splitDetailRecord: PickupRecord? {
        if let id = splitSelection,
           let hit = visibleList.first(where: { $0.id == id }) {
            return hit
        }
        return visibleList.first
    }

    /// 非 Pro 在**搜索态**下只给结果、不给详情（2026-11-16 主人：
    /// 「非Pro版本用户就只有搜到，无法点击查看详情」）。
    /// 不含搜索词时行为不变 —— 免费版本来就能看列表和详情。
    private var detailLocked: Bool {
        guard !EntitlementSnapshot.licensedPro else { return false }
        return !model.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 订阅页呈现态：搜索结果被拦下、或分栏右栏处于锁定态时打开。
    @State private var showPaywall = false

    /// 打开详情：宽屏只切右栏（不 push），窄屏照旧推栈。
    /// 🔴 非 Pro 搜索态一律拦在门外（见 `detailLocked`）。
    private func openDetail(_ record: PickupRecord) {
        if detailLocked {
            showPaywall = true
            return
        }
        if PadLayout.usesSplit, horizontalSizeClass == .regular {
            splitSelection = record.id
        } else {
            model.path.append(record)
        }
    }

    /// 列表本体（两种布局共用）。`navigationDestination` 由各布局挂到自己的栈上。
    private var splitPane: Bool { PadLayout.usesSplit && paneWidth >= PadLayout.splitMinWidth }

    private var listPane: some View {
        listBody
            .background(AppTheme.pageBackground.ignoresSafeArea())
    }

    private var listBody: some View {
        List {
                if splitPane {
                    Section {
                        PadSidebarHeader(title: "已取")
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                if list.isEmpty {
                    Section {
                        EmptyStateView(symbol: "archivebox",
                                       title: "已取件库还是空的",
                                       hint: "取件完成后，记录会留在这里")
                            .listRowInsets(EdgeInsets(top: 40, leading: AppTheme.hInset,
                                                      bottom: 0, trailing: AppTheme.hInset))
                            .listRowBackground(AppTheme.pageBackground)
                            .listRowSeparator(.hidden)
                    }
                } else if searchedList.isEmpty {
                    // 有记录但被搜索词筛空了（2026-11-16 与待取页同款提示）
                    Section {
                        NoResultView(query: model.query)
                            .listRowInsets(EdgeInsets(top: 36, leading: AppTheme.hInset,
                                                      bottom: 0, trailing: AppTheme.hInset))
                            .listRowBackground(AppTheme.pageBackground)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    // 顶部统计摘要卡 —— **只在关掉「显示「统计」」时出现**。
                    // 版式与待取页那张是同一份实现（`HeroStatsCard`），
                    // 内边距也取待取页同一档（top 2 / bottom 12），两页卡片落位、高度一致。
                    // 空态不显示：一条已取都没有时，「0 件已取」与上面的空态提示会互相打架。
                    // 搜索时也不显示：统计的是全部记录，跟筛选出的结果无关（2026-11-16）。
                    if showsStatsCard, model.query.isEmpty {
                        Section {
                            HeroStatsCard(primary: pickedTotal,
                                          primaryUnit: "件已取",
                                          primaryTint: AppTheme.doneTint,
                                          primaryTintLight: AppTheme.doneTintLight,
                                          stats: [
                                              .init(title: "本周已取", value: pickedThisWeek,
                                                    tint: AppTheme.sky, symbol: "calendar.badge.clock"),
                                              .init(title: "本月已取", value: pickedThisMonth,
                                                    tint: AppTheme.violet, symbol: "calendar"),
                                          ])
                            .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                      bottom: 12, trailing: AppTheme.hInset))
                            .listRowBackground(AppTheme.pageBackground)
                            .listRowSeparator(.hidden)
                        }
                    }

                    // 分组渲染（2026-11-16 与待取页同一套）：公司 / 驿站归类时组头换成名字，
                    // 其余仍是「今天 / 昨天 / 更早」的时间流。
                    if model.sort == .company {
                        ForEach(companyGroups, id: \.company) { bucket in
                            Section {
                                SectionHeader(title: bucket.company,
                                              trailing: "\(bucket.items.count) 件",
                                              symbol: "building.2.fill",
                                              tint: CourierBrand.info(for: bucket.company).color)
                                    .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                              bottom: 0, trailing: AppTheme.hInset))
                                    .listRowBackground(AppTheme.pageBackground)
                                    .listRowSeparator(.hidden)

                                ForEach(rows(bucket.items)) { record in
                                    row(for: record)
                                }
                            }
                        }
                    } else if model.sort == .station {
                        ForEach(stationGroups, id: \.station) { bucket in
                            Section {
                                SectionHeader(title: bucket.station,
                                              trailing: "\(bucket.items.count) 件",
                                              symbol: "mappin.circle.fill",
                                              tint: AppTheme.accent)
                                    .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                              bottom: 0, trailing: AppTheme.hInset))
                                    .listRowBackground(AppTheme.pageBackground)
                                    .listRowSeparator(.hidden)

                                ForEach(rows(bucket.items)) { record in
                                    row(for: record)
                                }
                            }
                        }
                    } else {
                        ForEach(groups, id: \.group) { section in
                            Section {
                                SectionHeader(title: section.group.rawValue,
                                              trailing: "\(section.items.count) 件")
                                    .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                              bottom: 0, trailing: AppTheme.hInset))
                                    .listRowBackground(AppTheme.pageBackground)
                                    .listRowSeparator(.hidden)

                                ForEach(rows(section.items)) { record in
                                    row(for: record)
                                }
                            }
                        }
                    }

                    if hiddenCount > 0 {
                        Section {
                            HiddenHint(count: hiddenCount)
                                .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                          bottom: 8, trailing: AppTheme.hInset))
                                .listRowBackground(AppTheme.pageBackground)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(AppTheme.listSpacing)
            .scrollContentBackground(.hidden)
            // 页面底 = 浅灰，卡片才是白（与全 App 统一口径）
            .background(AppTheme.pageBackground)
            .contentMargins(.bottom, 88, for: .scrollContent)
            // 复制回执（2026-10-25）：右滑直接复制后必须有提示，
            // 否则用户不知道复制上没有 —— 与待取页同款玻璃胶囊。
            .overlay(alignment: .bottom) {
                if let code = model.copiedCode {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(AppTheme.accent)

                        Text("已复制 \(code)")
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .appGlass(.capsule)
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            // 删除撤销条（2026-11-11）：与待取页同款，4 秒内可放回
            .overlay(alignment: .bottom) {
                if model.showDeleteUndo {
                    UndoToast(message: model.deleteUndoRecords.first.map { first in
                        model.deleteUndoRecords.count > 1
                            ? "已删除 \(first.company) 等 \(model.deleteUndoRecords.count) 件"
                            : "已删除 \(first.company) \(first.code)"
                    } ?? "已删除",
                              actionTitle: "撤销") {
                        model.undoDelete(in: store)
                    }
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // 📱 宽屏（iPhone Duo 展开态）内容限宽居中，与待取页同一口径
            .frame(maxWidth: splitPane ? .infinity : AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .background(AppTheme.pageBackground)
            // 搜索（2026-11-16 主人：已取页也要能搜，与待取页同款抽屉搜索）
            .modifier(SidebarSearchable(text: $model.query,
                                        enabled: !splitPane,
                                        prompt: "取件码 / 快递公司 / 地址"))
            // 与待取页同口径（三页统一）：导航栏常显、标题进导航栏、底色与列表同为浅灰。
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            // 分栏时标题自绘在列表里，导航栏只留按钮（三页统一）
            .navigationTitle(splitPane ? "" : "已取")
            .toolbarTitleDisplayMode(splitPane ? .inline : .large)
            .toolbar {
                if model.isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.snappy) { model.selectAll(of: visibleList) }
                        } label: {
                            Text(model.isAllSelected(of: visibleList) ? "全不选" : "全选")
                        }
                        .disabled(visibleList.isEmpty)
                    }

                    // 多选分享（2026-11-16 主人：已取页选中后也要有分享）。
                    // 🔴 面板关闭时用 `onFinish` 退出选择态 —— 分享完还停在勾选态
                    //    没有意义（主人：「不能还是选择状态吧」）。
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            shareSelection()
                        } label: {
                            Text(selectedRecords.isEmpty ? "分享" : "分享 \(selectedRecords.count)")
                                .fontWeight(.semibold)
                        }
                        .disabled(selectedRecords.isEmpty)

                        Button {
                            withAnimation(.snappy) { model.setEditing(false) }
                        } label: {
                            Text("完成")
                        }
                    }
                } else {
                    // 工具栏回到顶部右侧（2026-10-25 主人最终定：不再做左侧竖栏）
                    // 2026-11-16 主人：分组按钮放在「选择」左边。
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        groupMenu

                        if !list.isEmpty {
                            Button {
                                withAnimation(.snappy) { model.setEditing(true) }
                            } label: {
                                Text("选择")
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.isEditing {
                    // 删除与分享**同源**（都取 `selectedRecords`）：曾经这里用
                    // `list.filter { selection.contains }`，而分享用可见集 ——
                    // 顶上写「已选 3」、实际只动到 1 条，两个入口口径必须一致。
                    BatchDeleteBar(count: selectedRecords.count) {
                        withAnimation(.snappy) {
                            store.deleteMany(selectedRecords)
                            model.selection.removeAll()
                        }
                    }
                }
            }
            // 「清空已取件记录」的确认弹窗（2026-11-16 随按钮从待取页迁来）。
            // 🔴 不用 alert 也不用新页面：随机四位数就在**弹窗里**输入，
            //    输对了删除键才激活（2026-11-01 主人）。
            .destructiveConfirm(
                isPresented: $model.confirmClearPicked,
                title: "清空已取件记录",
                message: "记录只存在这台手机上，删除后无法恢复，也没有备份可以还原。"
            ) {
                DiagnosticsLog.record("records", "clear-picked \(list.count)")
                withAnimation(.snappy) { store.clearPickedUp() }
            }
            // 非 Pro 搜索态点详情被拦下 / 分栏右栏锁定时，打开订阅页
            .sheet(isPresented: $showPaywall) {
                NavigationStack { FullVersionView() }
                    .modifier(PaywallSheetSizing())
            }
            // 分享预览面板（单条）：与待取页共用同一个 `SharePreviewSheet`。
            .onAppear {
                openMenuFromScaffold()
                // 截图脚手架：`SIMCTL_CHILD_SEARCH=<关键词>` 启动即灌入搜索词。
                // `.searchable` 的输入框命令行点不到，搜索态（含非 Pro 锁定）只能这样取证。
                if let q = ProcessInfo.processInfo.environment["SEARCH"], !q.isEmpty {
                    model.query = q
                }
                // 截图脚手架：`SIMCTL_CHILD_SEARCH_PAYWALL=1` 直接亮起订阅页。
                if ProcessInfo.processInfo.environment["SEARCH_PAYWALL"] == "1" {
                    showPaywall = true
                }
                // 截图脚手架：`SIMCTL_CHILD_CONFIRM_DEMO=1` 打开页面就把确认弹窗亮起来
                // （2026-11-16 随清空入口从待取页迁来；纯色底拍不出"列表 + 弹窗"的叠放）
                if ProcessInfo.processInfo.environment["CONFIRM_DEMO"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        model.confirmClearPicked = true
                    }
                }
                // 截图脚手架：`SIMCTL_CHILD_EDIT=1` 启动即进编辑模式。
                if ProcessInfo.processInfo.environment["EDIT"] == "1", !list.isEmpty {
                    model.setEditing(true)
                }
                // 截图脚手架：`SIMCTL_CHILD_HISTORY_SORT=company|station|oldest|newest`
                // 直接切分组方式（菜单在命令行点不开，公司 / 驿站的组头只能这样取证）
                switch ProcessInfo.processInfo.environment["HISTORY_SORT"] {
                case "company": model.sort = .company
                case "station": model.sort = .station
                case "oldest":  model.sort = .oldest
                case "newest":  model.sort = .newest
                default: break
                }
                // 截图脚手架：`SIMCTL_CHILD_SELECT_SHARE=1|dismiss`
                //   1       → 进编辑 + 预选两条 + 走**真实的**分享动作（拍「分享 N」与面板）
                //   dismiss → 再把面板关掉，验证「分享完退出选择态」
                // 走的是 `shareSelection()`，与顶栏按钮同一条路径，不是另写一份假流程。
                if let raw = ProcessInfo.processInfo.environment["SELECT_SHARE"],
                   !model.isEditing, !visibleList.isEmpty {
                    model.setEditing(true)
                    visibleList.prefix(2).forEach { model.selection.insert($0.id) }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        shareSelection()
                        guard raw == "dismiss" else { return }
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        SharePresenter.shared.dismiss()
                    }
                }
                // 回到标签根页 → 露出标签栏（TabBarCloak 兜底，见 RootView）
                TabBarCloak.shared.reveal()
            }
    }

    // MARK: 分组与排序菜单

    /// 多选分享的统一入口（顶栏按钮与截图脚手架共用同一条路）。
    ///
    /// `onFinish` = 面板关闭后退出选择态 —— 主人 2026-11-16：
    /// 「分享面片中点击完成后，选择的状态就可以取消掉了，不能还是选择状态吧」。
    /// 点「完成」和点遮罩都会走 `SharePresenter.dismiss()`，两条路都会收干净。
    private func shareSelection() {
        SharePresenter.shared.present(selectedRecords) {
            withAnimation(.snappy) { model.setEditing(false) }
        }
    }

    /// 2026-11-16 主人：分组按钮搬到已取页，放在「选择」左边。
    ///
    /// 内容与待取页的 `filterMenuItems` 同一套排序项，但**没有**「全部标记为已取」
    /// （本页记录本来就全是已取），最后一项是「清空已取件记录」——
    /// 它清的就是本页的东西，入口在这儿才讲得通。
    private var groupMenu: some View {
        Button {
            showSortPanel = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("分组与排序")
        .popover(isPresented: $showSortPanel, arrowEdge: .top) {
            SortMenuPanel(
                current: model.sort,
                onPick: { choice in
                    choice.apply()
                    model.sort = choice.mode
                    model.bumpOrderRevision()
                    showSortPanel = false
                },
                extraAction: list.isEmpty
                    ? nil
                    : (title: "清空已取件记录", isDestructive: true,
                       action: {
                           model.confirmClearPicked = true
                           showSortPanel = false
                       })
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: 记录行

    @ViewBuilder
    private func row(for record: PickupRecord) -> some View {
        // 🔴 2026-11-16「一张卡片多个取件码」：整组同源记录共用一张卡。
        let group = PickupRecordGrouping.siblings(of: record, in: visibleList)
        let extraCodes = PickupRecordGrouping.extraCodes(for: record, in: visibleList)
        let restoreGroup = {
            withAnimation(.snappy) {
                if group.count > 1 {
                    store.restore(group)       // 批量恢复，只写盘一次
                } else {
                    store.toggle(record)
                }
            }
        }

        // ⚠️ 这里只能有**一份** `HistoryRow`（包在 `SwipeActionRow` 的尾闭包里）。
        // 2026-10-25 改造时漏删了原表达式，`@ViewBuilder` 把两份并列返回，
        // 结果是每行渲染两张一样的卡片（实测：8 条记录显示成 16 张卡）。
        //
        // 与待取页同口径改用自绘侧滑（2026-10-25）：系统 `.swipeActions` 的
        // 「卡片 ↔ 按钮」间距是写死的 29pt，收不紧；这里压到 8pt，
        // 且卡片不再被推开一大截。
        // 方向与待取页一致：**向右滑 = 直接复制**；向左滑 = 展开「恢复」需确认。
        SwipeActionRow(
            rowID: record.id,
            openRowID: $openSwipeRow,
            leading: model.isEditing ? [] : [
                SwipeActionItem(title: "复制", symbol: "doc.on.doc",
                                tint: AppTheme.accent) { model.copy(group) },
            ],
            trailing: model.isEditing ? [] : [
                SwipeActionItem(title: "恢复", symbol: "arrow.uturn.backward",
                                tint: AppTheme.pendingTint, action: restoreGroup),
            ],
            enabled: !model.isEditing,
            autoPerformSide: .leading,
            debugAllowsForcedOpen: ProcessInfo.processInfo.environment["SWIPE_OPEN"] != nil
        ) {
            HistoryRow(
                record: record,
                showsSelection: model.isEditing,
                isSelected: model.selection.contains(record.id),
                onToggle: restoreGroup,
                extraCodes: extraCodes
            )
            .contentShape(.rect)
            .onTapGesture {
                if model.isEditing {
                    withAnimation(.snappy) { model.toggleSelection(group) }
                } else {
                    // 宽屏只切右栏（不 push）、窄屏照旧推栈 —— 见 openDetail
                    openDetail(record)
                }
            }
        }
        // 编辑模式下完全不挂长按手势（`enabled: false`）
        .cardLongPress(for: record.id, state: cardMenu, enabled: !model.isEditing)
        // 🔴 行背景 / 分隔符 / insets 必须是链尾（写在前面会落到内层容器失效）。
        .listRowBackground(AppTheme.pageBackground)
        .listRowSeparator(.hidden)
        // 上下各 7.5pt = 卡片间实距 15pt，与待取页同口径。
        .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                  bottom: 7.5, trailing: AppTheme.hInset))
    }

    // MARK: 长按菜单

    /// 已取页只有三种操作：复制 / 分享 / 恢复为待取。
    private func menuItems(for record: PickupRecord,
                           group: [PickupRecord] = []) -> [CardMenuItem] {
        let related = group.isEmpty ? [record] : group
        return [
            CardMenuItem(title: "复制取件码",
                         symbol: "doc.on.doc",
                         action: { model.copy(related) }),
            // 分享由页面级 `.sheet` 承载 —— 菜单项不能自己弹面板（见 CardMenu.swift）
            CardMenuItem(title: "分享卡片",
                         symbol: "square.and.arrow.up",
                         action: { SharePresenter.shared.present(related) }),
            CardMenuItem(title: "恢复为待取",
                         symbol: "arrow.uturn.backward",
                         tint: AppTheme.pendingTint,
                         action: {
                             withAnimation(.snappy) {
                                 if related.count > 1 {
                                     store.restore(related)
                                 } else {
                                     store.toggle(record)
                                 }
                             }
                         }),
            // 单条删除（2026-11-11 内测反馈补）：此前已取页只有批量删除，长按没有删除项。
            CardMenuItem(title: "删除记录",
                         symbol: "trash",
                         tint: .red,
                         role: .destructive,
                         showsSeparatorBefore: true,
                         action: { model.delete(related, in: store) }),
            // 编辑收进详情页（2026-10-14 主人定稿）：本页菜单不再放「编辑」。
        ]
    }

    /// 菜单浮层：贴卡片定位，点空白处收起。
    @ViewBuilder
    private var cardMenuLayer: some View {
        if let id = cardMenu.openID,
           let record = store.records.first(where: { $0.id == id }) {
            let group = PickupRecordGrouping.siblings(of: record, in: store.records)
            CardMenuLayer(anchor: cardMenu.frame(of: id),
                          items: menuItems(for: record, group: group),
                          onDismiss: { cardMenu.close() }) {
                // 卡片替身：只负责「被看见」，所有回调留空。
                // 多码时也要画成多码，否则浮层与底下那张卡高度对不上（2026-11-16）。
                HistoryRow(record: record,
                           showsSelection: false,
                           isSelected: false,
                           onToggle: {},
                           extraCodes: PickupRecordGrouping
                               .extraCodes(for: record, in: store.records))
            }
        }
    }

    // MARK: 截图脚手架

    /// `SIMCTL_CHILD_MENU_OPEN=<序号>`：启动后自动打开列表第 N 条的菜单
    /// （命令行无法脚本化长按手势，这里走同一条 `cardMenu.open(_:)` 路径）。
    /// `SIMCTL_CHILD_SHARE_HIT=<序号>`：再自动「点」一次「分享卡片」行。
    private func openMenuFromScaffold() {
        let env = ProcessInfo.processInfo.environment
        let tapsShareRow = env["SHARE_HIT"] != nil
        guard let raw = env["SHARE_HIT"] ?? env["MENU_OPEN"],
              let index = Int(raw) else { return }

        Task { @MainActor in
            // 等卡片坐标上报（最多 3 秒）。
            var waited = 0
            while cardMenu.frames.isEmpty && waited < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }

            guard visibleList.indices.contains(index) else { return }
            let record = visibleList[index]
            cardMenu.open(record.id)

            guard tapsShareRow else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let action = menuItems(for: record)
                .first(where: { $0.title == "分享卡片" })?.action else { return }
            cardMenu.close()
            action()
        }
    }
}

// MARK: ============================================================================
// 统计页（取件数据分析）
// ============================================================================

/// 统计聚合的跨重建缓存（见 `StatsTabView.stats`）。
final class StatsCache: ObservableObject {
    private var key: Int = .min
    private var value = PickupStats(records: [])

    func stats(revision: Int, records: () -> [PickupRecord]) -> PickupStats {
        if key == revision { return value }
        value = PickupStats(records: records())
        key = revision
        return value
    }
}

struct StatsTabView: View {
    @EnvironmentObject private var store: PickupStore

    /// 统计数据的记忆化（2026-11-17 流畅度）。
    ///
    /// `stats` 原来是个纯计算属性：`PickupStats(records:)` 每次访问都全量聚合
    /// 一遍（按天分桶、按小时分桶、按公司分组、算平均停留 + Calendar 取值）。
    /// 而 body 里 `stats.isEmpty`、`stats.daily`、`stats.hourly`、`stats.company`
    /// 分属不同的卡，一次渲染就把 50 条记录重算 4~6 遍。
    ///
    /// 用 `@StateObject` 持有缓存：struct View 每次重建都会重新 init，
    /// 普通属性留不住；而 `@StateObject` 能跨重建存活。
    /// 🔴 缓存只改自己的私有字段、不发 `objectWillChange` —— body 求值期间写
    /// 「不可观察状态」是安全的，不会触发「Modifying state during view update」。
    @StateObject private var cache = StatsCache()

    private var stats: PickupStats {
        cache.stats(revision: store.revision) { store.records }
    }

    /// 宽屏（Duo 展开）判定：决定统计卡排成两列还是一列。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // 🔴 必须自带 NavigationStack：四个标签页里本页是唯一裸放的，
        // 之前漏包导致 navigationTitle 没有栈环境，大标题「统计」根本不显示
        // （待取/已取各自内部有栈、设置有 SettingsTabRoot 包装）。
        NavigationStack {
            // 截图脚手架：`SIMCTL_CHILD_SCROLL=freq|hour|company|kind|eff` 滚到对应统计卡。
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if horizontalSizeClass == .regular {
                            // 📊 宽屏（2026-10-25 主人：「统计页面也分列显示」）：
                            //    总览三格**独占一行全宽**（它是仪表盘主视觉，不该被挤成半宽），
                            //    下面五张分析卡两列并排。867pt 可用宽下每列约 400pt。
                            VStack(alignment: .leading, spacing: 16) {
                                overviewCard.id("top")

                                if !stats.isEmpty {
                                    // 用两个 VStack 手工分列，而不是 LazyVGrid：
                                    // 五张卡高度差很大（快递统计会长到一两屏），网格按行等高
                                    // 会在矮卡下方留大片空白；手工分列各自堆叠，观感紧实。
                                    HStack(alignment: .top, spacing: 16) {
                                        VStack(spacing: 16) {
                                            frequencyCard.id("freq")
                                            companyCard.id("company")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .top)

                                        VStack(spacing: 16) {
                                            // 2026-10-28 主人：效率是「结论」，要放在上面，
                                            // 时段分布是明细，往下排。
                                            efficiencyCard.id("eff")
                                            hourlyCard.id("hour")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .top)
                                    }
                                } else {
                                    emptyStats
                                }
                            }
                        } else {
                            // 🔴 2026-11-17 流畅度：这里是 `VStack` → `LazyVStack`。
                            //    五张卡的图表（`DailyBarChart` / `HourlyBarChart` 自绘 Path）
                            //    在 `VStack` 下首帧就要全部构建完，实测首次切到统计标签
                            //    冻结 99~180ms。懒加载后首帧只建屏幕内那几张。
                            //    ⚠️ 代价：`proxy.scrollTo` 到尚未构建的卡会失效 ——
                            //    那个入口只有截图脚手架在用，不影响正式功能。
                            LazyVStack(alignment: .leading, spacing: 16) {
                                // ① 总览三格：累计入库 / 累计取走 / 当前待取
                                overviewCard
                                    .id("top")

                                // ② 取件习惯分析（五张卡）
                                if !stats.isEmpty {
                                    // 2026-10-28 主人：把「取件效率」上移 ——
                                    // 它是最能一眼看出"我取件快不快"的结论卡，不该压在最底。
                                    frequencyCard.id("freq")
                                    efficiencyCard.id("eff")
                                    hourlyCard.id("hour")
                                    companyCard.id("company")
                                } else {
                                    emptyStats
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.hInset)
                    // 宽屏铺到 1200 上限（两列需要宽度）；窄屏仍是 700 居中列
                    .frame(maxWidth: horizontalSizeClass == .regular
                           ? 1200 : AppTheme.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .background(AppTheme.pageBackground)
                .onAppear {
                    scrollFromScaffold(proxy)
                    TabBarCloak.shared.reveal()
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    /// 无数据占位（两种布局共用）
    private var emptyStats: some View {
        EmptyStateView(symbol: "chart.bar.xaxis",
                       title: "还没有数据",
                       hint: "取几件之后，这里会长出你的取件画像")
            .padding(.top, 40)
    }

    /// 截图脚手架：`SIMCTL_CHILD_SCROLL=freq|hour|company|kind|eff` 滚到对应统计卡
    /// （simctl 没有滚动注入通道；默认「top」滚回页首）。
    private func scrollFromScaffold(_ proxy: ScrollViewProxy) {
        let anchor = ProcessInfo.processInfo.environment["SCROLL"] ?? "top"
        guard !anchor.isEmpty, anchor != "top" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    // MARK: ① 总览

    private var overviewCard: some View {
        StatTriple(items: [
            .init(title: "累计入库", value: "\(stats.receivedTotal)",
                  tint: AppTheme.pendingTint, symbol: "shippingbox.fill"),
            .init(title: "累计取走", value: "\(stats.pickedTotal)",
                  tint: AppTheme.doneTint, symbol: "checkmark.circle.fill"),
            .init(title: "当前待取", value: "\(stats.pendingTotal)",
                  tint: AppTheme.todayTint, symbol: "clock.fill"),
        ])
    }

    // MARK: ② 取件习惯分析

    private var frequencyCard: some View {
        StatCard(title: "取件频率",
                 note: "近 \(stats.window) 天 · 按完成取件的时刻统计") {
            VStack(alignment: .leading, spacing: 14) {
                DailyBarChart(points: stats.daily, peak: stats.busiestDayCount)

                Divider()

                HStack(spacing: 0) {
                    summary("日均", String(format: "%.1f", stats.dailyAverage) + " 件")
                    summary("有取件", "\(stats.activeDays) 天")
                    summary("连续", "\(stats.streak) 天")
                }

                if let trend = weekOverWeekText {
                    Text(trend.L)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 本周与上周的对比。`daily` 恰好是 14 天，后半段是本周、前半段是上周。
    private var weekOverWeekText: String? {
        let points = stats.daily
        guard points.count >= 14 else { return nil }
        let recent = points.suffix(7).reduce(0) { $0 + $1.picked }
        let previous = points.dropLast(7).suffix(7).reduce(0) { $0 + $1.picked }
        guard previous > 0 || recent > 0 else { return nil }

        let diff = recent - previous
        if diff == 0 { return "本周与上周都是 \(recent) 件" }
        let arrow = diff > 0 ? "多" : "少"
        return "本周取走 \(recent) 件，比上周\(arrow) \(abs(diff)) 件"
    }

    private func summary(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value.L)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title.L)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var hourlyCard: some View {
        StatCard(title: "取件时段", note: "一天中的取件分布") {
            VStack(alignment: .leading, spacing: 12) {
                HourlyBarChart(buckets: stats.hourly)

                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(peakText.L)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var peakText: String {
        var parts: [String] = []
        if let range = stats.busiestHourRange { parts.append("高峰 \(range)") }
        if let weekday = stats.busiestWeekday { parts.append("最常在\(weekday)取件") }
        return parts.isEmpty ? "还没有足够的样本" : parts.joined(separator: " · ")
    }

    private var companyCard: some View {
        StatCard(title: "各快递统计",
                 note: "\(stats.companies.count) 家公司 · 按件数排序") {
            VStack(spacing: 0) {
                ForEach(Array(stats.companies.enumerated()), id: \.element.id) { index, company in
                    if index > 0 {
                        Divider().padding(.leading, 36)
                    }
                    CompanyRow(point: company, total: stats.receivedTotal)
                }
            }
        }
    }

    private var efficiencyCard: some View {
        StatCard(title: "取件效率", note: "从收到通知到取走花了多久") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(PickupStats.durationText(stats.averageStay))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.doneTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("平均停留")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    summary("最快一次", PickupStats.durationText(stats.fastestStay))
                    summary("样本", "\(stats.staySampleCount) 件")
                    summary("今日已取", "\(stats.pickedToday) 件")
                }

                if stats.staySampleCount == 0 {
                    Text("还没有记录到取件时刻 —— 从收到通知到勾选「已取」走一遍，这里就会有数。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 记录行（已取页；同样支持行内恢复）

struct HistoryRow: View {
    let record: PickupRecord
    /// 编辑模式：码行右端换成「选择圆圈」，勾选框退场
    var showsSelection: Bool = false
    var isSelected: Bool = false
    let onToggle: () -> Void
    /// 同一条短信里的其它取件码（2026-11-16，与待取页 `PickupCard` 同规格）。
    var extraCodes: [String] = []

    /// 卡片强调色 —— 与待取页同一口径（2026-10-29）：
    /// **卡面、图标、取件码三者同源**，都取「快递公司 > 驿站 > 平台」。
    private var brand: Color { iconBrand }

    /// 取件码颜色**恒跟图标主题色**（2026-10-20 主人定）：与图标（快递公司>驿站>平台）同色。
    private var iconBrand: Color { CourierBrand.color(for: titleIconSource) }

    /// 与待取页 PickupCard v2 同一口径（26pt，图标下沉到取件码行）
    private static let iconSize: CGFloat = 26

    /// 一张卡上要画的码（主码永远在第一行；多码时与待取卡同为 24pt）。
    private var allCodes: [String] {
        [record.code] + extraCodes.filter { $0 != record.code }
    }

    /// 驿站名称库（内置 + 用户自定义），订阅以便用户在设置页增删后卡片即时刷新
    @ObservedObject private var stationDirectory = StationDirectory.shared

    /// 卡面命名 —— **统一走 `PickupNaming`**（与待取卡 / 详情页 / 分享卡同一真源）。
    private var naming: PickupNaming {
        record.namingResolved
    }
    private var titlePrimary: String { naming.primary }
    private var titleSecondary: String? { naming.secondaryLabel }
    /// 行 1 图标匹配串随主名走 —— 与「图标 = 第一行第一个字段」同源
    private var titleIconSource: String { naming.iconSource }
    /// 快递柜格口（与待取卡同口径）：有值就跟在快递驿站后面做胶囊标签
    private var lockerName: String? {
        let l = record.locker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return l.isEmpty ? nil : l
    }


    /// 码行左侧品牌图标（26pt，底部与取件码持平）
    private var logoBlock: some View {
        // 图标 = 卡面第一段（快递公司 > 短信平台 > 驿站），画法统一在 `PickupIcon`。
        PickupIcon(naming: naming, size: Self.iconSize)
            .frame(width: Self.iconSize, height: Self.iconSize)
    }

    var body: some View {
        // 2026-10-20：版式与待取页 PickupCard v2 对齐 ——
        // 26pt 图标下沉到取件码行（底部与码持平），上半文字左对齐到内容左缘；
        // 左侧不再有独立勾选列，勾选 / 选择圈都挪到码行右端。
        VStack(alignment: .leading, spacing: 0) {
                    // 行 1：主名（快递公司 > 驿站 > 平台）+「| 取件平台」+ 时间
                    HStack(spacing: 6) {
                        Text(titlePrimary.L)
                            .font(.system(size: 15.5, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(record.isPickedUp ? .secondary : .primary)

                        if let secondary = titleSecondary {
                            Text("|")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                            Text(secondary.L)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .foregroundStyle(record.isPickedUp ? .tertiary : .secondary)
                        }

                        // 快递柜标签（2026-10-28 主人定）：紧跟快递驿站，胶囊样式
                        if let lockerName {
                            Text(lockerName.L)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(brand)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(brand.opacity(0.14), in: .capsule)
                        }

                        Spacer(minLength: 6)

                        // 入库日期时间（2026-10-20 主人定：所有入库时间统一为日期时间格式；
                        // 由原来的 clockTime「HH:mm」升为 shortTime「M月d日 HH:mm」，跨天可辨）
                        Text(record.shortTime.L)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // 行 2：取件地址（图标已上移行 1，不再重复）
                    if !addressLine.isEmpty {
                        HStack(spacing: 6) {
                            Text(addressLine.L)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.top, 4)
                    }

                    DashedDivider()
                        .padding(.top, 8)
                        .padding(.trailing, 2)

                    // 行 3：图标 + 取件码 + 右端 复制 / 勾选
                    // 图标与码**视觉居中**对齐（2026-10-28 同待取卡口径：
                    // `.lastTextBaseline` 会让图标沉到基线以下约 4pt）
                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            logoBlock

                            // 与待取页 PickupCard 同一套多码版式：竖排、24pt、图标只画一次。
                            VStack(alignment: .leading,
                                   spacing: allCodes.count > 1 ? 1 : 0) {
                                ForEach(allCodes, id: \.self) { code in
                                    PickupCodeEmphasis.text(code,
                                                            isDone: record.isPickedUp,
                                                            tint: iconBrand)
                                        .font(.system(size: allCodes.count > 1 ? 24 : 30,
                                                      weight: .bold, design: .rounded))
                                        .monospaced()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        // 已取 → 划线（与详情页已取态同口径）
                                        .strikethrough(record.isPickedUp, color: .secondary)
                                }
                            }
                        }

                        Spacer(minLength: 6)

                        if showsSelection {
                            // 编辑模式：右端换成选择圈（点按选中交给整行手势）。
                            // 🔴 高度必须与 CompleteButton 的 44pt 一致（历史教训：36pt
                            // 会让行高被右侧控件压矮 8pt，整卡"变小"——2026-10-20 主人实测）
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(isSelected ? brand : Color.secondary.opacity(0.45))
                                .frame(width: 44, height: 44)
                        } else {
                            CompleteButton(isDone: record.isPickedUp, tint: brand, action: onToggle)
                        }
                    }
                    .padding(.top, 7)
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        .cardSurface(tint: brand)
        .opacity(record.isPickedUp ? 0.72 : 1)
    }

    private var addressLine: String {
        record.address.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 批量删除工具条（编辑模式底部悬浮）

/// 玻璃态底栏：左边已选计数，右边红色删除按钮。0 条时删除置灰。
struct BatchDeleteBar: View {
    let count: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(count > 0 ? "已选 \(count) 条" : "未选择")
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? Color.primary : Color.secondary)

            Spacer(minLength: 0)

            Button(action: onDelete) {
                Label("删除", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(count > 0 ? Color.white : Color.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(count > 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.secondary.opacity(0.18)),
                                in: .capsule)
            }
            .disabled(count == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }
}
