import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 桌面小组件「款式」清单（2026-11-22 重构）
//
// 主人原话：「桌面小组件中上面的显示内容的几个开关就不要了，我们直接可以内置多个
// 不同尺寸的小组件，当前显示不同内容的小组件我们根据尺寸做好，用户直接选择对应的
// 添加就行」。
//
// 也就是把 **「一个组件 + 六个显示开关」** 换成 **「多个组件，每个固定一种版式」**。
//
// 🔴 2026-11-22 晚定稿（主人：「中尺寸待取清单的详情页面中的显示开关应该有 4 个…
//    这三个尺寸的小组件名称统一为待取清单，这个三个小组件的尺寸可以小中大切换」）：
//    · **清单款三条**（精简 / 中 / 大），都叫「待取清单」，都声明 小+中+大 三种尺寸 ——
//      图库里各占一条，拖到桌面后长按即可换尺寸；
//    · 三个开关组：中/大/超大 = 取件地址 + 快递公司 + 快递驿站 + 完整信息；
//      精简款（小）只有 快递驿站 + 快递公司；
//    · 其余 7 个版式**按尺寸各占一条**（如「最近一件」小/中/大三条互不通用）。
//
// 🔴 为什么每个款式必须是独立的 `kind`（而不是同一个 kind 加参数）：
//    WidgetKit 的条目按 `kind` 注册，系统「小组件库」里**一个 kind 就是一条卡片**，
//    各自有名字、简介、尺寸。想让用户在图库里直接挑到「只有取件码的小尺寸」和
//    「带驿站的 3 条清单」，就只能拆成两个 kind —— 一个 kind 无论怎么配置都只占一条。
//
// 🔴 为什么每个 kind 只声明**一个**尺寸：
//    声明多个尺寸时图库里只有一条，用户拖到桌面后再长按能切成别的尺寸，
//    切过去就变成另一种行数（「取件码 · 极简」切到大尺寸会突然铺 8 行），
//    与这条款式的名字对不上。一个 kind 一个尺寸，名字才诚实。
//    唯一例外是 `.all`：iPad 横版超大与 iPhone 竖版超大是两块完全不同的画布，
//    但内容口径相同，合并成一条才不会在图库里出现两个同名条目。
//
// ⚠️ 与 App 侧的分工：`WidgetSettingsView` 用**同一份清单**渲染「款式库」与详情页的
//    等比预览 —— 桌面小组件无法在 App 内真正添加（系统不允许），
//    唯一能给用户看的真实形态，就是在 App 里用同一份视图代码按真实尺寸渲染一次。
// ============================================================================

// MARK: - 每行显示到哪一层（用户可调）

/// 清单款每一行**能**显示哪些字段 —— 也就是详情页里那排开关。
///
/// 主人 2026-11-22 晚定稿：
///   · 中 / 大（还有超大）四个开关：**取件地址 / 快递公司 / 快递驿站 / 完整信息**；
///   · 小尺寸两个开关：**快递驿站 / 快递公司** —— 158pt 里一行副标题都勉强，
///     地址与「完整信息」放进去只会变成「馨月湖小区南门…」这种半截字。
///
/// 取件码与柜位不在其中：码是这款组件存在的唯一理由，柜位跟码同一行、不占第二行宽度。
enum WidgetDisplayField: String, CaseIterable, Identifiable {
    case address
    case company
    case station
    /// 一把全开的总开关 —— 不想逐项点时直接开它
    case complete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .address:  return "取件地址"
        case .company:  return "快递公司"
        case .station:  return "快递驿站"
        case .complete: return "完整信息"
        }
    }
}

/// 四个开关的真值（App Group）。
///
/// 🔴 一行**能不能**显示某字段由款式决定（`WidgetPreset.fields`），
///    这一行**要不要**显示由用户决定 —— 两层不能混：
///    小尺寸款式根本没有「地址」这一项，用户在详情页也就看不到它。
enum WidgetDisplaySetting {
    static let addressKey = "codelumi.widget.showAddress"
    static let companyKey = "codelumi.widget.showCompany"
    static let stationKey = "codelumi.widget.showStation"
    static let completeKey = "codelumi.widget.showComplete"

