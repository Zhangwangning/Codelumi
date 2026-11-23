import SwiftUI
import Combine
import PhotosUI

// MARK: ============================================================================
// Codelumi 设计系统（App 专属组件）
//
// 依据 iOS 27 Liquid Glass 官方规则落地，三条硬约束：
//
//  1) 玻璃只用于「浮在内容之上的导航层」——系统标签栏、浮动提示条、独立浮起的主操作。
//     原文：「Liquid Glass is best reserved for the navigation layer that floats above
//     the content of your app.」把玻璃用在内容卡片上会与导航层争夺层级、
//     且在「降低透明度 / 增强对比度」下退化。
//
//  2) 内容层（卡片 / 列表行 / 数据）一律实体填充，且「第二层不再叠玻璃」。
//
//  3) 颜色要注入内容层——原文：「When every element is tinted, nothing stands out…
//     imbue color into your app… in the content layer instead.」
//     所以快递公司品牌色、状态色、关键数字着色全部落在卡片内部，而不是给导航铬上色。
//
// ── 已知例外（都是主人明确要求，不是漏网） ────────────────────────────────
//  `RecordDetailView` 的顶部主卡与主操作按钮**确实用了玻璃**，与本文件第 1/2 条相悖：
//    · 卡底 = 品牌色磨砂玻璃（`BrandPalette` 渐变 + `.ultraThinMaterial`）
//      —— 这里是「以材质表达品牌身份」，不是与导航层争层级。
//    · 主按钮 = 液态玻璃（`glassEffect(.regular.tint(...).interactive())`）
//      —— 等价于系统 `.glassProminent`；已取件态退成 `.regular` 中性玻璃，因为它不是主动作。
//  两处都只出现在详情页的**唯一一张主卡**上，不构成「层层叠玻璃」。逐条理由写在
//  `RecordDetailView.swift` 文件头与 `actionGlass` 注释里。
//
// ── 与共享层的分工 ────────────────────────────────────────────────────────
//  本文件只放 **App 专属** 组件。以下几项已移至 `CodelumiShared/`，与小组件扩展共用：
//    · AppTheme / Color(hex:) / PickupKind.tint  → CodelumiShared/AppTheme.swift
//    · CourierBrand / CourierLogo                → CodelumiShared/CourierBrand.swift
// ============================================================================

// MARK: - 内容层卡片（实体填充 + 发丝描边 + 极轻投影，不使用玻璃）

struct CardSurface: ViewModifier {
    var radius: CGFloat = AppTheme.cardRadius
    var tint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // 🔴 卡片 = **白**（浅色）/ #1C1C1E（深色），页面底 = 浅灰。
                    //
                    // 2026-09-23 修正：这里原先填 `.background.secondary`，
                    // 而各列表页都开了 `.scrollContentBackground(.hidden)`，
                    // 于是渲染成「白底 + 灰卡」，与 iOS 分组列表规范正好相反。
                    // 改用 `secondarySystemGroupedBackground` —— 它就是
                    // 「分组列表里的卡片色」这条语义，浅色下为纯白，
                    // 深色下与 `.background.secondary` 同值，深色观感不变。
                    .fill(AppTheme.cardSurface)
                    .overlay {
                        if let tint {
                            // 品牌色以对角线渐变铺在卡面上：左上角颜色最足、右下角褪去。
                            // 强度受 AppTheme.cardTintOpacity 统一约束，避免退化成「整卡染色」。
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(AppTheme.cardTintOpacity * 1.7),
                                                 tint.opacity(AppTheme.cardTintOpacity * 0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // v2：描边压轻一档（0.55 → 0.4）—— 大圆角卡靠「底色差 + 柔投影」
                    // 分层已经足够，重描边会让卡片看起来「被框住」。
                    .stroke(.separator.opacity(0.4), lineWidth: 0.5)
            }
            // v2：投影更柔更大（r7→r11, y2→y3, α0.05→0.06）——
            // 大圆角卡片配大半径软投影，是 iOS 27 系统 App 的卡片质感。
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06),
                    radius: colorScheme == .dark ? 0 : 11, x: 0, y: 3)
    }
}

// MARK: - 彩色圆底图标
//
// iOS 系统 App（健康 / 健身 / 设置）里最常见的一种「着色单位」：圆形浅色底 + 同色相图标。
// 比起裸图标，它让每一块信息有自己的颜色身份，一眼可分辨，且不喧宾夺主。

struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

extension View {
    func cardSurface(radius: CGFloat = AppTheme.cardRadius,
                     tint: Color? = nil) -> some View {
        modifier(CardSurface(radius: radius, tint: tint))
    }
}

// MARK: - 设置类页面卡片（iOS 26+ 玻璃 / iOS 18 系统卡片）

