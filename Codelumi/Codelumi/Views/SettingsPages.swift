import SwiftUI
import StoreKit

// MARK: ============================================================================
// 设置页二级页（2026-11-12 主人改版）
//
// 主人给的首页结构：
//   ① 通用：快捷指令 / 通知 / 桌面小组件 / 实时活动 / iCloud 同步 / Apple 智能
//   ② 外观与个性化（二级页收拢：App 图标 / 外观 / 字体大小 / 语言）
//   ③ 存储空间
//   ④ 帮助与反馈
//   ⑤ 更多：快递公司 / 驿站管理 / 关于 Codelumi
//
// 这一版把「界面自定义」和「关于」各自收成**一个入口**，首页不再一行行铺开。
// 宽屏（Duo 展开 / iPad）的分栏里，这些页是常驻详情列，`NavigationLink` 不落地，
// 所以都接受一个 `openPane` 回调，由外层把右栏切过去（与 HelpCenterView 同口径）。
// ============================================================================

// MARK: - 外观与个性化

struct AppearancePersonalizationView: View {
    /// 宽屏分栏下由外层注入「切换右栏」的能力；窄屏为 nil，走普通 push。
    var openPane: ((SettingsPane) -> Void)? = nil

    /// 底部菜单栏是否显示「统计」。放 App Group，主界面和本页读写同一份。
    @AppStorage(TabBarPrefs.showsStatsKey,
                store: PickupStorage.groupStore)
    private var showsStats = true

    /// 「显示「统计」」属于 Codelumi Pro：非 Pro 点一下直接弹订阅页（2026-11-15 主人）。
    @State private var showPaywall = false

    /// 当前是否 Pro。放进 `@State` 是为了**买完回来立刻生效** ——
    /// 直接读 `EntitlementSnapshot.licensedPro` 只在别的状态变化时顺带重算，
    /// 订阅页一关，开关常常还停在"未解锁"的样子。
    @State private var isPro = EntitlementSnapshot.licensedPro

