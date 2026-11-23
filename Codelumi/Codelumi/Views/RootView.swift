import SwiftUI
import UIKit

/// 布局开关（2026-11-14 主人）：「iPad 全部页面用原生组件，别只在统计页用」。
/// 结论：宽屏不再走 `NavigationSplitView`（顶部浮动标签栏下侧栏会被折叠、按钮丢失，
/// 且分栏 detail 里的 push 不落地），三个标签页统一走「单栈 + 系统导航栏」。
enum PadLayout {
    /// iPad（仅 iOS 26+）用系统分栏：HIG 明确 iPadOS 的标签栏在顶部、
    /// 可与侧栏共存；分栏是 iPad 上的原生信息结构，单列只是退路。
    /// iPad + iOS 26 起才算「iPad 原生形态」；iPhone / Duo 外屏不受影响。
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && {
            if #available(iOS 26.0, *) { return true }
            return false
        }()
    }

    /// 当前窗口尺寸。iOS 17+ 不再用 `UIScreen.main`：多窗口 / 投屏时它会取错，
    /// 而 Duo 折叠展开恰好就是要跟着窗口变。
    ///
    /// 🔴 2026-11-17 加缓存：这个方法会被**每一行卡片**间接触发
    ///    （`row(for:)` 里判断 `PadLayout.usesSplit`），50 行就是 50 次
    ///    `connectedScenes → windows → first(isKeyWindow)` 遍历。
    ///    100ms 的窗口足够覆盖「一次 body + 它的整轮行构建」，又短到
    ///    Duo 折叠后下一帧就会重新取值。
    private static var sizeCache: (size: CGSize, at: CFAbsoluteTime)?

    private static var windowSize: CGSize {
        let now = CFAbsoluteTimeGetCurrent()
        if let cache = sizeCache, now - cache.at < 0.1 { return cache.size }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        let size = window?.bounds.size ?? .zero
        sizeCache = (size, now)
        return size
    }

    /// iPhone Duo **展开态（内屏）且横屏**。
    ///
    /// 🔴 实测（2026-11-15，Duo 模拟器内屏）：
    /// ```
    ///   window.bounds = 951 × 669   ← 内屏横向，宽高按方向颠倒
    ///   UIScreen.main = 466 × 678   ← 报的是外屏，别用！
    /// ```
    /// 所以判据用**最短边**，与方向无关：
    /// ```
    ///   Duo 内屏   951 × 669  → 最短边 669 > 600 ✅
    ///   Duo 外屏   678 × 466  → 466 ✗
    ///   直板机     874 × 402  → 402 ✗（横屏也是 402）
    /// ```
    /// 没有公开的「是否折叠」API，Apple 只用尺寸与 size class 表达（2026-11-01 结论）。
    ///
    /// 🔴 2026-11-16 主人：「Duo 竖屏的时候单列显示，不要分列」。所以额外要求**横屏**才分栏：
    ///    竖屏内屏是 669 × 951（宽 < 高），分两栏每栏只剩 330pt，卡片挤成一团。
    static var isExpandedFoldable: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        // 截图/验真脚手架：本机没有 Simulator GUI（`open -a Simulator` 找不到、
        // System Events 被拒 -10004），命令行**无法旋转**设备，所以横屏分栏
        // 只能靠强制走分栏在竖屏内屏上取证（宽度 762 足够触发 splitMinWidth）。
        // ⚠️ 只用于取证「左列 UI 是否正常」，不能替代真实横屏：
        //    762×1080 下 NavigationSplitView 会自己把左列折叠成 detailOnly。
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_SPLIT"] == "1" { return true }
        #endif
        let size = windowSize
        guard size != .zero else { return false }
        return min(size.width, size.height) > 600 && size.width > size.height
    }

    /// 是否**允许**分栏（设备级门槛）：iPad 与 Duo 内屏都算。
    /// 真正是否分栏还要再看 `splitMinWidth` 与可用宽度 —— 见各页的 `paneWidth` 判断。
    static var usesSplit: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad {
            if #available(iOS 26.0, *) { return true }
            return false
        }
        // 🔴 2026-11-15 主人：Duo 内屏要分栏（左列表 / 右详情、设置左标题右页面）。
        //    之前这里写死 `idiom == .pad`，Duo 展开态被当成直板机走单列。
        return isExpandedFoldable
    }

    /// 分栏所需的最小可用宽度。
    /// · iPad mini 竖屏 744pt 不分栏 —— 两栏硬塞会把详情挤到屏幕外（2026-11-14 结论）；
    /// · Duo 内屏展开后内容区约 585pt（右侧竖排标签栏吃掉 84pt），阈值必须低于它。
    static var splitMinWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 900 : 520
    }

    /// 分栏左列宽度。
    /// · iPad 维持 440；
    /// · 🔴 iPhone Duo 内屏用 **466pt** —— 主人 2026-11-15：「左侧卡片区域宽度做成和外屏一样」。
    ///   Duo 外屏实测就是 466pt，这样左列的卡片尺寸与折叠状态下完全一致，切换姿势不会跳。
    static var splitColumnIdeal: CGFloat {
        isPad ? 440 : 466
    }
}

/// 应用根视图：**系统原生 `TabView` + 原生 Liquid Glass 标签栏**。
///
/// 🔴 **2026-10-14 信息架构定稿（主人）**：删除票夹功能，四个标签 =
///   **待取**（待取件列表）/ **已取**（取件回执库）/ **统计**（取件数据分析）/ **设置**。
/// 原「我的」面板重构进「设置」（见 ProfileView.swift 的 `SettingsView`），
/// 顶栏头像入口退役；VIP/会员体系整体退役，全功能开放。
///
/// 标签栏显隐沿用 `TabBarCloak`（原生 tabBar 视图本体 + 自驱动弹簧动画）：
/// 设置分支的二级页出现收起、转场开始即滑回，计数制保证嵌套 push/pop 不闪。
struct RootView: View {
    @StateObject private var model = RootTabModel()