extension View {
    /// 设置及其二三级页面的卡片外框。
    ///
    /// 🔴 2026-11-08 主人：设置首页已经改成玻璃卡片，二三级页也要跟上。
    /// 这里做一处开关，所有设置类页面共用：
    ///   · iOS 26+ 且「液态玻璃」开关开启 → 系统玻璃（`appGlass`）；
    ///   · 其它情况 → 原来的系统分组卡片（iOS 18 没有玻璃，硬套会发灰）。
    func settingsCard(radius: CGFloat = AppTheme.cardRadius) -> some View {
        modifier(SettingsGlassCard(radius: radius))
    }
}

private struct SettingsGlassCard: ViewModifier {
    var radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), GlassSettings.isActive {
            content.appGlass(.rect(cornerRadius: radius, style: .continuous))
        } else {
            content.cardSurface(radius: radius)
        }
    }
}

// MARK: - 卡片内直接完成取件（核心交互，无需进入详情页）

/// 圆形勾选控件：轻点即在卡片内完成 / 取消取件状态。
/// 命中区固定 44×44pt 以满足 HIG 最小可点尺寸。
struct CompleteButton: View {
    let isDone: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? tint : Color.secondary.opacity(0.5),
                                  lineWidth: 1.8)
                    .frame(width: 27, height: 27)

                Circle()
                    .fill(tint)
                    .frame(width: 27, height: 27)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .opacity(isDone ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isDone ? 1 : 0.3)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "已取件，轻点可恢复为待取件" : "标记为已取件")
    }
}

// MARK: - 类别标签（已于 2026-10-28 删除）
//
// 原来这里有个 `KindTag`：按凭证类型（取件码 / 运单号 / 尾号 / 特殊码）画彩色胶囊。
// 主人 2026-10-28 定：「Codelumi内再不区分取件码信息的类型」——
// 所有卡片、预览、编辑、通知、锁屏一律只认「取件码」，分类退化成纯后台字段，
// 于是这个组件没有任何调用点，整体删除。要恢复分类展示时别急着照抄旧样式：
// 先想清楚「用户拿到这条信息时真的需要知道它是哪类凭证吗」。

// MARK: - 虚线分隔（信息层 / 数据层的分界）

/// 一条虚线把「平台 + 地址」（信息层）与「取件码」（数据层）分开。
///
/// 取件码是整张卡片唯一需要「一眼读出」的内容。与其不断加大字号去争视觉权重，
/// 不如先用一条虚线把它单独分区 —— 分区之后即便字号只比正文大一档，
/// 眼睛也能立刻锁定它。这是成熟取件码 App 通行的信息分层手法。
struct DashedDivider: View {
    var body: some View {
        HorizontalRule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3.5, 3.5]))
            .foregroundStyle(Color.secondary.opacity(0.3))
            .frame(height: 1)
    }
}

/// 水平直线 —— 虚线的可描边载体（SwiftUI 没有内置虚线分隔视图）
private struct HorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

// MARK: - 票券撕票线（虚线 + 两侧打孔）
//
// 设计语言 v2（2026-10-14）：把普通卡片变成「票」的关键
// 就是这条撕票线 —— 虚线两侧各嵌一枚「打孔」半圆（填页面底色、外溢出卡边），
// 上下两层信息像被撕开的票根 —— 纸质票与钱包 Pass 都是这个视觉母语。
struct TicketPunchLine: View {
    /// 打孔直径（外溢一半，露出半圆缺口）
    private let punch: CGFloat = 13

    var body: some View {
        DashedDivider()
            .overlay {
                HStack(spacing: 0) {
                    Circle()
                        .fill(AppTheme.pageBackground)
                        .frame(width: punch, height: punch)
                        .offset(x: -punch / 2)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(AppTheme.pageBackground)
                        .frame(width: punch, height: punch)
                        .offset(x: punch / 2)
                }
            }
            .frame(height: punch)
    }
}

// MARK: - 支持的快递图标总览
//
// 把共享层的品牌清单可视化，既方便自查，也是「30+ 家快递覆盖」这一卖点的直观呈现。

struct CourierGalleryView: View {
    /// 「添加驿站」改成居中弹窗（2026-11-08 主人定）
    @State private var showAddStation = false
    /// 这一页管哪种东西（2026-10-27 主人：拆成「快递公司」与「驿站管理」两个模块）。
    /// 原先是**一页全包**（快递公司 / 驿站·代收平台 / 智能快递柜 / 商家 / 国际快递），
    /// 设置里只有一行「快递管理」，用户既不知道里面有什么、也不知道驿站自定义在哪。
    /// 拆开之后：承运方归 `.courier`，取件地点归 `.station`，各自只显示自己那几类和自己的说明。
    enum Scope {
        /// 承运方：快递公司 / 国际快递 / 商家·电商
        case courier
        /// 取件地点：驿站·代收平台 / 智能快递柜（含自定义驿站增删）
        case station

