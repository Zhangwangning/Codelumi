import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 小组件（我的 › 设置 › 二级页）
//
// 🔴 **2026-11-22 形态重构**（主人）：
//   ① 「桌面小组件中上面的显示内容的几个开关就不要了，我们直接可以内置多个不同尺寸
//      的小组件，当前显示不同内容的小组件我们根据尺寸做好，用户直接选择对应的添加就行」；
//   ② 「设置中桌面小组件的不同改成小组件，点击进去就是……默认显示所有尺寸的小组件，
//      双列宽高一致的不同尺寸的小组件，最上面显示精选也默认推荐中尺寸的小组件，
//      然后顶部左侧做一个更多的按钮，点击后可以切换显示不同尺寸的小组件」。
//
// 所以这一页 = **款式探索页**（系统小组件库那种形态）：
//   · 双列网格，卡片等宽等高 —— 缩略图区恒为正方形，八款摆在屏幕上一样齐；
//   · 顶部「精选」放**中尺寸**两款（一页 3 条，信息量与桌面可用面积最匹配，
//     是默认推荐形态）；「推荐」放其余六款；
//   · 左上角「更多」→ 按尺寸筛选（全部 / 小 / 中 / 大 / 超大）。
//   · 点卡片进**款式详情**：等比实际尺寸渲染 + 名称 + 简介 + 两个背景开关。
//
// 🔴 缩略图为什么用 `scaleEffect` 等比缩小、而不是另写一套小字号版式：
//    真实小组件 158~690pt 宽，缩到 ~170pt 后取件码已经看不清了，这是**缩略图**的
//    代价，不是缺陷 —— 它的职责是让人一眼分出「横条 / 方块 / 长条」和大致内容密度。
//    另写一套版式则一定会与桌面漂移（历史上「设置页看着好好的、桌面却不一样」
//    就是这么来的）。要看细节，点进详情页，那里按实际尺寸渲染。
//
// 🔴 背景开关是**全局**的，不是每款一套：背景是「桌面小组件长什么样」的整体偏好，
//    八款各设一遍毫无意义，同一屏并列材质不统一还会很脏。详情页只是它的入口。
//
// ⚠️ 改完必须 `reloadAllTimelines()` —— 否则桌面还是旧画面，用户会以为设置坏了。
// ============================================================================

// MARK: - 尺寸筛选

/// 「更多」菜单里的尺寸筛选项。
enum WidgetSizeFilter: String, CaseIterable {
    case all
    case small
    case medium
    case large
    case extraLarge

    var title: String {
        switch self {
        case .all: "全部尺寸"
        case .small: "小尺寸"
        case .medium: "中尺寸"
        case .large: "大尺寸"
        case .extraLarge: "超大尺寸"
        }
    }

    func matches(_ preset: WidgetPreset) -> Bool {
        switch self {
        case .all: true
        case .small: preset.family == .systemSmall
        case .medium: preset.family == .systemMedium
        case .large: preset.family == .systemLarge
        case .extraLarge: preset.families.contains(.systemExtraLarge)
        }
    }
}

// MARK: - 探索页

struct WidgetSettingsView: View {
    @State private var filter: WidgetSizeFilter = .all
    /// 内容区实测宽度 —— 双列卡片宽度由它算，不写死屏宽（iPad 上会散架）。
    @State private var contentWidth: CGFloat = 0

    /// 两列之间的间距（2026-11-22 主人：**8pt**，此前 24pt）。
    /// 卡片本身不动结构，靠缩窄列宽让出这段间距。
    /// 8pt 很窄，两列白卡几乎并在一起 —— 靠卡片自身的圆角 20 与背景色差分离，
    /// 不再靠缝隙宽度分离（主人要的就是「贴紧但仍是两张卡」）。
    private static let columnSpacing: CGFloat = 8
    /// 行间距（2026-11-22 主人：「两行卡片的上下间距也缩小为12pt」→ **12pt**）。
    /// 与列间距 8pt 一横一竖，差 4pt：横向要「贴紧成排」，纵向要「分得开组」，
    /// 两个都取 8 会让行与行糊成一片。
    private static let rowSpacing: CGFloat = 12

