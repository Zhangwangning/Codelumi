import WidgetKit
import SwiftUI

// MARK: ============================================================================
// 小组件壳（时间线 · 款式分发 · 容器背景）
//
// 本文件只负责「壳」：具体版式（勾选框 / 取件码 / 地址行 / 翻页控件）在
// `AlludeShared/WidgetVisuals.swift`，款式的定义与清单在
// `AlludeShared/WidgetPresets.swift` —— 放共享层是为了让 App 内能用同一份代码
// 做真实预览（桌面小组件无法脚本化添加）。
//
// 🔴 **2026-11-22 架构变更**：一个 `PickupWidget` + 六个显示开关 →
//    **每个款式一个 `PickupWidget` 实例**（8 个，各有独立 kind 与单一尺寸）。
//    理由与清单见 `WidgetPresets.swift` 文件头。
//
// 版式口径（不变）：
//   · **不放快递平台图标** —— 行首图标占宽约 41pt，去掉后全部让给取件码与地址；
//   · **取件码是唯一主角**；**行首圆形勾选框**可直接在桌面点掉；
//   · **中 / 大 / 超大尺寸支持上下翻页**（小尺寸没有分页余地）。
//
//   🔴 小组件不支持原生滚动 —— 已对 iOS 27 SDK 的 WidgetKit 与 SwiftUI 接口
//      逐一核实：不存在任何滚动相关 API。因此「上下翻动查看」用 iOS 17+ 的
//      可交互小组件实现：两个 `Button(intent:)` 改页码后重画时间线。
//
// 刷新策略（三层）：
//   1) **主 App 数据变更即刷新** —— PickupStore.records didSet 调
//      WidgetCenter.reloadAllTimelines()；
//   2) **桌面交互即刷新** —— 勾选 / 翻页意图写回后同样调用；
//   3) **兜底轮询 15 分钟** —— 覆盖跨天、系统内存回收后重新取时间线等场景。
//
// ⚠️ 与 App target 的差异：本文件不得使用 SwiftUI 宏（#Preview / @State），
//    原因见 DesignSystem.swift 顶部说明（本机 Xcode 命令行链路限制）。
// ============================================================================

// MARK: - 时间线条目

struct PickupEntry: TimelineEntry {
    let date: Date
    let configuration: PickupWidgetIntent
    let snapshot: WidgetSnapshot
    /// 这条款式每行显示到哪一层。
    ///
    /// 🔴 2026-11-22 晚：清单款的显示内容**回到用户开关**（详情页那三个），
    ///    所以这里存的是**取时间线时现读**的值 —— 与 `background` 同理，
    ///    用户在 App 里改完会 `reloadAllTimelines()`，缓存住就会一直画旧版式。
    ///    小尺寸三个固定变体则由 `preset.options` 覆盖，不看这个值。
    let options: WidgetDisplayOptions
    /// 背景材质（默认 / 真透明 / 液态玻璃）。
    ///
    /// Provider **每次取时间线时现读** App Group —— 用户在 App 里改了背景会
    /// `reloadAllTimelines()`，缓存住就会一直画旧材质。
    let background: WidgetBackground
}

// MARK: - 时间线提供者

struct PickupTimelineProvider: AppIntentTimelineProvider {
    /// 本实例服务的款式。由 `PickupWidget` 注入 —— 所有款式共用这一个 provider 类型。
    let preset: WidgetPreset

    private func makeEntry(date: Date,
                           configuration: PickupWidgetIntent,
                           snapshot: WidgetSnapshot) -> PickupEntry {
        let resolved = WidgetBackgroundSetting.current

        // 🔴 2026-11-23 诊断：把**小组件进程真正读到的背景态**回写给 App。
        //    桌面上还是白底时，这行读数能一眼区分两件完全不同的事：
        //      · 读到 `clear` —— 开关值到了扩展，问题在系统愿不愿意撤底板；
        //      · 读到 `solid` —— 值根本没传过来（App Group / 键名 / 时间线没刷新）。
        //    前者改渲染写法，后者查跨进程存储，方向正好相反。
        if let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) {
            defaults.set(resolved.rawValue, forKey: "allude.diag.widget.bg")
            defaults.set(Date(), forKey: "allude.diag.widget.bgAt")
        }

