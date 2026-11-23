import SwiftUI

// MARK: ============================================================================
// 使用教程（2026-10-14 合并定稿，主人：两个设置入口合成一个，内容优化去重）
//
// 由原「自动化设置」（AutomationGuideView，5 步配置详解）与
// 「引导教程」（首启引导回放）合并而来：
//   · 原「引导教程」三页里与本页重复的自动化概要已并入「短信自动入库」；
//   · 原引导的「认识Codelumi」三点收编为第一节；
//   · 原「搜不到动作」「运行横幅」两条提示分别归位到所属章节。
// 入口：设置 › 使用教程；首启引导第 2 页「查看完整配置教程」也进这里。
// ============================================================================

struct UsageGuideView: View {
    private struct Step: Identifiable {
        let id = UUID()
        let index: Int
        let title: String
        let detail: String
        /// 关键步骤：数字圈改用强调色，提醒这一步不做整套就白搭
        var isKey: Bool = false
    }

    /// 短信自动化五步（与快捷指令 App 的实际界面逐项对过）。
    private let automationSteps: [Step] = [
        Step(index: 1, title: "打开「快捷指令」App",
             detail: "切到底部「自动化」标签页，点右上角「+」新建一个。"),

        Step(index: 2, title: "触发条件选「信息」",
             detail: "在「当」一栏里把触发类型设为「信息」。"),

        Step(index: 3, title: "条件改成「信息内容 · 包含 · 一个字段」",
             detail: "左侧默认是「**发件人**」，**必须手动改成「信息内容」**；中间选「包含」；右侧**只能填一个完整字段**。\n\nApple 这里**不支持正则、不支持通配**，填什么就是「短信里必须原样包含这一段」。最省事的是「**【**」——快递短信几乎都以【平台名】开头；也可以填「**快递**」「**包裹**」「**取件**」。\n\n⚠️ 一条条件装不下两个词：想覆盖多种关键词，请**再建一个自动化**，而不是在同一个里加条件（原因见下方说明卡）。",
             isKey: true),

        Step(index: 4, title: "关闭「运行前询问」",
             detail: "**开着的话每收到一条短信都要手动点一次确认**，自动化等于没做。新建时把它关掉；新系统里这一项显示为打开「**立即运行**」。"),

        Step(index: 5, title: "添加动作「添加到Codelumi」",
             detail: "在动作搜索框输入「Codelumi」，选「**添加到Codelumi**」；「短信内容」一栏选「**快捷指令输入**」——自动化触发时它就是刚收到的那条短信。",
             isKey: true),
    ]

    /// 截屏收件四步（手动快捷指令，不是自动化）。
    ///
    /// 自动化只能监听「收到短信」。微信群转发的取件通知、快递 App 的推送、驿站发来的
    /// 聊天截图 —— 这些都没有可监听的系统事件，用户手上唯一能做的动作就是「截屏」。
    var body: some View {
        // 🔴 2026-10-25：同 VersionHistoryView —— 底色用 ZStack 独立铺，
        // 不再依赖 ScrollView 上的 `.background`（分栏 detail 列里撑不满会露白）。
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            ScrollView {
                UsageGuideContent()
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle("使用教程")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
    }

    // MARK: 内容视图（页面与「快捷指令自动化」页共用）

    /// 🔴 2026-11-08 主人：设置页里的「快捷指令自动化」把教程**内联**成一页，
    /// 所以正文抽成这个视图；左右边距不由它加，谁用它谁给。
    /// 「认识Codelumi」已删除 —— 与 设置 › 关于 › 软件说明 重复。
    struct UsageGuideContent: View {
        private let guide = UsageGuideView()

        var body: some View {
            VStack(spacing: 16) {
                guide.automationSection
                guide.screenshotSection
                guide.verifySection
            }
        }
    }

    // MARK: 二、短信自动入库（自动化）

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "短信自动入库")

            stepList(automationSteps)