    /// 分享面板的全局呈现状态（2026-10-25）：面板放在 TabView **外层**的 ZStack 里，
    /// 而不是页面级 cover —— 否则 Duo 右侧 84pt 标签栏、底部 34pt 安全区会被重新引入，
    /// 面板宽度和按钮位置都控不住（详见 `SharePresenter` 的注释）。
    @StateObject private var share = SharePresenter.shared

    /// 通知点击带来的记录 id（2026-10-25）：只负责**切到正确的标签**，
    /// 具体 push 详情由列表页自己消费（见 `NotificationRouter`）。
    @StateObject private var notificationRouter = NotificationRouter.shared

    /// 🔴 2026-11-12 主人：iPad 底部标签栏要**系统原生的液态玻璃**，不要自绘材质。
    /// 实测 iPadOS 18…27 的原生 `TabView` 标签栏都在**顶部**，`defaultTabBarPlacement(.tabBar)`
    /// （iOS 27）也挪不到底部 —— 系统没给这个能力。所以 iPad 走「内容 + `appGlass` 栏」：
    /// 玻璃由系统 `glassEffect`（iOS 26+）或系统 `.ultraThinMaterial`（低版本）绘制，
    /// 我们只排按钮。iPhone / Duo 外屏继续用原生 `TabView`。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var usesPadTabBar: Bool { horizontalSizeClass == .regular }

    /// 底部菜单栏是否显示「统计」（外观与个性化里可关）。
    @AppStorage(TabBarPrefs.showsStatsKey,
                store: PickupStorage.groupStore)
    private var showsStatsPreference = true

    /// 生效值；Debug 下可用 `ALLUDE_TAB_SHOWS_STATS=0` 强制关掉，方便截图验收。
    ///
    /// 🔴 2026-11-15：这项已是 **Codelumi Pro** 功能，非 Pro 一律显示统计页。
    ///    否则「Pro 期间关掉统计 → 订阅过期」会留下一个**没有任何入口**的统计页，
    ///    而设置里那个开关在非 Pro 下恒显示为"开" —— 两边自相矛盾。
    private var showsStats: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ALLUDE_TAB_SHOWS_STATS"] == "0" { return false }
        #endif
        guard EntitlementSnapshot.licensedPro else { return true }
        return showsStatsPreference
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                tabLayout

