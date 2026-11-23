import Foundation

// MARK: ============================================================================
// 全局字号倍率（2026-11-04）
//
// `AppTheme.TypeScale` 里每一档都乘它 —— 设置里调一次，列表、设置、二级页一起变。
// 放 shared 层是因为小组件/灵动岛由**扩展进程**渲染，要读同一份倍率；
// 主 App 通过 `AppearanceSettings` 写入，扩展启动时从 App Group 读一次。
// ============================================================================

enum FontScale {
    /// App Group 里的键名（与 `AppearanceSettings` 共用）
    static let key = "codelumi.fontSize.scale"

    /// 当前倍率。1.0 = 标准。扩展进程只读，主 App 会改它。
    static var value: CGFloat = load() {
        didSet { }   // 保持可写；落盘由 AppearanceSettings 负责
    }

    private static func load() -> CGFloat {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        let stored = defaults.double(forKey: key)
        return stored > 0 ? CGFloat(stored) : 1.0
    }
}