    /// 四个开关的当前状态（`complete` 是一把总开关，不改其余三个的值）。
    struct State {
        var address: Bool
        var company: Bool
        var station: Bool
        var complete: Bool
    }

    private static var store: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    /// 默认：驿站 + 地址开、公司关、完整信息关 —— 与改造前大尺寸的默认观感一致。
    /// 判据是「这个键从没被写过」，写过就照写的来（`store.bool` 读不到时返回 false，
    /// 直接用会把默认值吃掉，所以统一走 `flag(_:default:)`）。
    static var state: State {
        State(address: flag(addressKey, default: true),
              company: flag(companyKey, default: false),
              station: flag(stationKey, default: true),
              complete: flag(completeKey, default: false))
    }

    private static func flag(_ key: String, default def: Bool) -> Bool {
        store.object(forKey: key) == nil ? def : store.bool(forKey: key)
    }

    /// 只落盘，不重画 —— 调用方负责 `WidgetCenter.shared.reloadAllTimelines()`。
    static func setAddress(_ on: Bool) { store.set(on, forKey: addressKey) }
    static func setCompany(_ on: Bool) { store.set(on, forKey: companyKey) }
    static func setStation(_ on: Bool) { store.set(on, forKey: stationKey) }
    static func setComplete(_ on: Bool) { store.set(on, forKey: completeKey) }

    static func set(_ field: WidgetDisplayField, _ on: Bool) {
        switch field {
        case .address:  setAddress(on)
        case .company:  setCompany(on)
        case .station:  setStation(on)
        case .complete: setComplete(on)
        }
    }
}

// MARK: - 版式（画面怎么组织）

/// 小尺寸的**版式**。与 `WidgetContent` 是两件事：
/// `content` 决定「列表里每条显示到哪一层」，`layout` 决定「这块画布长什么样」。
///
/// 🔴 2026-11-22 主人：「你多几个小尺寸的小组件，不全是取件列表啊，还可以是
///    今日待取数量单独做一个，发散思维」。列表是「逐条读码」的形态，
///    但桌面上经常只想知道**一个数**（几件没取）、或者**一个码**（最近那件），
///    这些用列表画出来是浪费 —— 所以小尺寸另开四条非列表版式。
enum WidgetLayout: String {
    /// 取件码列表（现有全部款式都是这一种）
    case list
    /// 取件进度：**今日到件数 + 取件进度**（2026-11-22 合并原来两款）
    case todayProgress
    /// 单码聚焦：只放一件，取件码放到最大
    case focusCode
    /// 驿站分布：哪个驿站还压着几件
    case stationBars
    /// 最久未取：压了几天 + 那一件的取件码
    case oldestPending
    /// 取件码卡片：一件一件看（右侧竖排切换）+ 右上角一键拷贝
    case codeCard
}

// MARK: - 款式

struct WidgetPreset: Identifiable, Hashable {
    /// 同时是 WidgetKit 的 `kind`。系统按它认条目。
    ///
    /// 🔴 **发出去之后不可改**：改了等于换了一个组件 —— 老用户桌面上那个实例
    ///    会变成「无法载入」的空框。追加新款只能新增 id，不能改现有的。
    let id: String
    /// 系统小组件库里的标题（同时也是 App 款式库里的名字）。
    let name: String
    /// 系统小组件库里的简介。一句话说清「显示什么 + 几条」。
    let summary: String
    /// 支持的尺寸。99% 的款式只有一个；见文件头 `.all` 的例外说明。
    let families: [WidgetFamily]
    /// 版式。默认列表。
    var layout: WidgetLayout = .list
    /// 这一款在详情页里露哪几个开关（`WidgetDisplayField` 的顺序即显示顺序）。
    ///
    /// 🔴 小尺寸清单款只有驿站与公司两项；中 / 大 / 超大四个都有。
    ///    这是**款式能力**，不是用户偏好 —— 用户偏好存在 `WidgetDisplaySetting`。
    var fields: [WidgetDisplayField] = WidgetDisplayField.allCases

