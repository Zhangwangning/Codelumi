import SwiftUI

// MARK: ============================================================================
// 实时活动预览（App 内 · 真实渲染）
//
// 背景：锁屏卡片与灵动岛**都无法脚本化截图** —— 锁屏要真的把设备锁上，
// 灵动岛只在带灵动岛的机型上由系统绘制。唯一能拿到「真实渲染证据」的办法，
// 与桌面小组件（`WidgetPreviewGallery.swift`）同一套：在 App 内用**同一份视图代码**
// （`AlludeShared/PickupActivityAttributes.swift`）按各形态的约束渲染一次。
//
// 因此这里不是手工复刻：锁屏卡片与灵动岛四块区域引用的都是共享层那几个
// `ActivityLockScreenCard` / `IslandExpandedContent` / `IslandCompact*` / `IslandMinimal`
// 结构体本身，改版式两处一起变，预览不会与真机漂移。
//
// ⚠️ 唯一「模拟」的成分是外框：锁屏的卡片材质与灵动岛的黑洞形状由系统绘制，
//    这里用等尺寸的外壳近似，只为观察内容的排布与截断。
//
// 入口：`SCREEN=activity`（命令行验收截图）。
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

// MARK: - 外框

/// 锁屏 / 通知中心里的活动卡片外壳。
///
/// 真实卡片 = 系统给的圆角 + 半透明材质，再由活动自己的
/// `.activityBackgroundTint(...)` 叠一层品牌色。这里把同一套叠加顺序复现一次：
/// 材质在下、品牌色（opacity 0.10）在上 —— 顺序反了颜色会脏。
struct ActivityCardShell: View {
    let tint: Color
    /// 卡背那张"模糊封面"用的条目 —— 与真机 `PickupLiveActivity` 同一套画法，
    /// 否则预览里看不到背板，验收会失真（2026-11-23 老大要在模拟器里先看）。
    let backdropItem: PickupActivityAttributes.Item?
    let content: AnyView

    init(tint: Color,
         backdropItem: PickupActivityAttributes.Item? = nil,
         @ViewBuilder content: () -> some View) {
        self.tint = tint
        self.backdropItem = backdropItem
        self.content = AnyView(content())
    }

