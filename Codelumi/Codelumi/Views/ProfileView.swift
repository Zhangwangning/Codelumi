import SwiftUI
import MessageUI
import UIKit
import PhotosUI

// MARK: ============================================================================
// 设置（2026-10-14 由「我的」面板重构而来，主人定稿：底部标签栏直达）
//
// 结构调整：
//   · 原「我的」由右上角头像 push 进入，现改为**底部第 4 个标签页**；
//     顶部头像入口整体退役（三个列表页的工具栏不再放头像）。
//   · 🔴 **VIP/会员体系整体退役** —— 软件全功能、无任何限制：
//     无会员分区、无档位徽章、无行尾锁、无 TestFlight 档位说明。
//   · 新增「反馈」（mailto:zhang_wangning@126.com）与「使用教程」
//     （合并原「自动化设置」+「引导教程」，2026-10-14 主人定稿）。
//
// 版式沿用 iOS 分组面板：账户卡 + 若干分组卡，组标题在卡外。
// 账户仍为**本机档案**（无登录、无联网，2026-09-23 定稿口径不变）。
// ============================================================================

// MARK: - 分栏设置页的面板清单（宽屏用）
//
// 2026-10-25：Duo 展开态（regular）改成 macOS / iPad 设置式「左列表 + 右内容」，
// 这里把原来散落在 ScrollView 里的条目收成一个枚举，供侧栏与内容面板共用。
// 窄屏仍走原来的长页布局，与本枚举无关。

enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance
    case fontSize
    case language
    case automation
    case notification
    case widget
    /// 2026-11-16 主人：紧跟在「桌面小组件」下面
    case codeManagement
    case activity
    case courier
    case station
    case guide
    case license
    case activation
    case storage
    case feedback
    case version
    case privacy
    case aiCapability
    case appIcon
    case privacyDoc
    case termsDoc
    case disclaimer
    case help
    case trainingSamples
    case contactInfo
    // 2026-11-12 设置页改版：新增三个「聚合页」入口 + 两个二级页
    case appearanceGroup
    case aboutCodelumi
    case icloudSync
    case encourage
    case privacySimple
    /// 2026-11-21 主人：关于页新增「开源项目」与「特别鸣谢」两页
    case openSource
    case credits
    /// 2026-11-22 主人：「关于Codelumi页面中添加一个使用权限，里面列举App使用了的权限」
    case permissions
    /// 2026-11-21 主人：「推荐给朋友」从「鼓励一下」挪到关于页（这一行是 ShareLink，不是 push）
    case share
    // 🔴 2026-11-20 主人：**第三方模型通道整个删除**，只保留 Apple 端侧智能，
    //    「扩展」与「用量统计」两个面板连同它们的 pane case 一起消失。
    //    这条设置行现在直达 Apple 智能检测页（不经总览页）。

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance:   return "外观"
        case .fontSize:     return "字体大小"
        case .language:     return "语言"
        // 2026-11-12 主人：设置首页只写「快捷指令」，二级页标题仍是「快捷指令自动化」
        case .automation:   return "快捷指令"
        case .notification: return "通知"
        case .widget:       return "小组件"
        case .codeManagement: return "取件码管理"
        // 🔴 2026-11-08 主人：只叫「实时活动」—— 灵动岛只有部分机型有，
        //    写进标题会让其他机型以为是专属功能。
        case .activity:     return "实时活动"
        case .courier:      return "快递公司"
        case .station:      return "驿站管理"
        case .guide:        return "使用教程"
        case .license:      return "Codelumi Pro"
        case .activation:   return "激活"
        // 2026-11-12 主人：改叫「存储空间」，它现在是独立入口（不再挂在「本机数据」组下）
        case .storage:      return "存储空间"
        case .feedback:     return "反馈"
        case .version:      return "版本"
        case .privacy:      return "隐私"
        case .aiCapability: return "Apple 智能"
        case .appIcon:      return "App 图标"
        case .privacyDoc:   return "隐私政策"
        // 2026-11-12 主人：改叫「服务条款」，并把「声明与免责」并进这一页
        case .termsDoc:     return "服务条款"
        case .disclaimer:   return "声明与免责"
        case .help:         return "帮助与反馈"
        case .trainingSamples: return "帮助改进Codelumi"
        case .contactInfo:  return "联系方式"
        // 2026-11-12 设置页改版
        case .appearanceGroup: return "外观与个性化"
        case .aboutCodelumi:  return "关于 Codelumi"
        case .icloudSync:   return "iCloud 同步"
        case .encourage:    return "鼓励一下"
        case .privacySimple: return "隐私政策（简明版）"
        // 2026-11-22 主人：「开源项目」→「开源项目信息」
        case .openSource:   return "开源项目信息"
        case .credits:      return "特别鸣谢"
        case .permissions:  return "使用权限"
        case .share:        return "推荐给朋友"
        }
    }

    var symbol: String {
        switch self {
        case .appearance:   return "circle.lefthalf.filled"
        case .fontSize:     return "textformat.size"
        case .language:     return "globe"
        case .automation:   return "bolt.badge.automatic.fill"
        case .notification: return "bell.badge.fill"
        case .widget:       return "square.text.square.fill"
        case .codeManagement: return "number.square.fill"
        case .activity:     return "platter.filled.top.iphone"
        case .courier:      return "shippingbox.fill"
        case .station:      return "storefront.fill"
        case .guide:        return "book.fill"
        case .license:      return "sparkles"
        case .activation:   return "key.horizontal.fill"
        case .storage:      return "internaldrive.fill"
        case .feedback:     return "envelope.fill"
        case .version:      return "info.circle.fill"
        case .privacy:      return "hand.raised.fill"
        case .aiCapability: return "brain.head.profile"
        case .appIcon:      return "app.badge.fill"
        case .privacyDoc:   return "hand.raised.fill"
        case .termsDoc:     return "doc.text.fill"
        case .disclaimer:   return "text.badge.checkmark"
        case .help:         return "questionmark.bubble.fill"
        case .trainingSamples: return "sparkles.rectangle.stack.fill"
        case .contactInfo:  return "at"
        case .appearanceGroup: return "paintbrush.fill"
        case .aboutCodelumi:  return "info.circle.fill"
        case .icloudSync:   return "icloud.fill"
        case .encourage:    return "heart.fill"
        case .privacySimple: return "hand.raised.fill"
        case .openSource:   return "chevron.left.forwardslash.chevron.right"
        case .credits:      return "heart.text.square.fill"
        case .permissions:  return "lock.shield.fill"
        case .share:        return "square.and.arrow.up.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appearance:   return AppTheme.accent
        case .fontSize:     return AppTheme.sky
        case .language:     return AppTheme.indigo
        case .automation:   return AppTheme.amber
        case .notification: return AppTheme.pendingTint
        case .widget:       return AppTheme.sky
        case .codeManagement: return AppTheme.amber
        case .activity:     return AppTheme.accent
        case .courier:      return AppTheme.indigo
        case .station:      return AppTheme.violet
        case .guide:        return AppTheme.sky
        case .license:      return AppTheme.amber
        case .activation:   return AppTheme.indigo
        case .storage:      return AppTheme.todayTint
        case .feedback:     return AppTheme.doneTint
        case .version:      return AppTheme.todayTint
        case .privacy:      return AppTheme.doneTint
        case .aiCapability: return AppTheme.violet
        case .appIcon:      return AppTheme.doneTint
        case .privacyDoc:   return AppTheme.doneTint
        case .termsDoc:     return AppTheme.sky
        case .disclaimer:   return AppTheme.amber
        case .help:         return AppTheme.sky
        case .trainingSamples: return AppTheme.violet
        case .contactInfo:  return AppTheme.indigo
        case .appearanceGroup: return AppTheme.accent
        case .aboutCodelumi:  return AppTheme.indigo
        case .icloudSync:   return AppTheme.sky
        case .openSource:   return AppTheme.indigo
        case .credits:      return AppTheme.pink
        case .permissions:  return AppTheme.doneTint
        case .share:        return AppTheme.sky
        case .encourage:    return AppTheme.pendingTint
        case .privacySimple: return AppTheme.doneTint
        }
    }

    /// 🔴 **唯一数据源**（2026-11-07 主人：不管哪个平台、怎么排版，功能必须一模一样）。
    /// 单列布局与 iPad 分栏都从这几个数组渲染，不要再各写一份。
    ///
    /// 2026-11-12 主人定的新排布（设置首页五块）：
    ///   ① 通用：快捷指令 / 通知 / 桌面小组件 / 实时活动 / iCloud 同步 / Apple 智能
    ///   ② 外观与个性化（二级页收拢 App 图标 / 外观 / 字体大小 / 语言）
    ///   ③ 存储空间
    ///   ④ 帮助与反馈
    ///   ⑤ 更多：快递公司 / 驿站管理 / 关于 Codelumi
    static let generalGroupAll: [SettingsPane] = [
        .automation, .notification, .widget, .codeManagement, .activity,
        .icloudSync, .aiCapability,
    ]
    static let appearanceTopGroup: [SettingsPane] = [.appearanceGroup]
    static let dataGroup: [SettingsPane] = [.storage]
    static let supportGroup: [SettingsPane] = [.help]
    static let aboutGroupAll: [SettingsPane] = [.courier, .station, .aboutCodelumi]

    /// 「外观与个性化」二级页里的四条（顺序就是主人给的顺序）
    static let appearanceDetailGroup: [SettingsPane] = [.appIcon, .appearance, .fontSize, .language]

    /// 「关于 Codelumi」二级页的顺序：鼓励一下 / 服务条款 / 隐私政策（完整版）/
    /// 隐私政策简明版 / 版本信息
    static let aboutDetailGroup: [SettingsPane] = [
        .encourage, .share, .termsDoc, .privacyDoc, .privacySimple,
        .permissions, .openSource, .credits, .version,
    ]

    /// 「推荐给朋友」分享的文案（唯一真源）。
    /// 🔴 2026-11-22 老大：「点击推荐给朋友怎么是打开版本历史页面」——
    ///    `AboutCodelumiView` 里这一行没走 ShareLink，落进了 NavigationLink，
    ///    而它的 `destination` 又是 `default: VersionHistoryView()`，于是推到了版本历史。
    ///    文案与路由都收到这里，两处入口（设置页 / 关于页）共用一份。
    static let recommendText = "推荐 Codelumi：一个只在本机整理快递取件码的 App，不联网、不上传、不用注册。"
}