        var categories: [CourierBrand.Category] {
            switch self {
            case .courier: [.company, .international, .merchant]
            case .station: [.station, .locker]
            }
        }

        var title: String {
            switch self {
            case .courier: "快递公司"
            case .station: "驿站管理"
            }
        }
    }

    var scope: Scope = .courier

    /// 截图脚手架用：指定则进入后直接滚到该分类（分类越来越多，一屏放不下）
    var anchor: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    /// 驿站名称库（2026-10-14 集成进本页）：自定义增删后页面即时刷新
    @ObservedObject private var station = StationDirectory.shared
    /// 驿站位置库（2026-11-16 到达提醒）：设过位置的格子要即时显示角标
    @ObservedObject private var locationStore = StationLocationStore.shared
    /// 驿站组（2026-11-17）。刻意不是 `ObservableObject`：组的读写都走共享文件，
    /// 页面在 `onAppear` / 从编辑页返回时重读一次即可，多一层观察者反而容易出现
    /// 「两份内存状态谁覆盖谁」的回滚问题（小组件勾选那次踩过）。
    @State private var groups: [StationGroup] = []
    /// 驿站管理搜索（2026-11-21）：34 个内置 + 自定义 + 组，滑两屏才找得到，
    /// 直接给一个搜索框比再加说明文字有用。
    @State private var query: String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onAppear {
                guard let anchor else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
        .navigationTitle(scope.title)
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
        // 添加驿站：居中弹窗，不再推入独立页面
        .overlay {
            if showAddStation { stationAddOverlay }
        }
        .animation(.snappy(duration: 0.22), value: showAddStation)
        .onAppear {
            // 截图脚手架：SCREEN=gallery 时用 STATION_ADD_DEMO=1 直接把弹窗亮起来
            if ProcessInfo.processInfo.environment["STATION_ADD_DEMO"] == "1" {
                showAddStation = true
            }
            // 组与排序都在这里重读：从编辑页 pop 回来也会触发，建组 / 改组立刻可见
            groups = StationGroupStore.all()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 2026-11-21 主人：「提示文字能少则少」。驿站页原来顶着一张
            // 「内置 34 个取件地点图标 + 两句说明」的大卡，占掉半屏却没人看，
            // 换成搜索框 —— 34 个格子 + 自定义 + 组，滑两屏才找得到才是真问题。
            if scope == .station {
                searchField
            } else {
                summary
            }

            // 2026-11-17 主人：「驿站管理里面再添加一个驿站内排序」。
            // 放在最上面 —— 它是常用设置，不该埋在几十个格子的下面。
            if scope == .station {
                groupSection
            }

            ForEach(scope.categories) { category in
                let items = visibleItems(in: category)
                // 驿站分类即使全部被归组也要保留 —— 里面有「添加驿站」格子和空态引导；
                // 快递公司分类空了就整段不渲染。
                if !items.isEmpty || (scope == .station && category == .station) {
                    categoryGrid(category, items: items)
                }
            }

            if scope == .station, !groupedMembers.isEmpty {
                groupedMemberSection
            }

            if scope == .courier {
                Text("品牌图标版权归各公司所有，此处仅用于标识取件来源。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppTheme.hInset)
        .padding(.top, 8)
        .padding(.bottom, 110)
    }

    /// 一个分类的网格。驿站分类里已被归组的格子会被过滤掉（移到页面底部的
    /// 「已归入驿站组」段），快递公司分类不过滤。
    @ViewBuilder
    private func categoryGrid(_ category: CourierBrand.Category,
                              items: [CourierBrand.Info]) -> some View {
        let ungroupedCustoms = scope == .station
            ? StationGroupStore.ungroupedNames(in: station.customNames).filter(matchesQuery)
            : []

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(category.rawValue.L)
                    .font(.footnote.weight(.semibold))
                // 驿站分类把「还没归组」的自定义格子数并进去（网格里实际有几格就显示几）
                Text(category == .station
                     ? "\(items.count + ungroupedCustoms.count)"
                     : "\(items.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                // 驿站分类第一格 = 添加入口（驿站图标 + 加号）；
                // 其后跟用户自定义的驿站，最后才是内置品牌。
                // （2026-10-14 主人定稿：驿站管理融进网格，不要顶部列表）
                if category == .station {
                    addStationCell
                    ForEach(ungroupedCustoms, id: \.self) { name in
                        customStationCell(name)
                    }
                }
                ForEach(items) { item in
                    if scope == .station {
                        // 内置驿站：名称 / 图标只读，但**位置可以自己设**
                        // （2026-11-16 主人：「我们内置的也要支持这个功能」）
                        NavigationLink {
                            StationLocationEditor(stationName: item.name)
                        } label: {
                            brandCell(item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.name)，轻点设置位置")
                    } else {
                        brandCell(item)
                    }
                }
            }
            .padding(14)
            .settingsCard()
        }
        .id(category.rawValue)
    }

    // MARK: 驿站内排序 —— 已删除（2026-11-23）
    //
    // 老大定：组内**永远按取件码 0-9、A-Z 升序**，不再提供四档设置。
    // 少一个设置项，用户就不用去想"我上次选的是哪个"。

    // MARK: 驿站组（2026-11-17 主人）
    //
    // 老大定的三段优先级：**组驿站 > 未归组驿站 > 组内成员**。
    // 页面上就按这个顺序平铺：组段在最前，原有分类网格居中（已归组的格子被剔掉），
    // 已归组成员灰显在最末 —— 不折叠，折叠会让成员看起来像被删了。

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.violet)
                Text("驿站组")
                    .font(.footnote.weight(.semibold))
                Text("\(groups.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                addGroupCell
                ForEach(groups.filter { matchesQuery($0.name) }) { group in
                    groupCell(group)
                }
            }
            .padding(14)
            .settingsCard()

            Text("组＝一个取件地点。一个驿站只在一个组里，个别件可在详情页单独指定。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addGroupCell: some View {
        NavigationLink {
            StationGroupEditView(mode: .create)
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 54 * 0.29, style: .continuous)
                    .fill(AppTheme.violet.opacity(0.12))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(AppTheme.violet)
                    }

                Text("新建驿站组")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.violet)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新建驿站组")
    }

