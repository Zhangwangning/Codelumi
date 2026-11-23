import SwiftUI
import UIKit

// MARK: ============================================================================
// 自动收录：把「收到短信 → 添加到Codelumi」的自动化直接导入系统（2026-11-04）
//
// 事实基础（实测拆包）：
//   .shortcut 文件由 AA01 归档里的 `Shortcut.wflow` 组成，里面**带触发器**：
//   `WFWorkflowTriggers` = WFMessageTrigger +「信息 包含 关键词」。
//   导入后系统会把它放进「快捷指令 › 自动化」，状态**默认关闭**，
//   需要用户自己打开开关 —— 这是 iOS 的行为，App 无法代劳。
//
// 🔴 为什么只能给预设关键词：签名（`shortcuts sign`）只能在电脑上做，
//    App 里没有签名私钥，运行时生成的文件无法签名，iOS 会拒绝导入。
//    所以这里只打包了几个预签好的文件（【 / 快递 / 取件）。
// ============================================================================

enum ShortcutAutomation {

    struct Preset: Identifiable, Hashable {
        let keyword: String
        let file: String
        /// 是否推荐（界面打「推荐」标签）
        var recommended: Bool = false
        var id: String { keyword }

        /// 导入后显示的名称：Codelumi 取件码解析「关键词」
        var displayName: String { "Codelumi 取件码解析「\(keyword)」" }
        /// 一句话说明适用场景
        var hint: String {
            switch keyword {
            case "【": return "大多数快递短信的取件码都包在全角方括号里，先加这一个就够"
            case "取": return "只匹配一个「取」字，用于没有【的短信"
            case "快递": return "短信里写了「快递」两个字就触发"
            case "包裹": return "短信里写了「包裹」就触发"
            default: return ""
            }
        }
    }

    /// 预设关键词（顺序即界面顺序）
    static let presets: [Preset] = [
        Preset(keyword: "【", file: "auto-【", recommended: true),
        Preset(keyword: "取", file: "auto-取"),
        Preset(keyword: "快递", file: "auto-快递"),
        Preset(keyword: "包裹", file: "auto-包裹"),
    ]

    /// iCloud 链接（推荐方式）。在 Shortcuts 里「共享 › 拷贝 iCloud 链接」拿到后填这里；
    /// 为空时界面只给「用文件导入」。
    /// 🔴 2026-11-10 改名 Codelumi 后重新分享的一批：4 个都指向新 bundle
    ///    （com.jikezhang.codelumi.ParsePickupTextIntent）的包，链接均 200 可下载。
    ///    旧包（com.jikezhang.codeclip）的 4 条链接已全部作废，不要再用。
    static let icloudLinks: [String: String] = [
        "【": "https://www.icloud.com/shortcuts/52cc69832eb449368078193dc075e470",
        "取": "https://www.icloud.com/shortcuts/2d27df2cd8f847cbb25f6d097b49b971",
        "快递": "https://www.icloud.com/shortcuts/e95d068d00bf439482a99dfc5a379633",
        "包裹": "https://www.icloud.com/shortcuts/4ea6f434e78a4810a9c8b87eff6cf797",
    ]

    static func icloudURL(for keyword: String) -> URL? {
        guard let raw = icloudLinks[keyword], !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    /// 已导入过哪些关键词（本地记录，仅用于界面显示"已导入"）
    private static let key = "codelumi.automation.imported"

    static var importedKeywords: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func hasImported(_ keyword: String) -> Bool {
        importedKeywords.contains(keyword)
    }

    static func markImported(_ keyword: String) {
        var list = importedKeywords
        guard !list.contains(keyword) else { return }
        list.append(keyword)
        importedKeywords = list
    }

    /// 已经写好的临时文件（同一个关键词只复制一次）。
    private static var cachedImportURLs: [String: URL] = [:]

    /// 给界面用的可分享 URL：第一次调用时复制到临时目录，之后直接复用缓存。
    @MainActor
    static func preparedImportURL(for preset: Preset) -> URL? {
        if let cached = cachedImportURLs[preset.keyword],
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        guard let url = importFile(for: preset) else { return nil }
        cachedImportURLs[preset.keyword] = url
        return url
    }

    /// 把预签好的文件写一份到临时目录（带好读的名字），返回可分享的 URL。
    static func importFile(for preset: Preset) -> URL? {
        guard let url = Bundle.main.url(forResource: preset.file, withExtension: "shortcut") else {
            return nil
        }
        let target = FileManager.default.temporaryDirectory
            // 🔴 2026-11-11 修：这里曾被双重转义成 `\(preset.keyword)`，
            //    分享面板里显示成「Codelumi·自动收录（\(preset.…」这种字面量。
            //    文件名 = 导入后的名称（shortcuts sign 会剥掉 WFWorkflowName），
            //    所以直接用 displayName。
            .appendingPathComponent("\(preset.displayName).shortcut")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }
}

// MARK: - 分享面板（把 .shortcut 交给系统的「快捷指令」）

/// 直接把 `UIActivityViewController` 挂到当前最上层控制器上。
///
/// 🔴 2026-11-11（TestFlight 内测反馈）：「首次使用时一键导入自动化打不开」。
///    原因：原来把 `UIActivityViewController` 塞进 SwiftUI 的 `.sheet` 里，
///    系统分享面板的呈现被 SwiftUI 的 sheet 容器接管，实测会变成一张**空白/
///    点不动的面板**（分享面板自己还要再 present 一层内容）。
///    修法：跳过 SwiftUI 的呈现链，直接找到活跃窗口最顶层的 controller 去 present。
///    首启引导是 fullScreenCover、设置页在 NavigationStack 里，两种上下文都能用。
@MainActor
enum ShareSheetPresenter {
    static func present(_ items: [Any]) {
        guard !items.isEmpty,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX,
                                        y: top.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
