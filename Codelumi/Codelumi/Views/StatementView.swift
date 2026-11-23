import SwiftUI

// MARK: ============================================================================
// 声明与免责（2026-11-01 主人要求）
//
// 为什么单独成页而不是塞在关于页底部：这一段有四件事要讲清（来源、技术栈、
// 非抄袭、第三方标识与联系渠道），挤成一段小字没人读，审核员也看不出重点。
// ============================================================================

struct StatementView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(title: "来源",
                        body: """
                        Codelumi 由**极客ZHANG** 独立开发。

                        它衍生自开发者本人制作的「**快递取件码**」快捷指令：那一版快捷指令负责从快递短信里取出取件码，App 把这套逻辑搬进原生应用，再补上列表、搜索、桌面小组件与实时活动。**没有第二个来源。**
                        """)

                section(title: "技术",
                        body: """
                        全部使用 **Apple 官方工具与开发框架** 构建：Xcode、Swift、SwiftUI、WidgetKit、ActivityKit、StoreKit 与系统标准库。

                        工程内**没有任何第三方依赖**，没有引入任何第三方 SDK。
                        """)

                section(title: "设计来源",
                        body: """
                        产品形态、交互与视觉均为本人设计，**未使用其他应用的内容或素材**。

                        解析规则来自对真实快递短信的整理与回归测试，测试语料与判定基线都在项目记录里，可以逐条复核。
                        """)

                section(title: "第三方标识",
                        body: """
                        「快递公司」与「驿站管理」里出现的图标，仅用于**标识取件来源**（告诉你这一单是哪家送的、放在哪个驿站），版权归各快递公司与驿站品牌所有。

                        这不表示任何授权、合作或官方背书。相关权利人如有异议，联系我们后会立即移除。
                        """)

                section(title: "侵权联系",
                        body: """
                        生成式 AI 发展很快，本人无法穷尽核查所有可能撞车的设计。

                        如果你认为本应用存在侵权内容，请发邮件到 **zhang_wangning@126.com** 说明具体是哪一处；核实确认后，我会**立即删除或替换**。
                        """)

                Button {
                    UIPasteboard.general.string = FeedbackModel.mail
                    DiagnosticsLog.record("statement", "copy-mail")
                } label: {
                    Text("复制联系邮箱")
                        .font(AppTheme.TypeScale.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accent.opacity(0.12), in: .capsule)
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)

                Text("最后更新：2026-11-01")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("声明与免责")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.L)
                .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(.init(body))
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }
}

// MARK: - 声明与免责的 HTML 版本（2026-11-12）
//
// 设置页改版后，「声明与免责」不再单独占一页：它被**合并进「服务条款」**，
// 作为条款文档末尾的附加段落（`LegalDocumentView(document: .terms, extraHTML:)`）。
// SwiftUI 里那份保留原样（历史入口/截图脚手架还能直达），这里的 HTML 与它逐段对应，
// 改文案时两边要一起改。

enum StatementHTML {
    static let appended: String = """
    <hr style="border:none;border-top:1px solid #d1d1d6;margin:40px 0 8px">
    <p class="note" style="margin:0 0 8px">以下为「声明与免责」，最后更新：2026-11-01</p>

    <h2>来源</h2>
    <p>Codelumi 由<b>极客ZHANG</b> 独立开发。</p>
    <p>它衍生自开发者本人制作的「<b>快递取件码</b>」快捷指令：那一版快捷指令负责从快递短信里取出取件码，App 把这套逻辑搬进原生应用，再补上列表、搜索、桌面小组件与实时活动。<b>没有第二个来源。</b></p>

    <h2>技术</h2>
    <p>全部使用 <b>Apple 官方工具与开发框架</b> 构建：Xcode、Swift、SwiftUI、WidgetKit、ActivityKit、StoreKit 与系统标准库。</p>
    <p>工程内<b>没有任何第三方依赖</b>，没有引入任何第三方 SDK。</p>

    <h2>设计来源</h2>
    <p>产品形态、交互与视觉均为本人设计，<b>未使用其他应用的内容或素材</b>。</p>
    <p>解析规则来自对真实快递短信的整理与回归测试，测试语料与判定基线都在项目记录里，可以逐条复核。</p>

    <h2>第三方标识</h2>
    <p>「快递公司」与「驿站管理」里出现的图标，仅用于<b>标识取件来源</b>（告诉你这一单是哪家送的、放在哪个驿站），版权归各快递公司与驿站品牌所有。</p>
    <p>这不表示任何授权、合作或官方背书。相关权利人如有异议，联系我们后会立即移除。</p>

    <h2>侵权联系</h2>
    <p>生成式 AI 发展很快，本人无法穷尽核查所有可能撞车的设计。</p>
    <p>如果你认为本应用存在侵权内容，请发邮件到 <b>zhang_wangning@126.com</b> 说明具体是哪一处；核实确认后，我会<b>立即删除或替换</b>。</p>
    """
}