    private func groupCell(_ group: StationGroup) -> some View {
        NavigationLink {
            StationGroupEditView(mode: .edit(group.id))
        } label: {
            VStack(spacing: 7) {
                StationLogo(name: group.name, size: 54, showsShadow: false)
                    .overlay(alignment: .topTrailing) {
                        if groupArrivalEnabled(group) { locationBadge }
                    }
                    .overlay(alignment: .bottomLeading) {
                        // 成员数（2026-11-21）：不用点进去就知道这个组装了几家
                        if !group.memberIDs.isEmpty {
                            Text("\(group.memberIDs.count)")
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(AppTheme.violet, in: .capsule)
                                .offset(x: -3, y: 3)
                        }
                    }
                Text(group.name.L)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.name)，轻点编辑驿站组")
    }

    private func groupArrivalEnabled(_ group: StationGroup) -> Bool {
        let key = StationGroupStore.locationSourceName(for: group)
        return locationStore.location(for: key)?.enabled == true
    }

    /// 已被归组的成员（含内置与自定义），带所属组 ID 供点击回组。
    ///
    /// 2026-11-21：多组共享之后同一个驿站可能出现在**多个**组里，
    /// 这里按 (驿站, 组) 展开 —— 一格一个组，点哪个回哪个，
    /// 否则跨组的驿站会整条消失（`memberIndex()` 多组时给 nil）。
    private var groupedMembers: [(name: String, groupID: String, groupName: String)] {
        let candidates = CourierBrand.items(in: .station).map(\.name)
            + CourierBrand.items(in: .locker).map(\.name)
            + station.customNames
        let map = StationGroupStore.groupsByMember()
        var out: [(name: String, groupID: String, groupName: String)] = []
        for name in candidates {
            for group in map[name] ?? [] where group.name != name {
                out.append((name, group.id, group.name))
            }
        }
        return out
    }

    private var groupedMemberSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("已归入驿站组")
                    .font(.footnote.weight(.semibold))
                Text("\(groupedMembers.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(groupedMembers.filter { matchesQuery($0.name) }, id: \.groupID) { item in
                    NavigationLink {
                        StationGroupEditView(mode: .edit(item.groupID))
                    } label: {
                        VStack(spacing: 7) {
                            StationLogo(name: item.name, size: 54, showsShadow: false)
                            // 2026-11-21 起一个驿站只属于一个组，格子里不再缀组名
                            // （缀上会折成三行，还显得像两套东西）。
                            Text(item.name.L)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(height: 26, alignment: .top)
                        }
                        // 灰显：成员还在，但已经不单独出现在待取 / 已取页
                        .opacity(0.55)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name)，已归入「\(item.groupName)」，轻点回到组")
                }
            }
            .padding(14)
            .settingsCard()
        }
        // 截图脚手架 `GALLERY_ANCHOR=groupedMembers` 可以直接滚到这一段
        .id("groupedMembers")
    }

    /// 某一分类下**还没归组**的驿站。快递公司分类不过滤。
    private func visibleItems(in category: CourierBrand.Category) -> [CourierBrand.Info] {
        let items = CourierBrand.items(in: category)
        guard scope == .station else { return items }
        let grouped = Set(StationGroupStore.groupedNames(in: items.map(\.name)))
        return items
            .filter { !grouped.contains($0.name) }
            .filter { matchesQuery($0.name) }
    }

    /// 驿站搜索框（2026-11-21）
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("搜索驿站或驿站组", text: $query)
                .font(AppTheme.TypeScale.rowTitle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // 🔴 2026-11-23 老大：「搜索框圆角和整体不兼容」——
        //    原来用 innerRadius(14)，而周围卡片是 cardRadius(22)，摆在一起像两个体系。
        .settingsCard(radius: AppTheme.cardRadius)
    }

    /// 搜索词是否命中（空查询全部命中）
    private func matchesQuery(_ name: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return name.localizedStandardContains(q)
    }

    private var summary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((scope == .courier ? AppTheme.accent : AppTheme.indigo).opacity(0.13))
                    .frame(width: 52, height: 52)
                Image(systemName: scope == .courier ? "shippingbox.fill" : "storefront.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(scope == .courier ? AppTheme.accent : AppTheme.indigo)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scope == .courier
                     ? "内置 \(courierCount) 个承运方图标"
                     : "内置 \(stationCount) 个取件地点图标")
                    .font(.subheadline.weight(.semibold))
                Text(scope == .courier
                     ? "未收录的快递按名称自动生成图标"
                     : "驿站名称可自定义，添加后按名字自动匹配短信里的取件地点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .settingsCard()
    }

    /// 承运方品牌数（三个分类合计）
    private var courierCount: Int {
        Scope.courier.categories.reduce(0) { $0 + CourierBrand.items(in: $1).count }
    }

    /// 取件地点品牌数（驿站 + 快递柜）
    private var stationCount: Int {
        Scope.station.categories.reduce(0) { $0 + CourierBrand.items(in: $1).count }
    }

    // MARK: 品牌网格格子

    /// 已启用到达提醒的驿站，右上角挂一枚紫色定位角标（54pt 图标不额外占位）
    private var locationBadge: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.violet)
            .background(Color(.systemBackground), in: .circle)
            .offset(x: 5, y: -5)
    }

    /// 内置品牌格子（全分类通用）
    ///
    /// 🔴 网格里 **53+ 个图标全部关掉投影**（`showsShadow: false`）：
    /// 投影是离屏渲染，滚动时每帧要为每个可见图标重算一遍，
    /// 主人反馈「快递公司 / 驿站管理一点开就掉帧严重」——根因就在这里。
    /// 54pt 图标压在白色卡面上，投影本来就几乎看不见，关掉无观感损失。
    private func brandCell(_ item: CourierBrand.Info) -> some View {
        VStack(spacing: 7) {
            CourierLogo(info: item, size: 54, showsShadow: false)
                .overlay(alignment: .topTrailing) {
                    if scope == .station, locationStore.location(for: item.name)?.enabled == true {
                        locationBadge
                    }
                }
            Text(item.name.L)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 26, alignment: .top)
        }
    }

    /// 驿站分类第一格：**添加入口** —— 圆角矩形（与内置图标同圆角同尺寸）+ 中心十字。
    /// 刻意与 brandCell 完全同构（VStack：54pt 方块 + 双行文字位）—— LazyVGrid 里
    /// 结构差异过大的格子会算错 ideal size，曾有复杂版式被整格跳过不渲染。
    /// 点按 → 独立编辑页（名称 + 图标同页填，2026-10-15 主人定稿）。
    private var addStationCell: some View {
        Button {
            showAddStation = true
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 54 * 0.29, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                Text("添加驿站")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加自定义驿站")
    }

    /// 添加驿站的居中弹窗（蒙层 + 玻璃卡）
    private var stationAddOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { showAddStation = false }

            StationAddDialog { showAddStation = false }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    /// 自定义驿站格子：有自定义图标显示图片（统一圆角矩形），没有则按名兜底图标；
    /// 点按 → 独立编辑页（改名 / 换图 / 删除同页）
    private func customStationCell(_ name: String) -> some View {
        NavigationLink {
            StationEditView(mode: .edit(name))
        } label: {
            VStack(spacing: 7) {
                StationLogo(name: name, size: 54, showsShadow: false)
                    .overlay(alignment: .topTrailing) {
                        if locationStore.location(for: name)?.enabled == true {
                            locationBadge
                        }
                    }
                Text(name.L)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)，轻点编辑")
    }
}

// MARK: - 自定义驿站图标（有图用图、无图兜底，统一圆角矩形）

/// 自定义驿站格子 / 卡片上的驿站图标。
/// 2026-10-15 主人定稿：自定义驿站支持上传图标，「无论上传什么图片，
/// 都以圆角矩形显示」—— 图片分支与兜底分支走同一套圆角（0.29×size）与描边，
/// 保证网格里任何来源的图标观感一致。
struct StationLogo: View {

    let name: String
    var size: CGFloat = 54
    /// 是否画投影（2026-10-28 加，同 `CourierLogo`）：网格里关掉，单处展示保留
    var showsShadow: Bool = true

    /// 订阅图标增删（相册选完即时刷新）
    @ObservedObject private var station = StationDirectory.shared

    private var corner: CGFloat { size * 0.29 }

    /// 组驿站的图标：**继承成员**优先 → 组自己的图（key = 组 ID）→ 名称首字兜底。
    ///
    /// ⚠️ 继承成员时要分两路取图：成员可能是**内置品牌**（图标在 `CourierBrand`
    /// 资源里，走 `CourierLogo`），也可能是**自定义驿站**（图标在 `iconFiles` 里）。
    /// 只查 `iconImage` 会让「继承菜鸟驿站」落空、最后按组名首字画出来
    /// （第一次截图就踩到了：「恒大御府驿站」显示成「恒」）。
    @ViewBuilder
    var body: some View {
        if let group = StationGroupStore.group(named: name) {
            if let memberID = group.iconInheritMemberID,
               let memberName = StationIdentity.name(for: memberID) {
                if let image = station.iconImage(for: memberName) {
                    iconView(Image(uiImage: image))
                } else {
                    CourierLogo(company: memberName, size: size, showsShadow: showsShadow)
                }
            } else if let image = station.iconImage(for: group.id) {
                iconView(Image(uiImage: image))
            } else {
                CourierLogo(company: group.name, size: size, showsShadow: showsShadow)
            }
        } else if let image = station.iconImage(for: name) {
            iconView(Image(uiImage: image))
        } else {
            CourierLogo(company: name, size: size, showsShadow: showsShadow)
        }
    }

    /// 自定义图片的统一外壳：圆角矩形 + 细描边 +（可选）投影
    @ViewBuilder
    private func iconView(_ image: Image) -> some View {
        let base = image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.primary.opacity(0.10), lineWidth: 0.5)
            }
        // 与 CourierLogo 的投影同规格，有图无图观感一致；
        // 网格里传 false —— 几十个离屏阴影就是滚动掉帧的元凶。
        if showsShadow {
            base.shadow(color: .black.opacity(0.28),
                        radius: size * 0.14, x: 0, y: size * 0.06)
                .accessibilityLabel("\(name) 的自定义图标")
        } else {
            base.accessibilityLabel("\(name) 的自定义图标")
        }
    }
}

