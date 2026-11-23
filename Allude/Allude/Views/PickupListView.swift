import SwiftUI
import UIKit
import WidgetKit

// MARK: - 排序方式

enum PickupSortMode: String, CaseIterable, Identifiable {
    case newest, oldest, company, station

    var id: String { rawValue }

    /// 标题（含当前方向）统一由逻辑层给，视图不再自己拼字符串
    var logic: PickupSortLogic.Mode {
        PickupSortLogic.Mode(rawValue: rawValue) ?? .newest
    }

    var title: String { logic.title }

    var symbol: String {
        switch self {
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .company: "building.2"
        case .station: "mappin.and.ellipse"
        }
    }

    /// 旧版本存的是中文 rawValue（"最近收到"…），读回时做一次映射
    static func migrated(_ raw: String) -> PickupSortMode? {
        if let mode = PickupSortMode(rawValue: raw) { return mode }
        switch raw {
        case "最近收到": return .newest
        case "最早收到": return .oldest
        case "按快递公司": return .company
        case "按快递驿站": return .station
        default: return nil
        }
    }
}

/// 排序菜单的一个选项 = 「模式 + 方向」的完整状态。
///
/// 🔴 2026-11-24 两轮返工后的结论：
///    Menu 里**只能用纯 `Text` 行**（`Label` 的图标会被系统重画、自定义 `HStack`
///    整行文字会消失、`opacity(0)` 会被忽略）。所以干脆让每一行就是一个完整状态，
///    交给系统 `Picker` 去画那个蓝色对号 —— 对号只在选中项、位置在左、文字左对齐，
///    全由系统保证，我们不再跟它较劲。
enum SortMenuChoice: Hashable, Identifiable {
    case plain(PickupSortMode)
    case company(Bool)
    case station(Bool)

    var id: String {
        switch self {
        case .plain(let mode):  return mode.rawValue
        case .company(let asc): return "company-\(asc)"
        case .station(let asc): return "station-\(asc)"
        }
    }

    var mode: PickupSortMode {
        switch self {
        case .plain(let mode): return mode
        case .company:         return .company
        case .station:         return .station
        }
    }

    var title: String {
        switch self {
        case .plain(let mode):  return mode == .newest ? "最新收到" : "最早收到"
        case .company(let asc): return asc ? "按快递公司 ↑" : "按快递公司 ↓"
        case .station(let asc): return asc ? "按快递驿站 ↑" : "按快递驿站 ↓"
        }
    }

    static func current(mode: PickupSortMode) -> SortMenuChoice {
        switch mode {
        case .newest:  return .plain(.newest)
        case .oldest:  return .plain(.oldest)
        case .company: return .company(PickupStorage.companyAscending)
        case .station: return .station(PickupStorage.stationNameAscending)
        }
    }

    /// 点同一项时翻转方向（只有公司和驿站有方向）
    var flipped: SortMenuChoice? {
        switch self {
        case .company(let asc): return .company(!asc)
        case .station(let asc): return .station(!asc)
        default: return nil
        }
    }

    func apply() {
        switch self {
        case .plain(let mode):
            PickupStorage.sharedDefaults.set(mode.rawValue, forKey: PickupStorage.listSortKey)
        case .company(let asc):
            PickupStorage.setCompanyAscending(asc)
            PickupStorage.sharedDefaults.set(PickupSortMode.company.rawValue,
                                             forKey: PickupStorage.listSortKey)
        case .station(let asc):
            PickupStorage.setStationNameAscending(asc)
            PickupStorage.sharedDefaults.set(PickupSortMode.station.rawValue,
                                             forKey: PickupStorage.listSortKey)
        }
    }
}

/// 排序面板（**自己画，不用系统 Menu**）。
///
/// 🔴 2026-11-24 三次返工的结论：系统 Menu 对自定义行完全不友好 ——
///    `opacity(0)` 被忽略（四行全勾）、自定义 `HStack` 整行文字消失、
///    改成 `Picker` 又只能 6 行（方向拆成两条）。
///    所以这里直接用一个 popover 自己排版：**4 行、选中项蓝色对号在左、
///    文字统一左对齐、点同一行翻转方向**，全部可控。
struct SortMenuPanel: View {
    let current: PickupSortMode
    let onPick: (SortMenuChoice) -> Void
    /// 面板底部附加动作（待取页「全部标记为已取」/ 已取页「清空已取记录」）
    var extraAction: (title: String, isDestructive: Bool, action: () -> Void)? = nil

