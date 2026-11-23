import SwiftUI

// MARK: ============================================================================
// 液态玻璃兼容层（2026-11-07）
//
// 背景：`.glassEffect`（Liquid Glass）是 iOS 26 新增 API。
// Codelumi要同时兼容 iOS 18 / 26 / 27，所以统一走这一层：
//
//   · 系统 < 26           → 一律用系统毛玻璃 `.ultraThinMaterial` + 细描边
//   · 系统 >= 26 且开关开 → 真·液态玻璃
//   · 系统 >= 26 但关开关 → 也用毛玻璃（用户在「外观」里关掉了）
//
// 🔴 毛玻璃（`ultraThinMaterial`）本身就是 Apple 的系统材质，不是自绘 ——
//    在 iOS 18 上它就是系统设置/控制中心那种观感，符合规范。
// ============================================================================

enum GlassSettings {
    /// App Group 键：是否使用液态玻璃（外观设置项）
    static let key = "allude.usesLiquidGlass"

    /// 🔴 2026-11-23：必须用全 App 唯一的那个实例 ——
    ///    `UserDefaults(suiteName:)` 每调一次是新对象，写入不会通知绑在别处的
    ///    `@AppStorage`（"拨了开关界面不动"的老病根）。
    private static var defaults: UserDefaults { PickupStorage.groupStore }

    /// 当前系统是否支持液态玻璃（iOS 26+）
    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    /// 用户偏好（默认开）
    static var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    static func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }

    /// 实际是否走液态玻璃
    static var isActive: Bool { isSupported && isEnabled }
}

/// 真正的材质外壳。
///
/// 🔴 2026-11-23（老大：「液态玻璃的开关也实时变化」）：
///    材质分支不能写在**调用方**的 ViewBuilder 里 —— 调用方不重算，
///    拨开关就永远看不到变化。把这个决策关进一个自己观察 `allude.usesLiquidGlass`
///    的视图里，键一变它当场重画，已经铺满全 App 的玻璃卡片跟着换。
private struct GlassShell<S: Shape, Content: View>: View {
    @AppStorage(GlassSettings.key, store: PickupStorage.groupStore)
    private var enabled = true

    let shape: S
    let tint: Color?
    let interactive: Bool
    let content: Content

    init(shape: S, tint: Color?, interactive: Bool, @ViewBuilder content: () -> Content) {
        self.shape = shape
        self.tint = tint
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *), enabled {
            let base = Glass.regular
            let tinted = tint.map { base.tint($0) } ?? base
            let final = interactive ? tinted.interactive() : tinted
            content.glassEffect(final, in: shape)
        } else {
            // 🔴 2026-11-08 iOS 18 实测：tint 必须画在**内容下方**。
            //    早先写成 `.overlay { shape.fill(tint) }`，会把按钮文字盖住
            //    （详情页「标记为已取」的字直接看不见）。
            //    tint 自带 alpha（调用点传 0.65），叠两层把有效不透明度抬到 ~0.88，
            //    观感才贴近液态玻璃的实心感，白字对比也够。
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let tint {
                            shape.fill(tint)
                            shape.fill(tint)
                        }
                    }
                }
                .overlay {
                    // 毛玻璃没有液态玻璃的镜面高光，用一圈极淡描边找边界
                    shape.stroke(.white.opacity(0.16), lineWidth: 0.5)
                }
        }
    }
}

extension View {
    /// 统一玻璃外壳：支持则液态玻璃，否则系统毛玻璃。
    /// - Parameters:
    ///   - shape: 玻璃形状（`.rect(cornerRadius:)` / `.capsule` / `.circle`）
    ///   - tint: 可选染色（液态玻璃下生效；毛玻璃下用同色极淡叠层近似）
    ///   - interactive: 是否要按下形变（仅液态玻璃支持）
    func appGlass<S: Shape>(_ shape: S,
                            tint: Color? = nil,
                            interactive: Bool = false) -> some View {
        GlassShell(shape: shape, tint: tint, interactive: interactive) { self }
    }
}

// MARK: - `widgetAccentedRenderingMode` 兼容（2026-11-11 支持 iOS 17）

// `.widgetAccentedRenderingMode(.fullColor)` 是 iOS 18 才有的 API：灵动岛折叠态 /
// 小组件里不声明的话，方形品牌图会被 accented 渲染管线涂成单色灰块。
// 部署目标降到 iOS 17 后这行编不过；iOS 17 还没有「着色小组件」管线，本来也不会被重涂，
// 低版本直接返回原图即可。
extension Image {
    @ViewBuilder
    func widgetAccentedFullColor() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