        return PickupEntry(date: date,
                           configuration: configuration,
                           snapshot: snapshot,
                           options: preset.options,
                           background: resolved)
    }

    func placeholder(in context: Context) -> PickupEntry {
        makeEntry(date: .now,
                  configuration: PickupWidgetIntent(),
                  snapshot: .preview())
    }

    func snapshot(for configuration: PickupWidgetIntent, in context: Context) async -> PickupEntry {
        // 图库预览用示例数据，真实快照读共享容器 —— 避免用户在小部件图库里
        // 看到自己「只有 0 条」的尴尬空态。
        let snapshot: WidgetSnapshot = context.isPreview ? .preview() : .load()
        return makeEntry(date: .now, configuration: configuration, snapshot: snapshot)
    }

    func timeline(for configuration: PickupWidgetIntent, in context: Context) async -> Timeline<PickupEntry> {
        let entry = makeEntry(date: .now,
                              configuration: configuration,
                              snapshot: .load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)
            ?? Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

// MARK: - 入口视图（按款式与状态分发到共享可视层）

struct PickupWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    /// 宿主到底有没有给这块画布垫底色 —— 透明的**唯一**判据。
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    /// 当前渲染模式（fullColor / accented / vibrant）。
    @Environment(\.widgetRenderingMode) private var renderingMode

    var entry: PickupEntry
    var preset: WidgetPreset

    private var familyKey: String { WidgetPageSize.key(family) }

    var body: some View {
        content
            // 🔴 2026-11-23 排查用：把宿主的两项决定画在画布右下角。
            //    `b1` = 宿主仍在垫底（showsWidgetContainerBackground 为真），
            //    `b0` = 宿主已撤掉底板（此时才可能真透明）。
            //    字母 = 渲染模式：F 全彩 / A 强调 / V 活力。
            //    稳定后删掉这枚角标即可。
            .overlay(alignment: .bottomTrailing) {
                Text("\(showsContainerBackground ? "b1" : "b0")·\(renderModeLetter)·s\(descriptorStyle)·p\(descriptorPolicy)·v\(buildNumber)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.trailing, 3)
                    .padding(.bottom, 2)
            }
    }

    /// 我们写进描述符的背景样式值（排查用）。
    private var descriptorStyle: Int {
        diagnosticInteger("allude.diag.widget.style")
    }

    /// 扩展自己的构建号 —— 角标带上它，一眼能看出这块组件是哪个包画的，
    /// 不用再靠猜"他到底装没装到这一版"。
    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }

    /// 我们写进描述符的背景视图策略（-1 = 系统没有这个 setter）。
    private var descriptorPolicy: Int {
        diagnosticInteger("allude.diag.widget.policy")
    }

    /// 读一个诊断用的整数：键不存在时给 -8（`integer(forKey:)` 对缺失键返回 0，
    /// 会把它当成"写进去了 0"，排查时最容易看错）。
    private func diagnosticInteger(_ key: String) -> Int {
        guard let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) else { return -9 }
        return defaults.object(forKey: key) == nil ? -8 : defaults.integer(forKey: key)
    }

    private var renderModeLetter: String {
        if renderingMode == .accented { return "A" }
        if renderingMode == .vibrant { return "V" }
        return "F"
    }

    @ViewBuilder
    private var content: some View {
        let snapshot = entry.snapshot

        // 🔴 免费版只有小 / 中（`WidgetPageSize.freeFamilies`）。
        //    大尺寸以上款式照样注册（否则买完 Pro 也看不见），
        //    但免费用户拖到桌面时渲染「解锁 Codelumi Pro」占位，
        //    而不是空白或假数据 —— 见 `WidgetLockedContent`。
        //
        // 🔴 2026-11-22 晚：清单款一个 kind 撑 小+中+大，**必须按当前实际尺寸判**，
        //    不能再用 `preset.needsPro`（那是"主尺寸"的属性）—— 否则免费用户
        //    把清单放在小尺寸上也会看到一把锁。
        if !WidgetPageSize.isFreeFamily(family) && !EntitlementSnapshot.licensedPro {
            WidgetLockedContent()
        } else if snapshot.isEmpty {
            WidgetEmptyContent(pickedTodayCount: snapshot.pickedTodayCount,
                               compact: family == .systemSmall)
        } else {
            // 版式分发在共享层（`WidgetLayoutContent`）—— 与 App 内预览同一份代码。
            WidgetLayoutContent(preset: preset,
                                snapshot: snapshot,
                                family: family,
                                pageKey: familyKey,
                                pageSize: WidgetPageSize.rowCount(family: familyKey),
                                options: entry.options)
        }
    }
}

// MARK: - 小组件背景
//
// 三种材质，与 `WidgetBackgroundSetting` 一一对应：
//
//   · `.solid`（默认）—— 实体填充 + 顶部主色氛围渐变，改造前的观感；
//   · `.clear`（真透明）—— **什么都不画**。iOS 27 起桌面支持真透明小组件，
//     系统在没有背景内容时会直接透出壁纸；设备/系统不支持时，系统自己补默认底，
//     所以这里不需要写任何兜底分支 —— 这正是主人定的口径：
//     「如果设备不支持也没关系，只是用户打开后还是默认的背景罢了」。
//   · `.glass`（液态玻璃）—— `glassEffect`（iOS 26.0+）。低版本回落实体填充。
//
// ⚠️ 小组件里的液态玻璃**不是实时的壁纸折射**：WidgetKit 渲染的是静态快照，
//    拿不到桌面壁纸，系统不会为它做实时背景采样。这里的玻璃是一层带高光与
//    描边的半透明材质，观感接近但不会随壁纸变化 —— 这是平台边界，不是实现偷懒。

struct WidgetSurface: View {
    var style: WidgetBackground = .solid

    var body: some View {
        surface
    }