// MARK: - 一条短信的图标（唯一入口）

/// 「这条短信的图标」—— **全 App 唯一实现**。
///
/// 🔴 老大 2026-11-22 原话：「一条短信中，不管是待取卡、已取卡、详情页、分享卡、添加页、
///    锁屏/灵动岛、小组件中，图标都必须遵循同一套规则，那就是图标就是当前显示在
///    最前面的那一个（三个字段中谁在前面了，图标就显示谁的）」。
///
/// 规则本身只有一条，已经收在 `PickupNaming` 里：
/// ```
/// primary = 快递公司(courier) → 短信平台(company) → 快递驿站(station)
/// iconSource = primary          // 恒等于第一段，不存在第二套
/// ```
/// 这个组件负责的是**画法**：第一段若是驿站就交给 `StationLogo`（能用用户上传的自定义图、
/// 组驿站继承成员图），否则交给 `CourierLogo` 按品牌取图。
///
/// 以前这段 `if isStationPrimary { StationLogo } else { CourierLogo }` 在待取卡、已取卡、
/// 详情页、分享卡里**各抄了四五遍**，添加页干脆漏了驿站分支 —— 于是同一个「自定义驿站」
/// 在列表里画兜底箱子、在分享卡里画用户上传的图。抄写出现分歧只是时间问题，
/// 所以收成这一个组件：以后要么调用它，要么就是 bug。
///
/// ⚠️ 跨进程边界（小组件 / 锁屏实时活动）：那里不能读 `StationDirectory`
///    （依赖 `.standard` UserDefaults + App 沙盒里的 `StationIcons/` 图片），
///    所以走 `CourierLogo(..., usesStaticAsset: true)` —— 取名口径仍是同一个 `primary`，
///    内置驿站 / 快递公司的图标都能出图；只有「用户自己上传的自定义驿站图」跨进程取不到，
///    会退到品牌兜底。这是平台限制，不是两套规则。
struct PickupIcon: View {