    /// 库里展示用的尺寸（仅 App 款式库用）。
    ///
    /// 🔴 2026-11-23 老大：「待取清单在设置里把中尺寸和大尺寸也做一份，不然我以为它没有其他尺寸」——
    ///    一款支持三档尺寸时，系统图库只算**一条**，但 App 里的款式库如果也只画一张，
    ///    用户会以为"它只有小尺寸"。所以库里按 `libraryVariants` 展开成三张卡，
    ///    只改**预览画多大**，kind 与系统注册完全不变。
    var displayFamily: WidgetFamily? = nil

    /// 主尺寸（预览、尺寸标签都以它为准）。
    var family: WidgetFamily { displayFamily ?? families[0] }

    /// App 款式库里的展示条目：多尺寸款展开成每尺寸一条，单尺寸款就是自己。
    var libraryVariants: [WidgetPreset] {
        guard families.count > 1 else { return [self] }
        return families.map { size in
            var copy = self
            copy.displayFamily = size
            return copy
        }
    }

    /// 库里的列表身份：同一款的三个尺寸必须互不相同，否则 `ForEach` 会认成同一条。
    var libraryID: String { id + "-" + String(describing: family) }

    /// 免费版只能用**小 / 中**（`WidgetPageSize.freeFamilies`），大尺寸以上要 Pro。
    ///
    /// 🔴 判定看「这条款式的主尺寸」而不是全部 families：`.all` 是超大档，
    ///    两个 family 都超出免费档，用主尺寸判一次就够。
    var needsPro: Bool { !WidgetPageSize.isFreeFamily(family) }

    /// 尺寸标签（列表右侧）。
    var sizeName: String {
        switch family {
        case .systemSmall: "小"
        case .systemMedium: "中"
        case .systemLarge: "大"
        default: "超大"
        }
    }

    /// 这款要不要在详情页露出「显示内容」开关。
    ///
    /// 只有清单款露：非清单版式（取件进度 / 单码 / 驿站分布…）画什么由版式本身决定，
    /// 摆一排开关在那儿却不起作用，比没有更糟。
    var isCustomizable: Bool { layout == .list }

    /// 这一款生效的显示选项。
    ///
    /// 「完整信息」是一把总开关：开了就三项全显示（只显示本款**具备**的字段，
    /// 小尺寸款就算开了它也不会凭空长出地址行）。
    var options: WidgetDisplayOptions {
        let state = WidgetDisplaySetting.state
        let complete = fields.contains(.complete) && state.complete
        return WidgetDisplayOptions(
            showsCompany: fields.contains(.company) && (complete || state.company),
            showsStation: fields.contains(.station) && (complete || state.station),
            showsAddress: fields.contains(.address) && (complete || state.address),
            showsLocker: true)
    }
}

// ⚠️ 「款式 → 预览画布」的映射（`WidgetCanvas.Style`）不放在这里：
//    `WidgetCanvas` 是 App target 的视图（`WidgetPreviewGallery.swift`），
//    本文件要同时被小组件扩展编译，引用它会链接失败。映射写在 App 侧。