                // iPad 底部标签栏：浮在内容之上，材质交给系统玻璃（下面有内容才看得出折射）
                if PadLayout.isPad {
                    // 真液态玻璃：放进 GlassEffectContainer，让系统参与取样与合成
                    PadBottomBarGlassHost(selection: $model.selection, showsStats: showsStats)
                        .padding(.bottom, 18)
                        .ignoresSafeArea(edges: .bottom)
                }
            }

            // ── 分享面板（全屏浮动，盖住标签栏） ──
            if let records = share.records {
                SharePreviewSheet(records: records)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(\.suppressTabBarCloak, PadLayout.isPad)
        .animation(AppMotion.panel, value: share.records?.first?.id)
        // 🔴 **Pro 到期是一条纯时间事件**（2026-11-15 主人：到期后自动恢复非 Pro）。
        //    没有任何通知、没有任何数据变化会触发重算 —— 用户开着 App 跨过到期时间，
        //    界面就会一直显示「已开通」。这里每分钟对一次表：只在档位**真的变了**时
        //    才刷新并收敛实时活动，平时只是一次静态比较，代价可忽略。
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                let store = PickupStore.shared
                guard store.isPro != EntitlementSnapshot.licensedPro else { continue }
                store.refreshEntitlement()
                // 降级后这张卡必须当场收掉（第 2 道门用的是 licensedPro）
                PickupActivityController.sync(pending: store.pending)
                // iCloud 同步 2026-11-15 起也是 Pro 功能：到期后自动关掉，
                // 记录留在各设备本机，不会继续往 iCloud 写。
                ICloudSyncController.shared.disableIfNotPro()
            }
        }
        // 通知点击 → 切到这条记录所在的标签（待取 / 已取），
        // 具体打开详情由列表页消费同一个 `pendingRecordID`（2026-10-25）
        // 没有具体记录的通知（每日提醒等）被点击 → 至少切回待取
        // 关掉「统计」时如果正停在统计页，回到待取（否则会停在一个没有入口的页）
        .onChange(of: showsStatsPreference) { _, on in
            if !on, model.selection == .stats { model.selection = .pending }
        }
        .onChange(of: notificationRouter.shouldShowPendingTab) { _, show in
            guard show else { return }
            model.selection = .pending
        }
        .onChange(of: notificationRouter.pendingRecordID) { _, id in
            guard let id,
                  let record = PickupStore.shared.records.first(where: { $0.id == id })
            else { return }
            model.selection = record.isPickedUp ? .picked : .pending
        }
        .onAppear {
            #if DEBUG
            // 截图脚手架：`SIMCTL_CHILD_TAB=pending|picked|stats|settings`
            if let raw = ProcessInfo.processInfo.environment["TAB"] {
                switch raw {
                case "pending": model.selection = .pending
                case "picked": model.selection = .picked
                case "stats": model.selection = .stats
                case "settings": model.selection = .settings
                default: break
                }
            }
            // 性能取样：`AUTO_TAB=1` 每 1.2 秒循环切一次标签，配合 xctrace
            // 采样「切标签卡顿」的热点。只在 DEBUG 生效，正式包没有这段。
            if ProcessInfo.processInfo.environment["AUTO_TAB"] == "1" {
                Task { @MainActor in
                    let order: [RootTab] = [.pending, .picked, .stats, .settings]
                    var index = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        index = (index + 1) % order.count
                        FrameMonitor.currentTag = order[index].rawValue
                        model.selection = order[index]
                        print("[perf] tab=\(order[index].rawValue)")
                    }
                }
            }
            #endif
            // 记录"当前是不是 Duo 折叠态外屏"给小组件进程用（灵动岛由它渲染）
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) {
                DuoOuterDisplay.refresh(windowHeight: window.bounds.height)
            }

            // 冷启动场景：delegate 在视图起来之前就写好了 id，这里补切一次
            if let id = notificationRouter.pendingRecordID,
               let record = PickupStore.shared.records.first(where: { $0.id == id }) {
                model.selection = record.isPickedUp ? .picked : .pending
            }
        }
        // 首次启动的两级全屏：**先法律同意，再安装引导**。
        //
        // 🔴 2026-11-21 修（主人实测「点同意并继续没进下一级」）：
        //    原来是**两个** `fullScreenCover` 分别盯 `showConsent` / `showOnboarding`，
        //    `acceptConsent()` 在同一个更新周期里关前者、开后者 —— 两个呈现槽互相抢，
        //    结果是日志里 `[consent] accepted` 一直写、页面却退不出去。改成
        //    `onDismiss` 接力也不行：待取页 `.onAppear` 会弹系统通知授权，
        //    那个弹窗又把引导页的呈现顶掉。
        //    现在收成**一条呈现通道 + 阶段状态**（`launchStage`）：同意页和引导页
        //    共用同一个 cover，同意时只切阶段、不关不重开，彻底没有抢占位这回事。
        .fullScreenCover(isPresented: $model.showLaunchGate) {
            LaunchGateView(model: model)
        }
        // 首启流程刚走完、待取页真正露出来的这一刻才问通知授权。
        // （待取页 `.onAppear` 里那条请求在首启门开着时会被 `isLaunchGateActive` 拦下。）
        .onChange(of: model.launchStage) { _, stage in
            guard stage == nil else { return }
            guard ProcessInfo.processInfo.environment["SKIP_PERM"] == nil else { return }
            // 等 cover 收起动画走完再弹，否则系统弹窗会顶掉收起动作
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                PickupNotifier.requestAuthorizationIfNeeded()
            }
        }
    }

    /// 全平台同一个原生 `TabView`：
    /// · iPhone / Duo 外屏（compact）：原生底部标签栏，与以前完全一致；
    /// · iPad（regular）：走 iOS 18 的 `sidebarAdaptable` —— 系统自己决定
    ///   「侧边栏 / 顶部栏」形态（2026-11-13 主人定：放顶部，用系统方案，不自绘）。
    private var tabLayout: some View {
        TabView(selection: $model.selection) {
            PickupListView()
                .modifier(PadTabChrome(enabled: PadLayout.isPad))
                .tabItem { Label("待取", systemImage: "tray.fill") }
                .tag(RootTab.pending)

            PickedUpView()
                .modifier(PadTabChrome(enabled: PadLayout.isPad))
                .tabItem { Label("已取", systemImage: "checkmark.circle.fill") }
                .tag(RootTab.picked)

            if showsStats {
                StatsTabView()
                .modifier(PadTabChrome(enabled: PadLayout.isPad))
                    .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
                    .tag(RootTab.stats)
            }

            SettingsTabRoot()
                .modifier(PadTabChrome(enabled: PadLayout.isPad))
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(RootTab.settings)
        }
        // 标签栏**固定显示**，不随滚动收缩（2026-10-27 主人定）。
        // iOS 26 默认行为是 `onScrollDown` —— 列表往下滚时标签栏会缩成
        // 一小条胶囊、上滑再展开。主人要求常驻，所以显式设为 `.never`。
        // ⚠️ 别改回 `.automatic`：那等同于跟系统默认走，又会收起。
        // 注意这与下方 `TabBarCloak`（进设置二级页时**故意**收起）是两件事：
        // 那条是有意的导航语义，不受这里影响。
        // `.tabBarMinimizeBehavior` 是 iOS 26 新增；低版本没有这个行为，直接跳过。
        .modifier(TabBarMinimizeNever())
        // 🔴 2026-11-23（老大：「关掉显示统计，得退出 App 再进来标签才消失」）：
        //    `TabView` 里用 `if showsStats { ... }` 增删标签页，系统**不会**重建标签栏 ——
        //    它把首次装配时的那组 tabItem 记住了。改值只让内容变，底部那排不动。
        //    用 `.id(showsStats)` 把整棵子树换掉，才是"立刻就少一个标签"。
        //    代价：切换时各页滚动位置重置 —— 相比"必须重启 App"这点代价可以接受。
        .id(showsStats)
        .tint(AppTheme.accent)
        // 装配后接管系统 tabBar 引用（见 `TabBarCloak`），供显隐动画驱动。
        .background(NativeTabBarBridge())
        // 🔴 2026-11-15：整个窗口铺浅灰。iOS 26 的导航栏是玻璃材质，**取样背后的内容**；
        //    窗口默认是白，所以分栏左列顶部总有一条白。铺灰之后取样到灰，白块消失。
        .background(AppTheme.pageBackground.ignoresSafeArea())
        // 🔴 2026-11-14 主人定：iPad 要**底部标签栏**，
        // 不要系统顶部栏、也不要侧边栏。iPad 上把系统标签栏藏掉，自己画一条；
        // iPhone / Duo 外屏仍然用系统原生标签栏。

        // iPad 交给系统自适应（宽屏 = 侧边/顶部栏）；iPhone 保持原生底部栏。
        .modifier(AdaptiveTabBarStyle(enabled: false))
    }
}

// MARK: - 自适应标签栏样式

/// iPad（宽屏）用 iOS 18 起的 `sidebarAdaptable`：系统按宽度给侧边栏或顶部标签栏。
/// iPhone / 紧凑宽度不加这个修饰，保持原生底部标签栏（含最小化行为）。
/// iPad：藏掉系统标签栏（我们要底部自绘那条）。
/// `.toolbar(.hidden, for: .tabBar)` 是 iOS 16 起的 API，低版本无副作用。
private struct PadTabChrome: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            // 藏系统标签栏 + 给自绘那条留出高度（否则列表/详情滚到底会钻到栏下面）
            content
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 76)
                }
        } else {
            content
        }
    }
}

