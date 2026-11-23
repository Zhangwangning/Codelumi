import SwiftUI
import WebKit

// MARK: ============================================================================
// 法律文档（隐私政策 / 使用条款）—— **App 内直接看，不跳浏览器**
//
// 2026-10-31 主人要求：点开就在 App 里，不要跳到 Safari。
// 技术上完全允许 —— App Review 3.1.2 只要求"能访问到"，没要求必须跳出去。
//
// 做法：文档 HTML **打包进 App**，用 WKWebView 加载本地文件。
// 为什么不直接加载那个 GitHub Pages 地址：
//   · `github.io` 在中国大陆经常打不开，而本 App 要上国区，用户与审核员都可能点不开；
//   · 离线副本永远可用，也不受境外 CDN 波动影响。
//
// ⚠️ 两份 HTML 是 `codelumi-legal` 仓库里的**同一份**，改动要两边同步：
//    仓库那份给 App Store 元数据（隐私政策 URL 必须是公开网页）与网页用户看，
//    App 内这份保证离线可读。
// ============================================================================

enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    /// 打包进 App 的文件名（不含扩展名）
    var resource: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "隐私政策"
        case .terms: "使用条款"
        }
    }

    /// App Store Connect 表单里填的公开地址（App 内不用它）
    var publicURL: URL {
        switch self {
        case .privacy: LegalLinks.privacy
        case .terms: LegalLinks.terms
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument
    /// 追加到文档末尾的 HTML（2026-11-12：设置页改版后「服务条款」要**整合**
    /// 原来的「声明与免责」，两段文字并成一页，不再给用户两个入口）。
    var extraHTML: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LegalWebView(resource: document.resource, extraHTML: extraHTML)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

/// 加载 App 内 HTML 的 WebView。
///
/// 只读、禁跳转：文档里若出现外链（比如 Apple 官方 EULA），交给系统浏览器打开，
/// 不在这个内嵌视图里继续导航 —— 否则用户会困在一个没有地址栏的网页里。
private struct LegalWebView: UIViewRepresentable {
    let resource: String
    /// 追加到 `</body>` 之前的 HTML 片段；nil 时原样加载文件。
    var extraHTML: String? = nil

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear

        guard let url = Bundle.main.url(forResource: resource, withExtension: "html") else {
            return view
        }

        if let extraHTML,
           let base = try? String(contentsOf: url, encoding: .utf8) {
            // 插入点选在 `</body>` 前；文档里一定有这个标签（我们自己的模板）。
            let merged = base.replacingOccurrences(of: "</body>", with: extraHTML + "\n</body>")
            view.loadHTMLString(merged, baseURL: url.deletingLastPathComponent())
        } else {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // file:// 内导航放行（文档自身的锚点）；http(s) 交给系统
            if action.navigationType == .linkActivated,
               let url = action.request.url,
               url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