extension WidgetPreset {
    /// 系统小组件库里出现的全部款式，**顺序即图库顺序**（也是 App 里款式库的顺序）。
    ///
    /// 排列逻辑：先按尺寸从小到大，同尺寸内「清单款在前，非清单版式在后」——
    /// 用户在系统图库里横向滑动时看到的是一条由「逐条读码」到「一眼看结论」的连续序列。
    ///
    /// 🔴 2026-11-22 晚第二次改版（主人：「中尺寸的小组件你把待取清单继续合并为一个吧…
    ///    然后中尺寸的小组件你在按照小尺寸的小组件的内容做对应的中尺寸的小组件，
    ///    然后大尺寸的小组件亦是如此」）：
    ///    · 中 / 大各**一条清单款** + 七个非清单版式，与上一版「8 款清单穷举」相比
    ///      少了 14 条重复条目，图库不再被「待取清单 · 快递地址」这类同质卡塞满；
    ///    · 小尺寸保持 10 条（3 清单变体 + 5 总览 + 2 动作），语音添加随语音功能一起删除。
    static var all: [WidgetPreset] {
        var presets: [WidgetPreset] = [
            // ── 清单（一）：小尺寸 · 精简版 —— 只有驿站 / 公司两个开关 ──
            //
            // 🔴 2026-11-23 老大：「待取清单的小组件现在小中大各有一个，再没有其他的，
            //    但是在桌面添加的时候会出现同尺寸的好几个」——
            //    根因是这三条清单款（CodelumiCode / CodelumiList / CodelumiBoard）
            //    都把 `families` 写成了三段，于是**同一个尺寸在图库里出现三个同名条目**。
            //    → 改成一条只认一个尺寸：小 = 精简版（2 开关），中 / 大 = 完整版（4 开关）。
            //    代价：桌面上已经放着的那几个实例如果尺寸对不上，会显示「无法载入」，
            //    需要删掉重新添加（TestFlight 阶段可接受）。
            WidgetPreset(id: "CodelumiCode",
                         name: "待取清单",
                         summary: "小中大可切换。一页 3–4 条，四个显示开关可挑。",
                         families: [.systemSmall, .systemMedium, .systemLarge],
                         fields: [.address, .company, .station, .complete]),

            // ── 小尺寸 · 非列表（2026-11-22 主人：「不全是取件列表啊…发散思维」）──
            //
            // 这五款的共同点：**不逐条读码**，一块画布只回答一个问题。
            // 放在清单款之后，图库里是「先看码 → 再看总览」的顺序。
            WidgetPreset(id: "CodelumiProgress",
                         name: "取件进度",
                         summary: "一个环看取走几成，顶上带今日到件。",
                         families: [.systemSmall],
                         layout: .todayProgress),
            WidgetPreset(id: "CodelumiFocusCode",
                         name: "最近一件",
                         summary: "只放一件，取件码放到最大。",
                         families: [.systemSmall],
                         layout: .focusCode),
            WidgetPreset(id: "CodelumiStations",
                         name: "驿站分布",
                         summary: "哪个驿站还压着几件，最多 3 个。",
                         families: [.systemSmall],
                         layout: .stationBars),
            WidgetPreset(id: "CodelumiOldest",
                         name: "最久未取",
                         summary: "压了几天，加上那一件的取件码。",
                         families: [.systemSmall],
                         layout: .oldestPending),

            // ── 小尺寸 · 动作型 ─────────────────────────────────────
            // 🔴 2026-11-22 晚主人：「单个取件码的小组件可以和一键拷贝的小组件组合成一个，
            //    然后把这个内容的不做大尺寸的，不然太浪费了」——
            //    看码与拷贝本来是同一次动作的两半，拆两条等于让用户在图库里二选一。
            WidgetPreset(id: "CodelumiCodeCard",
                         name: "单个取件码",
                         summary: "一件一件看，右上角一键复制，底部可翻。",
                         families: [.systemSmall],
                         layout: .codeCard),

            // ── 中尺寸：一条清单款（显示内容由详情页开关决定）+ 七个版式 ──
            WidgetPreset(id: "CodelumiProgressM",
                         name: "取件进度",
                         summary: "左边今日到件，右边环看取走几成。",
                         families: [.systemMedium],
                         layout: .todayProgress),
            WidgetPreset(id: "CodelumiFocusCodeM",
                         name: "最近一件",
                         summary: "只放一件，取件码放到最大。",
                         families: [.systemMedium],
                         layout: .focusCode),
            WidgetPreset(id: "CodelumiStationsM",
                         name: "驿站分布",
                         summary: "哪个驿站还压着几件，最多 3 个。",
                         families: [.systemMedium],
                         layout: .stationBars),
            WidgetPreset(id: "CodelumiOldestM",
                         name: "最久未取",
                         summary: "压了几天，加上那一件的取件码。",
                         families: [.systemMedium],
                         layout: .oldestPending),
            WidgetPreset(id: "CodelumiCodeCardM",
                         name: "单个取件码",
                         summary: "一件一件看，右上角一键复制，底部可翻。",
                         families: [.systemMedium],
                         layout: .codeCard),

            // ── 大尺寸：一条清单款 + 七个版式 ───────────────────────
            WidgetPreset(id: "CodelumiProgressL",
                         name: "取件进度",
                         summary: "进度条加全年热力图，一眼看出哪段忙、哪天还压着件。",
                         families: [.systemLarge],
                         layout: .todayProgress),
            WidgetPreset(id: "CodelumiFocusCodeL",
                         name: "最近一件",
                         summary: "只放一件，取件码放到最大。",
                         families: [.systemLarge],
                         layout: .focusCode),
            WidgetPreset(id: "CodelumiStationsL",
                         name: "驿站分布",
                         summary: "哪个驿站还压着几件，最多 3 个。",
                         families: [.systemLarge],
                         layout: .stationBars),
            WidgetPreset(id: "CodelumiOldestL",
                         name: "最久未取",
                         summary: "压了几天，加上那一件的取件码。",
                         families: [.systemLarge],
                         layout: .oldestPending),
        ]

        // 超大：iPad 横版与 iPhone 竖版是两块画布，内容口径一致，合成一条 ——
        // 否则图库里会出现两个同名条目，用户分不清。
        //
        // ⚠️ `systemExtraLargePortrait` 是 iOS 27 新增，部署目标是 iOS 17，
        //    必须在可用性分支里拼，低版本系统上取这个枚举会崩。
        var extraFamilies: [WidgetFamily] = [.systemExtraLarge]
        if #available(iOS 27.0, *) {
            extraFamilies.append(.systemExtraLargePortrait)
        }
        presets.append(WidgetPreset(id: "CodelumiAll",
                                    name: "待取清单 · 超大",
                                    summary: "iPhone 竖屏超大画布，一页 14 条，四个显示开关可挑。",
                                    families: extraFamilies))
        return presets
    }

    /// 按 kind 反查。小组件扩展里 provider 拿到的是 kind 字符串，要还原成款式。
    static func preset(id: String) -> WidgetPreset? {
        all.first { $0.id == id }
    }

    /// App 款式库用的全量条目（多尺寸款已按尺寸展开）。
    ///
    /// 与 `all` 的关系：`all` 是**注册给系统的款式**（kind 列表，18 个 kind 不能变），
    /// 这里是**给用户看的卡片**（同一款可以出现三张，分别在 小 / 中 / 大 分组里）。
    static var libraryAll: [WidgetPreset] { all.flatMap(\.libraryVariants) }

    /// 免费版可用的款式（小 / 中）。
    static var freeOnes: [WidgetPreset] { all.filter { !$0.needsPro } }
}