    /// 每列宽度。
    ///
    /// 🔴 `contentWidth` 是**已经加过左右 padding 的**宽度 —— `onGeometryChange`
    ///    挂在 `.padding(.horizontal, hInset)` 外层，量到的是 ScrollView 的内容宽
    ///    （440pt 屏 = 440）。所以这里必须自己减掉两侧 `hInset`。
    ///
    ///    2026-11-22 实测抓到的 bug：没减之前列宽算成 208pt，
    ///    两列 416 + 24 间距 = 440 —— 右列直接顶出屏幕右缘，
    ///    左侧该有的 24pt 也全被吃掉（量像素时白边只有 18pt，剩下的是阴影）。
    ///
    ///    **列数可变**（2026-11-22 主人：「小尺寸的小组件一行四个」）：
    ///    小尺寸一行 4 个、其余一行 2 个，列数变了列宽必须跟着重算，
    ///    不能拿 2 列算出的宽度去排 4 列（会溢出屏幕）。
    private func cardWidth(columns: Int) -> CGFloat {
        let usable = (contentWidth > 0 ? contentWidth : 440) - AppTheme.hInset * 2
        let gaps = CGFloat(max(1, columns) - 1) * Self.columnSpacing
        return max(48, (usable - gaps) / CGFloat(max(1, columns)))
    }

    /// 精选位 —— **固定最多 4 个，目前只推荐中尺寸**（2026-11-21 主人）：
    /// 「精选只放四个，没有就先放两个」+「精选目前只推荐中尺寸」。
    ///
    /// 所以现在是 2 个（中尺寸只有两款），`prefix(4)` 是留给以后的天花板 ——
    /// 中尺寸款式变多时不用改代码，满 4 个自动停。
    /// 为什么是中尺寸：一页 3 条，信息量与桌面可用面积最匹配，是默认推荐形态。
    private var featuredPresets: [WidgetPreset] {
        Array(WidgetPreset.libraryAll.filter { $0.family == .systemMedium }.prefix(4))
    }

    /// 分区。
    ///
    /// 🔴 **一行里只能有一种尺寸**（2026-11-21 主人当场指出）：把所有款式塞进一个
    ///    网格时，`LazyVGrid` 按顺序两两成行，会排出「大尺寸挨着超大尺寸」这种行 ——
    ///    两张卡一高一矮，看着就是错的。所以按尺寸各自成组、各用一个网格。
    ///
    /// 🔴 **精选之下，尺寸分类必须完整**（2026-11-21 主人：「下面小尺寸完了应该是
    ///    中尺寸，为啥不放呢」）：精选只是**推荐位**，不代替分类。
    ///    中尺寸进了精选，下面照样要有「中尺寸」这一组 ——
    ///    推荐位与分类列表重复出现同一款，是系统图库 / App Store 都有的常规做法。
    ///
    /// 筛了某个尺寸时只出一个分区，标题就是那个尺寸名 ——
    /// 筛选后还挂着四五个标题，等于什么也没筛掉。
    ///
    /// 返回的 `columns` 是**这一行放几个**（2026-11-22 主人：「小尺寸的小组件一行四个」）：
    /// 小尺寸方块本身小、信息少，四个并排一屏能看全三款 + 留白；
    /// 中/大/超大信息密度高，仍是一行两个。
    private var sections: [(title: String, presets: [WidgetPreset], columns: Int)] {
        if filter != .all {
            return [(filter.title,
                     WidgetPreset.libraryAll.filter { filter.matches($0) },
                     Self.columns(for: filter))]
        }

        var result: [(String, [WidgetPreset], Int)] = []
        let featured = featuredPresets
        if !featured.isEmpty { result.append(("精选", featured, 2)) }

        for size in [WidgetSizeFilter.small, .medium, .large, .extraLarge] {
            let group = WidgetPreset.libraryAll.filter { size.matches($0) }
            if !group.isEmpty {
                result.append((size.title, group, Self.columns(for: size)))
            }
        }
        return result
    }

    /// 每个尺寸一行放几个。小尺寸 4 个，其余 2 个。
    private static func columns(for filter: WidgetSizeFilter) -> Int {
        filter == .small ? 4 : 2
    }

