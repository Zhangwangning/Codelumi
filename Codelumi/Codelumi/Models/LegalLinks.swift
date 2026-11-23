import Foundation

// MARK: ============================================================================
// 法律文档链接（隐私政策 / 使用条款）
//
// 2026-10-31：订阅类 App 的两条硬要求 ——
//   ① App Store Connect 必须填一个**公开可访问**的隐私政策 URL；
//   ② 订阅页上必须能点到隐私政策与使用条款（App Review 3.1.2）。
//
// 托管：GitHub Pages（公开仓库 `codelumi-legal`），国内可直连，无需登录。
// ⚠️ 这三个地址一旦写进 App Store Connect 就**不要改**：审核与商店页面都指向它。
//    将来要换域名（例如自有域名），先保证旧地址 301 到新地址再改代码。
// ============================================================================

enum LegalLinks {
    static let privacy = URL(string: "https://zhangwangning.github.io/codelumi-legal/privacy.html")!
    static let terms   = URL(string: "https://zhangwangning.github.io/codelumi-legal/terms.html")!
    /// Apple 标准 EULA —— App Store 下载的 App 默认适用，条款页里也引用了它
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