// MARK: - 背景效果（真正透明 / Liquid Glass）

/// 小组件背景 —— **两层可以叠加**的设置（2026-11-22 主人纠正口径）。
///
/// 主人原话：「使用 Liquid Glass 打开的话是小组件有了液态玻璃的材质效果，
/// 不是变成了透明；两个都打开才是全透明的液态玻璃的材质」。
///
/// 所以这是两个**正交**的开关，不是一个三选一枚举：
///   · 透明开不开 → 底色画不画（不画 = 透出壁纸）
///   · 玻璃开不开 → 上面盖不盖一层玻璃材质
/// 四种组合各自成立，这个枚举只是四种组合的**渲染态**：
///   `solid` 都不开 / `clear` 只透明 / `glass` 只玻璃（仍有默认底）/ `clearGlass` 都开。
///
/// ⚠️ 早先写成三者互斥、只存一个值，是把两层当成了一个东西 —— 已改。
enum WidgetBackground: String, CaseIterable {
    /// 系统默认底色（改造前的观感）
    case solid
    /// 真透明：让系统不画背景，直接透出桌面壁纸
    case clear
    /// 液态玻璃：盖一层玻璃材质，但底色还在（**不是透明**）
    case glass
    /// 透明 + 玻璃 = 全透明的液态玻璃
    case clearGlass

    /// 这一态要不要透出壁纸。
    var wantsTransparent: Bool { self == .clear || self == .clearGlass }
    /// 这一态要不要盖玻璃层。
    var wantsGlass: Bool { self == .glass || self == .clearGlass }

    /// 完全无底（要交给系统 `.containerBackground(.clear)` 的那一态）。
    ///
    /// 🔴 只有「透明、且不盖玻璃」才是真正的零背景 —— 盖了玻璃就还是有一层材质要画，
    ///    必须留在 view 形式的 `containerBackground` 里。
    var isFullyTransparent: Bool { wantsTransparent && !wantsGlass }

