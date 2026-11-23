import SwiftUI
import UIKit
import WidgetKit

// MARK: ============================================================================
// 小组件预览（App 内 · 真实渲染）
//
// 背景：桌面小组件在模拟器 / CI 里**无法脚本化添加**，唯一能拿到「真实渲染证据」的
// 办法，是在 App 内用**同一份视图代码**（`AlludeShared/WidgetVisuals.swift`）
// 按小组件尺寸渲染一次。因此这里不是手工复刻，是同一份实现。
//
// 两处使用：
//   1) 款式详情页（`WidgetPresetDetailView`）—— 等比实际尺寸渲染**这一款**；
//   2) `SCREEN=widgets` 命令行入口 —— 深/浅两套外观的验收截图都从这里出。
//
// 🔴 2026-11-22：原来的「全部尺寸铺开」改成「按款式铺开」。
//    款式本身带尺寸（`WidgetPreset.family`），所以不再有「一个组件渲染五种尺寸」
//    这种在真机上不存在的形态 —— 那是旧架构的遗留展示方式。
//
// 截图定位：`WIDGET_SIZE` 只渲染第一个匹配该尺寸的款式 —— 八块全铺出来是好几屏，
// 代码截图只能拍到最上面一屏，靠滚动取证等于没取证。
//
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

// MARK: - 款式 → 预览画布

extension WidgetPreset {
    /// 详情页里用来渲染等比预览的画布规格。
    ///
    /// 🔴 iPhone 上要把 iPad 横版超大（690×354）换成正版超大（338×690）：
    ///    前者比手机屏还宽，渲染出来只能横向滚动着看，等于看不懂这一款。
    ///    两款是同一内容口径，换画布不影响「这一款长什么样」的结论。
    var canvasStyle: WidgetCanvas.Style {
        if family == .systemExtraLarge, UIDevice.current.userInterfaceIdiom != .pad {
            return .extraLargePortrait
        }
        switch family {
        case .systemSmall: return .small
        case .systemMedium: return .medium
        case .systemLarge: return .large
        case .systemExtraLargePortrait: return .extraLargePortrait
        default: return .extraLarge
        }
    }
}

// MARK: - 仿真小组件容器

/// 仿真小组件的**圆角半径** —— 单独抽成常量，因为有两个地方要用同一个曲率：
/// ① `WidgetCanvas` 自己（预览块的形状）；
/// ② 小组件设置页里包住预览块的**底色卡片**（2026-11-22 主人：
///    「底色卡片的圆角和其中小组件的圆角曲率保持一致」）。
///
/// 🔴 必须是**同源**：早先卡片写死 20、预览块写死 24，卡片看着比里面的小组件更「方」，
///    肉眼看得出两层圆角不同心。改任意一处都不能再各写各的数。
enum WidgetCanvasMetrics {
    static let cornerRadius: CGFloat = 24

    /// 缩略图在给定容器里的等比缩放比。
    ///
    /// 🔴 与 `WidgetPresetThumbnail` 必须是**同一个算法**：那边拿它做 `scaleEffect`，
    ///    这边拿它反算「圆角缩放后到底还剩多少 pt」。两处各算一遍迟早对不上。
    static func thumbnailScale(base: CGSize, box: CGFloat, height: CGFloat) -> CGFloat {
        guard base.width > 0, base.height > 0, box > 0, height > 0 else { return 1 }
        return min(box / base.width, height / base.height)
    }

    /// 缩略图**在屏幕上呈现出来的**圆角半径。
    ///
    /// 🔴 2026-11-22 主人第二次指出「底色卡片的圆角还是没和里面小组件一致」——
    ///    根因是「数值相同」不等于「观感相同」：
    ///    小组件真实 158pt 宽配 24pt 圆角，缩进 88pt 的卡片后整体被缩到 0.56 倍，
    ///    屏上的弧只剩 13.4pt；而底色卡片还是按 24pt 画，于是外层比内层更圆。
    ///    所以卡片圆角取**缩放后的视觉半径**，两层弧才是同一条曲率。
    static func visualCornerRadius(base: CGSize, box: CGFloat, height: CGFloat) -> CGFloat {
        cornerRadius * thumbnailScale(base: base, box: box, height: height)
    }
}

