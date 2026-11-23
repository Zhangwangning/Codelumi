import Foundation
import SwiftUI

// MARK: - App 内切换显示语言（2026-11-08 主人定）
//
// 以前点「语言」是跳到 iOS 设置里的 App 语言项；主人要求改成**App 内列表直接选**，
// 版式参考系统的语言列表（一行一种语言、当前项打勾）。
//
// 实现方式：把选择写进 UserDefaults 的 `AppleLanguages`。
// iOS 在**进程启动时**读这个键决定本地化，所以：
//   · 选择后立即生效于下一次启动（页面上有明确提示）；
//   · 「跟随系统」＝把这个键清掉，交还给系统。
//
// 我们只有 zh-Hans / zh-Hant 两套文案，所以列表就这三项，不做假的多语言。

enum AppLanguageChoice: String, CaseIterable, Identifiable {
    case system
    case simplified
    case traditional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:      "跟随系统"
        case .simplified:  "中文（简体）"
        case .traditional: "中文（繁體）"
        }
    }

    /// 写进 `AppleLanguages` 的语言代码；`nil` = 跟随系统
    var code: String? {
        switch self {
        case .system:      return nil
        case .simplified:  return "zh-Hans"
        case .traditional: return "zh-Hant"
        }
    }
}

enum AppLanguageSettings {
    private static let key = "codelumi.appLanguage"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    /// 用户的选择（默认跟随系统）
    static var choice: AppLanguageChoice {
        get { AppLanguageChoice(rawValue: defaults.string(forKey: key) ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: key)
            apply()
        }
    }

    /// 写入/清除 `AppleLanguages`。**只在进程启动时被系统读取**，
    /// 所以 App 里调用它只是把设置备好，下次启动才看得到效果。
    static func apply() {
        let standard = UserDefaults.standard
        if let code = choice.code {
            standard.set([code], forKey: "AppleLanguages")
        } else {
            standard.removeObject(forKey: "AppleLanguages")
        }
        standard.synchronize()
    }

    /// 启动时调用一次：把上次的选择真正落到 `AppleLanguages`
    static func applyAtLaunch() { apply() }

    /// 设置行右侧显示的当前值
    static var summary: String {
        switch choice {
        case .simplified:  return "简体中文"
        case .traditional: return "繁體中文"
        case .system:
            let code = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
            return code.hasPrefix("zh-Hant") ? "繁體中文" : "简体中文"
        }
    }
}