/// iPad：底部标签栏（自绘，玻璃交给 `appGlass`）。用 `safeAreaInset` 占位，
/// 内容不会被压住；iPhone / Duo 外屏不加（走系统原生标签栏）。
private struct PadBottomBarInset: ViewModifier {
    var enabled: Bool
    @Binding var selection: RootTab
    var showsStats: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                PadBottomBar(selection: $selection, showsStats: showsStats)
            }
        } else {
            content
        }
    }
}

/// iPad 底部标签栏：一枚胶囊 + 四项，选中态是浅色胶囊底。
private struct PadBottomBar: View {
    @Binding var selection: RootTab
    var showsStats: Bool

    private var items: [RootTab] {
        showsStats ? [.pending, .picked, .stats, .settings] : [.pending, .picked, .settings]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon(tab))
                            .font(.system(size: 17, weight: .semibold))
                        Text(title(tab))
                            .font(AppTheme.TypeScale.badge)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selection == tab {
                            Capsule().fill(AppTheme.accent.opacity(0.14))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? AppTheme.accent : Color.secondary)
                .accessibilityLabel(Text(title(tab)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .appGlass(.capsule, interactive: true)
        .frame(maxWidth: .infinity)
    }

    private func title(_ tab: RootTab) -> String {
        switch tab {
        case .pending: return "待取"
        case .picked: return "已取"
        case .stats: return "统计"
        case .settings: return "设置"
        }
    }

    private func icon(_ tab: RootTab) -> String {
        switch tab {
        case .pending: return "tray.fill"
        case .picked: return "checkmark.circle.fill"
        case .stats: return "chart.bar.xaxis"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct AdaptiveTabBarStyle: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 18.0, *) {
                content.tabViewStyle(.sidebarAdaptable)
            } else {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - 底部菜单栏偏好

/// 底部菜单栏里「统计」是否显示。放 App Group，设置页与主界面共用一份。
enum TabBarPrefs {
    static let showsStatsKey = "codelumi.tabBar.showsStats"
}

// MARK: - 当前标签

enum RootTab: String, Hashable {
    case pending    // 待取
    case picked     // 已取
    case stats      // 统计
    case settings   // 设置
}

final class RootTabModel: ObservableObject {
    @Published var selection: RootTab

    /// 首启流程走到哪一步。`nil` = 已经走完，正常进 App。
    ///
    /// 2026-11-21 起把原来的 `showConsent` / `showOnboarding` 两个布尔合成这一个 ——
    /// 两个 `fullScreenCover` 抢同一个呈现槽会把引导页丢掉（见 body 里的注释）。
    enum LaunchStage {
        case consent
        case onboarding
    }

    /// 首启两级全屏是否还盖在最上面。
    ///
    /// 🔴 2026-11-21：待取页一出现就会问通知授权，而系统授权弹窗会**盖住引导页**
    ///    （用户在首启流程里第一眼看到的是权限弹窗，不是欢迎页）。
    ///    所以首启门还开着时先不问，等门关了再由 RootView 统一问一次。
    static var isLaunchGateActive = false

    @Published var launchStage: LaunchStage?

    /// 首启门是否还在（供 `.fullScreenCover(isPresented:)` 用）。
    var showLaunchGate: Bool {
        get { launchStage != nil }
        set {
            guard !newValue else { return }
            launchStage = nil
            RootTabModel.isLaunchGateActive = false
        }
    }

    private static let onboardingKey = "onboarding.completed.v1"
    private static let consentKey = "legal.consent.v1"

    init() {
        // ① 先把没有默认值的存储属性（selection）定下来 —— 否则后面读 launchStage
        //    会报 "'self' used before all stored properties are initialized"。
        //
        // 截图脚手架：`SIMCTL_CHILD_TAB=pending|picked|stats|settings` 直接落到目标页
        // （simctl 没有触摸注入通道，点不了底部标签栏）。旧值兼容映射：
        // ticket→picked（票夹已删，2026-10-14）、browse→stats。
        let raw = ProcessInfo.processInfo.environment["TAB"] ?? ""
        switch raw {
        case "picked", "ticket": selection = .picked
        case "stats", "browse":  selection = .stats
        case "settings":         selection = .settings
        default:                 selection = .pending
        }

        // ② 首启门控：截图脚手架统一跳过（SKIP_ONBOARDING=1）
        let skipping = ProcessInfo.processInfo.environment["SKIP_ONBOARDING"] != nil

        // 顺序很重要：**先同意条款，再看引导**。
        let consented = UserDefaults.standard.bool(forKey: Self.consentKey)
        let onboarded = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        if skipping {
            launchStage = nil
        } else if !consented {
            launchStage = .consent
        } else if !onboarded {
            launchStage = .onboarding
        } else {
            launchStage = nil
        }

        DiagnosticsLog.record("gate", "init skipping=\(skipping) consented=\(consented) onboarded=\(onboarded) stage=\(String(describing: launchStage))")
        RootTabModel.isLaunchGateActive = launchStage != nil
    }

    /// 同意条款：写标记，然后把同一个 cover 的内容换成引导页。
    ///
    /// 🔴 **不要再拆回两个 `fullScreenCover`**，也不要在外面用 `onDismiss` 接力 ——
    ///    两条路都踩过（页面退不出去 / 引导页被系统通知授权弹窗顶掉）。
    func acceptConsent() {
        UserDefaults.standard.set(true, forKey: Self.consentKey)
        let onboarded = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        DiagnosticsLog.record("gate", "acceptConsent onboarded=\(onboarded)")
        launchStage = onboarded ? nil : .onboarding
        RootTabModel.isLaunchGateActive = launchStage != nil
    }

    /// 引导完成：写标记 + 收起。
    func completeOnboarding() {
        DiagnosticsLog.record("gate", "completeOnboarding")
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        launchStage = nil
        RootTabModel.isLaunchGateActive = false
    }
}

// MARK: - 首次启动的两级全屏（同意 → 引导）

/// 首启流程的**唯一呈现者**。
///
/// 同意页与引导页必须共用同一个 `fullScreenCover`：分两个 cover 时，
/// 「关一个、开另一个」会在同一个更新周期里抢呈现槽 —— 表现是点「同意并继续」
/// 页面退不出去（2026-11-21 主人实测）。用 `onDismiss` 接力也不行，
/// 主界面 `.onAppear` 的系统通知授权弹窗会把后一个 cover 顶掉。
/// 这里只切内容、不关不重开，两页之间也顺带做到无闪烁。
private struct LaunchGateView: View {
    @ObservedObject var model: RootTabModel

    var body: some View {
        switch model.launchStage {
        case .consent:
            LegalConsentView { model.acceptConsent() }
        case .onboarding:
            OnboardingView { model.completeOnboarding() }
        case nil:
            // 走到这里说明刚刚收起，SwiftUI 会在下一帧把 cover 关掉。
            Color.clear
        }
    }
}

// MARK: - 首次安装引导（三页，放本文件避免增删工程文件引用）
//
/// 三页横滑引导：① 欢迎（这是什么）② 自动化（怎么自动收码）③ 完成。
/// 「设置 › 使用教程」是合并后的完整教程页（见 UsageGuideView.swift），
/// 本引导只做首启三页速览，不再提供回放入口。
struct OnboardingView: View {
    /// 完成回调（首启模式必传）。
    var onFinish: (() -> Void)? = nil

    // 宏规避：页码收进 ObservableObject（与全工程口径一致）
    @StateObject private var state = OnboardingPageState()

    // 首启页里的「导入自动化」用的分享面板

    var body: some View {
        // 保留 NavigationStack：引导住在 fullScreenCover 里（独立表现上下文），
        // 现在第 2 页已经没有内页跳转了（「查看完整使用教程」入口已按主人要求删除），
        // 但分享面板与后续可能的二级页仍依赖这层栈，去掉会多一次回归风险。
        NavigationStack {
            TabView(selection: $state.page) {
                welcomePage.tag(0)
                automationPage.tag(1)
                finishPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .background(AppTheme.pageBackground)
        .onAppear {
            // 截图脚手架：ONBOARDING_PAGE=0/1/2 直接落到某一页
            if let raw = ProcessInfo.processInfo.environment["ONBOARDING_PAGE"],
               let page = Int(raw), (0...2).contains(page) {
                state.page = page
            }
            // 截图脚手架：AUTO_FINISH_ONBOARDING=1 自动点「开始使用」，
            // 用来把「首启 → 待取页 → 通知授权」这条链路一次跑完（simctl 点不了屏幕）。
            if BuildFlags.scaffoldsEnabled,
               ProcessInfo.processInfo.environment["AUTO_FINISH_ONBOARDING"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onFinish?() }
            }
        }
    }

    // MARK: ① 欢迎

    private var welcomePage: some View {
        OnboardingPage(
            symbol: "tray.full.fill",
            tint: AppTheme.accent,
            title: "欢迎使用Codelumi",
            subtitle: "快递取件码自动收集，到驿站打开就能报码")
        {
            OnboardingPoint(symbol: "bubble.left.and.text.bubble.right.fill",
                            tint: AppTheme.accent,
                            title: "自动收码",
                            detail: "配合快捷指令，快递短信一到取件码自动入库")
            // 🔴 2026-11-08 主人：重点是**小组件实时更新**，以及灵动岛/锁屏的实时活动，
            //    不要只写「灵动岛常显」——那只是其中一个入口。
            OnboardingPoint(symbol: "rectangle.grid.2x2.fill",
                            tint: AppTheme.violet,
                            title: "小组件与实时活动",
                            detail: "待取码在桌面小组件实时更新，也常驻灵动岛与锁屏卡片")
            OnboardingPoint(symbol: "hand.raised.fill",
                            tint: AppTheme.doneTint,
                            title: "只在本机",
                            detail: "无账号、无联网，取件数据不出这台手机")
        }
    }

    // MARK: ② 自动化

    private var automationPage: some View {
        OnboardingPage(
            symbol: "bolt.badge.automatic.fill",
            tint: AppTheme.amber,
            title: "开启快捷指令自动化",
            subtitle: "一次配置，之后每一单都自动进来")
        {
            VStack(spacing: 0) {
                OnboardingStep(index: 1, tint: AppTheme.amber,
                               title: "导入自动化",
                               detail: quickImportAvailable
                                   ? "点下面的按钮，把「收到短信 → 添加到Codelumi」导进系统"
                                   : "当前系统不支持一键导入：到「设置 › 快捷指令」看 35 秒视频教程，照着建一次")
                SettingsDivider()
                OnboardingStep(index: 2, tint: AppTheme.amber,
                               title: "打开开关",
                               detail: "快捷指令 › 自动化 里找到它，把开关打开（导入后默认关）")
                SettingsDivider()
                OnboardingStep(index: 3, tint: AppTheme.amber,
                               title: "完成",
                               detail: "之后收到取件短信，列表自动出现新记录")
            }
            .settingsCard()

        }
    }

    // MARK: ③ 完成

    private var finishPage: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 8) {
                Text("一切就绪")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("所有功能已开放，数据只在本机。\n到驿站时打开Codelumi，报码就走。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    /// 一键导入自动化（分享 .shortcut → 快捷指令）只在 iOS 27 及以上可用。
    /// iOS 26 及更早的系统不支持把带触发器/App Intent 的自动化直接导入，
    /// 只能让用户照教程手动新建一条（2026-11-11 主人定）。
    private var quickImportAvailable: Bool {
        // 截图/验收脚手架：本机只有 iOS 27 运行时，用 FORCE_MANUAL_SHORTCUT=1
        // 模拟 iOS 26 及更早（Release 不含脚手架）。
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_MANUAL_SHORTCUT"] != nil { return false }
        #endif
        if #available(iOS 27.0, *) { return true } else { return false }
    }

    // MARK: 底栏

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // 自动化页底栏：iOS 27+ 给一键导入按钮；以下只给一段文字指路。
            if state.page == 1 {
                if quickImportAvailable {
                    Button {
                        // 🔴 2026-11-11 内测反馈修复：分享面板直接挂到最上层控制器，
                        //    不再塞进 SwiftUI 的 .sheet（那样在 fullScreenCover 里是空白面板）。
                        guard let preset = ShortcutAutomation.presets.first,
                              let url = ShortcutAutomation.preparedImportURL(for: preset) else { return }
                        ShortcutAutomation.markImported(preset.keyword)
                        ShareSheetPresenter.present([url])
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("一键导入自动化（关键词：【）")
                        }
                        .font(AppTheme.TypeScale.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .appGlass(.capsule, tint: AppTheme.amber, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)
                } else {
                    // 🔴 2026-11-15 主人：iOS 27 以下**只留文字引导**，
                    //    并且要明确告诉用户去哪里看视频 —— 不再给「查看完整使用教程」按钮
                    //    （那条路径在低版本上纯文字堆砌，不如直接看 35 秒视频）。
                    Text("这台设备不支持一键导入自动化。请打开「设置 › 快捷指令」，那里有一段 35 秒的视频教程，照着新建一条即可。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                }
            }

            // 🔴 2026-11-15 主人：引导页**不要**「查看完整使用教程」这个入口了
            //    （截图圈掉了）。iOS 27+ 只留一键导入；低版本只留文字指路，
            //    文字里已经写明去「设置 › 快捷指令」看视频。

            Button {
                if state.page < 2 {
                    withAnimation(.snappy) { state.page += 1 }
                } else {
                    onFinish?()
                }
            } label: {
                Text(state.page < 2 ? "下一步" : "开始使用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.accent, in: .capsule)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)

            if state.page == 0 {
                Button("跳过") {
                    onFinish?()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 24)
    }
}

/// 引导页骨架：图标 + 标题 + 副标题 + 要点列表。
private struct OnboardingPage<Points: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder let points: Points

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 104, height: 104)
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(spacing: 8) {
                Text(title.L)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle.L)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            VStack(spacing: 14) {
                points
            }
            .padding(.top, 30)

            Spacer(minLength: 30)
        }
        .padding(.horizontal, 28)
        // 页面圆点由 TabView 画在底部，内容要给它让位，否则会压住「一键导入」按钮
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 引导步骤行：数字徽标 + 标题 + 说明（放在同一张卡里，用分隔线分开）。
private struct OnboardingStep: View {
    let index: Int
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(index).circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.L)
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Text(detail.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

/// 引导要点行：彩色图标 + 标题 + 说明。
private struct OnboardingPoint: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.L)
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Text(detail.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// 引导页码状态（宏规避口径，与全工程一致）。
final class OnboardingPageState: ObservableObject {
    @Published var page = 0
}

// MARK: - 原生标签栏显隐（TabBarCloak）

/// 「设置」分支二级页显隐的**唯一真值 + 动画驱动器**，作用对象是系统 tabBar 视图本体。
///
/// 为什么显隐还是我们自己驱动：三条系统路线全部实测被否 ——
///   ① `.toolbar(.hidden, for: .tabBar)`：pop 恢复由 UIKit 托管在转场之外，
///      转场结束才蹦出来（僵硬，否）；
///   ② `hidesBottomBarWhenPushed` 桥接：SwiftUI NavigationStack 不理会（无效，否）；
///   ③ 不收起（"原生语义"）：主人明确要求二级页必须收起（否）。
/// 剩下的自由度只有"对原生 tabBar 视图自己做动画" —— 组件原生、动画顺滑。
///
/// 计数制（嵌套 push 安全）：
///   · **cover()** = 二级页 onAppear（设置分支），计数 +1；
///   · **popSecondary()** = 二级页 onDisappear（async 下一跳），计数 −1 ——
///     pop 转场一开始就触发滑回动画，与转场并行，不再等转场结束；
///   · **reveal()** = 标签根页 onAppear，计数归零（兜底防泄漏）。
final class TabBarCloak: ObservableObject {
    static let shared = TabBarCloak()

    private var coverCount = 0
    private var isHidden = false

    /// 系统 tabBar 视图本体（原生 Liquid Glass 组件，只动 transform/alpha）。
    private(set) weak var tabBar: UITabBar?

    /// 二级页出现：收起（计数 +1，嵌套安全）。
    func cover() {
        coverCount += 1
        sync()
    }

    /// 二级页消失：解除一层（计数 −1，下限 0）。
    /// 🔴 调用方必须 `DispatchQueue.main.async` 包一层：push 更深页时
    ///    新页 onAppear 与旧页 onDisappear 顺序不定，下一跳执行让
    ///    cover 先落账，计数才不会瞬间归零造成闪烁。
    func popSecondary() {
        coverCount = max(0, coverCount - 1)
        sync()
    }

    /// 回到标签根页：露出（计数归零，兜底防泄漏）。
    func reveal() {
        coverCount = 0
        sync()
        // 兜底归位（2026-11-11 内测反馈「底部菜单栏漂移」）：
        // 动画被打断 / iOS 27 浮动标签栏被系统重新布局时，transform 可能停在
        // 半路（表现为标签栏浮在列表中间）。根页出现时无条件把位置与透明度钉回。
        guard let bar = tabBar, !isHidden else { return }
        bar.transform = .identity
        bar.alpha = 1
        bar.isUserInteractionEnabled = true
    }

    /// 从装配好的视图层级里接管 tabBar 引用（幂等，可重复调用）。
    func locate(from vc: UIViewController) {
        guard tabBar == nil else { return }
        guard let root = vc.view.window?.rootViewController else { return }
        // 先沿 VC 树找 UITabBarController（SwiftUI 内部 addChild 托管），
        // 找不到再暴力遍历视图树找 UITabBar 实例兜底。
        tabBar = Self.findTabBarController(root)?.tabBar ?? Self.findBar(in: root.view)
    }

    private static func findTabBarController(_ root: UIViewController) -> UITabBarController? {
        if let tab = root as? UITabBarController { return tab }
        for child in root.children {
            if let found = findTabBarController(child) { return found }
        }
        return nil
    }

    private static func findBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews {
            if let found = findBar(in: sub) { return found }
        }
        return nil
    }

    private func sync() {
        let hidden = coverCount > 0
        guard hidden != isHidden else { return }
        isHidden = hidden
        apply(hidden)
    }

    /// 滑出 / 滑回动画。弹簧参数对齐主人认可的顺滑手感：
    /// response 0.38 / damping 0.86 ≈ UIKit spring(duration:damping:0.38/0.86)。
    private func apply(_ hide: Bool) {
        // iOS 27 的浮动标签栏会在换页 / 滚动时被系统重新布局，旧引用可能已被摘掉：
        // 拿不到视图就先重新定位一次，否则动画落在旧对象上（表现为「没反应」）。
        if tabBar == nil || tabBar?.window == nil {
            if let root = keyWindowRootViewController() {
                tabBar = nil
                locate(from: root)
            }
        }
        guard let bar = tabBar else { return }
        bar.layer.removeAllAnimations()

        // 出屏位移：直接按窗口高度算，不依赖 superview 的坐标系 ——
        // iOS 27 浮动标签栏的容器尺寸不可靠，旧的 `superview.height - minY`
        // 会算出离谱甚至负数的位移（这是「漂移」的来源之一）。
        let distance = (bar.window?.bounds.height ?? 900) + 40

        if hide {
            UIView.animate(withDuration: 0.38,
                           delay: 0,
                           usingSpringWithDamping: 0.86,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                bar.transform = CGAffineTransform(translationX: 0, y: distance)
                bar.alpha = 0
            } completion: { _ in
                guard self.isHidden else { return }
                // 🔴 收敛终值：动画被打断 / 系统重新布局后，残留位移会把标签栏
                //    停在屏幕中间。隐藏完成后清掉 transform，只留 alpha 与不可交互。
                bar.transform = .identity
                bar.alpha = 0
                bar.isUserInteractionEnabled = false
            }
        } else {
            // 先归位再淡入，避免任何历史位移把标签栏带偏。
            bar.transform = .identity
            bar.isUserInteractionEnabled = true
            UIView.animate(withDuration: 0.38,
                           delay: 0,
                           usingSpringWithDamping: 0.86,
                           initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                bar.alpha = 1
            } completion: { _ in
                guard !self.isHidden else { return }
                bar.transform = .identity
                bar.alpha = 1
            }
        }
    }

    /// 当前 key window 的根控制器（重新定位 tabBar 用）。
    private func keyWindowRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

/// 嵌在 `RootView` 里的装配钩子：TabView 建好系统层级后把 tabBar 引用
/// 交给 `TabBarCloak`。只做接管，不做任何显示干预。
private struct NativeTabBarBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Bridge { Bridge() }
    func updateUIViewController(_ vc: Bridge, context: Context) {}

    final class Bridge: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            // SwiftUI 装配可能晚一拍：本帧没拿到就下一帧再找。
            if TabBarCloak.shared.tabBar == nil {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    TabBarCloak.shared.locate(from: self)
                    // 深层兜底：再不行等 0.5s 补一次（App 冷启动慢机型）。
                    if TabBarCloak.shared.tabBar == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            TabBarCloak.shared.locate(from: self)
                        }
                    }
                }
            }
        }
    }
}

/// 量「当前页面可用宽度」用：拿宽度但不能影响布局（GeometryReader 会吃掉安全区，
/// 2026-11-14 把 iPad 分栏包进 GeometryReader 后，标签栏直接压到详情列标题上）。
/// Pro 订阅 sheet 的尺寸（2026-11-16 主人）。
///
/// Duo 内屏（regular 宽度）上 sheet 默认铺得很宽、内容拉成一条，底部按钮还被切掉。
/// 用 `.form` 收成 iPad 那种居中的表单宽度，整页（方案卡 + 解锁清单 + 购买按钮）才看得全。
/// iOS 18 以下没有 `presentationSizing`，退回系统默认。
struct PaywallSheetSizing: ViewModifier {
    /// 🔴 必须判宽度：iPhone 直板机只有 402pt，套上 500 的 minWidth 会溢出。
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), sizeClass == .regular {
            // 先给内容一个明确宽度区间，再让 sheet 按它收紧 ——
            // 单用 `.fitted` 会缩成一条 120pt 的窄条、单用 `.form` 在 Duo 上不生效（都实测过）;
            // `minHeight` 也不能省，否则 ScrollView 的 ideal 高度会把 sheet 压成一条横条。
            // 🔴 2026-11-16 主人：「再窄一些」+「弹出的订阅页面也要完全显示」。
            //
            // 踩坑记录（都在 Duo 内屏竖屏实测）：
            //   · `.form` 在这台设备上完全无效，`.page` 会铺满整屏 —— 两者都收不窄；
            //   · `.fitted` 才是收窄的唯一手段，但它的高度上限被系统 form sheet 卡在 890pt，
            //     `minHeight` 写 1000 得 890、写 1120 还是 900，底部「恢复购买」永远差最后一条；
            //   · `fitted(horizontal:vertical:)` 是实例方法，链式能编译但高度算成 0（弹层不可见）。
            // 所以最终方案：`.fitted` 收窄到 500 + 把订阅页正文的间距/字号小幅收紧，
            // 让内容高度压进 890 上限 —— 一屏装完全部，不需要滚动。
            // ⚠️ 高度必须给 `minHeight`：只写 `.frame(width:)` 时 `.fitted` 会算成
            //    一条小横条（实测只剩标题），因为 ScrollView 没有高度约束时 ideal = 极小值。
            content
                .frame(minWidth: 420, idealWidth: 450, maxWidth: 470, minHeight: 1000)
                .presentationDetents([.large])
                .presentationSizing(.fitted)
        } else {
            content
        }
    }
}

struct CodelumiPaneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// 设置分支内**任意层级**的二级页都挂这一个修饰符：
    /// 出现时收起标签栏、离开时恢复（转场一开始就滑回，不蹦出）。
    ///
    /// 🔴 **设置分支的每个二级页（含深层）都必须挂** ——
    ///    深层页不挂的话，push 进去时上一页的 `onDisappear` 会把计数
    ///    扣回零，标签栏就滑回来了（2026-09-23 主人实测抓到）。
    ///    计数制保证「设置 → 小组件 → …」这类嵌套 push/pop 不闪。
    ///
    /// ⚠️ 宽屏分栏例外（2026-10-25 审查修）：iPad 式设置页把这些页面当成
    /// **常驻 pane** 渲染，不再是「push 进来的二级页」。那时若照常 cover，
    /// 一进设置标签栏就被滑走、用户换不了标签。分栏侧通过环境值
    /// `suppressTabBarCloak` 关掉这套显隐。
    func cloaksTabBar() -> some View {
        modifier(TabBarCloakModifier())
    }
}

/// 环境值：true 时 `cloaksTabBar()` 只挂空修饰（用于宽屏设置分栏的常驻 pane）
private struct SuppressTabBarCloakKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var suppressTabBarCloak: Bool {
        get { self[SuppressTabBarCloakKey.self] }
        set { self[SuppressTabBarCloakKey.self] = newValue }
    }
}