/// 把共享视图装进一个「长得像小组件」的框里。
///
/// 尺寸取 iOS 常见取值 —— 真实值随机型与主屏缩放略有出入，这里只求版式比例正确。
/// 内边距 16pt 对应 WidgetKit 默认给内容的 margin。
///
/// 预览**不响应点击**：勾选框与翻页控件在真实小组件里由 AppIntent 直接写数据，
/// 而在 App 内预览时点击既不会更新界面、又会让内存副本与文件不一致，
/// 因此整块 `allowsHitTesting(false)`，只作视觉对照。
struct WidgetCanvas: View {
    enum Style: String, CaseIterable {
        case small
        case medium
        case large
        case extraLarge
        case extraLargePortrait

        /// 🔴 2026-11-08 主人：预览必须和桌面上真实大小一致。
        ///
        /// 原来写死 158 / 338 / 354 —— 那是 **390pt 屏**（iPhone 12/13/14 标准版）的数值。
        /// 系统小组件是按屏宽等比缩放的，402pt（16 Pro）、430pt（Pro Max）上会更大，
        /// 于是预览永远比真机小一圈。
        ///
        /// 基准值 158 / 338 / 354 是 iPhone 15·16 Pro（**393pt**）实测，按屏宽等比缩放。
        /// 预览尺寸（2026-11-08 回滚到「之前看着合适」的那组固定值）。
        ///
        /// 教训：我按屏宽比例缩放 + 读实测值，把这一页改坏了两版。
        /// 固定 158 / 338 / 354 是当年在真机上对过、主人认可的观感，
        /// 在没拿到可靠真机数据之前不要动它。
        var size: CGSize {
            switch self {
            case .small:  CGSize(width: 158, height: 158)
            case .medium: CGSize(width: 338, height: 158)
            case .large:  CGSize(width: 338, height: 354)
            case .extraLarge: CGSize(width: 690, height: 354)
            case .extraLargePortrait: CGSize(width: 338, height: 690)
            }
        }

        var title: String {
            switch self {
            case .small: "小尺寸"
            case .medium: "中尺寸"
            case .large: "大尺寸"
            case .extraLarge: "iPad 超大"
            case .extraLargePortrait: "超大"
            }
        }

        /// 与 `WidgetPageSize.key(_:)` 同一口径 —— 预览里的翻页控件要读到真的那一页
        var pageKey: String {
            switch self {
            case .small: "s"
            case .medium: "m"
            case .large: "l"
            case .extraLarge: "xl"
            case .extraLargePortrait: "xlp"
            }
        }

        /// 宽于手机屏的尺寸（iPad 超大）需要横向滚动才看得到右半部分
        var overflowsPhoneWidth: Bool { size.width > 360 }
    }

    let style: Style
    let content: AnyView

    /// `expandsToFill`：宽度吃满父视图（高度仍按 `style.size.height`）。
    /// 用于只有一块预览、需要撑满版面的场合；
    /// 多块并排时（款式库）必须保持真实宽度，所以默认仍是固定宽。
    var expandsToFill: Bool = false

