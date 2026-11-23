import SwiftUI

// MARK: ============================================================================
// 关于 Codelumi › 开源项目 / 特别鸣谢（2026-11-21 主人）
//
// 口径（主人 2026-11-21 第二次强调）：**页面上不写解释文字**。
//   · 开源项目：只有两个仓库，点进去自己看。
//   · 特别鸣谢：名单本身，一行分组标题足够。
// 两页都不放 IPA / 构建产物 / 签名私钥，这条写在 README 里，不写在 App 里。
// ============================================================================

/// GitHub 仓库地址（与 README 一致；改地址前先确认旧地址还能 301）
enum OpenSourceLinks {
    static let alludeApp = URL(string: "https://github.com/Zhangwangning/Allude")!
    static let shortcuts = URL(string: "https://github.com/Zhangwangning/shortcut_pickup_code")!

    struct Repo: Identifiable {
        let name: String
        let symbol: String
        let tint: Color
        let url: URL
        var id: String { name }
    }

    static let repos: [Repo] = [
        Repo(name: "Codelumi",
             symbol: "app.badge.checkmark.fill",
             tint: AppTheme.indigo,
             url: alludeApp),
        Repo(name: "快递取件码",
             symbol: "wand.and.stars",
             tint: AppTheme.amber,
             url: shortcuts),
    ]
}

// MARK: - 开源项目

struct OpenSourceView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(OpenSourceLinks.repos.enumerated()), id: \.element.id) { index, repo in
                        if index > 0 { SettingsDivider() }
                        Link(destination: repo.url) { row(repo) }
                            .buttonStyle(.plain)
                    }
                }
                .settingsCard()

                PageFooter()
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("开源项目信息")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ repo: OpenSourceLinks.Repo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: repo.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(repo.tint, in: .rect(cornerRadius: 8, style: .continuous))

            Text(repo.name)
                .font(AppTheme.TypeScale.rowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            // 🔴 2026-11-22 主人：跳转箭头改成 **Apple 蓝色文字「进一步了解」**。
            //    箭头只说明「能点」，一句话才说明「点进去看什么」。
            //    蓝色用系统语义色 `Color.blue`（#007AFF），不用 `AppTheme.accent`。
            Text("进一步了解")
                .font(AppTheme.TypeScale.bodyMedium)
                .foregroundStyle(Color.blue)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(.rect)
    }
}

// MARK: - 特别鸣谢

/// 只有名字（2026-11-21 主人：不要图标、不要首字块 —— 没有头像，硬做图反而别扭）。
/// 版式按片尾字幕的思路：居中、留白、不加任何装饰。
struct CreditsView: View {
    /// 2026-11-21 主人给的名单（顺序即名单顺序，不代表重要程度）。
    private let testers = [
        "@我爱吃派大星", "@么么", "@很酷的Z", "@无言",
        "@青云", "@momo", "@春山springhil", "@低调肚兜",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SectionHeader(title: "深度测试与反馈")

                VStack(spacing: 16) {
                    ForEach(testers, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 17))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .settingsCard()

                Text("排名不分先后")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)

                PageFooter()
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("特别鸣谢")
        .navigationBarTitleDisplayMode(.inline)
    }
}