    private var choices: [SortMenuChoice] {
        [.plain(.newest), .plain(.oldest),
         SortMenuChoice.current(mode: .company),
         SortMenuChoice.current(mode: .station)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(choices) { choice in
                Button {
                    if choice.mode == current, let flipped = choice.flipped {
                        onPick(flipped)          // 再点同一项 → 翻转方向
                    } else {
                        onPick(choice)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(choice.mode == current ? "✓" : "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18, alignment: .leading)
                        Text(choice.title)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if let extra = extraAction {
                Divider().padding(.vertical, 4)
                Button {
                    extra.action()
                } label: {
                    HStack(spacing: 8) {
                        Text("")
                            .frame(width: 18)
                        Text(extra.title)
                            .foregroundStyle(extra.isDestructive ? Color.red : .primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 232)
        .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 撤销动作// MARK: - 撤销动作// MARK: - 撤销动作

/// 记下「撤销」要撤销的到底是哪一件事。
///
/// 三种动作最终都落到 `records` 上，但方向相反：完成是把记录翻成已取、
/// 恢复是翻回待取、删除是把记录整条摘掉（撤销删除必须**放回**，只翻状态是放不回来的）。
/// 仅靠 `undoRecords` 反推不出是哪种，所以显式记一笔。
enum PickupUndoAction {
    case completed
    case deleted
    case restored
}

// MARK: - 首页状态

/// 首页的局部状态。放在 ObservableObject 里而不是 @State —— 这样工程在
/// 「Xcode GUI」与「命令行 xcodebuild」两条链路下都能编译（本机 Xcode 27 beta
/// 的 swift-plugin-server 在命令行下对 SwiftUI 宏返回 malformed response）。
final class PickupListModel: ObservableObject {
    /// 排序方式存本机（2026-11-15 主人：分组方式要记住，下次进来还是上次选的）。
    /// 用 App 自己的 UserDefaults 就够 —— 小组件不参与排序，不需要 App Group。
    private static let sortKey = PickupStorage.listSortKey

    @Published var path = NavigationPath()

    // 检索
    @Published var query = ""
    @Published var sort: PickupSortMode {
        didSet {
            // 写进 App Group：小组件要跟着同一套分组排（2026-11-15）
            PickupStorage.sharedDefaults.set(sort.rawValue, forKey: Self.sortKey)
            UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
            // 🔴 2026-11-21：光写值不够 —— 小组件的时间线不会自己知道偏好变了，
            //    不改这里的话，用户切了分组方式、桌面还是旧顺序（能拖几小时）。
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 排序方向翻转时 +1 —— 用于让 `displayedCacheKey` 失效（改方向不改 sort 枚举值）。
    @Published private(set) var orderRevision = 0

    func bumpOrderRevision() {
        orderRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    init() {
        // 读回上次选的分组方式（2026-11-15 主人：下次进来要保持上次的选择）
        let saved = PickupStorage.sharedDefaults.string(forKey: Self.sortKey)
            ?? UserDefaults.standard.string(forKey: Self.sortKey)
        sort = saved.flatMap(PickupSortMode.migrated) ?? .newest
    }

    // 交互反馈
    @Published var completing: Set<UUID> = []
    /// 刚复制成功的取件码（非 nil 时底部弹一条「已复制 xxx」）。
    /// 原来是 `copiedID: UUID?` —— 只写不读的死状态，复制完屏幕上什么反馈都没有
    /// （2026-10-25 主人：「向右滑复制后要有提示」）。
    @Published var copiedCode: String?
    @Published var undoRecords: [PickupRecord] = []
    @Published var undoAction: PickupUndoAction = .completed
    @Published var showUndo = false

    // 添加入口（手动粘贴 / 拍照·相册识别）
    @Published var showAdd = false
    @Published var showScan = false
    @Published var addedToast: String?

    // 多选（2026-09-23）：进多选 → 点卡片勾选 → 顶栏「分享」出图。
    @Published var selectionMode = false
    @Published var selectedIDs: Set<UUID> = []
    /// 非 nil 时弹出分享预览面板：单条（长按菜单「分享卡片」）传 `[record]`，
    /// 多条传选中集（按当前排序）—— 两个入口共用同一个面板，体验一致。
    @Published var shareRecords: [PickupRecord]?

    private var copyTask: Task<Void, Never>?

    // MARK: 重计算缓存

    /// `displayed` 的缓存（2026-11-17 流畅度专项）。
    ///
    /// **为什么需要**：`displayed` 是「过滤 + 全量排序」的计算属性，而一次 body
    /// 里会被读 5~10 次 —— 空态判断、四种分组各一次、`visibleRecordIDs`、
    /// 以及**每一行**的 `siblings`/`extraCodes` 都要拿它。每读一次就把整份记录
    /// 重排一遍。实测 14 秒内被算 54 次，其中同一次 body 内的重复占绝大多数。
    ///
    /// **为什么放在 model 而不是 view 的 `@State`**：body 求值期间写 state 会触发
    /// 「Modifying state during view update」警告，而且必然引起又一轮重算。
    /// 这个缓存对 SwiftUI 完全不可见，只是个朴素的记忆化。
    private var displayedCache: (key: String, value: [PickupRecord])?

    func cachedDisplayed(_ key: String, build: () -> [PickupRecord]) -> [PickupRecord] {
        if let cache = displayedCache, cache.key == key { return cache.value }
        let value = build()
        displayedCache = (key, value)
        return value
    }

    /// 每条记录各自的「勾选动效 → 落库」延迟任务。
    ///
    /// 🔴 必须按 `record.id` 分开存，不能共用一个数组后整批取消（2026-10-25 审查修）：
    /// 每个任务处理的是**不同**记录，取消前一个会让它的 `markPicked` 不执行、
    /// `completing` 里的 id 也永远清不掉 —— 那条记录就卡成「显示已勾选 + 半透明、
    /// 实际还在待取、且再点也没反应（被 `guard !completing.contains` 挡住）」的幽灵卡，
    /// 只有删除能动它，得杀进程才能恢复。
    private var completeTasks: [UUID: Task<Void, Never>] = [:]
    private var hideTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    // MARK: 多选分享

    func enterSelection(startingWith id: UUID) {
        selectionMode = true
        selectedIDs = [id]
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// 一张卡片挂了多个取件码（2026-11-16）：**整组一起选 / 一起取消**。
    /// 逐条 toggle 会让同一张卡里一半选中一半没选，分享出去少一个码，非常难查。
    func toggleSelection(_ records: [PickupRecord]) {
        let ids = Set(records.map(\.id))
        if ids.isSubset(of: selectedIDs) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    /// 从长按菜单进多选时，把整张卡上的码都预选上。
    func enterSelection(startingWith records: [PickupRecord]) {
        selectionMode = true
        selectedIDs = Set(records.map(\.id))
    }

    /// 全选当前可见（排序 / 检索之后）的记录。
    func selectAll(_ records: [PickupRecord]) {
        selectedIDs.formUnion(records.map(\.id))
    }

    func clearSelection() {
        selectedIDs = []
    }

    func exitSelection() {
        selectionMode = false
        selectedIDs = []
    }

    // MARK: 反馈

    func copy(_ record: PickupRecord) {
        UIPasteboard.general.string = record.code
        withAnimation(.snappy) { copiedCode = record.code }
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { copiedCode = nil } }
        }
    }

    /// 一张卡多个码：复制时按行拼全部码，提示语改成「已复制 N 个取件码」。
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

    /// 卡片内直接完成取件：先播放勾选反馈，再移出待取列表，最后给一次撤销机会。
    func complete(_ record: PickupRecord, in store: PickupStore) {
        guard !completing.contains(record.id) else { return }
        withAnimation(.snappy) { _ = completing.insert(record.id) }

        // 只取消**这一条**遗留的旧任务，绝不碰别的记录（见 `completeTasks` 的说明）
        completeTasks[record.id]?.cancel()

        completeTasks[record.id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else {
                // 真取消（页面销毁等）也要把标记清掉，不留幽灵卡
                completing.remove(record.id)
                completeTasks[record.id] = nil
                return
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                store.markPicked(record)
                completing.remove(record.id)
            }
            completeTasks[record.id] = nil
            armUndo([record], action: .completed)
        }
    }

    func completeAll(in store: PickupStore) {
        #if DEBUG
        let changed = PerfProbe.measure("completeAll.markAll") { store.markAllPendingAsPicked() }
        #else
        let changed = store.markAllPendingAsPicked()
        #endif
        guard !changed.isEmpty else { return }
        #if DEBUG
        PerfProbe.measure("completeAll.armUndo") { armUndo(changed, action: .completed) }
        #else
        armUndo(changed, action: .completed)
        #endif
    }

    /// 多选模式下把选中条目批量标记为已取（2026-10-14，参照取件喵「一键标记已取」）。
    /// 与单条 `complete(_:in:)` 同口径：直接落库 + 撤销条兜底（多选里没有勾选动画，
    /// 撤销条是唯一的后悔药）。只处理真正未取的条目，已取的混进选中集也不翻状态。
    func complete(_ records: [PickupRecord], in store: PickupStore) {
        let changed = records.filter { !$0.isPickedUp }
        guard !changed.isEmpty else { return }
        withAnimation(.snappy) {
            // 走批量重载：内部只落盘 / 刷新小组件一次（2026-10-25 审查修）
            store.markPicked(changed)
        }
        armUndo(changed, action: .completed)
    }

    /// 「已取件」列表里把记录恢复为待取件 —— 首页已不再展示已取件，
    /// 恢复动作只住在「取件库」，这里不再需要。

    func undo(in store: PickupStore) {
        hideTask?.cancel()
        switch undoAction {
        case .completed:
            withAnimation(.snappy) { store.restore(undoRecords) }
        case .deleted:
            // 撤销删除必须把记录**放回** `records`：`restore` 只在已有记录上翻状态，
            // 找不到刚被摘掉的那条 —— 原实现在这里其实是失效的，本轮一并修掉。
            withAnimation(.snappy) { store.insert(undoRecords) }
        case .restored:
            for record in undoRecords { store.markPicked(record) }
        }
        undoRecords = []
        withAnimation(.snappy) { showUndo = false }
    }

    /// 删除并给出撤销机会
    func delete(_ record: PickupRecord, in store: PickupStore) {
        withAnimation(.snappy) { store.delete(record) }
        armUndo([record], action: .deleted)
    }

    /// 一张卡多个码：删除 / 撤销都按整组走，不留半张卡。
    func delete(_ records: [PickupRecord], in store: PickupStore) {
        guard !records.isEmpty else { return }
        withAnimation(.snappy) { store.deleteMany(records) }
        armUndo(records, action: .deleted)
    }

    /// 弹出撤销条并在 4 秒后收起。三个动作共用同一套时序与计时器，
    /// 顺便把 `undoAction` 一并记下 —— 漏记会让撤销按上一个动作的方向执行。
    ///
    /// ⚠️ 自动隐藏的计时器单独放 `hideTask`，**不与完成动效任务合并**：
    /// `armUndo` 是在 `complete` 的延迟任务**内部**调用的，
    /// 若这里取消那批任务，会把正在执行的那一个一起取消，撤销条就永远不自动消失。
    /// （2026-10-25：完成动效任务已改为按 record.id 分开存的 `completeTasks`。）
    private func armUndo(_ changed: [PickupRecord], action: PickupUndoAction) {
        undoRecords = changed
        undoAction = action
        withAnimation(.snappy) { showUndo = true }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { showUndo = false } }
        }
    }

    // MARK: 添加后的收尾

    /// 新条目写进列表后要保证「用户能立刻看见它」。
    ///
    /// 若当前挂着检索词，新条目很可能被过滤掉 —— 用户会以为添加失败、
    /// 再点一次，于是触发去重拦下、更加困惑。所以这里直接清空检索词并把排序
    /// 切回「最近收到」，让新条目必定出现在第一屏。
    ///
    /// 范围也要拉回「待取件」：新进来的条目一定是待取件。（首页只有待取件一屏，
    /// 无需再切范围，清空检索即可保证新条目可见。）
    func revealNewest() {
        withAnimation(.snappy) {
            query = ""
            sort = .newest
        }
    }

    func flashAdded(_ outcome: IngestOutcome) {
        toastTask?.cancel()

        withAnimation(.snappy) { addedToast = outcome.dialog }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { addedToast = nil } }
        }
    }
}

// MARK: - 首页视图

struct PickupListView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = PickupListModel()
    /// 长按菜单（自绘，替代系统 contextMenu —— 见 CardMenu.swift 的说明）
    @StateObject private var cardMenu = CardMenuState()

    /// 通知点击待打开的记录 id（2026-10-25）
    @StateObject private var notificationRouter = NotificationRouter.shared

    /// 当前打开侧滑的行（自绘侧滑，2026-10-25）：全局只允许一行处于打开态
    @State private var openSwipeRow: UUID?

    // MARK: 列表作用域

    /// 首页**只服务待取件**（已取件的回执统一住在「取件库」）。
    private var scopedPending: [PickupRecord] {
        store.records.filter { !$0.isPickedUp }
    }

    /// 已取件 —— 首页列表不再展示，只给「今日已取」统计用。
    private var scopedPicked: [PickupRecord] {
        store.records.filter(\.isPickedUp)
    }

    /// 按免费版上限裁剪后的待办
    /// 搜索底稿：**不含条数上限**。
    ///
    /// 免费版上限只限制"屏幕上显示几条"，不限制"能搜到哪条"（2026-11-16 主人：
    /// 「可以搜索所有已完成取件的快递信息」，待取页同口径）。
    /// 代价是搜索时能搜到被折叠的记录，但**详情在非 Pro 搜索态是锁的**（见 `detailLocked`），
    /// 所以免费用户能看到"有这么一条"、看不到详情。
    private var searchBase: [PickupRecord] {
        // 排序时刻与卡面显示的时间同源（lastNotifiedAt）：
        // 刚被驿站催过的那件应当跳到最前，而不是按首次入库时间排在下面
        // 🔴 并列项必须走 tieBreak：`scopedList` 要按这个顺序 `prefix` 截条数，
        //    免费版「显示哪 4 条」否则每次都不一样（批量导入的短信大量同秒）。
        scopedPending.sorted {
            $0.lastNotifiedAt == $1.lastNotifiedAt
                ? PickupSortLogic.tieBreak($0, $1)
                : $0.lastNotifiedAt > $1.lastNotifiedAt
        }
    }

    private var scopedList: [PickupRecord] {
        Array(searchBase.prefix(store.visibleLimit))
    }

    private var scopedHiddenCount: Int {
        max(0, scopedPending.count - store.visibleLimit)
    }

    /// 🔴 2026-11-08 主人：「今天 1 件」但「今日新增 0」，数字自相矛盾。
    ///    根因：分组与卡面时间用的是 `lastNotifiedAt`（最后一次通知），
    ///    而这两个计数用的是 `receivedAt`（短信收到时刻）—— 同一条记录会在两处
    ///    落到不同天。计数改成与屏幕同源，看得见的与报出来的必须一致。
    private var scopedTodayNewCount: Int {
        scopedPending.filter { Calendar.current.isDateInToday($0.lastNotifiedAt) }.count
    }

    private var scopedTodayPickedCount: Int {
        scopedPicked.filter { Calendar.current.isDateInToday($0.lastNotifiedAt) }.count
    }

    /// 先按分类、范围与免费上限裁剪，再套用搜索与排序
    private var displayed: [PickupRecord] {
        #if DEBUG
        PerfProbe.count("list.displayed")
        #endif
        return model.cachedDisplayed(displayedCacheKey) {
            #if DEBUG
            PerfProbe.measure("list.displayed.ms") { computedDisplayed() }
            #else
            computedDisplayed()
            #endif
        }
    }

    /// 缓存判据：数据版本 + 检索词 + 排序方式 + 驿站内排序 + 可见上限
    /// + 自定义驿站清单 + 驿站组清单。
    ///
    /// 🔴 后两项**必须用 hashValue 而不是 count**：驿站改名、组换成员时数量不变，
    ///    用 count 会让缓存一直命中旧结果 —— 用户改完驿站名，列表还按旧名分组，
    ///    而且怎么退出重进都不变（缓存活在 model 里），极难排查。
    ///    `StationGroup` 与 `[String]` 都自动合成了 Equatable/Hashable，内容变了 hash 就变。
    private var displayedCacheKey: String {
        "\(store.revision)|\(model.query)|\(model.sort.rawValue)|"
            + "\(PickupStorage.companyAscending)|\(PickupStorage.stationNameAscending)|"
            + "\(model.orderRevision)|\(store.visibleLimit)|"
            + "\(StationDirectory.shared.customNames.hashValue)|"
            + "\(StationGroupStore.all().hashValue)"
    }

    private func computedDisplayed() -> [PickupRecord] {
        // 有搜索词就在**全量**里搜（免费用户也能搜到全部，只是详情锁着），
        // 没有搜索词才是裁过条数的可见集。两者的排序逻辑完全一致。
        let hasQuery = !model.query.trimmingCharacters(in: .whitespaces).isEmpty
        let base = store.filtered(hasQuery ? searchBase : scopedList, query: model.query)
        // 🔴 2026-11-23：四种排序**全部**交给 `PickupSortLogic.sort` ——
        //    它同时服务待取 / 已取 / 小组件 / 灵动岛 / 锁屏卡，只有一份实现。
        return PickupSortLogic.sort(base, mode: model.sort.logic)
    }

    /// 「一张卡片多个取件码」开启时，需要真正画出来的记录（每组只留代表）。
    /// 基于**全量 displayed** 计算，再拿去过滤各 Section，跨分组也不会重复画同一组。
    /// 关闭时返回全部 ID —— 与升级前一码一卡完全一致。
    private var visibleRecordIDs: Set<UUID> {
        PickupRecordGrouping.representativeIDs(displayed)
    }

    /// 过滤后的分组内记录（组头计数仍用未过滤的 `items.count`，按件数算才对）。
    private func rows(_ items: [PickupRecord]) -> [PickupRecord] {
        items.filter { visibleRecordIDs.contains($0.id) }
    }

    private var groups: [(group: DayGroup, items: [PickupRecord])] {
        store.grouped(displayed)
    }

    /// 「按快递公司」归类分组（2026-10-27 主人：选它之后列表要**按公司归类显示**，
    /// 不是筛出某一家）。
    ///  · 组头 = 公司名 + 该公司的件数；
    ///  · 组内按收到时间倒序（最近的在最上面）；
    ///  · 组与组之间**按件数多的在前** —— 和其余分组的取舍一致：先看量大的那家。
    ///
    /// 🔴 分组键必须用**卡片主名的口径**（`courier ?? 驿站 ?? company`），
    ///    不能用 `record.company` —— 那个字段是「发短信的平台」（拼多多、菜鸟），
    ///    不是承运的快递公司。第一版用了 `company`，结果「圆通承运、拼多多发的件」
    ///    被归到「拼多多」组，组头与卡片主名自相矛盾。
    private var companyGroups: [(company: String, items: [PickupRecord])] {
        var buckets: [(company: String, items: [PickupRecord])] = []
        for record in displayed {
            let name = groupingName(for: record)
            if let index = buckets.firstIndex(where: { $0.company == name }) {
                buckets[index].items.append(record)
            } else {
                buckets.append((name, [record]))
            }
        }
        buckets.sort {
            $0.company == "其他" ? false
                : $1.company == "其他" ? true
                : $0.items.count > $1.items.count
        }
        return buckets
    }

    /// 「按快递驿站」归类分组（2026-11-15 主人）：
    ///  · 组头 = 驿站名 + 件数；
    ///  · 站内按收到时间倒序（最近的在最上面）；
    ///  · 组与组之间按件数多的在前，与「按快递公司」同一取舍。
    private var stationGroups: [(station: String, items: [PickupRecord])] {
        var buckets: [(station: String, items: [PickupRecord])] = []
        for record in displayed {
            let name = stationName(for: record)
            if let index = buckets.firstIndex(where: { $0.station == name }) {
                buckets[index].items.append(record)
            } else {
                buckets.append((name, [record]))
            }
        }
        // 🔴 桶内顺序必须走「驿站内排序」—— 以前这里又按时间重排了一次，
        //    会把用户选的「按取件码」整个覆盖掉（2026-11-17）。
        // 组内永远按取件码 0-9、A-Z 升序（「驿站内排序」设置已删）
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

    /// 驿站名：`station` 是派生值（词表命中 / AI 修正后的 stationOverride），空则归到「未标注驿站」。
    /// 2026-11-17：已归组的驿站返回**组名** —— 待取页只显示组，不再把成员拆成几个分组。
    private func stationName(for record: PickupRecord) -> String {
        #if DEBUG
        PerfProbe.count("list.stationName")
        #endif
        // 2026-11-21：分组键与桌面小组件**同一门函数**（`PickupSortLogic.stationName`），
        // 里面走单一解析入口，带记录级手工指定与自定义驿站；以前这里只认词表名，
        // 手工指定的驿站/组在待取页不生效，桌面反而对。
        return PickupSortLogic.stationName(of: record)
    }

    /// 归类用的名字：快递公司 > 驿站名（名称库命中）> 短信平台，
    /// 与 `PickupCard.titlePrimary` 完全同源，保证组头和卡片主名永远一致。
    private func groupingName(for record: PickupRecord) -> String {
        let courier = record.courier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !courier.isEmpty { return courier }
        // 驿站不进分组名：分组名与卡片主名必须同源，否则组头写「兴裕隆超市」、
        // 卡片写「韵达快递」，用户会以为是两个东西（2026-10-28 与主名口径一起改）。
        return record.company.isEmpty ? "其他" : record.company
    }

    /// 宽屏（iPhone Duo 展开态 951×669pt）判定 —— 系统在该形态下给的是 `.regular`，
    /// 与 iPad 同语义。常规 iPhone（402/440/466pt）恒为 `.compact`，走单栈老路径。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// iPad 分栏：启动时两侧都可见（HIG：分栏对 iPad 是原生信息结构，
    /// 不要让用户先点一次侧栏按钮才看到列表）。
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 分栏下右侧当前显示的记录 id（2026-10-25）。
    /// **nil = 用户还没点过任何一条** → 右栏回落到列表第一条（见 `splitDetailRecord`）。
    @State private var splitSelection: PickupRecord.ID?
    /// 当前页可用宽度（只量不改布局，见 body 里的 preference）。
    @State private var paneWidth: CGFloat = 0

    /// 分栏右栏要显示的记录：选中的那条优先；没选中（首次进入 / 选中项已被取走或删除）
    /// 就显示列表第一条 —— 主人定「横屏默认显示第一个卡片」。
    private var splitDetailRecord: PickupRecord? {
        if let id = splitSelection,
           let hit = displayed.first(where: { $0.id == id }) {
            return hit
        }
        return displayed.first
    }

    /// 非 Pro 在**搜索态**下只给结果、不给详情（2026-11-16 主人：
    /// 「待取页面也是同样的只可以搜到，不能点击查看详情」）。
    /// 不含搜索词时行为不变。
    private var detailLocked: Bool {
        guard !EntitlementSnapshot.licensedPro else { return false }
        return !model.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 订阅页呈现态：搜索结果被拦下、或分栏右栏处于锁定态时打开。
    @State private var showPaywall = false
    /// 排序面板（自己画的 popover，见 `SortMenuPanel`）
    @State private var showSortPanel = false

    /// 打开详情：宽屏只切换右栏内容（不 push），窄屏照旧推进导航栈。
    /// 卡片点击 / 侧滑「详情」/ 长按菜单「详情」三处共用这一个入口 ——
    /// 所以门禁只需写在这里（🔴 非 Pro 搜索态一律拦下，见 `detailLocked`）。
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

    var body: some View {
        // 📱 2026-10-25（主人）：「Duo 内屏横屏那么大，不做成平行视图太浪费」——
        //    宽屏改为 **NavigationSplitView 左列表 / 右详情**；
        //    常规 iPhone 仍走原来的单栈，行为与历史版本逐像素一致。
        Group {
            // 🔴 2026-11-14：只看 horizontalSizeClass 不够 —— iPad mini 竖屏也是 regular，
            //    两栏硬塞进 744pt 会把详情挤到屏幕外。改判**实际可用宽度**（≥ 900pt 才分栏）。
            //    宽度用 preference 量，不能用 GeometryReader 包一层：那会让 NavigationSplitView
            //    丢掉顶部安全区，标签栏直接压在详情列标题上。
            if PadLayout.usesSplit, paneWidth >= PadLayout.splitMinWidth {
                splitLayout
            } else {
                stackedLayout
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: AlludePaneWidthKey.self, value: geo.size.width)
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .onPreferenceChange(AlludePaneWidthKey.self) { paneWidth = $0 }
        // 长按景深：整个界面轻微后退（模糊 + 缩放），被按的卡片由浮层里的「替身」
        // 接管 —— 替身与菜单都在下面这个 overlay 里，因此始终清晰。
        .blur(radius: cardMenu.openID == nil ? 0 : CardMenuMetrics.backgroundBlur)
        .scaleEffect(cardMenu.openID == nil ? 1 : CardMenuMetrics.backgroundScale)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: cardMenu.openID)
        .overlay { cardMenuLayer }
        // 通知点击 → 打开对应记录的详情（2026-10-25）
        .onAppear {
            consumeNotificationTarget()
            openSwipeFromScaffold()
            copyToastFromScaffold()
            applySortFromScaffold()
            completeAllFromScaffold()
        }
        .onChange(of: notificationRouter.pendingRecordID) { _, _ in consumeNotificationTarget() }
    }

    /// `SIMCTL_CHILD_SWIPE_OPEN=<序号>`：把列表第 N 行摆成「侧滑已打开」的形态。
    /// 命令行点不出拖拽手势，只能靠这个脚手架取证（2026-10-25 自绘侧滑引入）。
    /// `SWIPE_STRETCH=<pt>` 则把第一行直接放在「拉长形变」的位置上。
    static var scaffoldStretch: CGFloat {
        guard let raw = ProcessInfo.processInfo.environment["SWIPE_STRETCH"],
              let value = Double(raw) else { return 0 }
        return CGFloat(value)
    }

    /// `SIMCTL_CHILD_COPY_TOAST=1`：启动后对第一条执行一次复制，
    /// 用于截图验证「已复制」回执的样式。
    /// 这里**不复用** `model.copy` —— 它 1.6s 后自动消失，比冷启动首帧还早，
    /// 根本没机会截到。改为直接置状态且不自动清（重启即消失）。
    private func copyToastFromScaffold() {
        guard ProcessInfo.processInfo.environment["COPY_TOAST"] == "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let first = displayed.first else { return }
            UIPasteboard.general.string = first.code
            withAnimation(.snappy) { model.copiedCode = first.code }
        }
    }

    /// `AUTO_ONECLICK=1`：进页面 3 秒后自动点一次「全部完成取件」。
    /// 配合 `PERF_LOG=1` 量化这条路径（落盘 / 小组件 / 实时活动 / 提醒）的真实耗时。
    private func completeAllFromScaffold() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AUTO_ONECLICK"] == "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            PerfProbe.measure("action.completeAll") { model.completeAll(in: store) }
            PerfProbe.flush()
        }
        #endif
    }

    private func openSwipeFromScaffold() {
        guard let raw = ProcessInfo.processInfo.environment["SWIPE_OPEN"],
              let index = Int(raw) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard displayed.indices.contains(index) else { return }
            openSwipeRow = displayed[index].id
        }
    }

    /// 消费 `NotificationRouter` 里待打开的记录 id。
    ///
    /// 只处理**属于本页**的（待取集合里的）记录；已取的那条会由 `PickedUpView`
    /// 接走 —— 两个页面都监听、各自只认自己集合里的 id，谁匹配谁清空，
    /// 因此不依赖 RootView 切标签与页面回调的先后顺序。
    private func consumeNotificationTarget() {
        guard let id = notificationRouter.pendingRecordID,
              let record = store.pending.first(where: { $0.id == id }) else { return }
        notificationRouter.pendingRecordID = nil
        if horizontalSizeClass == .regular {
            splitSelection = record.id
        } else {
            model.path.append(record)
        }
    }

    /// `SIMCTL_CHILD_SORT=company|oldest|newest`：启动即切到指定排序/分组，
    /// 用于截图验收「按快递公司归类」的组头（菜单点不开，只能这样取证）。
    private func applySortFromScaffold() {
        switch ProcessInfo.processInfo.environment["SORT"] {
        case "company": model.sort = .company
        case "station": model.sort = .station
        case "oldest": model.sort = .oldest
        case "newest": model.sort = .newest
        default: break
        }

        // `SIMCTL_CHILD_SELECT=1|all`：进入多选态（`all` 顺带全选），截图验收「全选」按钮
        switch ProcessInfo.processInfo.environment["SELECT"] {
        case "1":
            model.selectionMode = true
        case "all":
            model.selectionMode = true
            model.selectAll(displayed)
        default:
            break
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

    /// 平行视图（宽屏）：左侧列表、右侧**常驻详情**。
    ///
    /// 🔴 2026-10-25 主人定：分栏下**不再有独立的详情页** ——
    /// 右栏直接渲染选中记录（无 push、无返回栈）；未选中时默认显示第一条。
    ///
    /// 列宽 = 左右等分（主人：「平均宽度分列，不要左窄右宽」）。
    /// ⚠️ 主人当天先要求「按铰链中轴分列」，实测系统会把列宽夹到 ~415pt、
    ///    左栏几乎被压扁，随即改回等分 —— 不要再试中轴方案。
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 🔴 2026-11-15：左列结构与右列**完全对称** —— 外层 ZStack 铺满浅灰 + 内层 NavigationStack。
            //    右列一直这么写，所以它顶部是灰的；左列只写 `NavigationStack { listPane }`
            //    时，那块灰铺不到状态栏/导航栏后面，顶部就露出系统白（主人说的「左上角一块白」）。
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()
                NavigationStack {
                    listPane
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: PadLayout.splitColumnIdeal, max: 600)
        } detail: {
            ZStack {
                // 右栏整列铺浅灰：详情限宽 760 居中，两侧不能露出系统白
                AppTheme.pageBackground.ignoresSafeArea()
            if detailLocked {
                // 分栏右栏是常驻区域，没有"点击"可拦 —— 不换成占位就等于白送详情
                ProLockedSplitPlaceholder { showPaywall = true }
            } else if let record = splitDetailRecord {
                // 🔴 `.id(record.id)` 必须加（2026-10-25 审查修）：
                // 右栏是同一个视图标识，换记录只是换入参，而 `draft` / `edit`
                // 都是 `@StateObject`（只认第一次 init 的值，不会随新记录重建）。
                // 上一轮编辑没保存就切到另一条时，B 的详情页会仍处于编辑态、
                // 且输入框里显示的是 **A 的草稿**，一点保存就把 A 的内容写进 B。
                // 绑定 id 后每条记录各自拥有一份状态。
                RecordDetailView(record: record)
                    .id(record.id)
                    // iPad 宽屏：详情卡不要拉满整列（1300pt 宽时取件码会大得离谱），
                    // 限宽居中，读起来像 iPad 原生 App。
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            } else {
                SplitDetailPlaceholder()
            }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // 🔴 2026-11-15 主人：「待取左上角为啥有一块白色」。
        //    给导航栏**上色压不住**系统材质（试过 toolbarBackground(色, .visible)，仍是白的），
        //    改成让它透明 —— 内容（listPane 的浅灰底）延伸上去，白块才真的没了。
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// 列表本体（两种布局共用）：List + 内边距 / 背景 / 搜索 / 工具栏 / 弹层。
    /// ⚠️ `navigationDestination` 不在这里 —— 它由各布局自己挂在对应的栈上，
    ///    否则分栏模式下会被注册到没有栈的 sidebar 列（无效且会告警）。
    private var splitPane: Bool { PadLayout.usesSplit && paneWidth >= PadLayout.splitMinWidth }

    private var listPane: some View {
        VStack(spacing: 0) {
            if splitPane {
                // 🔴 2026-11-15 主人：「左上角为啥有一块白色」——
                //    那块白是导航栏默认底色 + 这个 VStack 没铺底色，透出了窗口白。
                //    现在导航栏改成浅灰（见下面的 toolbarBackground），这里也补同色底。
                //    标题统一交给系统导航栏，不再自绘 PadSidebarHeader。
                // 🔴 2026-11-15 三页统一：大标题自绘在列表里（34pt bold，与直板机同字号）。
                //    侧栏列不让系统画 large title（设置页实测压成居中 inline），
                //    干脆三页都自己画，位置与字号才真的一致。
                PadSidebarHeader(title: "待取")
                PadSidebarSearchField(text: $model.query, prompt: "取件码 / 快递公司 / 地址")
                    .padding(.bottom, 4)
            }
            listBody
        }
        // 🔴 2026-11-15：`ignoresSafeArea()` 是关键 —— 不加的话底色只铺内容区，
        //    导航栏那一条露出的是 **sidebar 列自身**的系统白，看起来就是「左上角一块白」。
        .background(AppTheme.pageBackground.ignoresSafeArea())
    }

    private var listBody: some View {
        List {
                // 顶部统计卡：待取 / 今日新增 / 今日已取 三格一组，只报数不切页。
                // 搜索态不显示：它统计的是**全部**待取件，跟筛出来的结果无关，
                // 与已取页 `HeroStatsCard` 同一口径（2026-11-16）。
                if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        HeroStatsCard(primary: scopedPending.count,
                                      primaryUnit: "件待取",
                                      primaryTint: AppTheme.accent,
                                      primaryTintLight: AppTheme.accentLight,
                                      stats: [
                                          .init(title: "今日新增", value: scopedTodayNewCount,
                                                tint: AppTheme.todayTint, symbol: "arrow.down.circle.fill"),
                                          .init(title: "今日已取", value: scopedTodayPickedCount,
                                                tint: AppTheme.doneTint, symbol: "checkmark.circle.fill"),
                                      ])
                        .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                  bottom: 12, trailing: AppTheme.hInset))
                        .listRowBackground(AppTheme.pageBackground)
                        .listRowSeparator(.hidden)

                        // 列表头不放任何分段/切换控件：分组方式固定为时间流，
                        // 「按驿站」已于 2026-10-27 移除，筛选收在顶栏的漏斗菜单里。
                    }
                }

                content

                if scopedHiddenCount > 0 && model.query.isEmpty {
                    Section {
                        HiddenHint(count: scopedHiddenCount)
                            .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                      bottom: 8, trailing: AppTheme.hInset))
                            .listRowBackground(AppTheme.pageBackground)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(AppTheme.listSpacing)
            .scrollContentBackground(.hidden)
            // 🔴 页面底 = 浅灰，且**行背景必须显式写成同一个浅灰**（2026-09-23 二次修正）。
            //
            // 第一版只把 `.scrollContentBackground(.hidden)` + `.background(浅灰)`
            // 补上，行背景留 `Color.clear` 想"透出页面底" —— 实测**记录行仍然透出系统白**
            // （像素采样：统计卡区左边缘 #F2F2F7，记录卡片区左边缘 #FFFFFF），
            // 上半浅灰、下半白，比原来还难看。原因就是 `.plain` 样式下行的默认底是
            // `systemBackground`，`clear` 并不能可靠地透到 List 视图背景那一层。
            // 改成显式同色后，行区域不再依赖任何透明传递。
            .background(AppTheme.pageBackground)
            .contentMargins(.bottom, 88, for: .scrollContent)
            // 📱 宽屏（iPhone Duo 展开态 951pt / regular）内容限宽居中：
            //    卡片铺满 911pt 会让取件码与右端勾选相距过远、信息行过长。
            //    两段 frame = 「最多 700pt」+「撑满父级并居中」，
            //    常规 iPhone（402/440pt）触不到上限，行为与旧版完全一致。
            .frame(maxWidth: splitPane ? .infinity : AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
            // 限宽后两侧露出父级背景，需补同色，避免中间浅灰、两边纯白
            .background(AppTheme.pageBackground)
            .modifier(SidebarSearchable(text: $model.query,
                                        enabled: !splitPane,
                                        prompt: "取件码 / 快递公司 / 地址"))
            // 🔴 2026-10-08 结构重构：浏览（已取件）独立成 Tab 后，取件页不再需要
            //    分段切换器 —— 回归系统导航栏（大标题「取件」+ drawer 搜索 + 系统
            //    toolbar）。此前为「分段居中于标题位」做的自绘顶栏随分段一起退役。
            // 🔴 2026-11-15 三页统一（待取 / 已取 / 设置）：
            //    · 标题交给系统导航栏（分栏用 inline，单列仍是大标题）；
            //    · 导航栏底色与列表同为浅灰，不再是白块；
            //    · 工具栏按钮统一 topBarTrailing。
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            // 分栏时标题自绘在列表里，导航栏只留按钮
            .navigationTitle(splitPane ? "" : "待取")
            .toolbarTitleDisplayMode(splitPane ? .inline : .large)
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) { bottomOverlay }
            // 🔴 2026-11-16：「清空已取件记录」的确认弹窗随按钮一起搬到已取页
            //    （`PickedUpView`）。本页不再有任何清空入口，弹窗一并移走。
            // 非 Pro 搜索态点详情被拦下 / 分栏右栏锁定时，打开订阅页
            .sheet(isPresented: $showPaywall) {
                NavigationStack { FullVersionView() }
                    .modifier(PaywallSheetSizing())
            }
            .sheet(isPresented: $model.showAdd) {
                AddPickupSheet(onClose: { model.showAdd = false },
                               onAdded: handleAdded)
                    .environmentObject(store)
            }
            .sheet(isPresented: $model.showScan) {
                ScanPickupSheet(onClose: { model.showScan = false },
                                onAdded: handleAdded)
                    .environmentObject(store)
            }
            // 分享预览面板：单条（长按菜单「分享卡片」）与多条（多选后顶栏「分享」）
            // 共用 —— 内容 = 记录渲染成的一张分享卡图。
            // 🔴 必须挂在页面这一层：它的呈现者要活得比长按浮层久。
            //    挂进浮层的话，菜单一关浮层即销毁，面板根本弹不出来（见 CardMenu.swift）。
            // 分享预览面板：单条（长按菜单「分享卡片」）与多条（多选后顶栏「分享」）
            // 共用 —— 内容 = 记录渲染成的一张分享卡图。
            // 🔴 必须挂在页面这一层：它的呈现者要活得比长按浮层久。
            //    挂进浮层的话，菜单一关浮层即销毁，面板根本弹不出来（见 CardMenu.swift）。
            // 通知权限在这里才问：用户已经看见「待取件」列表长什么样了，
            // 此时解释「新短信进来时提醒你」才讲得通。冷启动就弹只会被随手拒掉。
            .onAppear {
                // 截图脚手架：`SIMCTL_CHILD_SKIP_PERM=1` 时不弹系统通知授权。
                // 那个弹窗会盖住屏幕中部，验收图上什么都看不见 —— 而 simctl
                // 点不到「允许」，只能从源头绕开。
                if ProcessInfo.processInfo.environment["SKIP_PERM"] == nil,
                   !RootTabModel.isLaunchGateActive {
                    // 🔴 首启门（同意 / 引导）还盖着时不问：系统授权弹窗会盖住引导页，
                    //    用户第一眼看到的是权限弹窗而不是欢迎页。门关后由 RootView 统一问。
                    PickupNotifier.requestAuthorizationIfNeeded()
                }
                openMenuFromScaffold()
                // 截图脚手架：`SIMCTL_CHILD_SEARCH=<关键词>` 启动即灌入搜索词。
                // `.searchable` 的输入框命令行点不到，搜索态（含非 Pro 锁定）只能这样取证。
                if let q = ProcessInfo.processInfo.environment["SEARCH"], !q.isEmpty {
                    model.query = q
                }
                // 截图脚手架：`SIMCTL_CHILD_SEARCH_PAYWALL=1` 直接亮起订阅页 ——
                // 「非 Pro 搜索态点卡片」这一步命令行点不到，但呈现路径必须验。
                if ProcessInfo.processInfo.environment["SEARCH_PAYWALL"] == "1" {
                    showPaywall = true
                }
                // 分栏验证脚手架：`SIMCTL_CHILD_SPLIT_DETAIL=<码子串>` 启动即选中一条，
                // 让命令行也能拍到「左列表 / 右详情」的联动 —— 点卡片的手势无法脚本化。
                // 宽屏下走的就是 `openDetail` 的同一条路径（只切右栏，不 push）。
                if let needle = ProcessInfo.processInfo.environment["SPLIT_DETAIL"],
                   !needle.isEmpty,
                   let hit = displayed.first(where: {
                       $0.code.localizedCaseInsensitiveContains(needle)
                   }) {
                    splitSelection = hit.id
                }
                // 多选分享截图脚手架：`SIMCTL_CHILD_SELECT_MODE=1` 启动即进多选
                // 并预选前三条 —— 命令行点不到卡片，选择圈与顶栏只能这样拍。
                if ProcessInfo.processInfo.environment["SELECT_MODE"] == "1",
                   !model.selectionMode {
                    let ids = displayed.map(\.id)
                    if let first = ids.first {
                        model.enterSelection(startingWith: first)
                        for id in ids.prefix(3) { model.selectedIDs.insert(id) }
                    }
                }
                // 🔴 回到标签根页 → 露出标签栏（TabBarCloak 计数归零兜底，
                //    pop 转场开始即触发，滑回动画与转场并行）
                TabBarCloak.shared.reveal()
            }
    }

    /// 两个添加入口共用的收尾：成功则解除过滤让新条目可见，同时给一条轻反馈。
    private func handleAdded(_ outcome: IngestOutcome) {
        if !outcome.added.isEmpty { model.revealNewest() }
        model.flashAdded(outcome)
    }

    // MARK: 列表内容

    @ViewBuilder
    private var content: some View {
        // 空态看的是「范围底稿」而不是「过滤后的结果」：前者空 = 真的没有，
        // 后者空但底稿非空 = 有记录、只是被检索词筛掉了，两种要给不同的提示。
        if scopedList.isEmpty {
            Section {
                EmptyStateView(symbol: "shippingbox",
                               title: "暂无待取件",
                               hint: "收到快递短信后，取件信息会自动出现在这里")
                    .listRowInsets(EdgeInsets(top: 40, leading: AppTheme.hInset,
                                              bottom: 0, trailing: AppTheme.hInset))
                    .listRowBackground(AppTheme.pageBackground)
                    .listRowSeparator(.hidden)
            }
        } else if displayed.isEmpty {
            Section {
                NoResultView(query: model.query)
                    .listRowInsets(EdgeInsets(top: 36, leading: AppTheme.hInset,
                                              bottom: 0, trailing: AppTheme.hInset))
                    .listRowBackground(AppTheme.pageBackground)
                    .listRowSeparator(.hidden)
            }
        } else if model.sort == .company {
            // 「按快递公司」= 按公司归类显示（组头是公司名），不是筛出某一家。
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
            // 「按快递驿站」= 按驿站归类显示（组头是驿站名），站内按时间倒序。
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
            // 最近收到 / 最早收到：按时间流分组（今天 / 昨天 / 更早）。
            ForEach(groups, id: \.group) { section in
                Section {
                    // 组头当普通行塞进 Section：Section header 的默认上下留白不受
                    // listRowInsets 控制（2026-11-15 踩过），当行放才能真正压到 2pt。
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
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.selectionMode {
            // 多选模式：顶栏换成「取消 · 已取 · 分享」，隐藏添加 / 扫描 / 筛选 / 头像
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { model.exitSelection() }
            }
            // 全选 / 取消全选：作用于当前可见集合（排序、检索之后），与「已取 N」「分享 N」同源
            ToolbarItem(placement: .topBarLeading) {
                Button(allVisibleSelected ? "取消全选" : "全选") {
                    if allVisibleSelected {
                        model.clearSelection()
                    } else {
                        model.selectAll(displayed)
                    }
                }
                .disabled(displayed.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.complete(selectedRecords, in: store)
                    model.exitSelection()
                } label: {
                    // 🔴 计数与实际处理集合同源（2026-10-25 审查修）：
                    // 以前用 `selectedIDs.count`，而真正处理的是
                    // `selectedRecords = displayed.filter { selectedIDs.contains }`。
                    // 多选态下 searchable 依然生效，一搜索就会有一部分选中项被
                    // `displayed` 裁掉 —— 顶栏显示「已取 3」实际只处理 1 条。
                    Text(selectedRecords.isEmpty ? "已取" : "已取 \(selectedRecords.count)")
                        .fontWeight(.semibold)
                }
                .disabled(selectedRecords.isEmpty)
                .tint(AppTheme.doneTint)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SharePresenter.shared.present(selectedRecords)
                } label: {
                    Text(selectedRecords.isEmpty ? "分享" : "分享 \(selectedRecords.count)")
                        .fontWeight(.semibold)
                }
                .disabled(selectedRecords.isEmpty)
            }
        } else {
            // 顶栏三胶囊（借鉴 Apple 邮件/提醒事项的工具栏口径，2026-10-14）：
            //   「+」菜单聚合两个添加入口（原「添加」「扫描」两个等权胶囊合并，
            //    对齐系统 App「一个 + 收纳多种新建方式」的惯例）；
            //   筛选菜单里管排序/分组/过滤；
            //   「选择」走照片 App 的文字按钮口径（checkmark 图标语义太弱）。
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    addMenuItems
                } label: {
                    // 与全局同一套矢量还原（圆圈加号），颜色走系统默认前景色
                    AddGlyph(size: 21)
                }
                .accessibilityLabel("添加取件信息")

                filterMenu

                // 多选入口（2026-09-24 主人定）：双指手势体验不稳，改常规按钮。
                Button {
                    model.selectionMode = true
                } label: {
                    Text("选择")
                }
                .accessibilityLabel("选择多条记录")
            }

            // 🔴 2026-10-14：顶栏头像入口退役 —— 设置已升格为底部第 4 个标签页
            // （原「我的」面板整体重构进设置页，见 RootView / ProfileView）。
        }
    }

    /// 当前可见的记录是否已全部选中（用来切「全选 / 取消全选」文案）
    private var allVisibleSelected: Bool {
        !displayed.isEmpty && displayed.allSatisfy { model.selectedIDs.contains($0.id) }
    }

    /// 多选分享的记录集：按当前显示顺序（排序 / 检索后的顺序）取
    private var selectedRecords: [PickupRecord] {
        displayed.filter { model.selectedIDs.contains($0.id) }
    }

    /// 添加菜单的**内容**（同上，横排/竖排共用）
    ///
    /// 🔴 2026-11-16 主人：删掉「扫描识别添加」（扫码在离线 App 里兑换不出任何东西），
    ///    换成「拍照 / 相册识别添加」—— 与相册选图同一条端侧 OCR 链路。
    ///
    /// 🔴 2026-11-22 主人：「将粘贴解析添加的改成文本录入，将拍照/相册识别添加改成照片录入」。
    ///    动词统一成"录入"，用户一眼分清「文字 / 照片」两种喂进来的方式。
    ///    （「语音录入」那一项随语音功能整块删除，不要再加回来。）
    @ViewBuilder
    private var addMenuItems: some View {
        Button {
            model.showAdd = true
        } label: {
            Label("文本录入", systemImage: "text.alignleft")
        }

        // 相机与相册都关掉（「关于 › 使用权限」）时整项隐藏：
        // 点进去两个路子都走不通，摆在那儿只会让用户以为 App 坏了。
        if PermGate.storedIsOn(.camera) || PermGate.storedIsOn(.photos) {
            Button {
                model.showScan = true
            } label: {
                Label("照片录入", systemImage: "text.viewfinder")
            }
        }
    }

    private var filterMenu: some View {
        Button {
            showSortPanel = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选与排序")
        .popover(isPresented: $showSortPanel, arrowEdge: .top) {
            SortMenuPanel(
                current: model.sort,
                onPick: { choice in
                    choice.apply()
                    model.sort = choice.mode
                    model.bumpOrderRevision()
                    showSortPanel = false
                },
                extraAction: store.pending.isEmpty
                    ? nil
                    : (title: "全部标记为已取", isDestructive: false,
                       action: {
                           model.completeAll(in: store)
                           showSortPanel = false
                       })
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: 底部浮层（新条目提示 / 撤销）

    /// 底部提示条距底高度。
    private var overlayBottomPadding: CGFloat { 92 }

    @ViewBuilder
    private var bottomOverlay: some View {
        if let message = model.addedToast {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.doneTint)

                Text(message.L)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .appGlass(.capsule)
            .padding(.horizontal, AppTheme.hInset)
            .padding(.bottom, overlayBottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let copiedCode = model.copiedCode {
            // 复制反馈（2026-10-25）：右滑直接复制之后必须给回执，
            // 否则用户不知道到底复制上了没有。
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.accent)

                Text("已复制 \(copiedCode)")
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .appGlass(.capsule)
            .padding(.horizontal, AppTheme.hInset)
            // 24 而不是上面那两条的 92：`.overlay(alignment: .bottom)` 本来就落在
            // 标签栏之上，92 会让它悬到屏幕中间压住卡片（Duo 外屏标签栏在右侧，
            // 底部根本没有那么高的一条要避）。
            .padding(.bottom, 24)
            .allowsHitTesting(false)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if model.showUndo {
            UndoToast(message: undoMessage, actionTitle: "撤销") {
                model.undo(in: store)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.bottom, overlayBottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// 撤销条的文案按**动作**取，而不是靠 `undoRecords` 反推 ——
    /// 同一条记录在"完成"与"恢复"里长的一模一样，反推不出方向。
    private var undoMessage: String {
        switch model.undoAction {
        case .completed:
            return model.undoRecords.count > 1
                ? "已标记 \(model.undoRecords.count) 条为已取"
                : "已标记为已取"
        case .deleted:
            return model.undoRecords.first.map { "已删除 \($0.company) \($0.code)" } ?? "已删除"
        case .restored:
            return "已恢复为待取件"
        }
    }

    // MARK: 单个卡片行

    /// 首页只有待取件一种行：`PickupCard`（图标下沉码行 + 右端勾选，标记已取走右滑 / 长按）。
    @ViewBuilder
    private func row(for record: PickupRecord) -> some View {
        // 🔴 2026-11-16「一张卡片多个取件码」：代表记录 + 同组兄弟记录。
        //    卡片只画一张，但勾选 / 复制 / 分享 / 删除 / 多选全部按整组走，
        //    免得同一张卡上两个码只处理了一个，另一个变成幽灵数据。
        let group = PickupRecordGrouping.siblings(of: record, in: displayed)
        let isDone = record.isPickedUp
            || group.contains { model.completing.contains($0.id) }

        let card = rowChrome(record, group: group,
                             content: PickupCard(record: record,
                                                 isDone: isDone,
                                                 selectionState: model.selectionMode
                                                     ? model.selectedIDs.contains(record.id)
                                                     : nil,
                                                 onToggle: {
                                                     if group.count > 1 {
                                                         model.complete(group, in: store)
                                                     } else {
                                                         // 单码仍走带勾选动效的原路径
                                                         model.complete(record, in: store)
                                                     }
                                                 },
                                                 extraCodes: PickupRecordGrouping
                                                     .extraCodes(for: record, in: displayed)))
        // 分栏时右栏显示的是哪一条，左列表要看得出来（系统不会给自绘卡片画选中态）。
        if PadLayout.usesSplit, splitSelection == record.id {
            card.overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
        } else {
            card
        }
    }

    /// 行外壳：内边距、点击进详情、左右侧滑、长按菜单。
    ///
    /// 抽出来的理由：两种卡片内容要的是**同一套操作**，只有动作名随状态不同。
    /// 复制两份迟早出现「其中一份忘了改」—— 这种漂移在 UI 上极难发现
    /// （得分别左滑、右滑、长按各比一遍才看得出来）。
    ///
    /// 多选模式（2026-09-23）：点击 = 勾选/取消，侧滑与长按菜单全部停用 ——
    /// 分享流程里不该有删除这类破坏性操作混进来。链尾三件套（背景 / 分隔符 /
    /// insets）两种模式共用一份，保证写法始终在链尾。
    private func rowChrome<Content: View>(_ record: PickupRecord,
                                          group: [PickupRecord] = [],
                                          content: Content) -> some View {
        // 默认空数组 = 一码一卡（截图脚手架 / 卡片替身等调用点不用改）。
        let related = group.isEmpty ? [record] : group
        let base = content
            .contentShape(.rect)
            .onTapGesture {
                if model.selectionMode {
                    model.toggleSelection(related)
                } else {
                    // 宽屏只切右栏（不 push）、窄屏照旧推栈 —— 见 openDetail
                    openDetail(record)
                }
            }

        return Group {
            if model.selectionMode {
                base
            } else {
                // 自绘侧滑（2026-10-25）：系统 `.swipeActions` 把「卡片 ↔ 按钮」
                // 间距写死成 29pt（且 iOS 26 的圆形按钮把它放得更明显），
                // 换 `SwipeActionRow` 后间距压到 8pt，按钮宽度也归自己控制。
                //
                // 🔴 方向按主人 2026-10-25 最终定稿：
                //   · **向右滑 = 直接复制**，滑过约六成松手就复制完，不用再点按钮
                //     （高频、可重复、不破坏数据，一步到位最省事）；
                //   · **向左滑 = 展开「已取」按钮**，需再点一下确认
                //     —— 它会把记录移出待取列表，不该一个手滑就执行。
                //   删除 / 详情 / 分享在长按菜单里，一个不少。
                SwipeActionRow(
                    rowID: record.id,
                    openRowID: $openSwipeRow,
                    leading: [
                        SwipeActionItem(title: "复制", symbol: "doc.on.doc",
                                        tint: AppTheme.accent) { model.copy(related) },
                    ],
                    trailing: [
                        SwipeActionItem(title: "已取", symbol: "checkmark.circle.fill",
                                        tint: AppTheme.doneTint) {
                            if related.count > 1 {
                                model.complete(related, in: store)
                            } else {
                                model.complete(record, in: store)
                            }
                        },
                    ],
                    autoPerformSide: .leading,
                    // 截图脚手架：`SWIPE_OPEN=<序号>` 时允许把它摆成打开态
                    debugAllowsForcedOpen: ProcessInfo.processInfo.environment["SWIPE_OPEN"] != nil,
                    // `SWIPE_STRETCH=<pt>`：把第一行拉到「已超出按钮 N pt」的形变态
                    debugStretch: Self.scaffoldStretch
                ) {
                    base
                }
                // 长按菜单：按住回弹 → 卡片放大浮起 + 描边，菜单贴着卡片弹出。
                // 不再用系统 `.contextMenu` —— 它会给卡片套一层白色圆角背景板。
                .cardLongPress(for: record.id, state: cardMenu)
            }
        }
        // 🔴 **`.listRowBackground` 必须写在整条链的最末尾**（2026-09-23 实测结论）。
            //
            // 症状：统计卡区是浅灰、记录卡片区却是白，页面上下两截颜色对不上。
            // 根因是**它写在了 `.swipeActions` 前面**：`.swipeActions` 会把行容器
            // 重新包一层，写在它之前的行级 modifier 就落到了被包住的**内层**，
            // 作用不到真正的行上 —— 行便回落到 cell 默认的白色底
            // （像素采样实测：那一截左边缘是 #FFFFFF）。
            //
            // ⚠️ 中途试过"把 insets 归零、改由内容自己铺底色"，**不要走这条路**：
            //    `.listRowInsets(EdgeInsets())` 的全零值会被系统当成"没设置"，
            //    行仍回落到默认 **16pt 水平内边距** —— 内容底色只铺到 x=16…385，
            //    左右各留 16pt 白边；同时内容还要再加一份 `hInset` 的 padding，
            //    结果卡片被整整挤进去 16pt（实测左边缘 16pt → 32pt）。
            //    正解就是这一行：insets 照常给，行背景放链尾。
            .listRowBackground(AppTheme.pageBackground)
            // 🔴 行分隔符同样必须在链尾（与 listRowBackground 同一个坑）：
            //    写在 `.swipeActions` 之前会落到被重新包住的内层而失效，
            //    系统那条 0.5pt 灰线就会漏出来横在两张卡片之间
            //    （2026-09-23 主人截图指认）。
            .listRowSeparator(.hidden)
            // 🔴 **listRowInsets 也在同一张"必须链尾"名单里**（2026-09-23 探针实测）：
            //    写在 swipeActions 之前同样落内层失效 —— 卡片间距 29.3pt 改不动，
            //    根因就是它（改的值从未生效，吃的全是系统默认行边距）。
            // 挪到链尾后真正生效：上下各 7.5pt = 卡片间实距 15pt，
            // 即主人要求的"原来 29.3pt 的一半"。
            .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                      bottom: 7.5, trailing: AppTheme.hInset))
    }

    // MARK: 长按菜单

    /// 菜单内容与顺序对齐原系统菜单：复制 / 分享 / 完成 / 详情 /（分隔）删除。
    private func menuItems(for record: PickupRecord,
                           group: [PickupRecord] = []) -> [CardMenuItem] {
        // 一张卡多个码时，菜单里的每个动作都作用于**整张卡**（见 rowChrome 注释）。
        let related = group.isEmpty ? [record] : group
        return [
            CardMenuItem(title: "复制取件码",
                         symbol: "doc.on.doc",
                         action: { model.copy(related) }),
            // 分享由页面级 `.sheet` 承载（见 body 里的 shareRecords）——
            // 🔴 菜单项**不能**自己弹面板：面板的呈现者会随浮层一起被销毁。
            CardMenuItem(title: "分享卡片",
                         symbol: "square.and.arrow.up",
                         action: { SharePresenter.shared.present(related) }),
            // 多选分享：进入多选模式并预选被长按的这一整张卡（2026-09-23）
            CardMenuItem(title: "多选分享",
                         symbol: "checkmark.circle",
                         action: { model.enterSelection(startingWith: related) }),
            CardMenuItem(title: "标记为已取",
                         symbol: "checkmark.circle",
                         action: {
                             if related.count > 1 {
                                 model.complete(related, in: store)
                             } else {
                                 model.complete(record, in: store)
                             }
                         }),
            // 编辑收进了详情页（2026-10-14 主人定稿：不弹二级编辑页），
            // 菜单不再放「编辑」—— 「查看详情」进详情页后工具栏就是「编辑」。
            CardMenuItem(title: "查看详情",
                         symbol: "info.circle",
                         action: { openDetail(record) }),
            CardMenuItem(title: "删除记录",
                         symbol: "trash",
                         tint: Color(uiColor: .systemRed),
                         role: .destructive,
                         showsSeparatorBefore: true,
                         action: { model.delete(related, in: store) }),
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
                // 多码时也要画成多码，否则浮层和底下那张卡高度对不上（2026-11-16）。
                PickupCard(record: record,
                           isDone: record.isPickedUp,
                           extraCodes: PickupRecordGrouping
                               .extraCodes(for: record, in: store.records))
            }
        }
    }

    // MARK: 截图脚手架

    /// `SIMCTL_CHILD_MENU_OPEN=<序号>`：启动后自动打开列表第 N 条的菜单。
    ///
    /// 命令行无法脚本化「长按」这一手势（`simctl` 没有触摸注入接口），
    /// 而菜单的定位与高亮恰恰只有真渲染才看得出对错 —— 所以留这个后门：
    /// 走的是与长按完全相同的 `cardMenu.open(_:)`，只是触发者从手指换成定时器。
    ///
    /// `SIMCTL_CHILD_SHARE_HIT=<序号>`：菜单打开后再自动「点」一次其中的
    /// 「分享卡片」行 —— 执行的就是该行 Button 的闭包体（收起菜单 + 交出记录），
    /// 只差一次 UIKit 手势识别，而那一环与本缺陷无关（菜单里其它行都正常触发）。
    /// 用来验证「点分享 → 预览面板弹出」这条呈现链路：缺陷正是**面板根本不出现**，
    /// 而它只在真渲染时暴露，所以必须留一个可脚本化的触发入口。
    private func openMenuFromScaffold() {
        let env = ProcessInfo.processInfo.environment
        let tapsShareRow = env["SHARE_HIT"] != nil
        guard let raw = env["SHARE_HIT"] ?? env["MENU_OPEN"],
              let index = Int(raw) else { return }

        Task { @MainActor in
            // 等卡片坐标上报（最多 3 秒）：首帧布局与几何上报有先后差，
            // 开得太早会拿不到锚点 —— 菜单会落到回落位置而不是卡片旁边。
            var waited = 0
            while cardMenu.frames.isEmpty && waited < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }

            let list = displayed
            guard list.indices.contains(index) else { return }
            let record = list[index]
            cardMenu.open(record.id)

            guard tapsShareRow else { return }
            // 等菜单入场动画走完再点，否则拍到的还是菜单在飞的中间帧。
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let action = menuItems(for: record)
                .first(where: { $0.title == "分享卡片" })?.action else { return }
            cardMenu.close()   // == 手指点击该行时的 onDismiss()
            action()           // == 手指点击该行时的 item.action?()
        }
    }
}

// MARK: - 无匹配结果

struct NoResultView: View {
    let query: String

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(symbol: "magnifyingglass", tint: AppTheme.sky, size: 66)

            VStack(spacing: 6) {
                Text("没有匹配的取件信息")
                    .font(.headline)
                Text(query.isEmpty
                     ? "换个关键词试试"
                     : "没有找到包含「\(query)」的记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }
}

// MARK: - 顶部 Hero 统计卡（设计语言 v2，2026-10-14）
//
/// 「待取件」顶部的**主视觉仪表盘**，参考 Apple 健康/钱包的「大数字卡」版式：
///  · 左侧主数字：待取件数 46pt rounded bold + accent 渐变 —— 进门第一眼就是它；
///  · 右侧次级列：今日新增 / 今日已取 两行小格，各带语义色图标，退居辅助位。
/// 与旧版「三格均分」的本质区别：主次有了层级 —— 旧版三个数字一样大，
/// 用户分不清哪个才是「现在要做的事」。
/// 顶部摘要大卡：左侧一个大数字 + 右侧两格小统计。
///
/// 🔴 **一份实现、两页共用**（2026-11-15 主人）。
///    设置 › 外观与个性化 里关掉「显示「统计」」之后，底栏就没有统计入口了，
///    但统计信息不该就此消失 —— 改在**已取页顶部**放一张简要卡。
///    主人的原话是「和待取页面的卡片保持同一高度、大小」，所以这里只有一份版式：
///    待取页传待取的数据、已取页传已取的，几何完全同源。
///    ⚠️ **不要**为某一页好看另写一张 —— 差一档字号、差 2pt 内边距就"不一样大"。
struct HeroStatsCard: View {
    /// 左侧大数字（待取件数 / 累计已取件数）
    let primary: Int
    /// 大数字后面的单位（「件待取」/「件已取」）
    let primaryUnit: String
    /// 主数字渐变的两个端点（待取 accent→accentLight，已取 doneTint→doneTintLight）
    let primaryTint: Color
    let primaryTintLight: Color
    /// 右侧两格
    let stats: [SideStat]

    /// 右侧的一格小统计
    struct SideStat {
        let title: String
        let value: Int
        let tint: Color
        let symbol: String
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // —— 主数字区 ——
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(primary)")
                        .font(.system(size: AppTheme.heroNumber, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(
                            LinearGradient(colors: [primaryTint, primaryTintLight],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                    Text(primaryUnit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            // —— 次级两格 ——
            // 🔴 2026-11-08 主人：0 也要显示 —— 只留一个大数字的卡片太空了。
            VStack(alignment: .leading, spacing: 10) {
                // 用 offset 做 id：`SideStat` 是个值类型、每次求值都会重建，
                // 挂 UUID 等于每次都换身份，会让这一列反复重算。
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    sideStat(stat)
                }
            }
        }
        // 内边距与列表卡同一档（AppTheme.cardPadding / 12），保证内容左缘共线
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        // Hero 卡用独立大圆角 + 稍强的主色氛围（主色即语义色，
        // 氛围强度走统一约束，不会退化成整卡染色）
        .cardSurface(radius: AppTheme.heroRadius, tint: primaryTint)
    }

    private func sideStat(_ stat: SideStat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: stat.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(stat.tint)
            Text(stat.title.L)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(stat.value)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(stat.tint)
                .frame(minWidth: 14, alignment: .trailing)
        }
    }
}

// MARK: - 取件码卡片（卡片内可直接完成取件）

struct PickupCard: View {
    let record: PickupRecord
    let isDone: Bool
    /// 多选分享模式（2026-09-23）：nil = 常规模式；true / false = 已选 / 未选。
    /// 多选态勾选框显示在**卡片右端**（与已取页 HistoryRow 编辑态同一位置同一样式，
    /// 2026-10-20 主人定：不再把勾选叠在左侧图标上，「太难看了」）；
    /// 点按选中由整卡手势承接（rowChrome 的 onTapGesture），选择圈本身只做展示。
    var selectionState: Bool? = nil
    /// 码行右端勾选的回调：点按切换「已取 / 待取」（2026-10-20 主人要求勾选回归卡片）
    var onToggle: () -> Void = {}
    /// 同一条短信里的其它取件码（2026-11-16「一张卡片多个取件码」）。
    /// 空数组 = 一码一卡，卡片与升级前**像素级一致**；非空时码行竖排展开，
    /// 字号从 30 收到 24，图标与右端勾选仍各只有一份。
    var extraCodes: [String] = []

    /// 卡片强调色（卡面底色 / 描边 / 勾选钮 / 货架胶囊）。
    ///
    /// 🔴 2026-10-29 主人改：「快递公司是圆通、图标也是圆通，卡片颜色却不是圆通紫」——
    ///    旧口径是**短信平台优先**（拼多多发的就染成拼多多红），于是图标和码都跟着
    ///    承运方走、唯独卡面跟平台走，同一张卡出现两套品牌色。
    ///    现在统一：**卡面与图标、取件码同源**，都取「快递公司 > 驿站 > 平台」。
    private var brand: Color { iconBrand }

    /// 取件码颜色**恒跟图标主题色**（2026-10-20 主人定）：与图标（快递公司>驿站>平台）同色。
    private var iconBrand: Color { CourierBrand.color(for: titleIconSource) }

    /// 品牌图标尺寸 —— 缩小到与取件码视觉同高（码为 30pt 字号，数字实际视觉高约 22pt，
    /// 图标取 26pt 兼顾辨识度），并下沉到取件码行、与码底部持平。
    private static let iconSize: CGFloat = 26

    /// 一张卡上要画的码（主码永远在第一行）。
    private var allCodes: [String] {
        [record.code] + extraCodes.filter { $0 != record.code }
    }

    /// 驿站名称库（内置 + 用户自定义），订阅以便用户在设置页增删后卡片即时刷新
    @ObservedObject private var stationDirectory = StationDirectory.shared

    /// 卡面命名 —— **统一走 `PickupNaming`**（2026-10-28 主人：
    /// 「整个Codelumi遵循一套逻辑，而不是东一套西一套」）。
    /// 这里只提供驿站数据源（App 侧带用户自定义驿站），取名规则一处不写。
    private var naming: PickupNaming {
        #if DEBUG
        PerfProbe.count("card.naming")
        #endif
        return record.namingResolved
    }
    private var titlePrimary: String { naming.primary }
    private var titleSecondary: String? { naming.secondaryLabel }
    /// 行 1 图标匹配串随主名走 —— 与「图标 = 第一行第一个字段」同源
    private var titleIconSource: String { naming.iconSource }
    /// 快递柜格口（解析器已补全单位：「2号柜」「12-34格口」「柜A12」）。
    /// 🔴 2026-10-28 主人：有柜信息就**跟在快递驿站后面以标签形式显示**，
    /// 不单独占行 —— 到柜场景一眼能看到是几号柜，又不会把信息层撑高。
    private var lockerName: String? {
        let l = record.locker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return l.isEmpty ? nil : l
    }


    var body: some View {
        // 2026-10-19 v2：图标缩小到与取件码视觉同高，下沉到取件码行、与码底部持平；
        // 上半部分（快递公司 / 平台 / 地址）左对齐到卡片内容左缘，与图标左缘对齐。
        VStack(alignment: .leading, spacing: 0) {
                    // 行 1：主名（快递公司 > 驿站 > 平台）+「| 取件平台」+ 入库时长
                    // （2026-10-14 主人定稿：删类别标签；图标从地址行首挪到主名行首）
                    HStack(spacing: 6) {
                        Text(titlePrimary.L)
                            .font(.system(size: 15.5, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(isDone ? .secondary : .primary)

                        if let secondary = titleSecondary {
                            Text("|")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                            Text(secondary.L)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .foregroundStyle(isDone ? .tertiary : .secondary)
                        }

                        // 快递柜标签（2026-10-28 主人定）：紧跟快递驿站，胶囊样式，
                        // 与行 2 的货架胶囊同规格（10.5pt semibold / 圆角 999）。
                        // fixedSize 保证它永不被主名或驿站名挤压变形。
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

                        // 入库日期时间（2026-10-20 主人定：所有入库时间统一为日期时间格式，
                        // 不再用相对时长「已入库5天1小时40分」）
                        Text(record.shortTime.L)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // 行 2：取件地址 + 货架号标签（图标已上移行 1，不再重复）
                    if !addressLine.isEmpty || record.shelf?.isEmpty == false {
                        HStack(spacing: 6) {
                            Text(addressLine.L)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            // 货架号（参照「码上取」）：到店场景直接定位包裹的那一格
                            if let shelf = record.shelf, !shelf.isEmpty {
                                Text("货架\(shelf)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(brand)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(brand.opacity(0.14), in: .capsule)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        .padding(.top, 4)
                    }

                    // 分界虚线：把「信息层」与「取件码」划开
                    DashedDivider()
                        .padding(.top, 8)
                        .padding(.trailing, 2)

                    // 行 3：品牌图标（左，与码视觉居中）+ 取件码 + 右端勾选（点按切换已取）
                    //
                    // 🔴 2026-10-28 主人：图标「向下显示了」，要与取件码视觉垂直对齐。
                    // 原来是 `.lastTextBaseline` —— 它把 26×26 的图标**底边贴到文字基线**，
                    // 而数字字形本身就坐在基线上（无下行部），于是图标整体沉下去约 4pt
                    // （实测截图：图标 y 509–532 / 取件码 y 505–526）。
                    // 数字没有 descender，字形中心 ≈ 行框中心，所以 `.center` 才是视觉对齐。
                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            logoBlock

                            // 🔴 2026-11-16「一张卡片多个取件码」：多码时竖排，
                            //    字号统一收到 24pt，避免两个 30pt 大字把卡片撑成两层楼。
                            //    单码时仍是原来那一条 30pt，视觉零变化。
                            VStack(alignment: .leading,
                                   spacing: allCodes.count > 1 ? 1 : 0) {
                                ForEach(allCodes, id: \.self) { code in
                                    PickupCodeEmphasis.text(code, isDone: isDone,
                                                            tint: iconBrand)
                                        .font(.system(size: allCodes.count > 1 ? 24 : 30,
                                                      weight: .bold, design: .rounded))
                                        .monospaced()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                            }
                        }

                        Spacer(minLength: 6)

                        // 右端：多选分享态显示勾选圈（点卡片=选中，圈只展示）；
                        // 常规态显示「标记为已取」勾选钮（2026-10-20 主人要求勾选回归卡片）
                        if let selected = selectionState {
                            // 多选态勾选圈。🔴 高度必须与 CompleteButton 的 44pt 完全一致：
                            // 行 3 的 HStack 高度取最高子视图，右端从 44 掉到 36 会让整卡
                            // 矮 8pt —— 主人 2026-10-20 实测「一点选择卡片就变小」，
                            // 根因就在这里。热区同为 44pt 也顺手满足 HIG 最小点击区域。
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(selected ? brand : Color.secondary.opacity(0.45))
                                .frame(width: 44, height: 44)
                        } else {
                            CompleteButton(isDone: isDone, tint: brand, action: onToggle)
                        }
                    }
                    .padding(.top, 7)
        }
        // 去掉竖条后左右内边距取同一值，卡片内不再有「被竖条吃掉」的左侧偏窄感
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        // 🔴 2026-11-08 主人：卡面还是品牌色淡染好看，不要自创竖条之类的装饰。
        //    浓度由 `AppTheme.cardTintOpacity` 统一控制（已再降一档，更淡）。
        .cardSurface(tint: brand)
        .opacity(isDone && selectionState == nil ? 0.72 : 1)
    }

    /// 左侧品牌图标（下沉到取件码行，底部与码基线持平）。
    /// 2026-10-20 主人定：多选态**不再**把勾选叠在图标上（原"图标淡圈+右上角小勾"方案废弃），
    /// 勾选框统一改到卡片右端，图标回归纯展示。
    private var logoBlock: some View {
        // 图标 = 卡面第一段（快递公司 > 短信平台 > 驿站），画法统一在 `PickupIcon`。
        PickupIcon(naming: naming, size: Self.iconSize)
            .frame(width: Self.iconSize, height: Self.iconSize)
    }

    /// 平台名已单独成行，地址行只保留地址本身
    private var addressLine: String {
        record.address.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 超出免费版展示上限的提示（规格 §二 R3）

/// 「还有 N 条 · 升级后查看」提示条。
///
/// 2026-10-30 主人要求：**提示类形状的圆角给最大**（原来是 14 的 innerRadius，
/// 夹在 22 圆角的卡片中间显得像个没做完的方块）。这里直接用满圆角成胶囊，
/// 与列表卡片的 22 拉开一档 —— 提示是「另一类东西」，视觉上本就该有区别。
struct HiddenHint: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
            Text("还有 \(count) 条记录 · Codelumi Pro 可查看全部")
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .cardSurface(radius: AppTheme.capsuleRadius)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let hint: String

    init(symbol: String, title: String, hint: String) {
        self.symbol = symbol
        self.title = title
        self.hint = hint
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 7) {
                Text(title.L)
                    .font(.headline)
                Text(hint.L)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}