    @ViewBuilder
    private var surface: some View {
        if style.wantsGlass {
            // 玻璃层要两态都支持：只开玻璃 —— 底色还在，只是表面多了材质；
            // 透明 + 玻璃 —— 底下什么都不画，玻璃直接浮在壁纸上（全透明液态玻璃）。
            if style.wantsTransparent {
                glassLayer
            } else {
                ZStack {
                    solidSurface
                    glassLayer
                }
            }
        } else if style.wantsTransparent {
            // 透明必须真的是 clear，不能是「几乎透明」——任何一点填充都不再透壁纸。
            //
            // 🔴 2026-11-22 定论（老大拿 Widgy 对拍 + iOS 27.2 SDK 头文件核实）：
            //    真透明由**系统**决定 —— 桌面外观选「透明 / 着色」时，系统会把这层
            //    container background 整个移除、直接透出壁纸（此时 `showsWidgetContainerBackground`
            //    为 false）；外观是「浅色 / 深色」时系统自己补不透明容器，谁也绕不过去。
            //    WidgetKit 全线没有「强制透明」的公开 API（`containerBackgroundRemovable`
            //    只是允许系统移除），所以这里唯一的正确写法就是**什么都不画**，
            //    让系统去决定 —— 不要再加任何壁纸截图之类的兜底。
            Color.clear
        } else {
            solidSurface
        }
    }

    private var solidSurface: some View {
        Rectangle()
            .fill(.background.secondary)
            .overlay(alignment: .top) {
                LinearGradient(colors: [AppTheme.accent.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 88)
            }
    }

    /// 玻璃材质层。
    ///
    /// 🔴🔴 2026-11-22 **不能用 `glassEffect`**（实测 + 官方口径）：
    ///    iOS 26 的 Liquid Glass 在小组件里**完全由系统决定**（按桌面主题 clear / tinted 渲染），
    ///    第三方在 `containerBackground` 里调 `.glassEffect` 不会被采纳，
    ///    轻则无效果，重则整块渲染失败 —— 桌面显示成模糊骨架占位（主人截图那个样子）。
    ///    小组件可用的材质是 `Material`，所以这里用 `.ultraThinMaterial`：
    ///    半透、带模糊，观感接近玻璃，且全系统版本都支持（不再需要 iOS 26 门槛）。
    ///    顶部再叠一道很淡的高光，避免整块发灰。
    private var glassLayer: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.22), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 72)
            }
    }
}

// MARK: - 小组件注册（每个款式一个）

/// 一个款式 = 一个 `Widget` 实例 = 系统小组件库里的一条独立条目。
///
/// 🔴 `kind` 就是 `preset.id`，**发出去之后不能改**（改了等于换组件，
///    老用户桌面上那个实例会变成「无法载入」的空框）。
struct PickupWidget: Widget {
    let preset: WidgetPreset

    /// 🔴 `Widget` 协议要求一个**无参 `init()`**（`WidgetKit` 在注册 / 还原条目时会调它）。
    ///    少了它，`PickupWidget` 直接报「does not conform to protocol 'Widget'」，
    ///    而且错误只会指向 `WidgetBundle` 的 `some Widget`，看不出真凶。
    ///
    ///    这里兜底给第一款（小尺寸「取件码」）—— 真实注册永远走 `init(preset:)`，
    ///    这个初始化器只是为了让类型满足协议。
    init() {
        preset = WidgetPreset.all[0]
    }

    init(preset: WidgetPreset) {
        self.preset = preset
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: preset.id,
                               intent: PickupWidgetIntent.self,
                               provider: PickupTimelineProvider(preset: preset)) { entry in
            // 🔴 2026-11-22 晚（老大拿 Widgy 对拍后定）：
            //    「透明」必须走 **ShapeStyle 版**的 `.containerBackground(.clear, for: .widget)`，
            //    而不能再包一层「body 返回 Color.clear 的自定义 View」——
            //    后者在 WidgetKit 眼里是"提供了一个背景视图"，只是画出来是透明的，
            //    系统仍会在这层之上补它自己的容器材质，于是桌面看上去还是有一块底。
            //    给 `.clear` 才是"我声明这里没有背景"，壁纸才会真的透出来（iOS 26 起支持）。
            Group {
                if entry.background.isFullyTransparent {
                    // 🔴 2026-11-23 第三次尝试（豆包那条「把容器背景不透明度设为 0」）：
                    //    `.clear` 在宿主眼里可能是「没有背景 → 我给你补默认材质」；
                    //    换成一个 **alpha≈0 的实色** —— 它是"有背景，只是看不见"，
                    //    某些实现据此就不再补底。视觉上与全透明等价（0.001 肉眼不可分）。
                    PickupWidgetEntryView(entry: entry, preset: preset)
                        .containerBackground(Color.white.opacity(0.001), for: .widget)
                } else {
                    PickupWidgetEntryView(entry: entry, preset: preset)
                        .containerBackground(for: .widget) {
                            WidgetSurface(style: entry.background)
                        }
                }
            }
        }
        .configurationDisplayName(preset.name)
        .description(preset.summary)
        .supportedFamilies(preset.families)
        // 允许用户在桌面「编辑小组件 › 样式」里把背景去掉 —— 只开放权限，
        // 不改变默认观感；不加这行的话系统层面就没这个选项。
        .containerBackgroundRemovable(true)
    }
}