struct SettingsView: View {
    @EnvironmentObject private var store: PickupStore

    /// 反馈结果的轻提示（邮件打不开时引导复制邮箱）。
    @StateObject private var feedback = FeedbackModel()

    /// 宽屏（iPhone Duo 展开态）判定 —— 与列表页同一口径。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 分栏设置页当前选中的面板（2026-10-25，参照 macOS / iPad 设置）。
    @State private var pane: SettingsPane? = SettingsView.scaffoldPane

    /// 侧栏搜索词（2026-10-25 照 iPad 设置：侧栏顶部有搜索框）
    @State private var query = ""

    /// 关于页「设备 UUID」的复制反馈（1.6s 后自动复原）
    @State private var copiedUUID = false

    /// 订阅入口的「暂不支持」提示（2026-10-31 主人：不让进二级页）

    /// 截图脚手架：`SIMCTL_CHILD_SETTINGS_PANE=courier|widget|…` 启动即选中该面板，
    /// 命令行点不到侧栏行，逐页验收底色/图标只能用这个入口。
    static var scaffoldPane: SettingsPane? {
        guard let raw = ProcessInfo.processInfo.environment["SETTINGS_PANE"] else {
            return .notification
        }
        return SettingsPane(rawValue: raw) ?? .notification
    }