    /// 液态玻璃开关（2026-11-14 从「外观」页移过来）：仅 iOS 26+ 展示；
    /// 关闭后走系统毛玻璃材质，与 iOS 18 的观感一致。
    ///
    /// 🔴 2026-11-23（老大：「液态玻璃开关最好也实时变化」）：
    ///    原来是 `@State` + 手工 `setEnabled(...)` —— 值写进 App Group 了，
    ///    但全 App 那些已经画好的玻璃卡片不会重算，得退出去再进来。
    ///    改成 `@AppStorage` 绑同一个存储实例，再配 `GlassCompat` 里的
    ///    `GlassShell`（它自己也观察这个键），拨完当场换材质。
    @AppStorage(GlassSettings.key, store: PickupStorage.groupStore)
    private var usesLiquidGlass = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(SettingsPane.appearanceDetailGroup.enumerated()),
                            id: \.element) { index, item in
                        if index > 0 { SettingsDivider() }
                        row(item)
                    }
                }
                .settingsCard()

                if GlassSettings.isSupported {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { usesLiquidGlass },
                                set: { newValue in
                                    usesLiquidGlass = newValue
                                    DiagnosticsLog.record("appearance", "liquidGlass=\(newValue)")
                                }
                            )) {
                                Text("液态玻璃")
                                    .font(AppTheme.TypeScale.rowTitle)
                            }
                            .tint(AppTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .settingsCard()

                    // 🔴 2026-11-22 主人：只留「需重启」这条猜不到的，其余删掉。
                    Text("关闭后改用系统毛玻璃，需重启 App 生效。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 底部菜单栏：统计页可以关掉（2026-11-13 主人要求）。
                // 关掉后底栏只剩 待取 / 已取 / 设置，统计页也就没有入口。
                //
                // 🔴 2026-11-15 主人：这一项属于 **Codelumi Pro**。非 Pro 点一下开关
                //    = 直接弹订阅页，与「超时未取提醒」同一套做法（不显示任何加锁标志、
                //    不先翻转开关再回弹）。买完回来开关立刻可用。
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        if isPro {
                            Toggle(isOn: $showsStats) {
                                Text("显示「统计」")
                                    .font(AppTheme.TypeScale.rowTitle)
                            }
                            .tint(AppTheme.accent)
                        } else {
                            // 非 Pro 时开关恒显示为「开」（统计页本来就在），
                            // 用 overlay 接管点击 —— 不能直接把 Toggle 包进 Button：
                            // 那样整行会被压扁、开关被挤到中间（2026-11-08 踩过）。
                            Toggle(isOn: .constant(true)) {
                                Text("显示「统计」")
                                    .font(AppTheme.TypeScale.rowTitle)
                            }
                            .tint(AppTheme.accent)
                            .allowsHitTesting(false)
                            .overlay {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { showPaywall = true }
                                    .accessibilityLabel("显示「统计」")
                                    .accessibilityHint("需要Codelumi Pro")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .settingsCard()

                // 🔴 2026-11-22 主人：删掉「关掉后底部菜单栏只剩 待取 / 已取 / 设置。」
                //    关掉开关底栏就少了那一项，用户当场看得见，不需要预告。

            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("外观与个性化")
        .navigationBarTitleDisplayMode(.inline)
        // 非 Pro 点「显示「统计」」→ 订阅页；关掉时重判一次权益，
        // 买完不必退出重进，回来就能直接关统计。
        .sheet(isPresented: $showPaywall, onDismiss: {
            isPro = EntitlementSnapshot.licensedPro
        }) {
            NavigationStack { FullVersionView() }
                .modifier(PaywallSheetSizing())
        }
        .onAppear {
            isPro = EntitlementSnapshot.licensedPro
            // 截图脚手架（仅调试）：命令行点不了开关，`PAYWALL_DEMO=1` 直接把订阅页亮起来。
            #if DEBUG
            if ProcessInfo.processInfo.environment["PAYWALL_DEMO"] == "1" { showPaywall = true }
            #endif
        }
    }

    /// 「推荐给朋友」是系统分享面板，不是 push（2026-11-21 主人从「鼓励一下」挪过来）
    private static let shareText = SettingsPane.recommendText

    @ViewBuilder
    private func row(_ item: SettingsPane) -> some View {
        if item == .share {
            ShareLink(item: Self.shareText) { label(item) }
                .buttonStyle(.plain)
        } else if let openPane {
            Button { openPane(item) } label: { label(item) }
                .buttonStyle(.plain)
        } else {
            NavigationLink { destination(item) } label: { label(item) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func label(_ item: SettingsPane) -> some View {
        if item == .appIcon {
            // 🔴 2026-11-14 主人：这一行叫「自定义 App 图标」，**右侧不显示当前图标名**
            //    （名字对选图标没有意义，还容易让人以为要点那个名字）。
            SettingsRow(symbol: item.symbol,
                        title: "自定义 App 图标",
                        detail: nil,
                        tint: item.tint)
        } else {
            SettingsRow(symbol: item.symbol,
                        title: item.title,
                        detail: detail(item),
                        tint: item.tint)
        }
    }

    private func detail(_ item: SettingsPane) -> String? {
        switch item {
        case .appIcon:    return AppIconStore.current.title
        case .appearance: return AppearanceSettings.shared.mode.title
        case .fontSize:
            return AppearanceSettings.shared.followSystem
                ? "跟随系统" : AppearanceSettings.shared.step.title
        case .language:   return AppLanguageSettings.summary
        default:          return nil
        }
    }

    @ViewBuilder
    private func destination(_ item: SettingsPane) -> some View {
        switch item {
        case .appIcon:    AppIconSettingsView()
        case .appearance: AppearanceSettingsView()
        case .fontSize:   FontSizeView()
        default:          AppLanguageView()
        }
    }
}

// MARK: - 存储空间

struct StorageSpaceView: View {
    @EnvironmentObject private var store: PickupStore
    @State private var showClearAll = false

    private var quotaText: String {
        store.isPro
            ? "不限量"
            : "最多 \(PickupStore.freeStorageLimit) 条（超出后按最早入库淘汰）"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    SettingsRow(symbol: "internaldrive.fill", title: "已存记录",
                                detail: "\(store.records.count) 条",
                                showsChevron: false,
                                tint: AppTheme.todayTint)

                    SettingsDivider()

                    SettingsRow(symbol: "shippingbox.fill", title: "待取",
                                detail: "\(store.pending.count) 条",
                                showsChevron: false,
                                tint: AppTheme.sky)

                    SettingsDivider()

                    SettingsRow(symbol: "checkmark.circle.fill", title: "已取",
                                detail: "\(store.pickedUpRecords.count) 条",
                                showsChevron: false,
                                tint: AppTheme.doneTint)

                    SettingsDivider()

                    SettingsRow(symbol: "doc.text.fill", title: "数据文件",
                                detail: PickupStorage.fileSizeDescription,
                                showsChevron: false,
                                tint: AppTheme.indigo)
                }
                .settingsCard()

                Button {
                    showClearAll = true
                } label: {
                    SettingsRow(symbol: "trash.fill", title: "一键清除数据",
                                showsChevron: false,
                                tint: .red)
                }
                .buttonStyle(.plain)
                .settingsCard()

                // 🔴 2026-11-22 主人：隐私承诺保留，删掉「不经过开发者服务器」这种自证式补充。
                Text("只在本机；开了 iCloud 同步就只进你的 iCloud。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                PageFooter()
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .destructiveConfirm(isPresented: $showClearAll,
                            title: "清除全部数据？",
                            message: "将删除这台设备上的 \(store.records.count) 条取件记录，无法恢复。",
                            confirmLabel: "清除") {
            store.deleteMany(store.records)
        }
        .navigationTitle("存储空间")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 关于 Codelumi

struct AboutCodelumiView: View {
    var openPane: ((SettingsPane) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(SettingsPane.aboutDetailGroup.enumerated()),
                            id: \.element) { index, item in
                        if index > 0 { SettingsDivider() }
                        row(item)
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
        .navigationTitle("关于 Codelumi")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 顶部：图标 + 名字 + 版本号（照 iOS「关于本机」的排版）
    private var header: some View {
        VStack(spacing: 8) {
            Image(AppIconStore.current.assetName)
                .resizable()
                .interpolation(.high)
                .frame(width: 78, height: 78)
                .clipShape(.rect(cornerRadius: 78 * 0.2237, style: .continuous))

            Text("Codelumi")
                .font(AppTheme.TypeScale.rowTitle.weight(.semibold))

            // 中文名只在关于页出现一次（2026-11-21 主人：主要使用英文名称）
            Text("珞米")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)

            Text(AppVersion.display.L)
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// ⚠️ 2026-11-22：这里曾经插过一张「四条事实卡」（离线 / 不收集 / 无广告 / 只存本机，
    /// 搬自没有入口的 `AboutView`）。老大看图否掉：「关于Codelumi页面中不要上面的这些内容，
    /// 多此一举，谁让你这么做的」—— 已撤。这一页只保留图标 + 名字 + 菜单列表。
    /// 「无广告」这个卖点仍然在：付费页按钮下方、隐私政策、使用条款第 1 条。

    @ViewBuilder
    private func row(_ item: SettingsPane) -> some View {
        // 🔴 分享行必须是 ShareLink：它不推任何页面。
        //    之前这里漏了分支，`.share` 走进 NavigationLink → destination 的 default
        //    把它推到「版本历史」，老大一眼看出来不对。
        if item == .share {
            ShareLink(item: SettingsPane.recommendText) { label(item) }
                .buttonStyle(.plain)
        } else if let openPane {
            Button { openPane(item) } label: { label(item) }
                .buttonStyle(.plain)
        } else {
            NavigationLink { destination(item) } label: { label(item) }
                .buttonStyle(.plain)
        }
    }

    private func label(_ item: SettingsPane) -> some View {
        // 🔴 2026-11-15 主人：行副标题一律不要。
        //    「服务条款」原来带一行「使用条款与声明和免责」，标题已经把内容说清楚了，
        //    再挂一行说明只是重复（主人原话：标题中不要有提示文字）。
        SettingsRow(symbol: item.symbol,
                    title: title(item),
                    subtitle: nil,
                    detail: item == .version ? AppVersion.display : nil,
                    // 分享行是 ShareLink（弹系统面板），不是 push，所以不画 chevron
                    showsChevron: item != .share,
                    tint: item.tint)
    }

    private func title(_ item: SettingsPane) -> String {
        switch item {
        case .privacyDoc: return "隐私政策（完整版）"
        default:          return item.title
        }
    }

    @ViewBuilder
    private func destination(_ item: SettingsPane) -> some View {
        switch item {
        case .encourage:     EncourageView()
        case .termsDoc:      LegalDocumentView(document: .terms, extraHTML: StatementHTML.appended)
        case .privacyDoc:    LegalDocumentView(document: .privacy)
        case .privacySimple: PrivacySimpleView()
        case .openSource:    OpenSourceView()
        case .credits:       CreditsView()
        case .permissions:   PermissionsView()
        case .share:         EmptyView()   // 永远走 ShareLink，不进这里
        case .version:       VersionHistoryView()
        default:
            // 🔴 别再写 `default: VersionHistoryView()` —— 那正是「推荐给朋友」
            //    被推到版本历史的成因：没写 case 的项会静默落到某个真实页面。
            //    现在缺 case 就给空视图 + DEBUG 断言，编译期看不出、跑起来立刻炸。
            #if DEBUG
            let _ = assertionFailure("AboutCodelumiView 缺少 \(item.rawValue) 的落点")
            #endif
            EmptyView()
        }
    }
}

// MARK: - 鼓励一下

/// 「鼓励一下」= 只做 App Store 评分（2026-11-21 主人：推荐给朋友挪到「关于 Codelumi」）。
/// 用系统的 `requestReview`：什么时候弹由 iOS 决定，我们不诱导、也不追踪。
struct EncourageView: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(AppTheme.pendingTint)
                        .padding(.top, 8)

                    // 🔴 2026-11-22 主人：「废话就删除」。原句绕了三层，压成一句。
                    Text("用得顺手，给个评分。")
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                Button {
                    requestReview()
                } label: {
                    SettingsRow(symbol: "star.fill", title: "在 App Store 上评分",
                                showsChevron: false,
                                tint: AppTheme.amber)
                }
                .buttonStyle(.plain)
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
        .navigationTitle("鼓励一下")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 隐私政策（简明版）

/// 完整版是随包的 HTML（法律文本）；这一页是给人看的大白话摘要。
struct PrivacySimpleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    SettingsRow(symbol: "wifi.slash", title: "不联网",
                                subtitle: "App 本体不发任何请求；内购由 Apple 处理。",
                                showsChevron: false, tint: AppTheme.doneTint)

                    SettingsDivider()

                    SettingsRow(symbol: "hand.raised.fill", title: "不收集数据",
                                subtitle: "没有账号、没有统计 SDK、没有广告。",
                                showsChevron: false, tint: AppTheme.sky)

                    SettingsDivider()

                    SettingsRow(symbol: "internaldrive.fill", title: "取件记录默认只在本机",
                                subtitle: "存在这台设备的 App Group 里，主 App 与小组件共用；驿站组、驿站编号、取件码样式等偏好同样只在本机。开启 iCloud 同步后才另存一份到你自己的 iCloud。",
                                showsChevron: false, tint: AppTheme.todayTint)

                    SettingsDivider()

                    SettingsRow(symbol: "camera.fill", title: "权限只在本机用",
                                subtitle: "通知提醒、相册选图、拍照识别、到达提醒定位，处理全在设备上；每项都能在 App 里关掉。",
                                showsChevron: false, tint: AppTheme.violet)

                    SettingsDivider()

                    SettingsRow(symbol: "trash.fill", title: "卸载或删除即消失",
                                subtitle: "没有回收站。开了 iCloud 同步时，记录会留在你自己的 iCloud 里，重装后可同步回来。",
                                showsChevron: false, tint: AppTheme.pendingTint)

                    SettingsDivider()

                    SettingsRow(symbol: "creditcard.fill", title: "内购由 Apple 处理",
                                subtitle: "我们看不到你的支付信息。",
                                showsChevron: false, tint: AppTheme.indigo)
                }
                .settingsCard()

                // 🔴 2026-11-15 主人：这里**不要**再放「查看完整隐私政策」入口。
                //    上一级「关于 Codelumi」里已经有「隐私政策（完整版）」，
                //    简明版再挂一个等于同一个东西两个入口，纯冗余。
                //    （原 NavigationLink + settingsCard 已删，别再加回来。）

                Text("最后更新：2026-11-17")
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
        .navigationTitle("隐私政策（简明版）")
        .navigationBarTitleDisplayMode(.inline)
    }
}
// MARK: - iCloud 同步

/// 2026-11-12 实现真正同步；布局参考常见 App 的「同步状态面板」：
/// 开关 → 状态（网络 / iCloud / 同步状态 / 最近同步）→ 立即同步 → 异常通知 → 说明。
/// 借的是信息层级，不是样式——每行仍用 App 自己的 SettingsRow。
struct ICloudSyncView: View {
    @StateObject private var sync = ICloudSyncController.shared
    @State private var showHelp = false
    /// 非 Pro 试图打开同步时弹订阅页（2026-11-15 主人：iCloud 同步并入 Pro）
    @State private var showPaywall = false

    private var isPro: Bool { EntitlementSnapshot.licensedPro }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                syncToggleCard
                helpLink
                statusCard
                actionCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHelp) {
            NavigationStack { ICloudSyncHelpView() }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { FullVersionView() }
                .modifier(PaywallSheetSizing())
        }
        // 截图/验真脚手架（仅调试）：`SYNC_TOGGLE=1` 模拟用户把开关拨到「开」，
        // 走的是与手指点击**同一个** setter，用来验收「非 Pro 弹订阅页」。
        .onAppear {
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["SYNC_TOGGLE"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { setSyncEnabled(true) }
            }
            if env["PAYWALL_DEMO"] == "1" { showPaywall = true }
            #endif
        }
    }

    /// 开关的唯一入口（手指点击与脚手架都走这里）。
    ///
    /// 🔴 2026-11-15 主人：iCloud 同步并入 Codelumi Pro —— 订阅页弹在**这个开关**上，
    ///    不是设置首页那一行（点标题照常进本页）。界面上不加锁形标记。
    private func setSyncEnabled(_ newValue: Bool) {
        if newValue, !isPro {
            showPaywall = true
            return
        }
        sync.setEnabled(newValue)
    }

    private var syncToggleCard: some View {
        Toggle(isOn: Binding(get: { sync.isEnabled },
                             set: { setSyncEnabled($0) })) {
            Text("开启同步")
                .font(AppTheme.TypeScale.rowTitle)
        }
        .tint(AppTheme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .settingsCard()
    }

    private var helpLink: some View {
        Button {
            showHelp = true
        } label: {
            HStack(spacing: 4) {
                Text("点此查看 iCloud 同步说明")
                Image(systemName: "arrow.right")
            }
            .font(AppTheme.TypeScale.rowSubtitle)
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private var statusCard: some View {
        VStack(spacing: 0) {
            SettingsRow(symbol: "wifi",
                        title: "网络",
                        detail: sync.networkAvailable ? "正常" : "无网络",
                        showsChevron: false,
                        tint: AppTheme.sky)
            SettingsDivider()
            SettingsRow(symbol: "icloud.fill",
                        title: "iCloud",
                        detail: sync.isAvailable ? "已连接" : "未启用",
                        showsChevron: false,
                        tint: AppTheme.accent)
            SettingsDivider()
            SettingsRow(symbol: "arrow.triangle.2.circlepath",
                        title: "同步状态",
                        detail: sync.isSyncing ? "正在同步…" : sync.statusSummary,
                        showsChevron: false,
                        tint: AppTheme.doneTint,
                        trailing: sync.isSyncing
                            ? AnyView(ProgressView().controlSize(.small))
                            : nil)
            SettingsDivider()
            SettingsRow(symbol: "clock",
                        title: "最近同步",
                        detail: sync.lastSyncedDescription,
                        showsChevron: false,
                        tint: AppTheme.indigo)
        }
        .settingsCard()
    }

    private var actionCard: some View {
        Button {
            sync.syncNow()
        } label: {
            SettingsRow(symbol: "arrow.clockwise",
                        title: sync.isSyncing ? "正在同步…" : "立即同步",
                        detail: sync.isEnabled ? "" : "先打开上面的开关",
                        showsChevron: false,
                        tint: AppTheme.accent,
                        trailing: sync.isSyncing
                            ? AnyView(ProgressView().controlSize(.small))
                            : nil)
        }
        .buttonStyle(.plain)
        .disabled(!sync.isEnabled || sync.isSyncing)
        .opacity(sync.isEnabled ? 1 : 0.5)
        .settingsCard()
        .animation(AppMotion.standard, value: sync.isSyncing)
    }

}

/// iCloud 同步说明：先讲前提，再讲开关与效果（参考同类 App 的同步教程结构）。
struct ICloudSyncHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("1", "两台设备登录同一个 Apple ID"),
        ("2", "设置 › Apple ID › iCloud › iCloud 云盘 打开"),
        ("3", "同一页的「使用 iCloud 的 App」里确认有 Codelumi"),
        ("4", "回到本页打开「开启同步」，两台设备各打开一次 Codelumi"),
        ("5", "之后任意一台改动，另一台启动或回到前台时自动合并")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("同步怎么工作")
                    .font(AppTheme.TypeScale.section)
                    .foregroundStyle(.secondary)

                ForEach(steps, id: \.0) { number, text in
                    HStack(alignment: .top, spacing: 12) {
                        Text(number)
                            .font(AppTheme.TypeScale.badge.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 20, height: 20)
                            .background(AppTheme.accent.opacity(0.12), in: Circle())
                        Text(text)
                            .font(AppTheme.TypeScale.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("冲突怎么处理")
                    .font(AppTheme.TypeScale.section)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                // 🔴 2026-11-22 主人：去重。原句把「后改的赢」说了两遍，
                //    并附送一句「关掉开关记录不少」—— 关掉开关不删数据是常识。
                Text("同一件在两台设备上都改过，以后改的为准。")
                    .font(AppTheme.TypeScale.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("iCloud 同步说明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}