    let naming: PickupNaming
    var size: CGFloat = 26
    var showsShadow: Bool = true
    /// 跨进程渲染（小组件 / 锁屏 / 灵动岛）时传 true —— 见上面的边界说明
    var usesStaticAsset: Bool = false

    var body: some View {
        if naming.isStationPrimary, let station = naming.station, !usesStaticAsset {
            StationLogo(name: station, size: size, showsShadow: showsShadow)
        } else {
            CourierLogo(company: naming.iconSource,
                        size: size,
                        showsShadow: showsShadow,
                        usesStaticAsset: usesStaticAsset)
        }
    }
}

// MARK: - 复制取件码按钮（内容层实体着色，不叠玻璃）

struct CopyCodeButton: View {
    let isCopied: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isCopied ? .white : tint)
                .frame(width: 34, height: 34)
                .background {
                    Circle().fill(isCopied ? tint : tint.opacity(0.15))
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCopied ? "已复制取件码" : "复制取件码")
    }
}

// MARK: - 分组标题

/// 「实验室」标记（2026-11-22 主人：「把所有实验室功能的都改成一样的标签来标记」）。
///
/// 🔴 **全 App 唯一真源**：文案、字号、配色、内边距都只在这里定义。
///    任何页面要标"实验性"都必须用这一枚，不要再手写 `Text("实验室")` 或
///    往标题里拼「实验室 · 」前缀 —— 那样三个地方会长出三种样子。
///
/// 用在：通知 › 到达提醒 / 使用教程 › 截屏收件 /
///      驿站位置编辑页。凡 `SectionHeader(isLab: true)` 都是它。
struct LabBadge: View {
    var body: some View {
        Text("实验室")
            .font(AppTheme.TypeScale.badge)
            .foregroundStyle(AppTheme.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(AppTheme.amber.opacity(0.15), in: .capsule)
            .accessibilityLabel("实验室功能")
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    /// 可选彩色前置图标：给分区一个颜色身份（标题本身仍保持次级灰，避免整屏都在喊）
    var symbol: String? = nil
    var tint: Color? = nil
    /// 标题后面挂「实验室」徽章（统一标记，见 `LabBadge`）
    var isLab: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol, let tint {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title.L)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            if isLab {
                LabBadge()
            }
            if let trailing {
                Text(trailing.L)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }
}

// MARK: - 时间分组的颜色身份（首页分区标题使用）

extension DayGroup {
    var tint: Color {
        switch self {
        case .today: AppTheme.accent
        case .yesterday: AppTheme.todayTint
        case .earlier: AppTheme.violet
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .yesterday: "clock.fill"
        case .earlier: "calendar"
        }
    }
}

// MARK: - 浮动操作提示条（浮在内容之上 → 这里用玻璃是符合规则的）

struct UndoToast: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.doneTint)

