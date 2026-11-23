import Foundation
import SwiftUI

// MARK: ============================================================================
// 繁体中文查表（2026-11-04）
//
// 现状：界面文案是**简体硬编码**，绝大多数以 `String` 在模型/组件间传递
// （`SettingsRow(title:)`、卡片标题、按钮标签…）。`Text(String.L)` 走的是**逐字显示**，
// 不会去查 `Localizable.strings`；只有 `Text("字面量")` 才会查表。
// 所以光放一个 zh-Hant 表只有部分生效 —— 要让动态字符串也查表，用 `L(...)`。
//
// 用法：把要本地化的 `Text(x.L)` 改成 `Text(x.L)`（或 `Text(L(x))`）。
// 表在 `zh-Hant.lproj/Localizable.strings`，键 = 简体原文。
// ============================================================================

extension String {
    /// 当前语言对应的文案（查不到时原样返回简体）。
    var L: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }

    /// 带格式参数的版本（键里用 %@ / %lld）
    func L(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}