    /// 是否画投影。
    ///
    /// 🔴 款式库的缩略图传 **false**（2026-11-22 主人量的是「小组件的物理边缘到
    ///    底色卡片的边缘」= 24pt）：投影向外扩 3~4pt，白卡里那圈 24pt 边距
    ///    会被吃掉三分之一，看着只剩 20pt。白卡本身就是容器，不需要再浮一层。
    ///    详情页 / 命令行截图仍用 true —— 那里没有白卡，要靠投影从页面背景上浮起来。
    var showsShadow: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    // 🔴 2026-11-22 老大：「这两个开关要起到真实的作用啊，不是打开了而没有反应」——
    //    根因就是**这块画布压根不读设置**：背景写死 `secondarySystemBackground`，
    //    下面「设置 › 小组件」里怎么开都一个样，用户当然以为开关是假的。
    //    这里用 `@AppStorage` 直接绑 App Group 的两个键，改开关 → 预览立刻重绘。
    @AppStorage(WidgetBackgroundSetting.clearKey,
                store: WidgetCanvas.groupDefaults) private var clearBackground = false
    @AppStorage(WidgetBackgroundSetting.glassKey,
                store: WidgetCanvas.groupDefaults) private var glassBackground = false

    private static let groupDefaults =
        PickupStorage.groupStore

    private var background: WidgetBackground {
        .resolve(clear: clearBackground, glass: glassBackground)
    }

    init<Content: View>(_ style: Style,
                        padding: CGFloat = 16,
                        expandsToFill: Bool = false,
                        showsShadow: Bool = true,
                        @ViewBuilder content: () -> Content) {
        self.style = style
        self.expandsToFill = expandsToFill
        self.showsShadow = showsShadow
        self.content = AnyView(content().padding(padding))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WidgetCanvasMetrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: expandsToFill ? .infinity : nil, alignment: .topLeading)
            .frame(width: expandsToFill ? nil : style.size.width,
                   height: style.size.height,
                   alignment: .topLeading)
            // 与真实 WidgetKit 小组件同一套外观，四种背景态与 `WidgetSurface` 一一对应
            .background { backgroundLayer }
            .clipShape(shape)
            // 🔴 2026-11-08 主人：预览和页面背景分不清 —— 给一张**软阴影 + 发丝描边**，
            //    这是 iOS 系统里「浮起卡片」的标准做法（比加深底色更像真机）。
            .shadow(color: showsShadow
                        ? .black.opacity(colorScheme == .dark ? 0.45 : 0.10)
                        : .clear,
                    radius: 12, y: 6)
            .overlay {
                shape.stroke(.primary.opacity(colorScheme == .dark ? 0.10 : 0.06),
                             lineWidth: 0.5)
            }
            // 🔴 描边 + 阴影（2026-10-27 主人：「下面都融在一起看不见底了」）：
            // `secondarySystemBackground` 与设置页的 `systemGroupedBackground`
            // 在浅色下几乎是同一个浅灰白，没有分离手段时小组件下边缘直接消失。
            .overlay {
                shape.strokeBorder(Color(.separator).opacity(colorScheme == .dark ? 0.55 : 0.35),
                                   lineWidth: 0.5)
            }
            .shadow(color: showsShadow
                        ? .black.opacity(colorScheme == .dark ? 0.50 : 0.12)
                        : .clear,
                    radius: 12, y: 5)
            .allowsHitTesting(false)
    }

    // MARK: 背景四态（与 `WidgetSurface` 同一套语义）

    @ViewBuilder
    private var backgroundLayer: some View {
        switch background {
        case .solid:
            solidSurface
        case .clear:
            // 真透明：什么都不画，透出下面的底（桌面上就是壁纸）
            Color.clear
        case .glass:
            // 只开玻璃 —— 底色还在，表面多一层材质
            ZStack {
                solidSurface
                glassSurface
            }
        case .clearGlass:
            // 两个都开 —— 全透明液态玻璃
            glassSurface
        }
    }

    private var solidSurface: some View {
        AppTheme.cardSurface
            .overlay(alignment: .top) {
                LinearGradient(colors: [AppTheme.accent.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 88)
            }
    }

    private var glassSurface: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.22), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
            }
    }
}

// MARK: - 款式渲染（详情页与目录页共用同一份分发逻辑）