    private func gridColumns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.columnSpacing), count: count)
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 20) {
                    // 🔴 2026-11-22 主人：「两个开关移出来，放在精选的上面」——
                    //    它们写的是 App Group 里的两个全局键，改一次**所有款式一起变**；
                    //    放在每个款式的详情页里，会让人以为能单独控制某一张小组件。
                    WidgetBackgroundToggles()

                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(section.title.L)
                                .font(.title3.weight(.bold))

                            LazyVGrid(columns: gridColumns(section.columns),
                                      alignment: .leading,
                                      spacing: Self.rowSpacing) {
                                ForEach(section.presets, id: \.libraryID) { preset in
                                    NavigationLink {
                                        WidgetPresetDetailView(preset: preset)
                                    } label: {
                                        WidgetPresetCard(preset: preset,
                                                         box: cardWidth(columns: section.columns))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        // 截图脚手架用：`WIDGET_SECTION=4` 启动即滚到该分区（超大尺寸在最底）。
                        .id(index)
                    }
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.top, 4)
                .padding(.bottom, 60)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    contentWidth = width
                }
                .onAppear {
                    guard let raw = ProcessInfo.processInfo.environment["WIDGET_SECTION"],
                          let target = Int(raw) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("小组件")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 固定在右上角，跟着页面滚动也不消失 —— 它是这一页唯一的切换入口。
            ToolbarItem(placement: .topBarTrailing) {
                moreButton
            }
        }
    }

    /// 右上角「更多」—— 按尺寸筛选。
    ///
    /// 🔴 **不要再自己套一层玻璃**（2026-11-22 主人：「这个更多按钮本身你就使用液态
    ///    玻璃的官方组件就可以啊，为什么还有再套一个液态玻璃呢」）。
    ///
    ///    iOS 26 的导航栏里，`ToolbarItem` 会被系统自动装进**官方的液态玻璃容器**
    ///    （`UIBarButtonItem` 的 glass 外观），再调 `.appGlass(.circle)` 等于在系统的
    ///    玻璃上又糊一层自绘玻璃 —— 截图里能明显看到双圈：外圈是系统玻璃的边缘，
    ///    内圈是 `appGlass` 的描边。所以这里只留图标本身，材质交给系统。
    ///
    ///    低版本（iOS 17/18）没有液态玻璃，系统导航栏按钮本来就是无底色的图标按钮，
    ///    这也正是那时候的标准外观 —— 不会因为去掉自绘玻璃而变难看。
    ///
    ///    ⚠️ 图标控件**不要写死 38/44 的 frame**：系统会按玻璃容器的内边距给足
    ///    44pt 命中区，自己撑成 44 反而把胶囊拉大、与相邻的返回键比例失衡。
    private var moreButton: some View {
        Menu {
            // 🔴 2026-11-22 主人对照「提醒事项」：对号可以留在左边，
            //    但**所有项的文字必须左对齐**，不能因为有没有对号而左右挪。
            //
            //    早先是手写 `Label(title, systemImage: "checkmark")` 只给选中项，
            //    未选中项少了图标位 → 文字靠左，选中项文字被推右，一行一个位置。
            //    现在交给系统 `Picker`：菜单会把对号放在固定图标位，
            //    没选中的项也保留同一段缩进 —— 这正是 Apple 自己菜单的排版方式。
            Picker("", selection: $filter) {
                ForEach(WidgetSizeFilter.allCases, id: \.self) { item in
                    Text(item.title.L).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("更多尺寸")
    }
}

// MARK: - 全局背景开关

/// 小组件背景的两个开关 —— **全局生效，不按款式分开**。
///
/// 🔴 2026-11-22 主人：「把详情页面中的两个开关移出来，放在精选的上面位置。
///    也不用每个小组件都放这个开关，但又没法单独控制……关一下其余的小组件也都关了。」
///    原因就是数据只有一对 App Group 键：`codelumi.widget.clear` / `codelumi.widget.glass`。
///    摆在单个款式的详情页里，看着像"只对这一张生效"，实际一改全变 —— 干脆提到列表页顶部。
///
/// 两个开关互不影响：各写各的键、各自刷一次时间线。组合的四态见 `WidgetBackground`。
private struct WidgetBackgroundToggles: View {
    // 与预览画布（`WidgetCanvas`）绑同一对 App Group 键：
    // 开关一拨，下面的缩略图立刻变，不用退出去看桌面 —— 否则用户会以为开关是假的。
    @AppStorage(WidgetBackgroundSetting.clearKey,
                store: WidgetBackgroundToggles.groupDefaults) private var useClear = false
    @AppStorage(WidgetBackgroundSetting.glassKey,
                store: WidgetBackgroundToggles.groupDefaults) private var useGlass = false

    private static let groupDefaults =
        PickupStorage.groupStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                row("可用时使用真正透明", isOn: $useClear)

                SettingsDivider(style: .plain)

                row("使用 Liquid Glass", isOn: $useGlass)
            }
            .settingsCard()

            // 🔴 2026-11-22 晚（真机对拍后改口径）：
            //    不需要用户去改桌面外观。iOS 26 起小组件容器本身就不是死白板，
            //    App 只要声明"没有背景"（`.containerBackground(.clear, for: .widget)`），
            //    壁纸就会透出来。所以这里只讲开关本身的语义，不再引导去切外观。
            Text("打开后小组件不再自己画底，桌面壁纸直接透出；关掉回到系统默认底色。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            // 🔴 2026-11-23：跨进程调试没有控制台可看（TestFlight 包连日志都抓不到），
            //    只能把小组件扩展那边的读数借 App Group 传回来，摆成这一行小字：
            //    到底是「装到的不是这一版」「系统接口改了」还是「接上了但系统仍不给透明」。
            //    三种情况的修法完全不同，没有这行只能靠猜。
            if let diagnosis = widgetTransparencyDiagnosis {
                Text(diagnosis)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
        // 老用户可能只写过旧单值键：这里跑一次迁移，写完 `@AppStorage` 会自动读到新值
        .task { _ = WidgetBackgroundSetting.current }
    }

    /// 小组件扩展回报的透明链路状态（没跑过小组件时为空）。
    ///
    /// `swizzled` = 扩展里有没有挂上那个私有接口；
    /// `lastPatched` = 上次宿主来取 descriptor 时，我们改了几款（-1 = 当时开关是关的）。
    private var widgetTransparencyDiagnosis: String? {
        guard let defaults = UserDefaults(suiteName: PickupStorage.appGroupID),
              defaults.object(forKey: "codelumi.diag.widget.at") != nil
                || defaults.object(forKey: "codelumi.diag.widget.bg") != nil
                || defaults.object(forKey: "codelumi.diag.widget.swizzled") != nil
        else { return nil }

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        // 接口状态：ok / noClass / noMethod / badArgs（旧版本写的是布尔，读成 nil）
        let raw = defaults.string(forKey: "codelumi.diag.widget.swizzled")
        let interfaceText: String
        switch raw {
        case "ok":       interfaceText = "接口 ok"
        case "noClass":  interfaceText = "接口 找不到类"
        case "noMethod": interfaceText = "接口 找不到方法"
        case "badArgs":  interfaceText = "接口 签名不对"
        default:         interfaceText = "接口 未挂上"
        }
        let patched = defaults.integer(forKey: "codelumi.diag.widget.lastPatched")
        let patchedText = patched <= 0 ? "从未声明" : "声明透明 \(patched) 款"

        // 🔴 最关键的一项：小组件进程**真正读到的**背景态。
        //    读不到（nil）= 时间线还没跑过；读到 solid = 值没传过去；
        //    读到 clear = 值到了，剩下是系统给不给。
        let resolved = defaults.string(forKey: "codelumi.diag.widget.bg") ?? "未取过"
        let argc = defaults.integer(forKey: "codelumi.diag.widget.argc")
        let appSide = defaults.object(forKey: "codelumi.diag.app.clear") == nil
            ? "App 未写"
            : (defaults.bool(forKey: "codelumi.diag.app.clear") ? "App 开" : "App 关")
        let argcText = argc > 0 ? " · 参数\(argc)" : ""
        return "诊断 · 构建 \(build) · \(interfaceText)\(argcText) · \(appSide) · 小组件读到 \(resolved) · \(patchedText)"
    }

    /// 一行开关：只有标题与开关，没有图标、没有副标题（2026-11-22 主人定的口径）。
    ///
    /// 写入走 `@AppStorage`（= 直接写 App Group 的同名键），
    /// `onChange` 里再刷时间线 —— 两步都不能少：只写键桌面不重画，只 reload 不写键等于没改。
    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTheme.TypeScale.rowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.accent)
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    // 🔴 2026-11-23：把 App 侧看到的值单独记一份 ——
                    //    342 的读数是「小组件读到 solid」而开关明明是开的，
                    //    必须分清是"没写进去"还是"写了、小组件没读到"。
                    if title.hasPrefix("可用时") {
                        PickupStorage.groupStore.set(newValue, forKey: "codelumi.diag.app.clear")
                    }
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

// MARK: - 款式卡片

private struct WidgetPresetCard: View {
    let preset: WidgetPreset
    /// 卡片宽度（= 列宽）。
    let box: CGFloat

    /// 缩略图到白卡边缘的边距（2026-11-22 主人定：**4pt**）。
    ///
    /// 这条值改了三轮：24pt →「太大了」→ 12pt → 仍要更紧 → **4pt**。
    /// 4pt 是「几乎贴着卡片边」的观感：白卡不再是相框，而是缩略图自己的一圈描边。
    /// 左、右、上三边同值 —— 小组件是一块完整的矩形，三边等距才「正面朝上」。
    /// 下边不给同样的值：那里要放款式名字，名字本身就撑开了视觉留白
    /// （主人原话：「只是下面要放名称，所以边距不是固定的罢了」）。
    private static let sideInset: CGFloat = 4
    private static let topInset: CGFloat = 4
    /// 名字下方的收尾留白。
    private static let bottomInset: CGFloat = 10
    /// 缩略图与名字之间的间距。
    private static let nameGap: CGFloat = 8

    private var innerWidth: CGFloat { box - Self.sideInset * 2 }

    /// 底色卡片的形状：**四角统一**，取值 = 里面小组件**缩放后**的视觉圆角。
    ///
    /// 2026-11-22 主人连改三点，最终口径：
    /// ①「底色卡片的圆角和其中小组件的圆角曲率保持一致」；
    /// ②「底色卡片自己的下面的圆角与上面的保持一致，上面的圆角和小组件的上面的圆角保持一致」；
    /// ③ 看完截图再指出「你也没做到」—— 因为缩略图是整体 `scaleEffect` 缩小的，
    ///    24pt 的圆角缩到 88pt 宽的卡片里只剩约 13pt，而卡片还按 24pt 画，
    ///    于是外层弧度明显比内层大。现在改取 `visualCornerRadius`（× 缩放比），
    ///    两层弧在屏幕上才是同一条曲率，四角仍同一个数。
    private var cardShape: RoundedRectangle {
        let radius = WidgetCanvasMetrics.visualCornerRadius(
            base: preset.canvasStyle.size,
            box: innerWidth,
            height: canvasHeight
        )
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// 缩略图区高度 —— **按该款真实长宽比算，不是所有款共用一个高度**。
    ///
    /// 早先写死 `innerWidth * 0.78`：中尺寸（2.14:1）正好，但小尺寸（1:1）被高度卡住，
    /// 左右各空出 17pt，加上卡片内边距就是一圈 27pt 的白边 —— 这才是「边距太大」的真凶。
    ///
    /// 现在宽度优先填满，高度完全跟着比例走。
    ///
    /// 🔴 2026-11-22 主人（超大尺寸截图）：**「左右的内边距与上面的内边距保持一致」**。
    ///    原因是这里原本有个 `innerWidth * 1.2` 的高度上限，用来挡超大竖版（338×690，
    ///    2.04:1）把卡片撑成一根杆。结果上限反过来生效：高度先到顶 → 缩放比由高度定 →
    ///    宽度只占到 59%，左右空出两条宽白边，与 4pt 的上面内边距完全不对称。
    ///    现在**取消上限**，宽度永远填满，代价是超大竖版那一张卡片本身就很高 ——
    ///    这是真实比例，也是主人要的「比例放大一些」。
    private var canvasHeight: CGFloat {
        let ratio = preset.canvasStyle.size.height / max(1, preset.canvasStyle.size.width)
        return innerWidth * ratio
    }

    /// 窄卡（小尺寸一行四个）用的紧凑口径。
    ///
    /// 4 列时列宽只有约 96pt、内容区 88pt：13pt 的名字「取件码 · 快递」一行放不下，
    /// 勉强折成两行会把卡片撑高、四张卡看着虚。所以窄卡降到 11.5pt，
    /// 名字与底边的留白也一起收 2pt —— 比例跟着尺寸走，不是一套数字用到底。
    private var isCompact: Bool { box < 120 }
    private var nameFontSize: CGFloat { isCompact ? 11.5 : 13 }
    private var effectiveNameGap: CGFloat { isCompact ? 6 : Self.nameGap }
    private var effectiveBottomInset: CGFloat { isCompact ? 8 : Self.bottomInset }

    var body: some View {
        VStack(spacing: effectiveNameGap) {
            WidgetPresetThumbnail(preset: preset,
                                  box: innerWidth,
                                  canvasHeight: canvasHeight)

            HStack(spacing: 3) {
                // 付费档标记：名字前一把小锁（缩略图太小，角标会挡住取件码）。
                if preset.needsPro && !EntitlementSnapshot.licensedPro {
                    Image(systemName: "lock.fill")
                        .font(.system(size: isCompact ? 8 : 9, weight: .bold))
                        .foregroundStyle(AppTheme.amber)
                }

                Text(preset.name.L)
                    .font(.system(size: nameFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    // 两行：名字长的款式（「待取总览 · 极简」）不会被截成省略号。
                    // 一行还是两行由名字决定，**卡片高度不跟着变** —— 见下面的 maxHeight。
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Self.sideInset)
        .padding(.top, Self.topInset)
        .padding(.bottom, effectiveBottomInset)
        // 🔴 **撑满整个网格单元**（2026-11-21 主人）：「底色的圆角矩形的高度会因为
        //    小组件的名称长度而影响，但是同一行底色高度保持一致」。
        //
        //    不写这一行时，每张白卡只有自己内容那么高 —— 一行里左边名字一行、
        //    右边名字两行，两张白卡就一高一矮，网格下缘参差。
        //    撑满后本行所有卡片取同一高度（= 行内最高的那张），
        //    名字短的底部自然留白；不同行之间仍按各自名字长度各算各的。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 🔴 底色卡片 = **玻璃材质**（2026-11-22 主人）：
        //    「左下角的底色卡片做成液态玻璃的材质，当然这个可以在设置的外观与个性化中
        //      随液态玻璃的开关一并关闭液态玻璃的材质显示，变成毛玻璃的」。
        //    所以不自己写死颜色，一律走 `appGlass` —— 它内部已经串好了这条链：
        //      iOS 26+ 且 `GlassSettings.isActive`（外观 › 液态玻璃 开）→ 真玻璃 `glassEffect`
        //      其余情况（低版本 / 开关关掉）→ `.ultraThinMaterial` 毛玻璃 + 淡描边
        //    开关在 `SettingsPages` 的外观页里，改的是 App Group 同一个键
        //    （`codelumi.usesLiquidGlass`），这里是读值不是存值，天然跟随。
        //
        //    圆角走 `cardShape`：四角都与里面小组件**同源**（`WidgetCanvasMetrics.cornerRadius`
        //    = 24）—— 2026-11-22 主人：「底色卡片自己的下面的圆角与上面的保持一致，
        //    上面的圆角和小组件的上面的圆角保持一致」。
        .appGlass(cardShape)
        .contentShape(.rect)
    }
}

/// 等比缩略图：把真实小组件按实际尺寸渲染，再整体缩进卡片里。
private struct WidgetPresetThumbnail: View {
    let preset: WidgetPreset
    let box: CGFloat
    let canvasHeight: CGFloat

    private var base: CGSize { preset.canvasStyle.size }

    /// 等比缩放比：宽高两个方向取较小者，保证整块都塞进卡片。
    ///
    /// 🔴 **宽度必须填满**（2026-11-22 实测）：早先封了 1.0 上限（怕小尺寸被放大
    ///    显得突兀），结果小尺寸 158pt 在 168pt 的内容区里居中，左右各多 5pt，
    ///    加上内边距就是 17pt —— 主人量的是 12pt，对不上。
    ///    现在宽度优先填满，内边距给多少，视觉边距就是多少。
    ///    高度用 `canvasHeight` 兜住（它本身就是 `innerWidth × 真实比例`，
    ///    正常情况下两个方向同时到边；只有超大竖版会先撞高度上限）。
    private var scale: CGFloat {
        WidgetCanvasMetrics.thumbnailScale(base: base, box: box, height: canvasHeight)
    }

    var body: some View {
        let s = scale
        WidgetPresetPreview(preset: preset, snapshot: .preview(), showsShadow: false)
            // 🔴 `scaleEffect` 只改渲染、不改布局尺寸，所以要再用 frame 把
            //    缩放后的视觉尺寸报出去，否则 LazyVGrid 会按真实尺寸排（一行放不下）。
            .scaleEffect(s, anchor: .center)
            .frame(width: base.width * s, height: base.height * s)
            // 尺寸从估算切到实测时会有一次隐式过渡，中间帧像两层文字叠在一起。
            .transaction { $0.animation = nil }
            .frame(width: box, height: canvasHeight)
    }
}

// MARK: - 款式详情

struct WidgetPresetDetailView: View {
    let preset: WidgetPreset

    /// 清单款的「显示内容」开关（2026-11-22 晚二次定稿）。
    ///
    /// 🔴 这是**全局**偏好，不是这一款私有的：所有清单款共用同一组键 ——
    ///    之前那套开关本来就是所有尺寸一起生效，口径保持一致。
    /// 🔴 **露哪几个由款式决定**（`preset.fields`）：
    ///    小尺寸清单只有 快递驿站 / 快递公司；中 / 大 / 超大是
    ///    取件地址 / 快递公司 / 快递驿站 / 完整信息 四个。
    ///    非清单版式不显示这组开关（画什么由版式决定，摆一排开关却不起作用更糟）。
    @State private var displayState = WidgetDisplaySetting.state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 等比实际尺寸渲染。超宽尺寸自带横向滚动（见 `WidgetPresetPreview`）。
                WidgetPresetPreview(preset: preset)
                    .frame(maxWidth: .infinity, alignment: .center)

                if preset.isCustomizable {
                    displayOptionsCard
                }

                // 🔴 2026-11-22 主人：「详情页面中的小组件下面不要小组件的名字了，
                //    因为上面的标题就是小组件的名称」，改为**一张简介卡**说清这一款干什么用的。
                //    卡片走 `settingsCard()` —— iOS 26 + 开了液态玻璃就是真玻璃，否则系统分组卡。
                Text(preset.summary.L)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .settingsCard()

                // 🔴 这一步是**必要**信息：iOS 不允许 App 把小组件加到桌面，
                // 用户看完这一页必须知道下一步去哪操作。
                Text("添加方式：长按桌面空白处 › 左上角 ＋ › 搜索 Codelumi。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(preset.name.L)
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 显示内容

    /// 开关列表：取件地址 / 快递公司 / 快递驿站 / 完整信息（小尺寸款只露后两个里的两个）。
    ///
    /// 取件码与柜位不在里面 —— 码是这款组件存在的唯一理由，
    /// 柜位跟码同一行、关掉只会让用户到柜前再回 App 查一遍。
    private var displayOptionsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(preset.fields.enumerated()), id: \.element.id) { index, field in
                if index > 0 {
                    SettingsDivider(style: .plain)
                }
                row(field.title, isOn: binding(for: field))
            }
        }
        .settingsCard()
    }

    /// 单个字段的开/关：改完立刻落盘并重画桌面（只写 App Group 的话要等几小时才生效）。
    ///
    /// 🔴 2026-11-23 老大：「完整信息的开关与上面几个其他的开关是互斥的……打开完成信息之后，
    ///    其他的开关也应该全部打开，当其他的任一开关关闭，完整信息的开关就不会是开的」。
    ///    → 「完整信息」不是独立一档，而是**三项全开的另一种说法**，所以两边必须双向联动：
    ///      · 打开它 → 地址 / 公司 / 驿站 一起打开；
    ///      · 关掉它 → 三项一起关（否则会出现"关着完整信息、三项却全亮"的自相矛盾态）；
    ///      · 任一项被关 → 完整信息立刻跟着灭；三项都打开 → 完整信息自动亮。
    ///      存盘同样四处一起写，小组件与 App 内预览才不会各显示一套。
    private func binding(for field: WidgetDisplayField) -> Binding<Bool> {
        Binding(
            get: {
                switch field {
                case .address:  return displayState.address
                case .company:  return displayState.company
                case .station:  return displayState.station
                case .complete: return displayState.complete
                }
            },
            set: { on in
                switch field {
                case .complete:
                    displayState.complete = on
                    displayState.address = on
                    displayState.company = on
                    displayState.station = on
                    WidgetDisplaySetting.setAddress(on)
                    WidgetDisplaySetting.setCompany(on)
                    WidgetDisplaySetting.setStation(on)
                    WidgetDisplaySetting.setComplete(on)
                case .address, .company, .station:
                    switch field {
                    case .address: displayState.address = on
                    case .company: displayState.company = on
                    default:       displayState.station = on
                    }
                    // 三项全开才等于「完整信息」：任一项关掉，总开关立刻跟着灭
                    let all = displayState.address && displayState.company && displayState.station
                    displayState.complete = all
                    WidgetDisplaySetting.set(field, on)
                    WidgetDisplaySetting.setComplete(all)
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
        )
    }

    /// 与「背景」那组开关同一套行样式（同一个卡片语言，不另发明一种）。
    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTheme.TypeScale.rowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