    var body: some View {
        content
            // HIG：锁屏卡标准内边距 14pt（宽=屏宽−22、高 84–160）
            .padding(.horizontal, 18)   // 与真机同值：内容到卡片四边等距
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 背板：模糊图标 + 上淡下深的暗色渐变（与真机一致）
            .background {
                if let item = backdropItem {
                    ZStack {
                        CourierLogo(company: item.displayName, size: 240,
                                    showsShadow: false, usesStaticAsset: true)
                            .blur(radius: 28)
                        LinearGradient(colors: [Color.black.opacity(0.18),
                                                Color.black.opacity(0.34)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // 🔴 2026-10-28 主人：真机锁屏卡是 iOS 26 的**液态玻璃**，
            //    原来那层 `.ultraThinMaterial` 只是磨砂玻璃，发灰、没有折射和高光。
            //    `.glassEffect` 是系统 Liquid Glass 的原生实现：折射下层内容、
            //    边缘镜面高光、可带品牌色 tint —— 与真机同一个渲染器。
            .appGlass(.rect(cornerRadius: 24, style: .continuous),
                      tint: tint.opacity(0.16))
            .allowsHitTesting(false)
    }
}

/// 灵动岛外壳。
///
/// 🔴 **几何按 Apple HIG 官方尺寸**（2026-09-23 修正）：
/// ```
///                        Compact leading / trailing      Minimal          Expanded
///   393x852 (17 Pro)         52.33 x 36.67 pt         36.67–45 x 36.67     371 x 84–160
///   430x932 (17 Pro Max)     62.33 x 36.67 pt         36.67–45 x 36.67     408 x 84–160
///
///   紧凑态整岛宽：17 Pro **230** / 17 Pro Max **250**
///   （= 单侧 × 2 + 挖孔 125.34，两档机型的挖孔宽度相同）
/// ```
/// 旧版预览把紧凑态画成「148pt 的一个连续黑框、里面 leading 与 trailing 并排」——
/// 两处都错：**总宽差了一倍**，而且真机上 leading / trailing 是被 TrueDepth 挖孔
/// **隔开的两块独立画布**，不是一条横条里的左右两端。于是"预览宽松、真机发挤"，
/// 这就是主人说的"真机截图与模拟器对比相差很大"。
///
/// 预览一律取 **393x852（17 Pro）** 这一档，不按机型分流：它的单侧更窄（52.33 < 62.33），
/// 预览偏保守 —— 与"预览别比真机更好看"的既定口径一致。
struct IslandShell: View {

    enum Style {
        /// 展开态：整岛宽度（Pro Max 档 408）
        case expanded(width: CGFloat)
        /// 紧凑态：两翼 + 挖孔（官方 230 = 52.33 × 2 + 125.34）
        case compact
        /// 最小态：只有约 45×36.67pt 可画
        case minimal

        /// 紧凑态单侧可画宽度（393x852 档）
        static let compactSide: CGFloat = 52.33
        /// 单侧可画高度（两个形态共用）
        static let contentHeight: CGFloat = 36.67
        /// TrueDepth 挖孔的宽度
        static let punchHole: CGFloat = 125.34

        var cornerRadius: CGFloat {
            switch self {
            // 🔴 2026-10-28 主人：「灵动岛卡片的圆角再做大一点点」→ 43 → **46**。
            //    46 × 缩放 0.817 ≈ 37.6pt 渲染（机模屏幕圆角 42.9 × 0.817 ≈ 35），
            //    视觉上岛角比屏幕角略圆一档，是「再大一点点」的合适幅度。
            case .expanded: 46
            // 紧凑/最小态是**居中的胶囊**（两端半圆），半径 = 高/2。
            // 之前写的 22 是猜的；按 36.67 的内容高 + 上下各 3.17 的岛体余量 = 43，
            // 半径取 21.5。
            case .compact, .minimal: 21.5
            }
        }

        /// 外壳总宽（= 真机整岛宽，黑框包含在内）。
        var width: CGFloat {
            switch self {
            case .expanded(let w): w
            case .compact: Self.compactSide * 2 + Self.punchHole
            case .minimal: 44
            }
        }

        /// 外壳总高。展开态由内容撑开，另两种形态高度固定。
        var height: CGFloat? {
            switch self {
            case .expanded: nil
            case .compact, .minimal: 43
            }
        }
    }

    let style: Style
    let content: AnyView
    /// 真机岛外圈有一圈 `keylineTint`（品牌色细线）。预览壳复现它：
    /// 🔴 必须用 `islandTint` 亮化后的品牌色 —— 顺丰的纯黑主色描边
    /// 贴着黑色壳 + 暗黑页面就是隐形的（2026-09-24 主人真机指认）。
    var keyline: Color?

    init(_ style: Style, keyline: Color? = nil, @ViewBuilder content: () -> some View) {
        self.style = style
        self.keyline = keyline
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            // 外框宽度 = 真机整岛宽度。顺序不能反：frame 在 padding 之前会让总宽超出。
            // 紧凑/最小态**连高度一起定死**，宽度才是有意义的对照 ——
            // 否则外壳会跟着内容缩，量出来的"余量"全是假的。
            .frame(width: style.width, height: style.height, alignment: .center)
            // 灵动岛恒为黑色挖孔：不跟随 App 外观，深色下也是这块黑，
            // 所以这里写死 .black 而不是语义色。
            .background(Color.black, in: .rect(cornerRadius: style.cornerRadius, style: .continuous))
            // 暗黑页面底也是黑的，黑壳直接融进去 —— 画一圈真机同款的
            // keyline 描边把岛的轮廓勾出来（浅色下多这一圈也自然）。
            .overlay {
                if let keyline {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(keyline, lineWidth: 1)
                }
            }
            // 同时把外观锁成深色 —— 岛内是黑底，品牌图标要取它在深色下的那一档。
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }

    private var horizontalPadding: CGFloat {
        switch style {
        // 🔴 展开态 **不给** 外壳内边距（2026-10-28）。
        //    `IslandExpandedContent` 已经按 `previewLeading / previewHInset /
        //    previewTrailing` 精确模拟了系统 region 的 inset，这里再补 16
        //    就是**双重内缩** —— 实测内容距岛缘变成 32pt，
        //    主人一眼看出「图标、取件码、地址偏右，待取数量偏左」。
        //    展开态的左右边距统一由 preview* 常量负责，外壳只管画黑底和圆角。
        case .expanded: 0
        // 🔴 紧凑态左右各留 **7pt**（2026-09-23 从主人真机截图逐像素量得：
        //    系统给紧凑态内容的前边距 ≈ 7.3pt，不是 0）。之前写 0 的理由
        //    （"官方可画宽从岛边缘算起"）导致预览里图标**整个贴在胶囊左缘**、
        //    左角被帽形圆角压住 —— 主人："超出灵动岛紧凑显示区域了"。
        //    预览要复现的是"系统边距之后的内容区"，所以这 7pt 必须给。
        case .compact: 7
        case .minimal: 12
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .expanded: 14
        case .compact: 3.17
        case .minimal: 3.17
        }
    }
}

// MARK: - 机模底图（浅色 / 深色）

/// 机模底图选择。
///
/// 实时活动的内容是**软件真实渲染**的（与扩展同一份 View），机模只提供机身与壁纸。
/// 深色外观必须配深色壁纸 —— 否则黑色岛屿叠在浅色壁纸上、卡片的液态玻璃按深色渲染，
/// 拼出来是一个真机上不存在的组合。
///
/// 2026-10-30 主人给的四张 16 Pro 真实尺寸机模（1350×2760，白底已抠成透明）：
/// ```
/// 主屏幕   PhoneFrameLight  / PhoneFrameDark
/// 锁屏     LockFrameLight   / LockFrameDark
/// ```
enum MockupArt {
    enum Kind {
        case home, lock

        var light: String {
            switch self {
            case .home: "PhoneFrameLight"
            case .lock: "LockFrameLight"
            }
        }

        var dark: String {
            switch self {
            case .home: "PhoneFrameDark"
            case .lock: "LockFrameDark"
            }
        }
    }

    static func name(_ kind: Kind, scheme: ColorScheme) -> String {
        scheme == .dark ? kind.dark : kind.light
    }

    /// iPhone Duo 折叠态（外屏）官方机模，2026-11-01 主人提供（1574×2194）。
    /// 这两张是**带壳带壁纸**的成品图，不需要再拼屏幕。
    enum Duo {
        static let home = "DuoFrameHome"
        static let lock = "DuoFrameLock"
        /// 素材宽高比（1574 / 2194）
        static let ratio: CGFloat = 1574.0 / 2194.0

        /// 主人拍的实机截图（放进来就会优先使用）
        static let shotHome = Self.existing("DuoActivityHome")
        static let shotLock = Self.existing("DuoActivityLock")
        /// 展开态（宽黑条 + 取件码）
        static let shotExpanded = Self.existing("DuoActivityExpanded")

        /// 资源存在才返回名字 —— 没放截图时回落到官方机模
        private static func existing(_ name: String) -> String? {
            UIImage(named: name) != nil ? name : nil
        }
    }

    // MARK: 壁纸亮度（描边不透明度用）

    /// 机模**灵动岛两侧壁纸**的平均亮度（0…1，Rec.709）。
    ///
    /// 只采岛体左右那两条窄带：那里就是描边贴着的背景，岛本身是黑的、不能算进去。
    /// 结果按图名缓存 —— 每帧重解一张 1350×2760 的图会让滑动明显掉帧。
    static func wallpaperBrightness(scheme: ColorScheme) -> CGFloat {
        let key = name(.home, scheme: scheme)
        if let cached = brightnessCache[key] { return cached }
        let value = measureBrightness(imageName: key)
        brightnessCache[key] = value
        return value
    }

    private static var brightnessCache: [String: CGFloat] = [:]

    /// 岛体在 450pt 设计宽里占 39.5…410.5，两侧留白各约 15pt。
    private static let sampleStrips = [
        CGRect(x: 24, y: 38, width: 15, height: 42),
        CGRect(x: 411, y: 38, width: 15, height: 42),
    ]

    private static func measureBrightness(imageName: String) -> CGFloat {
        guard let cg = UIImage(named: imageName)?.cgImage else { return 0.5 }
        let scale = CGFloat(cg.width) / 450        // 1350px ↔ 450pt
        var total: CGFloat = 0
        var counted = 0
        for strip in sampleStrips {
            let px = CGRect(x: strip.minX * scale, y: strip.minY * scale,
                            width: strip.width * scale, height: strip.height * scale)
            guard let crop = cg.cropping(to: px) else { continue }
            total += averageLuminance(of: crop)
            counted += 1
        }
        return counted > 0 ? total / CGFloat(counted) : 0.5
    }

    /// 把整块缩小画进 1×1 像素 —— 逐像素平均最省事的写法。
    private static func averageLuminance(of image: CGImage) -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &pixel, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0.5 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = CGFloat(pixel[0]) / 255
        let g = CGFloat(pixel[1]) / 255
        let b = CGFloat(pixel[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

// MARK: - 预览页

struct ActivityPreviewGallery: View {
    @EnvironmentObject private var store: PickupStore
    /// 机模与描边强度都按外观分档，所以要读当前外观。
    @Environment(\.colorScheme) private var colorScheme

    /// 预览分页：0 展开 / 1 紧凑 / 2 锁屏。
    /// 🔴 2026-10-28 主人：三个机模做成**滑动切换**，底部一排按钮指示当前页
    /// （参考 Apple 官网那种轮播选择器的意思，不是照抄）。
    /// 过渡时长。截图脚手架 `ACTIVITY_SLOWMO=1` 拉长到 4 秒 ——
    /// 命令行点不到底部按钮、也没有帧抽取工具，只能把动画放慢再截图抓中间帧。
    private var transitionDuration: Double {
        ProcessInfo.processInfo.environment["ACTIVITY_SLOWMO"] == "1" ? 4.0 : 0.34
    }

    /// 截图脚手架：`SIMCTL_CHILD_ACTIVITY_PAGE=1` 可直接落到指定页（默认 0）。
    @State private var previewPage = Int(ProcessInfo.processInfo.environment["ACTIVITY_PAGE"] ?? "") ?? 0

    /// 当前窗口宽度：用来判断是不是 iPhone Duo 折叠态。
    /// 🔴 不能用机模自己的宽度 —— 它被 `aspectRatio` 锁死在 ~215pt；
    ///    也不能只看某一行的宽度（受内容约束）。窗口尺寸随折叠/展开变化，
    ///    页面因此重绘时会重新读到最新值。
    private var windowWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.bounds.width ?? 0
    }

    /// 真实待办里的前三条。
    private var realItems: [PickupActivityAttributes.Item] {
        store.pending.prefix(3).map { record -> PickupActivityAttributes.Item in
            let station = StationDirectory.shared.matchedName(in: [record.rawMessage])
            // 取色与主名同源 —— 走统一命名规则（`PickupNaming`），
            // 与真机卡面 / 列表卡取的是同一个字符串。
            let nameSource = record.naming(station: station).iconSource
            return PickupActivityAttributes.Item(
                id: record.id.uuidString,
                company: record.company,
                courier: record.courier,
                station: station,
                code: record.code,
                address: record.address,
                // 🔴 2026-11-22：锁屏卡 / 灵动岛永远是**深色玻璃底**，这里不能再传
                //    `resolvedFrom`（品牌原色）—— 圆通紫这种暗品牌在上面就是一团暗紫。
                //    统一传 `inkOnDark`（提亮版），与 App 内深色模式同一个取色口径。
                tint: CourierBrand.info(for: nameSource).inkOnDark,
                locker: record.widgetLockerLabel(WidgetDisplayOptions.full)
            )
        }
    }

    /// 兜底样本：库里一条待办都没有时（刚装、刚清空）预览不至于空着。
    /// 第一条带柜位，好让「码 + 柜位」这一段在预览里也能被看到。
    private static let sampleItems: [PickupActivityAttributes.Item] = [
        .init(id: "preview-1", company: "顺丰速运", code: "8-2-4031",
              address: "丰巢智能柜 · 望京SOHO T1 大堂", tint: 0x000000,
              locker: "2号柜"),
        .init(id: "preview-2", company: "蜜雪冰城", code: "A128",
              address: "望京SOHO T2 1层", tint: 0xE4002B),
    ]

    /// 预览数据：**优先用你库里的真实待办**，一条都没有时才退回样本。
    ///
    /// 🔴 2026-10-28 主人：「再加一条模拟数据，不就是真机的实际效果一模一样了吗」。
    /// 以前的门槛是「≥2 条才用真实数据」，手里只有 1 条待办时预览仍然画样本
    /// （拼多多 / D-1-3516），于是预览和真机上的岛永远是两套内容 ——
    /// 看着就像"预览在骗人"。现在只要有一条真实待办就用它，条数就用真实条数。
    private var items: [PickupActivityAttributes.Item] {
        // 截图脚手架：ACTIVITY_LONG_CODE=1 → 用 13 位运单号压测「码太长会不会冲出卡片」
        if ProcessInfo.processInfo.environment["ACTIVITY_STATION"] == "1" {
            return [.init(id: "st-1", company: "拼多多", courier: "圆通速递",
                          station: "兔喜生活", code: "YT8861990771306",
                          address: "家佳福超市甘州院子店", tint: 0x5D3FD3, locker: "2号柜")]
        }
        if ProcessInfo.processInfo.environment["ACTIVITY_LONG_CODE"] == "1" {
            return [
                .init(id: "long-1", company: "圆通速递", code: "YT8861990771306",
                      address: "家佳福超市甘州院子店", tint: 0x5D3FD3, locker: "2号柜"),
                .init(id: "long-2", company: "顺丰速运", code: "8-2-4031",
                      address: "丰巢智能柜 · 望京SOHO T1 大堂", tint: 0x000000, locker: "2号柜"),
                .init(id: "long-3", company: "拼多多", code: "D-1-3516",
                      address: "菜鸟驿站 · 恒大名都东门", tint: 0xE4002B, locker: nil),
                .init(id: "long-4", company: "申通快递", code: "3-7-12",
                      address: "蓝山公馆六期西门免喜生活", tint: 0x1B6AC9, locker: nil),
            ]
        }
        return realItems.isEmpty ? Self.sampleItems : realItems
    }

    private var usingSample: Bool { realItems.isEmpty }

    /// 带「还有 N 条」的状态：卡面只画一条，其余用计数交代
    private var multiState: PickupActivityAttributes.ContentState {
        // 锁屏卡一页三条：把预览也按三条给，才能看出翻页与分隔线
        // 截图脚手架：ACTIVITY_ROWS=1|2 控制锁屏卡这一页显示几条
        let rows = Int(ProcessInfo.processInfo.environment["ACTIVITY_ROWS"] ?? "") ?? PickupActivityAttributes.LockScreenMetrics.perPage
        let page = Array(items.prefix(max(1, min(rows, PickupActivityAttributes.LockScreenMetrics.perPage))))
        return .init(item: page.first ?? items[0],
                     pendingCount: max(items.count, 5),
                     items: page.isEmpty ? items : page)
    }

    /// 单条状态：不出现计数文案，用来对照两种排布
    private var singleState: PickupActivityAttributes.ContentState {
        .init(item: items.count > 1 ? items[1] : items[0], pendingCount: 1)
    }

    /// 灵动岛展开用的状态：只画**最近一条**的完整信息，条数交给右上角计数。
    ///
    /// 计数用 `max(items.count, 3)`：多条时的计数样式（一位数）与单条一致，
    /// 预览取 3 是为了让右上角的两位数以内的排布也能被看到。
    private var islandState: PickupActivityAttributes.ContentState {
        .init(item: items[0], pendingCount: max(items.count, 3))
    }

    // 🔴 预览壳上所有品牌色一律走 `islandTint` 亮度插值 —— 与真机锁屏卡
    //    / 岛的亮化口径一致；原始品牌色（顺丰纯黑）在暗色页面上全部隐形。
    private var accent: Color { islandTint(multiState.item.tint) }

    /// 灵动岛外圈描边 = **取件码的颜色**（2026-10-30 主人口径）。
    ///
    /// 它不是装饰：真机的 `keylineTint` 就是让"这个岛和下面那个码是同一件事"的视觉线索，
    /// 所以取色必须与岛内码走同一条路（`islandTint` 亮度插值），不能另取品牌原色 ——
    /// 顺丰那种纯黑在暗壁纸上描边会直接隐形。
    ///
    /// 强度随壁纸亮度自适应：**0.75 − 0.30 × 亮度**，夹在 0.45…0.75。
    ///
    /// 亮壁纸上一圈实色环会显脏、抢走取件码的注意力，所以压到 0.45 一带；
    /// 暗壁纸上它是唯一的轮廓线索，要顶到 0.75 一带才看得见。
    /// 亮度由 `MockupArt.wallpaperBrightness` 现场从机模图采样，不写死。
    private var islandKeylineOpacity: Double {
        let brightness = Double(MockupArt.wallpaperBrightness(scheme: colorScheme))
        return min(0.75, max(0.45, 0.75 - 0.30 * brightness))
    }

    private var islandKeyline: Color {
        islandTint(islandState.item.tint).opacity(islandKeylineOpacity)
    }

    /// 线宽固定 0.8pt：真机的 keyline 是「一根细线」而不是描边效果，
    /// 线宽跟着亮度变会让它在深色下显得发糊。
    private let islandKeylineWidth: CGFloat = 0.8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                activityToggleSection
                if isDuoDevice {
                    duoUnavailableNote
                } else {
                    previewPagerSection
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(AppTheme.pageBackground)
        // 🔴 2026-11-01 主人：开关行保留「实时活动」，导航栏换成更具体的名字，
        //    否则一行字在同一屏出现两次。
        .navigationTitle("实时活动")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startAutoplayIfNeeded)
        .sheet(isPresented: $showPaywall) {
            NavigationStack { FullVersionView() }
                .modifier(PaywallSheetSizing())
        }
    }

    /// iPhone Duo：**不做预览**，只说明原因（2026-11-01 主人定）。
    ///
    /// 试过渲染、也试过贴实拍截图，都不好看：Duo 外屏的灵动岛是侧边竖排形态，
    /// 与 iPhone 横向岛不是一套几何，在静态机模上拼总有违和感。
    /// 与其给一个"看起来像、其实不像"的预览，不如老实说明。
    private var duoUnavailableNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("暂不提供预览")
                    .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text("这台设备的灵动岛形态比较特殊，暂不提供预览。\n\n开关仍然有效：打开后，锁屏与灵动岛会按系统的方式显示最新待取的取件码。")
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    /// 截图脚手架：`ACTIVITY_AUTOPLAY=1` 每 2.4 秒自动翻一页。
    ///
    /// 只为了取证「切换是交叉淡入、不是左右滑」——本机没有触摸注入，
    /// 也没装帧抽取工具，只能让页面自己动、再由外部定时截图抓中间帧。
    private func startAutoplayIfNeeded() {
        guard ProcessInfo.processInfo.environment["ACTIVITY_AUTOPLAY"] == "1" else { return }
        Task { @MainActor in
            // 放慢模式下把间隔也拉长，否则 4 秒的过渡与 2.4 秒的间隔会一直叠着走
            let interval: UInt64 = transitionDuration > 1 ? 6_000_000_000 : 2_400_000_000
            while true {
                try? await Task.sleep(nanoseconds: interval)
                withAnimation(.smooth(duration: transitionDuration)) {
                    previewPage = (previewPage + 1) % max(pageMeta.count, 1)
                }
            }
        }
    }


    // MARK: 滑动分页预览

    /// 三个形态共用一个机模位，左右滑动切换，底部一排按钮同时指示 + 可点。
    ///
    /// 为什么不再各占一块：三张真机截图纵向铺开要滚两屏半，
    /// 而它们本来就是同一件事（实时活动在不同位置的样子）——
    /// 分页看更接近用户真实的心理模型，也让一屏装得下。
    private var previewPagerSection: some View {
        // 🔴 2026-10-28 主人：说明文字挪到**按钮下方**，上方只留标题。
        //    原因是说明长度随页面变化（一行 / 两行），若把说明放在机模上方，
        //    切换页面时机模会被推着上下跳 —— 位置不固定，看着晃。
        VStack(alignment: .leading, spacing: 12) {
            // 标题/说明**瞬时替换**：它们跟着过渡交叉淡入的话，两个不同的句子
            // 会在中途叠印（慢放时看得很清楚）。机模要连贯、文字要干断。
            Text(currentPageTitle.L)
                .font(.headline)
                .transaction { $0.animation = nil }

            stage

            pagePicker
                .frame(maxWidth: .infinity)

            Text(currentPageNote.L)
                .font(.caption)
                .transaction { $0.animation = nil }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)

        }
    }

    // MARK: 舞台：一台机模 + 一个会变形的活动

    /// 三个状态**共用同一台机模**，动的只有那块活动。
    ///
    /// 🔴 2026-10-30 主人的两轮口径合起来是：①不要左右滑动（那是翻页语汇）；
    ///    ②也别整块交叉淡入（两个手机叠印，不优雅）。所以这里做成**一个连续动画**：
    ///
    ///    · 岛展开 ⇄ 岛收起：黑岛的 宽 / 高 / 圆角 连续插值
    ///      （371×92×46 ⇄ 230×43×21.5），两套内容在同一个黑岛里交叉 ——
    ///      看起来就是岛在长、在缩，而不是两张图对穿；
    ///    · 岛 ⇄ 锁屏卡片：壁纸交叉 + 岛原地淡出 + 卡片从下方浮到锁屏位置，
    ///      读作「这条活动落到了锁屏上」。
    ///
    /// 机身为什么允许整张交叉：两张机模是同一台 16 Pro 渲出来的，
    /// 屏幕以外平均差 11/765（肉眼不可见），交叉时看到的只有壁纸在换。
    /// iPhone Duo 折叠态（外屏）的判定：只靠**可用宽度**。
    /// 直板机 ≈370pt、Duo 外屏 ≈434pt、Duo 内屏 ≈637pt —— 区间互不重叠。
    /// ⚠️ 没有公开的"是否折叠"API，Apple 只按 size class / 尺寸表达。
    /// 当前窗口尺寸（判断设备几何用）
    private var windowSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.bounds.size ?? .zero
    }

    /// 是不是 iPhone Duo —— **折叠态与展开态都要算**（2026-11-01 主人要求内屏也不给预览）。
    ///
    /// 两个几何特征互为补充，且都与任何 iPhone 直板机不重叠：
    /// ```
    ///   Duo 折叠态  466 ×  678   → 高 < 720
    ///   Duo 展开态  669 ×  951   → 宽 > 600（iPhone 最宽 440）
    ///   直板机      402 ×  874 / 440 × 956   → 两条都不满足
    /// ```
    /// ⚠️ 不要只写宽度带 `400…520`：iPhone 16 Pro 的 402pt 正好在里面，
    /// 直板机会被误判成 Duo（2026-11-01 踩过）。
    private var isDuoDevice: Bool {
        // 🔴 2026-11-12 主人：「iPad 的 UI 不要和 iPhone Duo 混在一起」。
        //    iPad 宽度恒 > 600（iPad mini 也有 744），会被下面的几何判断误判成 Duo。
        //    先按 idiom 闸掉 iPad；iPhone 仍用原来的几何判断。
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        let size = windowSize
        return size.height < 720 || size.width > 600
    }

    private var stage: some View {
        Group {
            if isDuoDevice {
                GeometryReader { proxy in
                    duoStage(width: proxy.size.width)
                }
            } else {
                GeometryReader { proxy in
                    phoneStage(proxy: proxy)
                }
            }
        }
        // Duo 的机模是 1574×2194（比例 0.717），和 iPhone 的 450×920（0.489）不同，
        // 容器比例得跟着换，否则图会被宽度限制、缩成一小块。
        .aspectRatio(isDuoDevice ? MockupArt.Duo.ratio : 450.0 / 920.0, contentMode: .fit)
        .frame(height: isDuoDevice ? 470 : 440)
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: transitionDuration), value: previewPage)
        .clipped()
    }

    /// Duo 折叠态：**用截图展示，不渲染**（2026-11-01 主人定）。
    ///
    /// 原因：Duo 外屏的灵动岛是侧边竖排形态，跟 iPhone 的横向岛不是一套几何；
    /// 在机模上叠渲染既难对齐、也容易和机模里烤进去的时间和 Wi-Fi 打架。
    /// 所以这里直接显示**成品截图**，与真机一模一样。
    ///
    /// 素材约定（把截图丢进 Assets 即可，无需改代码）：
    ///   · `DuoActivityHome` —— 外屏主屏幕 + 灵动岛（折叠态紧凑）
    ///   · `DuoActivityLock` —— 外屏锁屏 + 实时活动卡片
    /// 没有提供时，回落到主人给的官方机模（`DuoFrameHome` / `DuoFrameLock`）。
    private func duoStage(width: CGFloat) -> some View {
        // 三种形态各用各的截图：展开（宽条）/ 紧凑（竖岛）/ 锁屏（卡片）
        let shot: String?
        let fallback: String
        if isLockState {
            shot = MockupArt.Duo.shotLock; fallback = MockupArt.Duo.lock
        } else if currentState == .expanded, let expanded = MockupArt.Duo.shotExpanded {
            shot = expanded; fallback = MockupArt.Duo.home
        } else {
            shot = MockupArt.Duo.shotHome; fallback = MockupArt.Duo.home
        }
        return Image(shot ?? fallback)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func phoneStage(proxy: GeometryProxy) -> some View {
        Group {
            let scale = max(proxy.size.width, 1) / 450

            ZStack(alignment: .top) {
                mockupLayers
                islandLayer
                lockCardLayer
            }
            .frame(width: 450, height: 920, alignment: .top)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 450 * scale, height: 920 * scale, alignment: .topLeading)
        }
    }

    // MARK: 舞台 · 壁纸

    private var mockupLayers: some View {
        ZStack {
            Image(MockupArt.name(.home, scheme: colorScheme))
                .resizable()
                .frame(width: 450, height: 920)
                .opacity(isLockState ? 0 : 1)

            Image(MockupArt.name(.lock, scheme: colorScheme))
                .resizable()
                .frame(width: 450, height: 920)
                .opacity(isLockState ? 1 : 0)
        }
    }

    // MARK: 舞台 · 灵动岛（展开 ⇄ 折叠，缩放变形）

    /// 岛只有一个动作：**在黑岛自己的形状里缩放**。
    ///
    /// ```
    /// 展开   371 × 115   圆角 46      （内容按 92 布局，见 activityHeight 注释）
    /// 紧凑   230 × 43    圆角 21.5
    /// ```
    ///
    /// 宽高、圆角连续插值，两套内容在同一个黑岛里交叉 —— 读起来是"这张卡展开 / 收起"，
    /// 不是两张图对穿。切到锁屏时它**自己收掉**（淡出 + 轻微缩小），
    /// 不会往屏幕下面走：锁屏卡片和灵动岛是两回事，没有从岛里长出卡片的道理。
    private var islandLayer: some View {
        ZStack {
            compactIslandContent
                .opacity(isCompactState ? 1 : 0)

            IslandExpandedContent(state: islandState)
                .frame(width: 371, height: IslandExpandedMetrics.previewTotalHeight)
                .opacity(currentState == .expanded ? 1 : 0)
        }
        .frame(width: islandWidth, height: islandHeight)
        .clipShape(.rect(cornerRadius: islandRadius, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: islandRadius, style: .continuous)
                .fill(Color.black)
        }
        .overlay {
            RoundedRectangle(cornerRadius: islandRadius, style: .continuous)
                .strokeBorder(islandKeyline, lineWidth: islandKeylineWidth)
        }
        // 岛内恒为深色底，品牌色与文字取深色档（与真机一致）
        .environment(\.colorScheme, .dark)
        // 落向锁屏时收起来：淡出 + 缩一点，像岛收回了传感器那边
        .opacity(isLockState ? 0 : 1)
        .scaleEffect(isLockState ? 0.88 : 1, anchor: .top)
        // 450 宽居中、贴顶 37.7pt —— 与机模挖孔顶边等高
        .frame(width: 450, height: 920, alignment: .top)
        .offset(y: 37.7)
    }

    private var compactIslandContent: some View {
        HStack(spacing: 0) {
            IslandCompactLeading(state: islandState)
            Spacer(minLength: 0)
            IslandCompactTrailing(state: islandState)
        }
        .padding(.horizontal, 7)
        .frame(width: 230, height: 43)
    }

    // MARK: 舞台 · 锁屏卡片（独立对象，就地浮出）

    private var lockCardLayer: some View {
        ActivityCardShell(tint: accent, backdropItem: multiState.item) {
            ActivityLockScreenCard(state: multiState)
        }
        .frame(width: 374)
        .frame(width: 450, height: 920, alignment: .bottom)
        // 卡片底距屏幕底 148pt（真机锁屏实测）；出现前低 18pt，浮上来才自然
        .offset(y: -148 + (isLockState ? 0 : 18))
        .opacity(isLockState ? 1 : 0)
    }

    // MARK: 舞台 · 尺寸与状态

    private enum PreviewState: Int, CaseIterable {
        case expanded, compact, lock
    }

    private var states: [PreviewState] {
        DeviceProfile.hasDynamicIsland ? [.expanded, .compact, .lock] : [.lock]
    }

    private var currentState: PreviewState {
        states[min(max(previewPage, 0), states.count - 1)]
    }

    private var isCompactState: Bool { currentState == .compact }
    private var isLockState: Bool { currentState == .lock }

    /// 岛的几何：在展开 / 紧凑两套值之间连续插值；锁屏态沿用紧凑值（此时已淡出）。
    private var islandWidth: CGFloat { isCompactState ? 230 : 371 }

    /// 展开态比 `previewTotalHeight` 再高 1/4。
    ///
    /// 🔴 2026-10-30 主人对着真机比：预览里这块黑岛**自身的高度**偏矮（不是位置偏），
    ///    差约四分之一。所以外壳高度 = 92 × 1.25 = **115**，内容仍按 92 布局、
    ///    在壳里居中 —— 多出来的 23pt 均匀落在上下，取件码与地址的相对间距不变。
    private var islandHeight: CGFloat {
        // 2026-11-23：内容自身已带四周等距内边距，外壳不再额外放大 1.25，
        // 否则上下又会多出一圈空。
        isCompactState ? 43 : IslandExpandedMetrics.previewTotalHeight
    }

    private var islandRadius: CGFloat { isCompactState ? 21.5 : 46 }

    // MARK: 文案

    private var pageMeta: [(title: String, note: String)] {
        states.map { state in
            switch state {
            case .expanded:
                return (title: "灵动岛 · 展开",
                        note: "长按或同时有两个活动时展开，可画面积最大；只画最近一条待办，条数看右上角")
            case .compact:
                return (title: "灵动岛 · 紧凑",
                        note: "同时有两个活动时收成紧凑态：左 App 图标、右待取数量（超过 99 显示 99+），三个以上只剩图标")
            case .lock:
                return (title: "锁屏卡片",
                        note: "锁屏上多条待办时取最新一条，其余用「还有 N 条」交代")
            }
        }
    }

    private var currentPageTitle: String { pageMeta[pageIndex].title }
    private var currentPageNote: String { pageMeta[pageIndex].note }
    private var pageIndex: Int { min(max(previewPage, 0), pageMeta.count - 1) }

    /// 底部切换按钮：选中的拉成胶囊并填主色，未选中的是浅灰胶囊。
    private var pagePicker: some View {
        HStack(spacing: 10) {
            ForEach(Array(pageMeta.enumerated()), id: \.offset) { index, page in
                let on = index == pageIndex
                Button {
                    withAnimation(.smooth(duration: transitionDuration)) { previewPage = index }
                } label: {
                    Text(page.title.L)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .lineLimit(1)
                        .padding(.horizontal, on ? 16 : 13)
                        .padding(.vertical, 7)
                        .background {
                            Capsule(style: .continuous)
                                .fill(on ? AnyShapeStyle(AppTheme.accent)
                                          : AnyShapeStyle(Color(.secondarySystemFill)))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }


    // MARK: 总开关

    /// 🔴 总开关（2026-09-23 主人要求）。
    ///
    /// 存储在 **App Group**（`LiveActivitySetting`），理由见该类型注释：
    /// 桌面小组件的勾选意图在**扩展进程**里直接调 `PickupActivityController.sync`，
    /// 那条路径不经本页，开关只存 App 的 standard defaults 就会被勾选"复活"。
    ///
    /// 切换后立即 `sync` 一次：
    ///   · 关 → 控制器第 0 道门当场收掉正在跑的活动；
    ///   · 开 → 按当前待办立刻补起一张卡，不用等下一次数据变动。
    /// 非 Pro 点「实时活动」开关时直接弹订阅页（预览切换按钮不受影响）
    @State private var showPaywall = false

    private var activityToggleSection: some View {
        // 🔴 2026-10-28 主人：「总开关」三个字删掉 —— 卡片里那行「显示实时活动」已说明一切。
        // 🔴 2026-11-22 主人：只留作用，删掉「关闭后立刻收掉、重开自动恢复」这两句过程描述。
        SettingsGroup(title: "",
                      note: "在锁屏与灵动岛上显示最新待取的取件码。") {
            // 🔴 2026-11-01 主人：去掉「显示」二字，标题就叫「实时活动」。
            SettingsPlainRow(title: "实时活动") {
                if EntitlementSnapshot.licensedPro {
                    Toggle("", isOn: Binding(
                        get: { LiveActivitySetting.isEnabled },
                        set: { on in
                            LiveActivitySetting.isEnabled = on
                            PickupActivityController.sync(pending: store.pending)
                        }))
                        .labelsHidden()
                        .tint(AppTheme.accent)
                } else {
                    // 与「通知」页同一套：看着是普通关闭态开关，点一下弹订阅页，
                    // 用 overlay 接管点击（overlay 不参与布局，开关不会被挤走）
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .allowsHitTesting(false)
                        .overlay {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showPaywall = true }
                                .accessibilityLabel("实时活动")
                                .accessibilityHint("需要Codelumi Pro")
                        }
                }
            }
        }
    }

    // MARK: 小节标题

    private func label(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.L)
                .font(.headline)
            Text(note.L)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