/// 按款式渲染一块小组件内容。
///
/// 与 `PickupWidgetEntryView` 的分发逻辑**必须一致**（尺寸判断、空态、免费占位）——
/// 这里唯一的差别是不读真实数据，只吃传进来的快照。
///
/// 🔴 抽成独立视图而不是两处各写一遍：预览与桌面一旦漂移，
///    就会出现「设置页看着好好的、桌面却不一样」的假象，那正是这个页面存在的意义所在。
struct WidgetPresetContent: View {
    let preset: WidgetPreset
    let snapshot: WidgetSnapshot

    var body: some View {
        let isSmall = preset.family == .systemSmall

        // 🔴 这里是**商品预览**，不是运行时，所以**不做档位判断** ——
        //    始终渲染真实内容（示例数据）。
        //
        //    之前这里跟桌面一样画「解锁 Codelumi Pro」占位，结果是：免费用户在
        //    图库里点开「待取总览」，满屏一个锁，根本看不到自己到底在买什么。
        //    档位信息交给卡片名字前的小锁（`WidgetPresetCard`）表达就够了。
        //
        //    真的加到桌面后加不了这件事，由 `PickupWidgetEntryView` 渲染锁占位 ——
        //    那是运行时状态，与这里的商品展示是两件事，不要混。
        if snapshot.isEmpty {
            WidgetEmptyContent(pickedTodayCount: snapshot.pickedTodayCount, compact: isSmall)
        } else {
            // 版式分发与桌面同一个视图（`WidgetLayoutContent`），不会再漂移。
            WidgetLayoutContent(preset: preset,
                                snapshot: snapshot,
                                family: preset.family,
                                pageKey: preset.canvasStyle.pageKey,
                                pageSize: WidgetPageSize.rowCount(family: preset.canvasStyle.pageKey),
                                options: preset.options)
        }
    }
}

/// 等比实际尺寸的预览画布（含超宽尺寸的横向滚动兜底）。
struct WidgetPresetPreview: View {
    let preset: WidgetPreset
    var snapshot: WidgetSnapshot = .preview()
    /// 卡片缩略图传 false —— 白卡就是容器，再叠投影会吃掉那圈 24pt 边距。
    var showsShadow: Bool = true

    var body: some View {
        let canvas = WidgetCanvas(preset.canvasStyle, showsShadow: showsShadow) {
            WidgetPresetContent(preset: preset, snapshot: snapshot)
        }
        if preset.canvasStyle.overflowsPhoneWidth {
            ScrollView(.horizontal, showsIndicators: false) { canvas }
        } else {
            canvas
        }
    }
}

// MARK: - 全部款式目录（SCREEN=widgets 截图入口）

/// 「所有款式」铺开。每块标题写清款式名与尺寸，下面渲染真实尺寸的小组件。
///
/// 🔴 **一律用示例数据，不读用户的待取件。**
///
/// 起因是主人报的问题：这一页原先是「用你自己的数据渲染真实观感」，
/// 但用户把件取完之后，设置页里整页预览全变成空态 ——
/// 「小组件长什么样」这个页面在**最需要看它的时候**（想确认版式 / 想挑款式）
/// 恰好什么都没有，等于把预览做废了。
/// 现在永远铺 14 条示例记录：它展示的是**版式**，不是**你的数据**。
struct WidgetGalleryContent: View {
    private var snapshot: WidgetSnapshot { .preview() }

    /// 内容区实测宽度（用来把小尺寸的左缘对齐到中尺寸卡片的左缘）
    @State private var contentWidth: CGFloat = 0