    /// 按搜索词过滤某一组（空词 = 原样返回）。
    /// 2026-11-12：设置页改成「聚合入口」后，搜「App 图标 / 字体 / 隐私」也要能
    /// 命中对应的二级页所在的那个入口（否则搜索突然变笨）。
    private func filtered(_ items: [SettingsPane]) -> [SettingsPane] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        func hit(_ title: String) -> Bool { title.localizedCaseInsensitiveContains(q) }
        return items.filter { item in
            if hit(item.title) { return true }
            switch item {
            case .appearanceGroup: return SettingsPane.appearanceDetailGroup.contains { hit($0.title) }
            case .aboutCodelumi:     return SettingsPane.aboutDetailGroup.contains { hit($0.title) }
            default:               return false
            }
        }
    }

    /// 🔴 2026-11-16 删掉了这里原有的 `@State private var detailPath = NavigationPath()`。
    ///
    /// 它当时是 2026-11-14 为「分栏里 destination 型 push 会被吞」加的，但**加了 path
    /// 反而正是 push 失效的原因**：右栏的 `NavigationStack(path:)` 里再放
    /// destination 型 `NavigationLink`，在常驻 pane（内容还挂着 `.id(pane)`）这套组合下
    /// 推不动。主人实测：Duo 内屏**横屏**（分栏）时「Apple 智能与扩展」的两个下级页、
    /// 以及扩展列表里的服务商行、用量统计全都点不进去；**竖屏 / 外屏 / 直板机
    /// （单列，栈上没有 path）全部正常** —— 差别就只有这个 path。
    /// 去掉后 `NavigationStack` 自己管栈，destination 型 push 恢复；切面板重置由
    /// 内容上的 `.id(pane)` 负责。

    /// **是否真的在分栏**（左列目录 + 右栏内容）。
    ///
    /// 🔴 2026-11-16 主人：「Duo 内屏竖屏时，外观与个性化里的四个功能、关于 Codelumi 里的
    /// 五个功能全部点不进去」。根因就是下面几处只判了 `horizontalSizeClass == .regular`：
    /// Duo 内屏**竖屏也是 regular 宽度（762pt）**，但布局走的是 `stackedSettings` 单列分支，
    /// `pane` 没有绑定任何导航 —— 子行被当成「分栏模式」渲染成 `Button { openPane(item) }`，
    /// 点下去只是改了个没人读的 `pane`，所以一点反应都没有。
    ///
    /// 判据必须与 body 里选 `splitSettings` / `stackedSettings` 的条件**完全一致**，
    /// 否则又会分叉。以后加新判定请一律走这里。
    private var isSplitLayout: Bool {
        PadLayout.usesSplit
            && horizontalSizeClass == .regular
            && ProcessInfo.processInfo.environment["SETTINGS_COMPACT"] != "1"
    }

    var body: some View {
        Group {
            // 🔴 2026-11-07 主人：宽屏（Duo 展开态 / iPad）就该用分栏，窄屏用单列。
            //    两种排版渲染的是**同一份目录**（`generalGroupAll` / `dataGroup` / `aboutGroupAll`），
            //    所以功能完全一致，只是排列不同。
            // 截图脚手架：`SETTINGS_COMPACT=1` 强制走单列，用来在宽屏模拟器上
            // 验证窄屏样式（尤其 iOS 26 的玻璃行），平时不影响任何布局。
            if isSplitLayout {
                splitSettings
            } else {
                stackedSettings
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .overlay { feedbackToast }
        // 截图/验真脚手架（仅调试）：`SETTINGS_OPEN=icloudSync` 直接切到该面板
        // （命令行点不到行）。正式运行时该环境变量不存在，零影响。
        .onAppear {
            #if DEBUG
            // 探针：确认「单列 / 分栏」判定与实际渲染一致。
            // 判错的后果就是子行拿到 openPane、渲染成按钮、点了没反应（2026-11-16 那个 bug）。
            print("[codelumi-layout] isSplit=\(isSplitLayout) "
                  + "sizeClass=\(horizontalSizeClass == .regular ? "regular" : "compact")")
            applyScaffoldOpen()
            #endif
        }
        // 订阅暂未开放：点了只弹提示，不进入二级页
        .sheet(isPresented: $feedback.showComposer) {
            MailComposeView(subject: feedback.composerSubject,
                            body: feedback.composerBody,
                            attachment: feedback.composerAttachment) {
                feedback.showComposer = false
            }
        }
    }


    // MARK: 目录渲染（单列布局；iPad 分栏共用同一份目录）

    /// 最下面的「Codelumi Pro」区：标题 + 一张卡，点进去是订阅页。
    private var proSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Codelumi Pro")
            proBanner
        }
    }

    /// 2026-11-12 主人：首页不再显示「通用 / 外观与个性化 / 存储空间…」这类分组标题，
    /// 每一块自己聚成一组，组与组之间只用留白分隔（见 `stackedSettings` 的 spacing）。
    private func catalogSection(_ items: [SettingsPane]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 🔴 2026-11-08 主人：iOS 26+ 起每行一条**独立玻璃胶囊**，
            //    行间留 8pt，不再用一张大白卡 + 分隔线；iOS 18 没有液态玻璃，
            //    保持原来的整卡分组（系统材质），两种版本各自成立。
            if GlassSettings.isActive {
                VStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        catalogRow(item)
                            .appGlass(.rect(cornerRadius: 22, style: .continuous))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        if index > 0 { SettingsDivider() }
                        catalogRow(item)
                    }
                }
                .settingsCard()
            }
        }
    }

    @ViewBuilder
    private func catalogRow(_ item: SettingsPane) -> some View {
        if item == .language {
            // 语言不在 App 内切换，点了直接跳系统设置
            NavigationLink {
                AppLanguageView()
            } label: {
                SettingsRow(symbol: item.symbol, title: item.title,
                            detail: AppLanguageSettings.summary, tint: item.tint)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                paneContent(item)
            } label: {
                SettingsRow(symbol: item.symbol, title: item.title,
                            detail: detailValue(for: item), tint: item.tint)
            }
            .buttonStyle(.plain)
        }
    }

    /// 行尾的值（只有这几项有）
    private func detailValue(for item: SettingsPane) -> String? {
        switch item {
        case .appearance: return AppearanceSettings.shared.mode.title
        case .fontSize:   return AppearanceSettings.shared.followSystem
                                ? "跟随系统" : AppearanceSettings.shared.step.title
        case .appIcon:    return AppIconStore.current.title
        case .version:    return AppVersion.display
        case .storage:    return "\(store.records.count) 条"
        default:          return nil
        }
    }

    /// 窄屏：一张长页（目录驱动，与 iPad 分栏功能完全一致）。
    private var stackedSettings: some View {
        ScrollView {
            // 🔴 2026-11-17 流畅度：这里是 `VStack` → 改成 `LazyVStack`。
            //
            // 设置页有 5 个目录块、几十行 SettingsRow（每行一个 SF Symbol 图标 +
            // 玻璃行底），`VStack` 会在**首帧把全部行一次性构建完**。实测首次
            // 切到设置标签时主线程冻结 **247ms** —— 是所有页面里最重的一个。
            //
            // 按 `LazyVStack` 懒加载后，首帧只构建屏幕内那几块，其余滚到才建。
            // ⚠️ 块内部仍是全量的（一块 5~8 行，量小），不需要再拆。
            LazyVStack(spacing: 28) {   // 块与块之间靠留白分隔，不再画分组标题
                // 🔴 2026-11-08 主人：Pro 入口恢复放到**顶部**（此前挪到最下面，
                //    体验下来还是顶部更显眼，改回来）。
                proBanner
                catalogSection(SettingsPane.generalGroupAll)
                catalogSection(SettingsPane.appearanceTopGroup)
                catalogSection(SettingsPane.dataGroup)
                catalogSection(SettingsPane.supportGroup)
                catalogSection(SettingsPane.aboutGroupAll)
                footer
            }
            .padding(.horizontal, AppTheme.hInset)
            // 📱 宽屏限宽居中（iPhone Duo 展开态）：设置项与账户卡按阅读列排布，
            //    窄屏触不到 700 上限，视觉零变化。
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // 截图脚手架（2026-10-30）：`SETTINGS_ANCHOR=about` 时整页从底部起滚，
        // 直接露出「关于」组末行的「设备标识」。
        // 起因：命令行既不能滚动（simctl 无手势），又不能驱动模拟器点击
        // （AppleScript 被辅助功能权限拒绝，报 -10004），而这行在长页最底部。
        // 默认 `.top`，不注入变量时与改动前完全一致。
        .defaultScrollAnchor(
            ProcessInfo.processInfo.environment["SETTINGS_ANCHOR"] == "about" ? .bottom : .top
        )
        // 页面底 = 浅灰，卡片才是白（2026-09-23 修正口径，与全 App 一致）
        .background(AppTheme.pageBackground)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // 设置是标签根页：兜底露出标签栏（其它标签返回同口径，见 RootView）
            TabBarCloak.shared.reveal()
        }
    }

    /// 宽屏：macOS / iPad 设置式「左侧分组列表 + 右侧内容面板」。
    ///
    /// 2026-10-25 主人：「设置页面参考 Apple 的 mac、iPad 这种设置页面布局」，
    /// 并当场指正配色 —— **左侧栏浅灰底、选中行白色**（我第一版做反了）。
    /// 所以这里不用 `List(selection:)` 的系统高亮（iOS 会给灰色/蓝色选中块），
    /// 改成 plain List + 自绘行背景：底色浅灰、选中行白色圆角块。
    private var splitSettings: some View {
        NavigationSplitView {
            // 与待取 / 已取 同一套骨架：ZStack 铺灰 + NavigationStack。
            // 🔴 缺了 NavigationStack 标题会退化成**居中 inline**，和另外两页的大标题不一致
            //    （2026-11-15 主人要求「标题大小与直板机一致」）。
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()
                NavigationStack {
                    VStack(spacing: 0) {
                        // 🔴 2026-11-15 三页统一：大标题自绘（34pt bold），位置字号与待取 / 已取 一致。
                        PadSidebarHeader(title: "设置")
                        // 🔴 2026-11-15 主人：设置页**不要**左上角那个搜索框（截图圈掉了）。
                //    设置项本来就不多，一页能扫完；标题统一交给导航栏，
                //    与待取 / 已取 保持同一套（日期 2026-11-15）。
                List {
                    proBanner
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 10, trailing: 10))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    settingsGroup("", items: filtered(SettingsPane.generalGroupAll))
                    settingsGroup("", items: filtered(SettingsPane.appearanceTopGroup))
                    settingsGroup("", items: filtered(SettingsPane.dataGroup))
                    settingsGroup("", items: filtered(SettingsPane.supportGroup))
                    settingsGroup("", items: filtered(SettingsPane.aboutGroupAll))
                }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(AppTheme.pageBackground)
                        // 🔴 标题必须挂在 **List 上**（与待取 / 已取 同口径）。
                        //    挂在外面那层 VStack 上会退化成居中 inline 小字，
                        //    和另外两页的大标题对不齐（2026-11-15 实测）。
                        .toolbar(.visible, for: .navigationBar)
                        .toolbarBackground(.hidden, for: .navigationBar)
                        // 侧栏标题自绘（三页统一），导航栏只留按钮
                        .navigationTitle("")
                        .toolbarTitleDisplayMode(.inline)
                }
            }
            }
            // 侧栏宽度**按屏幕宽比例**（2026-10-25 主人：Duo 展开竖屏也要照 iPad 竖屏布局）：
            // 横屏 951pt → ~380pt；竖屏 669pt → ~280pt（下限）。
            // 写死 434 会让竖屏侧栏占到 65%，右侧内容被挤扁。
            .navigationSplitViewColumnWidth(min: 400, ideal: PadLayout.splitColumnIdeal, max: 600)
        } detail: {
            // 右栏与左栏**同一底色**（2026-10-25 主人两次强调：Duo 展开时左侧浅灰、
            // 右侧白色，「先全部是一个底色」）。
            // 三层兜底，任何一层漏掉都不会露出白：
            //   ① ZStack 铺满浅灰（含安全区）；
            //   ② NavigationStack 自身再垫一层浅灰；
            //   ③ 导航栏 toolbar 背景也显式设为浅灰（默认是 systemBackground 白）。
            ZStack {
                AppTheme.pageBackground
                    .ignoresSafeArea()

                // 🔴 不带 `path:` —— 见 `isSplitLayout` 上方那段注释，path 会让
                //    destination 型 NavigationLink 在常驻 pane 里推不动。
                NavigationStack {
                    // 照 iPad 设置的内容列：左右留白更大、内容限宽居中
                    paneContent(pane ?? .notification)
                        // 🔴 2026-11-16 去掉了这里的 `.id(pane)`。
                        //    它原本是「切面板后旧栈路径残留」的修法，但 `.id` 会让整棵内容树
                        //    在每次切 pane 时重建，挂在这棵树上的 `navigationDestination`
                        //    也跟着重建 —— 实测 push 被调用（有日志）却推不动。
                        //    现在栈上没有 path、也没有 `.id`，SwiftUI 按正常语义管理栈：
                        //    切 pane 时 `paneContent` 返回的是不同视图，栈自然重置。
                        // 🔴 2026-11-07：帮助页里那两个入口是「切详情列」打开的
                        //    （push 在这层不落地），所以补一个返回按钮回到帮助与反馈。
                        .toolbar {
                            if pane == .trainingSamples || pane == .contactInfo {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        pane = .help
                                    } label: {
                                        Label("返回", systemImage: "chevron.backward")
                                            .labelStyle(.titleAndIcon)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                        // 🔴 分栏里的这些页面是**常驻 pane**，不是 push 进来的二级页，
                        // 不能再让 `cloaksTabBar()` 把底部标签栏收走
                        // （2026-10-25 审查修：否则一进宽屏设置标签栏就没了）。
                        .environment(\.suppressTabBarCloak, true)
                }
                .background(AppTheme.pageBackground)
                // 导航栏透明 → 露出下面的浅灰，避免顶部一条白
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        .navigationSplitViewStyle(.balanced)
        // 与待取页同口径：导航栏透明，露出列底色（上色压不住系统材质，2026-11-15 实测）
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { TabBarCloak.shared.reveal() }
    }

    /// 侧栏目标宽：按屏幕宽的 40% 取，夹在 280…400 之间。
    /// Duo 横屏（951）→ 380；竖屏（669）→ 280。
    private var settingsSidebarWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let width = scene?.screen.bounds.width ?? 844
        return min(400, max(280, width * 0.40))
    }

    /// 侧栏搜索框（照 iPad 设置）
    private var settingsSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("搜索", text: $query)
                .font(AppTheme.TypeScale.body)
                .textFieldStyle(.plain)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTheme.TypeScale.rowSubtitle)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemFill), in: .capsule)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    /// 侧栏的一个分组（标题 + 若干行）
    @ViewBuilder
    private func settingsGroup(_ title: String, items: [SettingsPane]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    settingsSidebarRow(item)
                        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                if !title.isEmpty {
                    Text(title.L)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.leading, 10)
                }
            }
        }
    }

    /// 侧栏一行（照 iPad 设置：小图标 + 15pt 文字 + 灰色选中块，行高紧凑）
    private func settingsSidebarRow(_ item: SettingsPane) -> some View {
        HStack(spacing: 10) {
            SettingsGlyph(symbol: item.symbol, tint: item.tint, size: 26)

            Text(item.title.L)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            // iPad 设置的选中块是**灰色**（不是白色），圆角 9
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(pane == item ? Color(.systemGray5) : Color.clear)
        }
        .contentShape(.rect)
        .onTapGesture {
            // 语言没有 App 内页面：按主人要求直接跳到 设置 › App › Codelumi
            pane = item
        }
        .tag(item)
    }

    /// 截图脚手架：`SETTINGS_OPEN=icloudSync` 时启动直接切到该面板
    /// （单列布局点不到侧栏，也点不到行）。
    private func applyScaffoldOpen() {
        guard let raw = ProcessInfo.processInfo.environment["SETTINGS_OPEN"],
              let target = SettingsPane(rawValue: raw) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { pane = target }
    }

    /// 右侧内容：选中项展开的页面 / 卡片
    @ViewBuilder
    private var appleIntelligencePane: some View {        if #available(iOS 26.0, *) { AICapabilityView() } else { AICapabilityUnsupportedView() }
    }

    @ViewBuilder
    private func paneContent(_ item: SettingsPane) -> some View {
        switch item {
        case .appearance: AppearanceSettingsView()
        case .fontSize:   FontSizeView()
        case .language:   languageDetailPane
        case .automation: AutoRecordSettingsView()
        case .notification: NotificationSettingsView()
        case .widget:     WidgetSettingsView()
        case .codeManagement: CodeManagementView()
        case .activity:   ActivityPreviewGallery()
        case .courier:    CourierGalleryView(scope: .courier)
        case .station:    CourierGalleryView(scope: .station)
        case .guide:      UsageGuideView()
        case .license:    FullVersionView()
        case .activation: ActivationView()
        case .version:    VersionHistoryView()
        // 2026-11-12 设置页改版：存储空间独立成页（不再是原来的「本机数据」面板）
        case .storage:    StorageSpaceView()
        case .feedback:   feedbackPane
        case .privacy:    privacyPane
        // 2026-11-20 主人：第三方模型通道已删，这一行直达 Apple 端侧智能检测页
        case .aiCapability: appleIntelligencePane
        case .appIcon:      AppIconSettingsView()
        case .privacyDoc:   LegalDocumentView(document: .privacy)
        // 2026-11-12 主人：服务条款与「声明与免责」合并成一页
        case .termsDoc:     LegalDocumentView(document: .terms, extraHTML: StatementHTML.appended)
        case .disclaimer:   StatementView()
        case .help:
            // 宽屏下这页是常驻详情列，里面 push 不落地；交给它直接切 pane。
            if isSplitLayout {
                HelpCenterView { pane = $0 }
            } else {
                HelpCenterView()
            }
        case .trainingSamples: TrainingDataView()
        case .contactInfo:  ContactView()
        // 2026-11-12 设置页改版新增
        case .appearanceGroup:
            AppearancePersonalizationView(
                openPane: isSplitLayout ? { pane = $0 } : nil
            )
        case .aboutCodelumi:
            AboutCodelumiView(
                openPane: isSplitLayout ? { pane = $0 } : nil
            )
        case .icloudSync:   ICloudSyncView()
        case .encourage:    EncourageView()
        case .privacySimple: PrivacySimpleView()
        // 2026-11-21 主人：关于页新增两页
        case .openSource:   OpenSourceView()
        case .credits:      CreditsView()
        // 2026-11-22 主人：关于页新增「使用权限」
        case .permissions:  PermissionsView()
        // 这一行在关于页里是 ShareLink，不会走到 push；留个安全落点
        case .share:        EncourageView()
        }
    }

    /// 语言：App 内直接选（2026-11-08 主人：不再跳系统设置）
    private var languageDetailPane: some View {
        AppLanguageView()
    }

    /// 「反馈」面板：邮件直达 + 邮箱展示
    private var feedbackPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    Button {
                        DiagnosticsLog.record("feedback", "open")
                        feedback.startMail(includeLog: feedback.includeLog)
                    } label: {
                        SettingsRow(symbol: "envelope.fill", title: "发送邮件反馈",
                                    subtitle: FeedbackModel.mail,
                                    showsChevron: false,
                                    tint: AppTheme.doneTint)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Toggle(isOn: $feedback.includeLog) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("附带诊断日志")
                                .font(AppTheme.TypeScale.body)
                            Text("版本、系统、最近的操作记录，不含短信内容")
                                .font(AppTheme.TypeScale.badge)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .settingsCard()

                // 🔴 2026-11-22 主人：保留隐私承诺，去掉「滚动保存 / 你点并确认」这类过程描述。
                Text("日志只存本机，点发送才随邮件送出。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(AppTheme.hInset)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("反馈")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 「隐私」面板：把原关于组里的隐私口径单独成页
    private var privacyPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    SettingsRow(symbol: "hand.raised.fill", title: "隐私",
                                showsChevron: false,
                                tint: AppTheme.doneTint)
                }
                .settingsCard()

                // 🔴 2026-11-22 主人：压成一句。无账号、无服务器本身就在标题「隐私」的语境里。
                Text("数据只在本机；开了 iCloud 同步就只进你的 iCloud。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                footer
            }
            .padding(AppTheme.hInset)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("隐私")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 设置


    // MARK: 顶部订阅横幅

    /// 设置页顶部那条 PRO 横幅（2026-10-31 定）。
    ///
    /// 为什么放到最顶上：App 免费下载、靠订阅解锁，**入口必须显眼**；
    /// 藏起来既不厚道，也会被审核按「付费功能没有明显入口」挑刺。
    /// 已购时同一块横幅改口径为「完整版已开通」，不摆第二次购买。
    @ViewBuilder
    private var proBanner: some View {
        // 🔴 2026-11-07 主人：恢复订阅页 —— 横幅直接进 FullVersionView。
        // 🔴 同一天又发现：分栏侧栏里放 `NavigationLink` 点了没反应
        //    （侧栏是 List + 选中状态，push 会被吞）。所以分栏改用 Button 切右栏。
        if isSplitLayout {
            Button { pane = .license } label: { proBannerLabel }
                .buttonStyle(.plain)
        } else {
            NavigationLink { FullVersionView() } label: { proBannerLabel }
                .buttonStyle(.plain)
        }
    }

    private var proBannerLabel: some View {
        Group {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Codelumi")
                            .font(.system(size: 23, weight: .bold))
                        Text("PRO")
                            .font(AppTheme.TypeScale.note.weight(.heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.55), in: .rect(cornerRadius: 6))
                    }
                    .foregroundStyle(AppTheme.champagneInk)

                    Text(store.isPro ? "Codelumi Pro 已开通" : "了解Codelumi Pro")
                        .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                        .foregroundStyle(AppTheme.champagneInk.opacity(0.8))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                    .foregroundStyle(AppTheme.champagneInk.opacity(0.75))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 23)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 橙色渐变：整页唯一的彩色块。
                // 🔴 这里**故意不用**主题色（主题是蓝的）：横幅是营销面，
                //    用高饱和橙更像"付费墙"，也更容易被注意到。
                //    原来的 amber(#B45309) 起手偏褐，压到白底上像脏了。
                LinearGradient(colors: [AppTheme.champagneLight, AppTheme.champagne],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            }
            .clipShape(.rect(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: AppTheme.champagneInk.opacity(0.16), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    // 2026-11-07 主人：上架前移除「激活」入口（App Review 3.1.1），
    // 对应分组已从两种布局里删除，激活页代码保留但不再有入口。

    // MARK: 关于（版本 / 反馈 / 隐私）


    /// 复制本机 UUID：**复制完整值**（界面上是打码的）
    private func copyDeviceUUID() {
        UIPasteboard.general.string = LicenseDevice.current
        withAnimation(AppMotion.quick) { copiedUUID = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(AppMotion.quick) { copiedUUID = false }
        }
    }

    /// 法律文档整行：**推入 App 内页面**（2026-10-31 主人：不要跳浏览器）。
    /// 文档 HTML 随包发布，离线可读；Store 表单里的地址另填 `LegalLinks`。
    private func legalRow(symbol: String, title: String, note: String,
                          document: LegalDocument, tint: Color) -> some View {
        NavigationLink {
            LegalDocumentView(document: document)
        } label: {
            SettingsRow(symbol: symbol, title: title, subtitle: note, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        // 🔴 2026-11-22 主人：上一句已经把「只在本机 / 只进自己 iCloud」说完，
        //    页脚再说一遍就是重复，只留品牌行。
        VStack(spacing: 6) {
            Text("Codelumi")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    /// 邮件打不开时的提示条（复制邮箱兜底）。
    @ViewBuilder private var feedbackToast: some View {
        if feedback.showFallback {
            VStack(spacing: 10) {
                Text("邮件 App 不可用，已复制邮箱到剪贴板：")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(FeedbackModel.mail.L)
                    .font(.footnote.weight(.semibold).monospaced())
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .appGlass(.capsule)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.85),
                       value: feedback.showFallback)
        }
    }
}

// MARK: - 反馈

/// 打开邮件反馈；邮件 App 不可用时自动复制邮箱兜底并提示。
final class FeedbackModel: ObservableObject {
    static let mail = "zhang_wangning@126.com"

    @Published var showFallback = false
    /// 是否附带诊断日志（默认开：出问题的人一般不知道该带什么）
    @Published var includeLog = true
    /// 系统邮件编辑器
    @Published var showComposer = false
    @Published var composerSubject = ""
    @Published var composerBody = ""
    @Published var composerAttachment: (name: String, data: Data)?

    private var hideTask: Task<Void, Never>?

    var subtitle: String { Self.mail }

    /// 组织一封带诊断日志的反馈邮件（2026-10-31 主人：日志随反馈一起发过来）。
    ///
    /// 优先用系统邮件编辑器（能带附件）；设备没配邮件时退回复制邮箱的兜底，
    /// 那种情况下把日志正文贴进剪贴板不合适（太长），所以只提示用户去配置邮件。
    func startMail(includeLog: Bool) {
        let version = AppVersion.display
        composerSubject = "Codelumi反馈（\(version)）"
        composerBody = """
        请描述你遇到的问题（什么时候、做了什么、预期是什么）：



        —— 以下由 App 自动填写 ——
        版本：\(version)
        系统：iOS \(UIDevice.current.systemVersion)
        """

        if includeLog {
            let text = DiagnosticsLog.exportText()
            composerAttachment = (name: "codelumi-log.txt", data: Data(text.utf8))
        } else {
            composerAttachment = nil
        }

        if MFMailComposeViewController.canSendMail() {
            showComposer = true
        } else {
            // 没有邮件账号：不硬弹，复制邮箱兜底（日志留在本机，下次配好再发）
            copyMailFallback()
        }
    }

    func openMail() {
        // 主题带上版本号，定位问题更快
        let subject = "Codelumi反馈（\(AppVersion.display)）"
        let url = URL(string: "mailto:\(Self.mail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!

        // 2026-10-20：iOS 27 起 `canOpenURL` 已弃用（官方建议「直接尝试打开、按失败分支处理」）。
        // 改为用 open 的 completion 判断结果：成功即正常，失败走复制邮箱兜底。
        UIApplication.shared.open(url, options: [:]) { success in
            DispatchQueue.main.async {
                if success {
                    self.showFallback = false
                } else {
                    self.copyMailFallback()
                }
            }
        }
    }

    /// 邮件 App 不可用时的兜底：复制邮箱到剪贴板并浮出提示（3.2s 自动收起）
    private func copyMailFallback() {
        UIPasteboard.general.string = Self.mail
        showFallback = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if !Task.isCancelled { showFallback = false }
        }
    }

}

// MARK: - 版本号显示（单一真值）
//
// 以 Info.plist 的 MARKETING_VERSION 为准（工程已改 0.2.3），
// 版本历史页与设置页共用，避免「两处各写一个号」漂移。
enum AppVersion {
    static var display: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return (short?.isEmpty == false) ? short! : "0.3.2"
    }
}

// MARK: - 签名凭证（买断解锁）

/// 输入凭证 → 本地验签 → 写入权益。全程离线，不联网、不涉及账号。
///
/// 凭证格式见 `OfflineLicense.swift`：`CLIP1.<base64载荷>.<ECDSA-P256 签名>`。
/// 本页只做三件事：把本机设备码摆出来让人复制、收一串凭证、把结果说清楚。
///
/// 🔴 **App 内不出现任何价格**（见 `MembershipPlan` 里的历史注释）：
///    档位归属由卖家在店外说明，这里只说「已解锁 / 未解锁」。
// MARK: - 完整版（订阅）

/// 免费下载 + 两档解锁（终身买断 + 按年订阅；价格取自 StoreKit）。
///
/// 版式：**大标题 → 竖排方案（单选）→ 功能清单 → 主行动键 → 恢复购买**。
/// 刻意不走"三张并排卡 + 橙色线稿图标 + 直接点卡即买"那套订阅页套路：
/// 信息结构可以参考，视觉签名不能照搬 —— 并排卡＋线稿图标是它最显眼的识别点。
/// 这里用一个可选方案列表 + 一枚主按钮，买之前先明确"我要买哪一档"。
/// 订阅面板占位（宽屏分栏用）。
///
/// 2026-10-31 主人：订阅未开放，不允许进入二级页 —— 分栏布局里点侧栏
/// 「完整版」不该出现定价页，这里给一张说明卡。
struct SubscriptionUnavailablePane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("暂不支持订阅")
                .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
            Text("敬请期待……")
                .font(AppTheme.TypeScale.rowSubtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.pageBackground)
        .navigationTitle("Codelumi Pro")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FullVersionView: View {
    @EnvironmentObject private var store: PickupStore
    @ObservedObject private var purchase = PurchaseStore.shared

    /// 默认落在主推档（买断）
    @State private var selected: PurchaseStore.Plan = .lifetime
    /// 条款 / 隐私以 App 内页面弹出，不跳浏览器
    @State private var legalSheet: LegalDocument?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // 2026-10-31 主人：**一屏放得下，不要翻页**。
            // 所以去掉了页首的大标题块，版式与其它设置页同口径：
            // 分组标题 13pt、行标题 17pt、说明 11–12pt，靠紧凑间距压进一屏。
            VStack(alignment: .leading, spacing: 10) {
                // 页内标题（2026-10-31 主人要求补上）。导航栏那个「完整版」太小，
                // 进页面第一眼得知道这一页在卖什么；字号取 24pt，介于正文 17 与
                // 系统大标题 34 之间，不与导航栏抢层级。
                titleBlock

                // 2026-10-31 主人：**已购后页面结构不变**，只把三张方案卡换成一张「谢谢您」，
                // 解锁清单、恢复购买、条款链接都还在。不要另做一个"订阅成功页"。
                if purchase.isOwned {
                    thanksCard
                } else {
                    planList
                }

                featureList

                if !purchase.isOwned {
                    primaryButton

                    // 商品拉不到时（内测/商店暂时不可达），给一个手动的重试入口：
                    // 商品在 App Store Connect 上架后，不退出页面也能重新拉一次。
                    if !purchase.canPurchase {
                        Button {
                            Task { await purchase.loadProducts() }
                        } label: {
                            Text("重新获取商品信息")
                                .font(AppTheme.TypeScale.note.weight(.medium))
                                .foregroundStyle(AppTheme.champagneInk)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }

                restoreButton
                finePrint

                if let message = purchase.message, !purchase.isOwned {
                    Text(message.L)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        // 截图脚手架：命令行点不了、也滚不动屏幕，`PAYWALL_ANCHOR=bottom`
        // 时直接落到页底，用来验「恢复购买 + 条款链接」这两行确实在。
        .onAppear {
            guard ProcessInfo.processInfo.environment["PAYWALL_ANCHOR"] == "bottom" else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .navigationTitle("Codelumi Pro")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .onAppear {
            // 🔴 2026-11-16：以前只在「商品完全取不到」时才重试。StoreKit 若先
            //    给了美元基准价，`canPurchase` 已是 true，就再也不会重拉 ——
            //    用户只能干等系统自己把 storefront 切成中国区才看到人民币。
            //    改成每次进页面都刷新一次（正在购买时不打扰），配合
            //    `PurchaseStore` 的 `Storefront.updates` 监听，价格能及时收敛。
            guard purchase.purchasingPlan == nil else { return }
            Task { await purchase.loadProducts() }
        }
        .sheet(item: $legalSheet) { document in
            LegalDocumentView(document: document)
        }
        }
    }

    // MARK: 页内标题

    private var titleBlock: some View {
        // 两行标题（2026-10-31 主人指定文案）。断行位置按语义切：
        // 「感谢」单独一行，「订阅 Codelumi Pro」整行 —— 与参考页同样的
        // 大标题节奏，但不复制它的字句。
        VStack(alignment: .leading, spacing: 2) {
            Text("感谢订阅")
            Text("Codelumi Pro")
        }
        .font(.system(size: 24, weight: .bold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 方案（横排）

    private var planList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "选择方案")

            // 三档**横排**（2026-10-31 主人：横向分布）。
            // 402pt 屏上内容宽 370pt，卡片间距 8 → 每张约 118pt，
            // 价格 20pt 字刚好放得下「$9.99」这类四位数价格。
            HStack(spacing: 8) {
                ForEach(PurchaseStore.displayedPlans) { plan in
                    planCard(plan)
                }
            }
            .padding(.top, 9)     // 给「推荐」徽章留出上探的空间

            // 🔴 2026-11-08 主人：两句话共用**下面这一格**（固定高度）：
            //    选终身显示「推荐买断」，选每年显示续期说明；
            //    高度写死，切换方案时下面的内容不会跟着上下跳。
            Text(selected == .lifetime
                 ? "推荐买断：一次付清，永久有效。"
                 : "订阅会自动续期：到期前 24 小时自动扣款，可在「设置 › Apple ID › 订阅」里取消。")
                .font(.caption)
                .foregroundStyle(selected == .lifetime ? Color.secondary : Color.secondary)
                .lineLimit(2)
                .frame(height: 30, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func planCard(_ plan: PurchaseStore.Plan) -> some View {
        let on = selected == plan
        let price = purchase.price(for: plan)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selected = plan }
        } label: {
            VStack(spacing: 6) {
                Text(plan.title.L)
                    .font(AppTheme.TypeScale.note.weight(.medium))
                    .foregroundStyle(.secondary)

                // 价格是这个卡片的主角：三档之间要比的是这个数
                Text(price ?? "—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(on ? AppTheme.champagneInk : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(plan.shortPeriod.L)
                    .font(AppTheme.TypeScale.badge)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? AppTheme.champagneLight.opacity(0.55)
                              : AppTheme.cardSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    // 深色下 champagne 是石墨，描边要用金色才看得出来
                    .strokeBorder(on ? AppTheme.champagneInk : Color.clear, lineWidth: 1.5)
            }
            .overlay(alignment: .topTrailing) {
                // 只靠描边颜色不够：截图、色弱、或渲染晚一帧都可能看错档位。
                // 加一个勾，选中与否有形状上的差别。
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(AppTheme.champagne)
                        .padding(7)
                }
            }
            .overlay(alignment: .top) {
                if plan.isRecommended {
                    Text("推荐")
                        .font(AppTheme.TypeScale.badge.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.champagneInk, in: .capsule)
                        .foregroundStyle(AppTheme.champagneLight)
                        .offset(y: -9)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 功能清单

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "解锁什么")

            VStack(spacing: 0) {
                // 🔴 2026-11-21 主人：整段还是啰嗦，再压一遍 ——
                //    说明里不再重复「Codelumi / Codelumi Pro」这两个全名（标题区已经写了），
                //    「经不经开发者服务器」「搜索态不给详情」这类定语收进隐私政策与拦截弹窗，
                //    清单只留「免费版多少 / Pro 给什么」。行数仍是 5，不动一屏放得下的前提。
                featureRow(symbol: "tray.full.fill", title: "不限条数",
                           note: "免费版同屏 \(PickupStore.freeVisibleLimit) 条、最多存 \(PickupStore.freeStorageLimit) 条，Pro 不限、详情全开")
                SettingsDivider()
                featureRow(symbol: "square.grid.2x2.fill", title: "小组件全尺寸",
                           note: "免费版只有小、中，Pro 有大尺寸与大号竖版")
                SettingsDivider()
                featureRow(symbol: "iphone.gen3.radiowaves.left.and.right", title: "实时活动",
                           note: "灵动岛与锁屏常驻取件码")
                SettingsDivider()
                // 2026-11-15 主人：iCloud 同步并入 Pro —— 门加上了，清单也得写上，
                // 否则用户被拦下来却看不到「同步」在解锁项里。
                featureRow(symbol: "icloud.fill", title: "iCloud 同步",
                           note: "存进你自己的 iCloud，多设备自动合并")
                SettingsDivider()
                featureRow(symbol: "arrow.triangle.2.circlepath", title: "后续更新",
                           note: "后续新功能都包含")
            }
            .settingsCard()
        }
    }

    private func featureRow(symbol: String, title: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsGlyph(symbol: symbol, tint: AppTheme.champagneIcon, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.L)
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                Text(note.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 主行动

    private var primaryButton: some View {
        Button {
            Task { await purchase.purchase(selected) }
        } label: {
            Text(primaryTitle.L)
                .font(AppTheme.TypeScale.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(canBuy ? AppTheme.ctaFill : Color(.tertiarySystemFill), in: .capsule)
                .foregroundStyle(canBuy ? AppTheme.ctaInk : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canBuy)
    }

    private var canBuy: Bool { purchase.canPurchase && purchase.purchasingPlan == nil }

    private var primaryTitle: String {
        if purchase.purchasingPlan != nil { return "处理中…" }
        guard let price = purchase.price(for: selected) else { return "暂时无法购买" }
        switch selected {
        case .monthly:  return "\(price) / 月 订阅"
        case .yearly:   return "\(price) / 年 订阅"
        case .lifetime: return "\(price) 买断"
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await purchase.restore() }
        } label: {
            Text("恢复购买")
                .font(AppTheme.TypeScale.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .overlay {
                    Capsule().strokeBorder(AppTheme.champagneInk.opacity(0.55), lineWidth: 1.5)
                }
                .foregroundStyle(AppTheme.champagneInk)
        }
        .buttonStyle(.plain)
    }

    /// 自动续期说明 + 隐私政策 / 使用条款（App Review 3.1.2 要求在订阅页能点到）
    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ⚠️ 2026-11-22 老大：「无广告是好事，但也不用到处写，订阅页面底部的提示删除掉」。
            //    这里原本放了一句「没有广告，也没有广告 SDK…」，已撤。
            //    「无广告」现在只留在隐私政策与使用条款（法务口径该写），App 内不再重复推销。
            HStack(spacing: 12) {
                Button("隐私政策") { legalSheet = .privacy }
                Text("·").foregroundStyle(.tertiary)
                Button("使用条款") { legalSheet = .terms }
            }
            .font(AppTheme.TypeScale.note)
            // 付费面上统一用橙，别让两条蓝色链接在整页里跳出来
            .tint(AppTheme.champagneInk)
            .foregroundStyle(AppTheme.champagneInk)
        }
        .padding(.horizontal, 4)
        .id("bottom")
    }

    // MARK: 已开通

    /// 已购状态的那张卡：与三张方案卡**同一位置、同一视觉语言**
    /// （同样的圆角、浅金底、金色描边），只是内容换成一句道谢。
    /// 这样买完之后页面不会"换一张脸"，只是卡片本身变了。
    private var thanksCard: some View {
        VStack(spacing: 6) {
            Text("谢谢您")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.champagneInk)

            Text(store.plan == .lifetime ? "已买断 · 永久有效" : "Codelumi Pro 已开通")
                .font(AppTheme.TypeScale.rowSubtitle)
                .foregroundStyle(AppTheme.champagneInk.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.champagneLight.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.champagne, lineWidth: 2)
        }
    }

}

// MARK: - 语言（App 内直接选，2026-11-08 主人定）

/// 版式参考系统语言列表：一行一种语言，当前项打勾。
/// 只有两套本地化（简体 / 繁体）+ 跟随系统，**不做导入、不塞一堆语言**。
struct AppLanguageView: View {
    @State private var choice = AppLanguageSettings.choice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(AppLanguageChoice.allCases.enumerated()), id: \.element) { index, item in
                        if index > 0 { SettingsDivider() }
                        Button {
                            choice = item
                            AppLanguageSettings.choice = item
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.title)
                                    .font(AppTheme.TypeScale.rowTitle)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 0)

                                if choice == item {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .settingsCard()

                Text("切换后需要**重新打开Codelumi**才会生效。".richText)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("语言")
        .navigationBarTitleDisplayMode(.inline)
    }
}