            Text(message.L)
                .font(.subheadline)

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .appGlass(.capsule)
    }
}

// MARK: - 顶栏矢量图标（添加 / 扫描）
//
// 两个图标都按设计稿给定的 48×48 网格逐点还原，而不是拿相近的 SF Symbol 顶上 ——
// 「三条等长文本行」「圆圈加号」这些细节正是它们与其他同类别图标的区别所在。
//
// 颜色一律不写死：Shape 只负责描边，颜色由 `foregroundStyle` 决定。
// 放进顶栏后与相邻的「筛选」一样走系统默认前景色，因此深浅色模式自动切换，
// 也与系统图标尺寸口径一致。
//
// 尺寸统一走同一个 `size`：内容占位按各自设计稿的比例换算（扫描框 36/48、
// 圆 40/48），线宽同样按 4/48 换算 —— 所以两个图标并排时粗细与重量是一致的。

/// 设计稿统一的 48×48 网格 → 实际尺寸换算
private struct GlyphGrid {
    private let origin: CGPoint
    private let scale: CGFloat

    init(rect: CGRect) {
        scale = min(rect.width, rect.height) / 48
        origin = rect.origin
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func box(x: CGFloat, y: CGFloat, side: CGFloat) -> CGRect {
        CGRect(x: origin.x + x * scale, y: origin.y + y * scale,
               width: side * scale, height: side * scale)
    }
}

// MARK: 添加（圆圈 + 十字）

struct AddGlyph: View {
    var size: CGFloat = 21
    var lineWidth: CGFloat { size * 4 / 48 }

    var body: some View {
        AddGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: lineWidth,
                                       lineCap: .round,
                                       lineJoin: .round))
            .frame(width: size, height: size)
    }
}

private struct AddGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = GlyphGrid(rect: rect)
        var path = Path()

        // 外圆：设计稿圆心 (24,24)、直径 40
        path.addEllipse(in: grid.box(x: 4, y: 4, side: 40))

        // 十字
        path.move(to: grid.point(24, 16))
        path.addLine(to: grid.point(24, 32))
        path.move(to: grid.point(16, 24))
        path.addLine(to: grid.point(32, 24))

        return path
    }
}

// MARK: - 带强调的文案
extension String {
    /// 把文案里的 `**重点**` 渲染成真正加粗的富文本。
    ///
    /// ⚠️ 直接用 `Text(某个 String 变量)` **不会**解析 Markdown ——
    /// 那条路径只对编译期字面量生效，从变量传进来的字符串会把 `**` 原样显示给用户
    /// （已在自动化引导页真实复现）。所以凡是含强调标记的文案，一律走这里。
    var richText: AttributedString {
        (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
    }
}

// MARK: - 视图模型（局部状态统一放在 ObservableObject 里）
//
// 说明：这样写是为了让工程在「Xcode GUI」与「命令行 xcodebuild」两条链路下
// 都能编译——本机 Xcode 27 beta 的 swift-plugin-server 在命令行下对 SwiftUI 宏
// （#Preview / @State）返回 malformed response。避开宏之后，单一代码库即可双跑，
// 不必再维护一份改写副本。

final class CopyFeedbackModel: ObservableObject {
    @Published var copied = false
    private var resetTask: Task<Void, Never>?