    /// iPad 横版超大只在 iPad 上渲染（iPhone 装不下 690pt 宽的画布）。
    private var presets: [WidgetPreset] {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        return WidgetPreset.all.filter { isPad || $0.family != .systemExtraLarge || $0.families.count > 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(presets) { preset in
                block(title: "\(preset.name) · \(preset.sizeName)尺寸") {
                    HStack(spacing: 0) {
                        // 🔴 2026-11-08 主人：小尺寸要和中尺寸的**左缘**对齐。
                        //    中尺寸是居中的，左缘 = (内容宽 − 中宽) / 2，小尺寸补同样的左缩进。
                        if preset.family == .systemSmall {
                            Spacer().frame(width: max(0, (contentWidth - WidgetCanvas.Style.medium.size.width) / 2))
                        } else {
                            Spacer(minLength: 0)
                        }

                        ZStack(alignment: .topTrailing) {
                            WidgetPresetPreview(preset: preset, snapshot: snapshot)
                                // 🔴 2026-11-08：尺寸从「估值」切到「实测」时会发生一次
                                //    隐式过渡，动画中间帧看起来像两层文字叠在一起（乱套）。
                                //    预览尺寸变化不需要动画，直接关掉。
                                .transaction { $0.animation = nil }

                            if preset.needsPro && !EntitlementSnapshot.licensedPro {
                                proBadge
                                    .padding(8)
                            }
                        }

                        if preset.family != .systemSmall { Spacer(minLength: 0) }
                    }
                }
            }

            block(title: "空态：一件待取都没有时") {
                HStack(spacing: 0) {
                    // 与上面小 / 中尺寸同一条左缘（中尺寸居中带来的偏移要补上）
                    Spacer().frame(width: max(0, (contentWidth - WidgetCanvas.Style.medium.size.width) / 2))
                    WidgetCanvas(.small) {
                        WidgetEmptyContent(pickedTodayCount: 0, compact: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            // 2026-11-20 主人：「提示文字能少则少，非必要不提示」。
            // 只留一句能力边界（免费档能加哪些尺寸、同屏几条），说明性脚注全部删除。
            if !EntitlementSnapshot.licensedPro {
                Text("小、中尺寸可直接添加，最多 \(PickupLimits.freeVisible) 条。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
    }

    /// 档位说明。命名按主人定的：免费版 = Codelumi，付费版 = Codelumi Pro。
    private var proBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
            Text("Codelumi Pro")
                .font(AppTheme.TypeScale.badge)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.amber, in: .capsule)
    }

    private func block<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.L)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - 预览页（SCREEN=widgets 截图入口）

struct WidgetPreviewGallery: View {
    /// 截图定位：只渲染该尺寸的第一款。
    /// 值域仍是 `WidgetCanvas.Style` 的 rawValue（small / medium / large / …），
    /// 这样 `tools/widget-shots.sh` 里的 `WIDGET_SIZE` 不用改。
    private var onlyStyle: WidgetCanvas.Style? {
        WidgetCanvas.Style(rawValue: ProcessInfo.processInfo.environment["WIDGET_SIZE"] ?? "")
    }

    /// 是否处于 `SIMCTL_CHILD_SCREEN` 截图模式
    private var screenshotMode: Bool { ProcessInfo.processInfo.environment["SCREEN"] != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let style = onlyStyle {
                    // 单块模式：截图验收用（示例数据，与目录页同一口径）
                    if let preset = WidgetPreset.all.first(where: { $0.canvasStyle == style }) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(preset.name) · \(style.title)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            WidgetCanvas(style) {
                                WidgetPresetContent(preset: preset, snapshot: .preview())
                            }
                        }
                    }
                } else {
                    WidgetGalleryContent()

                    // 命令行验证专用：真实数据往往缺少「极端组合」，这里用示例数据压测一次 ——
                    // 最长凭证（15 位运单号）与最长副标题同页出现时不折行、不溢出。
                    if screenshotMode,
                       let preset = WidgetPreset.preset(id: "AlludeListStation") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("压测：最长凭证 + 最长副标题同页")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            WidgetPresetPreview(preset: preset)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("小组件")
        .navigationBarTitleDisplayMode(.inline)
    }
}