private struct TabBarCloakModifier: ViewModifier {
    @Environment(\.suppressTabBarCloak) private var suppressed
    /// 必须在**出现那一刻**记下当时是否被抑制，否则中途环境值变化会让
    /// onDisappear 少扣一次计数，把标签栏永久卡在收起态。
    @State private var engaged = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !suppressed else { engaged = false; return }
                engaged = true
                TabBarCloak.shared.cover()
            }
            .onDisappear {
                guard engaged else { return }
                engaged = false
                DispatchQueue.main.async { TabBarCloak.shared.popSecondary() }
            }
    }
}

// MARK: - 设置 Tab 根容器

/// 「设置」Tab 的导航栈容器（SettingsView 本体在 ProfileView.swift）。
/// 单独包一层 NavigationStack：四个标签各自持有独立栈，push/pop 互不干扰。
struct SettingsTabRoot: View {
    var body: some View {
        NavigationStack {
            SettingsView()
        }
        .modifier(PaywallSheetDemo())
    }
}

/// 截图脚手架（仅调试）：`PAYWALL_SHEET=1` 直接在当前容器里弹订阅页。
///
/// 为什么要单独开这个口子：订阅页平时挂在「外观与个性化」和「iCloud 同步」两个
/// **二级页**上，而竖屏单列时它们是 NavigationLink 驱动的，`SETTINGS_OPEN`
/// 脚手架只对分栏分支（`pane` 绑定）有效，命令行进不去那条路。
/// 这里用的 sheet 容器与两处正式入口**完全相同**（同一个 `FullVersionView` +
/// 同一个 `PaywallSheetSizing`），量出来的宽度/可见性可以直接当准。
/// 正式运行时该环境变量不存在，零影响。
private struct PaywallSheetDemo: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $shown) {
                NavigationStack { FullVersionView() }
                    .modifier(PaywallSheetSizing())
            }
            .onAppear {
                guard ProcessInfo.processInfo.environment["PAYWALL_SHEET"] == "1" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { shown = true }
            }
    }
}