    func flash() {
        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { copied = false }
        }
    }
}

// MARK: - 分栏占位（宽屏 · iPhone Duo 展开态）

/// 分栏布局下详情列的空态：还没点选任何记录时显示。
///
/// 只在 `horizontalSizeClass == .regular`（Duo 展开态 / iPad）出现；
/// 常规 iPhone 走单栈，永远不会渲染到这个视图。
struct SplitDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("未选择取件码", systemImage: "rectangle.split.2x1")
        } description: {
            Text("从左侧列表点选一条，详情会显示在这一栏。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.pageBackground)
    }
}

/// 分栏右栏的「非 Pro · 搜索态」占位（2026-11-16 主人）。
///
/// 背景：非 Pro 用户可以用搜索查到任意一条已取 / 待取记录，但**点不开详情**
/// （详情是 Codelumi Pro 的权益）。窄屏下点击会被拦下来弹订阅页；分栏右栏这块
/// 常驻区域没有"点击"这个动作可拦 —— 它会自动渲染第一/选中那条，
/// 所以必须在这里换成锁定说明，否则一搜就把详情白送了。
struct ProLockedSplitPlaceholder: View {
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.tertiary)

            Text("详情需要 Codelumi Pro")
                .font(AppTheme.TypeScale.rowTitleMedium)

            Text("免费版可以搜索并看到记录，打开详情需要解锁。")
                .font(AppTheme.TypeScale.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onUnlock) {
                Text("了解 Codelumi Pro")
                    .font(AppTheme.TypeScale.bodyMedium)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.pageBackground)
    }
}

// MARK: - 动效（2026-11-14 主人：把 0.3s ease 换成苹果那种"有肉感"的弹簧）
/// 全 App 动效统一出口。
///
/// 为什么不用 `.easeInOut(duration: 0.3)`：
/// · 固定时长 + 固定贝塞尔**忽略手势松手瞬间的速度**——慢慢拖和甩一下，动画一模一样，
///   这就是"AI 味"最明显的来源；
/// · 到边界是硬停，没有回弹。
///
/// 苹果用的是**弹簧物理**（mass / stiffness / damping）。真正决定"肉不肉"的是
/// **阻尼比** ζ = damping / (2·√(stiffness·mass))：
///   ζ < 1  → 会来回晃（过冲）；
///   ζ = 1  → 临界阻尼，平稳停住；
///   ζ ≈ 0.8–0.9 → 一下到位、末端微微收住，就是系统控件的观感。
///
/// SwiftUI 的 `.spring(response:dampingFraction:)` 里，`response` ≈ 一次完整
/// 响应的秒数（越小越"紧"），`dampingFraction` 就是 ζ。所以这里不写 duration，
/// 只给"多快 + 多稳"两个物理量。
enum AppMotion {
    /// 常规界面变化（开关、行高亮、卡片显隐）。ζ=0.86：到位快、末端收得住。
    static let standard = Animation.spring(response: 0.34, dampingFraction: 0.86)

    /// 轻量反馈（复制提示、按钮状态）。比 standard 更快，仍然带一点回弹。
    static let quick = Animation.spring(response: 0.26, dampingFraction: 0.84)

    /// 面板 / 浮层进出（分享面板、长按菜单、弹窗）。ζ 稍低 → 有可见的一下"落地"。
    static let panel = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// 纯平滑、不要任何过冲（进度、旋转等连续量）。
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 1.0)

    /// 跟手手势收尾：把手势速度带进弹簧，松手快就冲得快、慢慢拖就稳稳停。
    /// - Parameters:
    ///   - velocity: 手势结束时的速度（pt/s），直接来自 `DragGesture.Value.predictedEndTranslation`
    ///   - base: 基准动画，默认 `panel`
    static func interactive(velocity: CGFloat, base: Animation = panel) -> Animation {
        // 速度越大，response 越短（更"冲"）；夹在 0.22…0.42 之间，避免甩一下飞出去。
        let v = min(abs(velocity), 2_400)
        let response = max(0.22, 0.42 - Double(v / 2_400) * 0.18)
        return .spring(response: response, dampingFraction: 0.82)
    }

    /// 连续量（计数、进度、进度条）用这个：不晃、稳。
    static func numeric(duration: Double = 0.32) -> Animation {
        .spring(response: duration, dampingFraction: 1.0)
    }
}
