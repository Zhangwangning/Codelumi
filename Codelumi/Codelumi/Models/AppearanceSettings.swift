import SwiftUI
import UIKit

// MARK: ============================================================================
// 外观与字体大小（2026-11-04 主人定）
//
// 三件事：
//   · 外观：自动（跟随系统）/ 浅色 / 深色
//   · 字体大小：二级页里预览 + 滑块 + 「跟随系统」
//   · 语言：只做入口，跳到 iOS 设置 › App › Codelumi（系统里改语言，App 自己不做切换）
//
// 存 **App Group**（`PickupStorage.appGroupID`）而不是 standard：
//   · 小组件/灵动岛由扩展进程渲染，也要跟随同一份字号倍率；
//   · 外观（深浅色）由 SwiftUI 的 preferredColorScheme 管，扩展跟随系统即可，不落盘。
//
// 🔴 字号是**全局倍率**，不是逐页改字号：`AppTheme.TypeScale` 里每一档都乘 `FontScale.value`。
//    这样列表、设置、二级页一起变，不会出现"设置里调大了、结果列表没变"。
// ============================================================================

/// 外观档位
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "自动"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var detail: String {
        switch self {
        case .system: return "跟随系统设置"
        case .light:  return "始终使用浅色"
        case .dark:   return "始终使用深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// 字号档位（滑块上的 7 档，1.0 为标准）
enum FontSizeStep: Int, CaseIterable, Identifiable {
    case smallest, small, slightlySmall, standard, slightlyLarge, large, largest

    var id: Int { rawValue }

    var scale: CGFloat {
        switch self {
        case .smallest:      return 0.88
        case .small:         return 0.94
        case .slightlySmall: return 0.97
        case .standard:      return 1.00
        case .slightlyLarge: return 1.06
        case .large:         return 1.12
        case .largest:       return 1.20
        }
    }

    /// 档位名（设置行尾、字体页底部都用它）
    var title: String {
        switch self {
        case .smallest:      return "最小"
        case .small:         return "较小"
        case .slightlySmall: return "偏小"
        case .standard:      return "标准"
        case .slightlyLarge: return "偏大"
        case .large:         return "较大"
        case .largest:       return "最大"
        }
    }

    /// 对应到系统的 Dynamic Type 档位（改这个不会重建视图树）
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .smallest:      return .xSmall
        case .small:         return .small
        case .slightlySmall: return .medium
        case .standard:      return .large
        case .slightlyLarge: return .xLarge
        case .large:         return .xxLarge
        case .largest:       return .xxxLarge
        }
    }

    static func nearest(to scale: CGFloat) -> FontSizeStep {
        allCases.min { abs($0.scale - scale) < abs($1.scale - scale) } ?? .standard
    }
}

@MainActor
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    private enum Key {
        static let mode = "codelumi.appearance.mode"
        static let scale = FontScale.key
        static let followSystem = "codelumi.fontSize.followSystem"
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    var mode: AppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Key.mode)
        }
    }

    /// 手动档位（「跟随系统」关闭时生效）
    var step: FontSizeStep {
        didSet {
            applyScale()
        }
    }

    var followSystem: Bool {
        didSet {
            defaults.set(followSystem, forKey: Key.followSystem)
            applyScale()
        }
    }

    /// 🔴 2026-11-04：这里原来有个 `generation`，根视图拿它做 `.id(...)` 强制重建整棵树。
    /// 结果是一拖滑块就整页重建、导航栈清空、弹回首页（主人报的 bug）。
    /// 现在字号走 `dynamicTypeSize` 环境，**不需要重建**，这个字段已删除。

    private init() {
        // 初始化阶段不能读 `self.defaults`（存储属性还没全就位），先取一份局部变量
        let store = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        mode = AppearanceMode(rawValue: store.string(forKey: Key.mode) ?? "") ?? .system
        followSystem = store.object(forKey: Key.followSystem) as? Bool ?? false
        let storedScale = store.double(forKey: Key.scale)
        step = FontSizeStep.nearest(to: storedScale > 0 ? CGFloat(storedScale) : 1.0)
        FontScale.value = followSystem ? FontScale.value : step.scale
    }

    /// 当前应使用的倍率。「跟随系统」时按 Dynamic Type 档位换算。
    func scale(for dynamicType: DynamicTypeSize) -> CGFloat {
        followSystem ? Self.scale(for: dynamicType) : step.scale
    }

    /// Dynamic Type → 倍率。映射到与手动档位同一量级，避免跟随系统时突然很大。
    static func scale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall:            return 0.88
        case .small:             return 0.94
        case .medium:            return 1.00
        case .large:             return 1.06
        case .xLarge:            return 1.12
        case .xxLarge:           return 1.20
        case .xxxLarge:          return 1.28
        case .accessibility1:    return 1.38
        case .accessibility2:    return 1.50
        case .accessibility3, .accessibility4, .accessibility5: return 1.62
        @unknown default:        return 1.00
        }
    }

    /// 把倍率写进共享层，并让根视图重建一次。
    private func applyScale() {
        // 只落盘，不重建视图树 —— 界面靠 dynamicTypeSize 环境自己跟着变。
        let scale = followSystem ? Self.scale(for: .large) : step.scale
        defaults.set(Double(scale), forKey: Key.scale)
    }
}