            // 🔴 2026-11-01 主人：别让用户以为"没有【的短信 App 处理不了"。
            //    【 只是自动化的筛选条件，App 本身不依赖它。
            infoCard(symbol: "text.alignleft", tint: AppTheme.doneTint,
                     title: "一条条件只装一个词，多条是「并且」",
                     detail: "同一个自动化里点「添加筛选条件」再加一条，两条之间是**并且**——短信必须**同时**包含两段文字才触发。所以把「快递」和「包裹」各加一条，覆盖范围反而更窄，不是更宽。\n\n**想覆盖多种关键词，就建多个自动化**：一个填「【」，一个填「快递」，一个填「包裹」，谁先命中谁处理，彼此不冲突。\n\n另外，关键词只是**筛选条件**，不是解析前提：短信里没有【同样能识别，手动粘贴、截图识别都不受影响。")

            // 第 5 步的常见卡点直接跟在这一节后面
            infoCard(symbol: "questionmark.circle.fill", tint: AppTheme.sky,
                     title: "搜不到「Codelumi」这个动作？",
                     detail: "先在手机上**打开一次Codelumi**再回快捷指令搜索。iOS 需要 App 至少运行过一次，才会把它提供的动作索引到动作库。")
        }
    }

    // MARK: 三、截屏收件（手动）

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 🔴 2026-11-22 主人：实验性统一用 `LabBadge` 标记 —— 标题里不再写
            //    「是实验性功能」这几个字，徽章一眼就够；正文只留代价与例外。
            SectionHeader(title: "截屏收件", isLab: true)

            // 🔴 2026-11-08 主人：截屏收件先一句话带过。
            //    原因：文字识别要靠端侧模型（国内机型暂不可用），只靠正则从截图里
            //    抽码并不可靠，写长了反而抬高预期。收码正路是上面的自动化。
            Text("识别效果依赖端侧模型，部分机型暂不支持；日常收码还是用上面的自动化。".richText)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard()
        }
    }

    // MARK: 四、配好之后

    private var verifySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "配好之后")

            infoCard(symbol: "checkmark.seal.fill", tint: AppTheme.doneTint,
                     title: "怎么验证配置生效",
                     detail: "让家人或同事给你发一条带取件码的快递短信试试。自动化运行几秒后切回Codelumi，「待取」里会多出一条；桌面小组件也会同步刷新，同时你会收到一条通知（标题就是取件码，下面是平台与地址）。若没反应，多半是第 3 步的条件没切到「信息内容」。")

            infoCard(symbol: "lightbulb.fill", tint: AppTheme.pendingTint,
                     title: "小提示",
                     detail: "自动化每次运行时，系统会弹出「正在运行」的横幅提示，这是 iOS 的系统行为、无法关闭。它不影响识别，只是说明它在工作。")
        }
    }

    // MARK: 步骤列表（数字圈 + 关键徽标）

    private func stepList(_ steps: [Step]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { position, step in
                if position > 0 {
                    Divider().padding(.leading, 58)
                }

                HStack(alignment: .top, spacing: 14) {
                    Text("\(step.index)")
                        .font(AppTheme.TypeScale.noteStrong)
                        .frame(width: 26, height: 26)
                        .background((step.isKey ? AppTheme.pendingTint : AppTheme.accent).opacity(0.15),
                                    in: .circle)
                        .foregroundStyle(step.isKey ? AppTheme.pendingTint : AppTheme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(step.title.L)
                                .font(AppTheme.TypeScale.bodyMedium)

                            if step.isKey {
                                Text("关键")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(AppTheme.pendingTint.opacity(0.16), in: .capsule)
                                    .foregroundStyle(AppTheme.pendingTint)
                            }
                        }

                        Text(step.detail.richText)
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.tertiary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
            }
        }
        .settingsCard()
    }

    // MARK: 信息卡

    private func infoCard(symbol: String, tint: Color,
                          title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(tint)
                Text(title.L)
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)

            Text(detail.richText)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }
}