    /// 由两个开关算出渲染态。
    static func resolve(clear: Bool, glass: Bool) -> WidgetBackground {
        switch (clear, glass) {
        case (false, false): return .solid
        case (true, false):  return .clear
        case (false, true):  return .glass
        case (true, true):   return .clearGlass
        }
    }
}

enum WidgetBackgroundSetting {
    /// 旧的单值键（`solid|clear|glass`）。**只读不写**，用于把老用户的选择迁移到两个新开关。
    private static let legacyKey = "codelumi.widget.background"
    /// 两个新开关。跨进程契约：只增不改，读不到就当关。
    static let clearKey = "codelumi.widget.clear"
    static let glassKey = "codelumi.widget.glass"

    private static var store: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    static var isClear: Bool {
        migrateLegacyIfNeeded()
        return store.bool(forKey: clearKey)
    }

    static var isGlass: Bool {
        migrateLegacyIfNeeded()
        return store.bool(forKey: glassKey)
    }

    /// 当前生效的组合态（小组件扩展只读这一个）。
    static var current: WidgetBackground {
        .resolve(clear: isClear, glass: isGlass)
    }

    /// 玻璃层不再有系统版本门槛。
    ///
    /// 🔴 2026-11-22：小组件里不能用 `glassEffect`（系统不采纳，见 `WidgetSurface` 注释），
    ///    改用 `Material` 后 iOS 17+ 全都支持，所以原来「需要 iOS 26」的限制撤销。
    static var isGlassSupported: Bool { true }

    /// 只落盘，不重画 —— 调用方负责 `WidgetCenter.shared.reloadAllTimelines()`。
    static func setClear(_ on: Bool) { store.set(on, forKey: clearKey) }
    static func setGlass(_ on: Bool) { store.set(on, forKey: glassKey) }

    /// 从旧单值键迁移一次：旧的 `clear` → 开透明，旧的 `glass` → 开玻璃。
    ///
    /// 判据是「两个新键都还没写过」。写完就再也不会跑，旧键留着不删
    /// （回滚安装旧版本时还能读到原来的选择）。
    private static func migrateLegacyIfNeeded() {
        guard store.object(forKey: clearKey) == nil,
              store.object(forKey: glassKey) == nil else { return }
        guard let raw = store.string(forKey: legacyKey),
              let legacy = WidgetBackground(rawValue: raw) else { return }
        store.set(legacy.wantsTransparent, forKey: clearKey)
        store.set(legacy.wantsGlass, forKey: glassKey)
    }
}

// MARK: - 小组件动作桥（拷贝反馈）

/// 小组件上「轻点就发生」的动作，要在扩展进程与主 App 之间传话，靠 App Group 当信箱。
///
/// 为什么用 App Group 而不是 URL Scheme：本工程**没有注册 `CFBundleURLTypes`**
/// （`Info.plist` 里一条都没有），`Link(destination:)` 打不开未注册的 scheme；
/// 而 `AppIntent` 的 `openAppWhenRun` 是系统给小组件拉起宿主 App 的正路 ——
/// 代价是意图本身没有「打开后要做什么」的通道，只能先写一个字条，App 前台再读。
enum WidgetActionBridge {
    private static var store: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    private static let copiedAtKey = "codelumi.widget.copiedAt"
    private static let copiedCodeKey = "codelumi.widget.copiedCode"

    /// 拷贝反馈窗口：3 秒内同一张卡片画「已复制」。
    /// 短一点更合适 —— 小组件下一次重画可能已是十几分钟后，挂太久会一直显示已复制。
    private static let copiedWindow: TimeInterval = 3

    static func markCopied(_ code: String) {
        store.set(Date().timeIntervalSince1970, forKey: copiedAtKey)
        store.set(code, forKey: copiedCodeKey)
    }

    static func justCopied(_ code: String) -> Bool {
        guard store.string(forKey: copiedCodeKey) == code,
              let stamp = store.object(forKey: copiedAtKey) as? Double else { return false }
        return Date().timeIntervalSince1970 - stamp < copiedWindow
    }

}