/// TabView 的「常驻标签栏」行为只有 iOS 26 才有，用 modifier 收起来。
private struct TabBarMinimizeNever: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

// MARK: - iPad 底部标签栏（原生液态玻璃）

/// iPadOS 18+ 的原生标签栏在顶部、且没有公开 API 挪到底部。这里用系统
/// **Liquid Glass（iOS 26+ `glassEffect`，经 `appGlass`）**/ 系统毛玻璃（18 及以下）
/// 当背景，只负责排版四个按钮 —— 玻璃本身由系统绘制，不是自绘材质。

// MARK: - iPad 分栏侧栏的公共头（2026-11-14）

/// 分栏侧栏的大标题：与「统计」页 large title 同字号（34pt bold）。
/// 系统在 `NavigationSplitView` 的侧栏里只画 inline 标题，这里自己排一行。
struct PadSidebarHeader: View {
    var title: String
    /// 分栏侧栏的收放按钮（导航栏藏掉后要自己提供）
    var onToggleSidebar: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
            Spacer(minLength: 0)
            if let onToggleSidebar {
                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换侧栏")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// 分栏侧栏的搜索框（胶囊，与系统设置同观感）。
struct PadSidebarSearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill), in: .capsule)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }
}

/// `.searchable` 只在窄屏（单栈）启用；分栏侧栏改用 `PadSidebarSearchField`。
struct SidebarSearchable: ViewModifier {
    @Binding var text: String
    var enabled: Bool
    var prompt: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text,
                               placement: .navigationBarDrawer(displayMode: .automatic),
                               prompt: prompt)
        } else {
            content
        }
    }
}


/// iOS 26+ 把底栏放进 `GlassEffectContainer`（液态玻璃需要容器参与合成）；
/// 低版本只是普通容器，观感由 `appGlass` 的毛玻璃兜底。
private struct PadBottomBarGlassHost: View {
    @Binding var selection: RootTab
    var showsStats: Bool

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                PadBottomBar(selection: $selection, showsStats: showsStats)
            }
        } else {
            PadBottomBar(selection: $selection, showsStats: showsStats)
        }
    }
}
