import ActivityKit
import SwiftUI
import UserNotifications

@main
struct AlludeApp: App {
    /// 通知点击的 delegate 要在启动最早期就位（见 AppDelegate 注释）
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 全局唯一实例：与 App Intent（快捷指令调用）共用同一份数据
    @StateObject private var store = PickupStore.shared

    /// 用于「桌面小组件改了数据 → App 回前台时同步」这一条链路
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 🔴 2026-11-16 删掉了 `UINavigationBar.appearance()` 那套全局不透明外观。
        //
        // 它原本是 2026-11-15 为「待取左上角白块」加的，但那次真正的修复是
        // `RootView` 里给 TabView 铺 `systemGroupedBackground` 窗口底色（玻璃导航栏
        // 取样的是窗口背景，不是页面背景），这段是同时期的遗留尝试。
        //
        // 它带来的副作用：`UINavigationBarAppearance` 被整体替换后
        // `largeTitleTextAttributes` 变成空值，**大标题占位还在、文字一个都不画**。
        // 表现为 iPhone Duo 内屏竖屏时「统计 / 设置」页顶部一片空白
        // （regular 宽度才走系统大标题，外屏 compact 不受影响，所以一直没暴露）。
        // 删掉后三个状态（外屏 / 内屏横屏 / 内屏竖屏）标题全部正常，白块也没回来。

        // 命令行验证脚手架：走的是 ParsePickupTextIntent.perform() 里**同一个**
        // `PickupStore.shared.ingest`，用于在模拟器上取证「短信文本 → 解析 → 落库 →
        // 列表 / 小组件」整条链路。只在注入 SCREEN=ingest 时执行一次，正式运行零影响。
        let environment = ProcessInfo.processInfo.environment

        // 图标切换的验真脚手架（仅调试）：`ICON_TRY=Icon17` 直接在启动时切一次并打结果。
        // 为什么不走上面那段「启动对齐」：模拟器里 `CODE_SIGNING_ALLOWED=NO` 的包
        // **没有 App Group**，AppGroup 偏好读不到 → `AppIconStore.current` 回落到默认图标，
        // 那条分支根本不会触发。这里直接调系统 API，验的是「声明与文件是否齐备」。
        #if DEBUG
        if let raw = environment["ICON_TRY"] {
            print("[allude-icon] ICON_TRY=\(raw)")
            UIApplication.shared.setAlternateIconName(raw) { error in
                if let error {
                    print("[allude-icon] 失败: \(error.localizedDescription)")
                } else {
                    print("[allude-icon] 成功切换到 \(raw)，当前=\(UIApplication.shared.alternateIconName ?? "nil")")
                }
            }
        }
        #endif

        // 通知的前台抑制策略必须尽早挂上：自动化触发时 App 是被系统**静默拉起**的，
        // delegate 没就位就收不到 willPresent，前台抑制会失效。
        PickupNotificationPresenter.shared.install()

        // 实时活动要显示「快递驿站」名，而 `StationDirectory` 只在 App target ——
        // 把这个能力注入给共享层的控制器（2026-10-28）。
        // 只做一次赋值，之后控制器只读；扩展进程里没注入时恒为 nil，卡面自然降级。
        // 锁屏卡翻页用的待办来源（与 stationResolver 同一套路：共享层拿不到 Store）
        // 语言：把上次在「设置 › 语言」里的选择落到 AppleLanguages（下次启动生效）
        AppLanguageSettings.applyAtLaunch()

        // 只有主 App 进程能起 / 重建实时活动；扩展进程只 update（2026-11-16）
        PickupActivityController.isAppProcess = true
        PickupActivityController.pendingProvider = { PickupStore.shared.pending }
        // 到达提醒：启动即把定位 manager / delegate 挂起来，否则系统围栏事件
        // 把被杀的 App 拉起来时收不到（2026-11-16）
        StationLocationService.shared.bootstrap()

        // 2026-11-21：灵岛/锁屏的驿站名也走单一解析入口（自定义驿站、记录级指定的组
        // 都算进去）。以前这里直接问 StationDirectory，扩展侧规则与 App 会漂。
        PickupActivityController.stationResolver = { record in
            let r = record.stationResolution
            return r.hasStation ? r.stationName : nil
        }

        // 把自定义驿站名单补进 App Group：小组件进程读不到 App 私有的偏好域，
        // 不同步就会出现「App 里建了组、桌面显示未标注驿站」（2026-11-21）。
        StationDirectory.shared.syncCatalog()

        // 🔴 设备码必须**冷启动最早期**就把它写进 App Group（2026-09-23）。
        //
        // `LicenseDevice.current` 会「读 Keychain → 没有就生成 → 落 App Group 缓存」。
        // 这一步放在这里而不是等用户点开「解锁」页，是因为小组件扩展
        // 也在校验设备（`EntitlementSnapshot.load()`），而扩展**只读缓存、不生成**。
        // App 少写一次，扩展就读到 nil，那段时间里已购用户的小组件会按免费版渲染。
        //
        // 注意它带副作用（首次会生成并持久化），所以**不能**塞进 `body` 或任何
        // 会被反复求值的位置 —— 这里 `init()` 只走一次，是正确的位置。
        // 截图脚手架：APPEARANCE=system|light|dark、FONT_STEP=0…6 强制指定（仅调试用）
        let env = ProcessInfo.processInfo.environment
        if let mode = env["APPEARANCE"].flatMap(AppearanceMode.init(rawValue:)) {
            AppearanceSettings.shared.mode = mode
        }
        // 模拟"进二级页后再拖滑块"：延迟 3 秒改字号，用来验证不会把导航栈冲掉
        if let raw = env["FONT_STEP_LATE"], let step = Int(raw), let value = FontSizeStep(rawValue: step) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                AppearanceSettings.shared.followSystem = false
                AppearanceSettings.shared.step = value
            }
        }
        if let raw = env["FONT_STEP"], let step = Int(raw), let value = FontSizeStep(rawValue: step) {
            AppearanceSettings.shared.followSystem = false
            AppearanceSettings.shared.step = value
        }

        let deviceCode = LicenseDevice.current
        print("[allude-verify] device=\(deviceCode)")

        #if DEBUG
        // 性能探针保底冲刷：`PERF_LOG=1` 时每 2 秒把累计统计写进 Documents/perf.log，
        // 不需要任何交互也能取到数据（采样靠 simctl 读文件，不能靠 print）。
        if PerfProbe.enabled {
            Task.detached(priority: .background) {
                while true {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    PerfProbe.flush()
                }
            }
        }
        // `PERF_FPS=1`：起一个 CADisplayLink 数帧间隔，把掉帧率写进 Documents/frames.log。
        if FrameMonitor.enabled {
            DispatchQueue.main.async { FrameMonitor.shared.start() }
        }
        #endif

        // 2026-11-15 图标编号重排（带空洞的 2,3,5,…22 → 连续的 1…16）：
        // 老用户存的 rawValue 与新编号**同名不同图**，必须一次性换算，
        // 并把系统侧的备用图标同步过去 —— 否则桌面还挂着换号前那张。
        if let migrated = AppIconStore.migrateLegacyNumberingIfNeeded() {
            print("[allude-verify] appIcon=migrated->\(migrated.rawValue)")
            DispatchQueue.main.async {
                UIApplication.shared.setAlternateIconName(migrated.alternateName)
            }
        }

        // 2026-11-17 驿站组：
        // ① 先把身份登记表对齐 —— 内置 / 自定义清单一次性发号落盘（之后只追加末尾），
        //    组关系挂的是这些 ID，晚一步初始化会让刚建的组指向不存在的成员。
        // ② 再把 App 层的「清理解散产物」「重排围栏」两个动作接进共享层：
        //    `StationGroups.swift` 要给桌面小组件一起编译，不能直接引用 App target 的类型。
        _ = StationDirectory.shared
        StationGroupAppearanceBridge.cleanUp = { group in
            StationDirectory.shared.removeGroupArtifacts(group)
        }
        StationGroupLocationBridge.syncRegions = {
            StationLocationService.shared.syncRegions()
        }

        // 内购（StoreKit 2）：拉起交易监听并取商品。冷启动最早期挂上，
        // 否则「购买待批准 / 跨设备购买」这类更新要等下一次冷启才反映出来。
        PurchaseStore.shared.start()

        // 冷启动先对账一次权益。
        //
        // `load()` 会重新验签凭证 + 比对设备码，并把时间水位往前推 —— 放在这里
        // 而不是等用户翻到「VIP 模式」页，是为了让**每次冷启动都完成一次校验**：
        // 越狱用户手改 `entitlement.json` 的档位字段，只要 App 再启动一次就归位。
        // 这一行的 print 也是售后排障的第一手线索（用户说"会员突然没了"时，
        // 日志里就能看到启动当时的档位）。
        //
        // ⚠️ 2026-09-24：这条日志补上了 `hasLicense` —— 只打 `plan` 时，无法区分
        //    「由凭证背书的永久」与「无凭证的残留永久」（脚手架 PLAN= / 老数据），
        //    而这两者在「导入低档凭证能否生效」上行为完全不同（见
        //    `LicenseActivation.activate` 的 backedByLicense 判定）。售后排障时
        //    这一项是第一手判据。
        let bootEntitlement = EntitlementSnapshot.load()
        // 2026-11-01：启动时对齐"已存的选择"与"系统当前图标"。
        // 重装、或从备份恢复时，偏好还在但系统图标可能已回主图标，这里补一次。
        if UIApplication.shared.supportsAlternateIcons,
           UIApplication.shared.alternateIconName != AppIconStore.current.alternateName {
            let name = AppIconStore.current.alternateName
            UIApplication.shared.setAlternateIconName(name) { error in
                // 切换结果打出来：命令行环境没有点击通道，验「新加的一套图标能不能真的切过去」
                // 只能靠预置偏好 + 冷启动走这条对齐分支（2026-11-16 加第 17 套时补）。
                #if DEBUG
                if let error {
                    print("[allude-icon] 切换失败 name=\(name ?? "主图标") err=\(error.localizedDescription)")
                } else {
                    print("[allude-icon] 已切到 \(name ?? "主图标")")
                }
                #endif
            }
        }

        // 通知点击的验证脚手架：PUSH_TEST=1 → 5 秒后发一条带 recordID 的本地通知，
        // 退到桌面点它，看 App 是否打开并跳到对应记录（日志里有 [notify] tapped）。
        if environment["PUSH_TEST"] == "1" {
            let content = UNMutableNotificationContent()
            content.title = "Codelumi测试通知"
            content.body = "点我：应该打开Codelumi并跳到这条取件记录。"
            content.sound = .default
            if let record = PickupStore.shared.records.first {
                content.userInfo = ["recordID": record.id.uuidString]
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "allude.pushTest",
                                      content: content, trigger: trigger))
        }

        // 🔴 每次装新构建后，强制结束旧的实时活动：
        //    锁屏卡的视图会被系统**缓存**，只改代码不换活动实例时，截到的/看到的
        //    永远是旧渲染（2026-10-28 已踩过一次）。这里用构建号做标记，
        //    构建号变了就把在册活动全部收掉，让 sync 重新创建一个新的。
        let buildKey = "allude.lastBuildForActivity"
        let currentBuild = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
        let shared = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        if shared.string(forKey: buildKey) != currentBuild {
            shared.set(currentBuild, forKey: buildKey)
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        // 签名到期提醒（没有描述文件的 App Store 版内部会直接返回）
        SigningExpiryNotifier.reschedule()

        DiagnosticsLog.record("signing",
                              "days=\(SigningProfile.daysRemaining.map(String.init) ?? "nil") "
                              + "expires=\(SigningProfile.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")")

        DiagnosticsLog.record("launch",
                              "version=\(AppVersion.display) plan=\(bootEntitlement.plan.rawValue)"
                              + " isPro=\(bootEntitlement.isPro)")

        print("[allude-verify] device=\(deviceCode) plan=\(bootEntitlement.plan.rawValue)"
              + " hasLicense=\(!(bootEntitlement.license ?? "").isEmpty)"
              + " isPro=\(bootEntitlement.isPro)"
              + " expires=\(bootEntitlement.expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")")

        // ⚠️ 2026-10-25：`ACCOUNTS` / `AVATAR` 两个账户脚手架随**账户功能整体下线**
        // 一并删除 —— 产品是纯离线本地工具，不需要任何账户概念。

        // ⚠️ 2026-11-22：小组件显示内容脚手架 `DISPLAY=…` 随「六个开关」一起删除 ——
        //    显示内容现在由款式（`WidgetPreset`）编译期固定，没有可写的用户配置了。
        //    需要拍某一款的截图时用 `SCREEN=widgets` + `WIDGET_SIZE=small|medium|…`
        //    （见 `WidgetPreviewGallery`），它按款式渲染，不需要预写任何状态。

        // 小组件背景材质脚手架：`WIDGET_BG=solid|clear|glass|clearGlass`
        // （2026-11-22 起是两个叠加开关，四种组合；走正式 setter，写 App Group）。
        if let raw = environment["WIDGET_BG"],
           let style = WidgetBackground(rawValue: raw) {
            WidgetBackgroundSetting.setClear(style.wantsTransparent)
            WidgetBackgroundSetting.setGlass(style.wantsGlass)
        }

        // ⚠️ 2026-09-23：原先这里的 `SIGNED_IN` / `BOUND` 两个脚手架随第三方登录
        //    体系一起删除 —— 账户不再是登录态，注入"已登录/已绑定的方式"已经没有意义。
        // ⚠️ 2026-10-14：`PLAN` / `PRO` / `LICENSE` 三个脚手架随 VIP 会员体系退役
        //    （全功能开放后档位与凭证不再存在，见 Models.swift 全功能化注释）。

        // 取件码外观脚手架（2026-11-16）：命令行一次性拍「固定色 / 关强调 /
        // 一卡多码」等形态。全部走正式 setter（写 App Group），
        // 桌面时间线与实时活动一起重画，不留特例分支。
        if let raw = environment["CODE_COLOR"] {
            CodeAppearanceSettings.setColorRaw(raw)
        }
        if let raw = environment["CODE_EMPHASIS"] {
            CodeAppearanceSettings.setEmphasisEnabled(raw != "0")
        }
        if let raw = environment["CODE_OPACITY"], let value = Double(raw) {
            CodeAppearanceSettings.setOpacity(value)
        }
        if let raw = environment["CODE_GROUP"] {
            CodeAppearanceSettings.setGroupsMultipleCodes(raw == "1")
        }

        // 2026-11-23：驿站内排序设置已删除，`INNER_ORDER` 脚手架参数一并作废。

        switch environment["SCREEN"] {
        case "ingest":
            // `INGEST_INAPP=1` 走「App 内录入」那条来源（不推通知），
            // 用来验 2026-11-22 的口径：「除 App 内录入外，其他入库都要推通知」。
            // 不带这个变量 = 外部来源（快捷指令 / 分享扩展），会推。
            let source: PickupIngestSource = environment["INGEST_INAPP"] == "1" ? .inApp : .external
            let outcome = PickupStore.shared.ingest(environment["SEED"] ?? "", source: source)
            print("[allude-verify] ingest => \(outcome.dialog) source=\(source)")

        case "codeGroupSeed":
            // 2026-11-16「一张卡片多个取件码」验收种子：一条短信两个码，
            // 待取 / 已取各放一组，配合 `TAB=pending|picked` 两页一起验。
            // ⚠️ 只在 DEBUG 脚手架生效；正式包由 BuildFlags 整段裁掉。
            let store = PickupStore.shared
            store.ingest("【圆通速递】您有 2 个包裹到站，取件码 8-4-3019、8-4-3020，幸福里小区3号楼东侧门店")
            let done = store.records.filter { $0.code == "8-4-3019" || $0.code == "8-4-3020" }
            store.markPicked(done)
            store.ingest("【中通快递】您有 2 个包裹到站，取件码 7-3-8812、7-3-8813，幸福里小区3号楼东侧门店")
            print("[allude-verify] codeGroupSeed done=\(done.count) pending=\(store.pending.count)")

        case "stationGroupSeed":
            // 2026-11-17 驿站组验收种子：把三家不同驿站归成「恒大御府驿站」，
            // 再写三条短信 —— 待取页只应出现**一个**组分组，卡面副名写「组名/原名」。
            // 配合 `SCREEN=stationGroups`（管理页）/ `TAB=pending`（待取页）分别取证。
            let memberNames = ["菜鸟驿站", "妈妈驿站", "丰巢"]
            let memberIDs = memberNames.compactMap { StationIdentity.id(for: $0) }
            if StationGroupStore.all().isEmpty {
                _ = StationGroupStore.create(name: "恒大御府驿站",
                                             memberIDs: memberIDs,
                                             iconInheritMemberID: memberIDs.first)
            }
            let groupStore = PickupStore.shared
            groupStore.ingest("【圆通速递】取件码 8-4-3019，菜鸟驿站")
            groupStore.ingest("【中通快递】取件码 8-4-3020，妈妈驿站")
            groupStore.ingest("【丰巢】取件码 7-3-8812，丰巢智能柜")
            // 解析器对驿站的命中依赖词表，这里显式补一次 stationOverride，
            // 保证截图取的是「归组后的显示效果」而不是「有没有识别出驿站」。
            for name in memberNames {
                if let record = groupStore.pending.first(where: { $0.rawMessage.contains(name) }) {
                    var copy = record
                    copy.stationOverride = name
                    groupStore.update(copy)
                }
            }
            // 顺手取走一件，让「已取页」也有组数据可验（副名同样是 组名/原名）
            if let done = groupStore.pending.first(where: { $0.rawMessage.contains("妈妈驿站") }) {
                groupStore.markPicked(done)
            }
            print("[allude-verify] stationGroupSeed groups=\(StationGroupStore.all().count) "
                  + "pending=\(groupStore.pending.count)")

        case "ingestDelayed":
            // 验证脚手架：延迟 DELAY 秒（默认 8）再写入。
            // 用途是验证**本地通知真的会弹**：前台写入会被
            // `PickupNotificationPresenter` 按设计抑制掉，脚本必须先借这段时间
            // 把 App 切到后台，才能拍到横幅。正式运行零影响。
            let text = environment["SEED"] ?? ""
            let delay = Double(environment["DELAY"] ?? "8") ?? 8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let outcome = PickupStore.shared.ingest(text)
                print("[allude-verify] delayed ingest => \(outcome.dialog)")
            }

        case "detailPicked":
            // 截图脚手架：详情页在同一时刻只会显示「标记为已取」或「恢复为待取件」
            // 其中一个，要拍后者的样子就得先真的把一条标成已取。
            //
            // 口径 = **确保全表最新的一条处于已取**（`pickedUpRecords` 按时间倒序，
            // 于是它必然是第一张，`SCREEN=detailPicked` 拍到的就是它）。
            // ⚠️ 幂等条件不能用 `pickedUpRecords.isEmpty` —— 示例数据里本来就躺着
            // 昨天的已取记录，那个条件恒为假，等于永远不标。这里只判「最新一条还没取」
            // 才动手，反复启动不会有副作用，`pending.first` 也不会一路往后挪。
            if let newest = PickupStore.shared.records.max(by: { $0.receivedAt < $1.receivedAt }),
               !newest.isPickedUp {
                PickupStore.shared.markPicked(newest)
            }

        case "activityLive":
            // 取证脚手架：实时活动的**真实生命周期**无法用截图证明 —— 锁屏要真的锁上、
            // 灵动岛只在带灵动岛的机型上绘制。这里改从 ActivityKit 自己的账本取证：
            // 走的是正式链路 `PickupActivityController.sync`，稍后把在册活动数与
            // 当前 state 打到 stdout，用来确认 Info.plist 开关、扩展注册、
            // 以及「后台由 App Intent 触发时能否起活动」这三件事都成立。
            // 2026-10-28：先结束在册活动再 sync —— 锁屏卡的视图会被系统缓存，
            // 只改代码不换活动实例，截图永远是旧渲染（这一轮踩了三次）。
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(500))
                PickupActivityController.sync(pending: PickupStore.shared.pending)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let running = Activity<PickupActivityAttributes>.activities
                let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
                print("[allude-verify] activitiesEnabled=\(enabled) running=\(running.count)"
                      + " liveActivityEnabled(our toggle)=\(LiveActivitySetting.isEnabled))")
                for activity in running {
                    print("[allude-verify] activity id=\(activity.id) "
                          + "code=\(activity.content.state.item.code) "
                          + "pending=\(activity.content.state.pendingCount) "
                          // 岛内图标由 state 带过去（2026-11-15）：这一位就是扩展
                          // 真正会画的资源名，nil 表示回落到了本进程读到的选择。
                          + "icon=\(activity.content.state.appIconRaw ?? "nil")->\(activity.content.state.appIcon.assetName) "
                          + "state=\(activity.activityState)")
                }
            }

        case "activityAudit":
            // 🔴 只读体检（2026-09-25）：**不注入数据、不主动动活动**，只把
            //    ActivityKit 自己账本里的在册活动逐条报出来 —— 用来在**真机**上
            //    回答「锁屏上到底挂着几张卡」这个只有用户能看到的问题。
            //
            //      DEVICECTL_CHILD_SCREEN=activityAudit \
            //        xcrun devicectl device process launch --device <UDID> \
            //        --terminate-existing --console com.jikezhang.allude
            //
            //    两次报数的语义：
            //      audit-0 at-launch  ── 启动瞬间的现场。冷启动对齐要等 UIScene
            //                            连上（1 秒后才 sync），所以这里读到的是
            //                            **未被修复逻辑碰过**的真实状态：
            //                            `running>1` 就是用户看到的重复卡。
            //      audit-1 after-align ── 冷启动对齐跑完后的结果，应当收敛为 1。
            //
            //    与 `activityLive` 的区别：后者会先 `sync` 一次，因此看不到
            //    收敛**之前**有几张；本模式纯读。
            Self.auditReport("audit-0 at-launch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Self.auditReport("audit-1 after-align")
            }

        case "activityRace":
            // 🔴 竞态取证脚手架（2026-09-25）：复现「锁屏上重复出现两张实时活动卡」。
            //
            // 真实触发路径：一条短信到达 → `records` 的 `didSet` 调一次
            // `PickupActivityController.sync`；而 App 被静默拉起后 `scenePhase`
            // 转 `.active` 又会走 `reloadFromStorage` —— 两次 sync 挤在同一秒里。
            // 本脚手架把这种重叠放大成 N 次连发，最后从 ActivityKit 自己的账本
            // 报出在册活动数：**修复前会 > 1，修复后必须恒为 1**。
            //
            //   RACE_N    连发次数（默认 24）
            //   RACE_GAP  连发间隔秒数（默认 0 = 全部挤在同一轮里）
            let raceN = Int(environment["RACE_N"] ?? "24") ?? 24
            let raceGap = Double(environment["RACE_GAP"] ?? "0") ?? 0

            Task { @MainActor in
                Self.raceLog("race activitiesEnabled="
                             + "\(ActivityAuthorizationInfo().areActivitiesEnabled) n=\(raceN) gap=\(raceGap)")

                // 等 UIScene 连上：`Activity.request` 要求 App 处于前台，
                // 冷启动 init 期间（scene 还没 active）发起会被系统拒绝。
                try? await Task.sleep(for: .seconds(2))

                // 阶段 0：🔴 **不动任何东西**，先把启动瞬间的账本报出来。
                //   这是「修复前现场」的唯一取证机会 —— 装的是修复版，而 `SCREEN`
                //   已注入时冷启动对齐会被跳过，所以此刻读到的就是主人手上
                //   （可能正挂着两张卡）的真实状态。修复版的收敛发生在后面的阶段。
                let audit = Activity<PickupActivityAttributes>.activities
                Self.raceLog("race-0 audit running=\(audit.count) isPro="
                             + "\(EntitlementSnapshot.licensedPro) codes=["
                             + audit.map(\.content.state.item.code).joined(separator: ",") + "]")

                // 探针：显式试一次 request 并把**错误原文**落盘。
                // 控制器 catch 里的 `print` 在非交互启动下看不到，只剩「running=0」
                // 这个结果 —— 分不清是「竞态」还是「这台机器根本起不了活动」。
                do {
                    let probe = try Activity.request(
                        attributes: PickupActivityAttributes(),
                        content: ActivityContent(
                            state: .init(item: .init(id: "probe",
                                                     company: "菜鸟驿站",
                                                     code: "8-2-109",
                                                     address: "探针",
                                                     tint: 0x2F7BFF),
                                          pendingCount: 1),
                            staleDate: nil),
                        pushType: nil)
                    Self.raceLog("probe request ok id=\(probe.id)")
                    await probe.end(nil, dismissalPolicy: .immediate)
                } catch {
                    Self.raceLog("probe request FAILED: \(error)")
                }
                try? await Task.sleep(for: .milliseconds(600))

                // 从**干净状态**起跑：先把上一轮遗留的活动全收掉，否则 running 数读不出因果
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(600))

                // 阶段 A：常规起一张，作为「活动已存在」的基线
                // 2026-10-28：先结束在册活动再 sync —— 锁屏卡的视图会被系统缓存，
            // 只改代码不换活动实例，截图永远是旧渲染（这一轮踩了三次）。
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(500))
                PickupActivityController.sync(pending: PickupStore.shared.pending)
            }
                try? await Task.sleep(for: .seconds(2))
                Self.raceReport("race-A baseline")

                // 阶段 B：🔴 **先清空、再并发连发** —— 这才是竞态的真正检验。
                //   账本非空时后续 sync 全走 update 分支，永远撞不出第二张；
                //   只有「列表为空 + 多个 sync 同时发起」才可能各自 request 一张。
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(800))
                Self.raceReport("race-B ready")

                let burst = PickupStore.shared.pending
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<raceN {
                        group.addTask { PickupActivityController.sync(pending: burst) }
                    }
                }
                try? await Task.sleep(for: .seconds(4))
                Self.raceReport("race-B concurrent-burst")

                // 阶段 C：顺序连发（真实形态：didSet 与回前台 reload 相隔一个 runloop）
                // 2026-10-28：先结束在册活动再 sync —— 锁屏卡的视图会被系统缓存，
            // 只改代码不换活动实例，截图永远是旧渲染（这一轮踩了三次）。
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(500))
                PickupActivityController.sync(pending: PickupStore.shared.pending)
            }
                for _ in 0..<raceN {
                    // 2026-10-28：先结束在册活动再 sync —— 锁屏卡的视图会被系统缓存，
            // 只改代码不换活动实例，截图永远是旧渲染（这一轮踩了三次）。
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(500))
                PickupActivityController.sync(pending: PickupStore.shared.pending)
            }
                }
                try? await Task.sleep(for: .seconds(4))
                Self.raceReport("race-C spaced gap=\(raceGap)")

                // 阶段 D：🔴 **人为造出「两张卡」**，直接复现主人截到的画面
                //   （同类型活动并排两张、各带不同取件码），
                //   然后调一次**正式链路** sync，验证能被收敛回 1 张。
                Self.raceLog("race-D 人为发起两个活动（复现用户看到的重复卡）")
                for index in 0..<2 {
                    do {
                        _ = try Activity.request(
                            attributes: PickupActivityAttributes(),
                            content: ActivityContent(
                                state: .init(item: .init(id: "dup-\(index)",
                                                         company: "菜鸟驿站",
                                                         code: index == 0 ? "118-5-6178" : "110-5-6178",
                                                         address: "临沂大学菜鸟驿站",
                                                         tint: 0x2F7BFF),
                                              pendingCount: 2),
                                staleDate: nil),
                            pushType: nil)
                    } catch {
                        // 🔴 错误原文必须落盘：ActivityKit 对 request 有频率节流，
                        //    连续压测时可能被拒 —— 不打出错误就会把"没造出来"
                        //    误读成"收敛生效了"。
                        Self.raceLog("race-D request\(index) FAILED: \(error)")
                    }
                }
                try? await Task.sleep(for: .seconds(1))
                Self.raceLog("race-D duplicated running="
                             + "\(Activity<PickupActivityAttributes>.activities.count)"
                             + "（人为造出，模拟主人截图里的两张卡，此处不看判定）")

                // 2026-10-28：先结束在册活动再 sync —— 锁屏卡的视图会被系统缓存，
            // 只改代码不换活动实例，截图永远是旧渲染（这一轮踩了三次）。
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(500))
                PickupActivityController.sync(pending: PickupStore.shared.pending)
            }
                try? await Task.sleep(for: .seconds(4))
                Self.raceReport("race-D after-sync")

                // 阶段 E：🔴 模拟「**迟到的旧活动**」—— 复现主人截图里两张卡
                //   **取件码不同**（118-5-6178 / 110-5-6178）的成因：
                //   第二条短信到达时走到了账本还没同步完的进程里，`activities`
                //   读到空列表 → 于是又 request 一张，旧的那张成了幽灵卡。
                //   这里在 sync 起了活动之后 700ms 再人为 request 一张（旧内容），
                //   验证「延迟复查」能在**同一轮收敛内**把它收掉 ——
                //   不需要等用户下一次操作（这正是修复前后的关键差别）。
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(1500))

                // 2026-10-28：先结束在册活动再 sync —— 锁屏卡的视图会被系统缓存，
            // 只改代码不换活动实例，截图永远是旧渲染（这一轮踩了三次）。
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(500))
                PickupActivityController.sync(pending: PickupStore.shared.pending)
            }
                try? await Task.sleep(for: .milliseconds(700))
                do {
                    _ = try Activity.request(
                        attributes: PickupActivityAttributes(),
                        content: ActivityContent(
                            state: .init(item: .init(id: "late",
                                                     company: "菜鸟驿站",
                                                     code: "118-5-6178",
                                                     address: "临沂大学菜鸟驿站",
                                                     tint: 0x2F7BFF),
                                          pendingCount: 2),
                            staleDate: nil),
                        pushType: nil)
                    Self.raceLog("race-E 已注入「迟到的旧活动」，等延迟复查收掉它")
                } catch {
                    Self.raceLog("race-E 注入失败（ActivityKit 节流？）: \(error)")
                }

                try? await Task.sleep(for: .seconds(4))
                Self.raceReport("race-E late-arrival")
                Self.raceLog("race done")
            }

        case "metrics":
            // 尺寸上报脚手架（2026-10-25，iPhone Duo 适配）：
            // 折叠屏/宽屏的布局决策必须依据**真实点尺寸 + size class**，
            // 而模拟器截图只给像素（内屏 2853×2007 到底是 @3x 的 951×669 还是别的，
            // 靠猜会做错）。这里把几何写进 UserDefaults，
            // 命令行 `simctl spawn <udid> defaults read com.jikezhang.allude` 直接读，
            // 不必依赖 --console 跟流（那条路会被 SIGTERM）。
            //
            // ⚠️ 延后 2 秒：App init 时 scene 往往尚未连上，
            //    立即取会拿到空集（此前其它脚手架踩过同样的坑）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                        ?? scenes.first else {
                    UserDefaults.standard.set("no-scene", forKey: "scaffold.metrics")
                    return
                }
                let b = scene.screen.bounds
                let t = scene.traitCollection
                let insets = scene.windows.first?.safeAreaInsets ?? .zero
                let hSize = t.horizontalSizeClass == .regular ? "regular" : "compact"
                let vSize = t.verticalSizeClass == .regular ? "regular" : "compact"
                let report = "bounds=\(b.width)x\(b.height) scale=\(scene.screen.scale) "
                    + "hSize=\(hSize) vSize=\(vSize) "
                    + "safe=(\(insets.top),\(insets.left),\(insets.bottom),\(insets.right)) "
                    + "idiom=\(UIDevice.current.userInterfaceIdiom.rawValue)"
                UserDefaults.standard.set(report, forKey: "scaffold.metrics")
                print("[allude-verify] metrics => \(report)")
            }

        case "shareMulti":
            // 多码分享卡渲染脚手架（2026-09-23）：分享图由 ImageRenderer 离屏渲染，
            // 不走屏幕 —— 模拟器截屏拍不到，只能渲成 PNG 落到沙盒 Documents，
            // simctl 拷出来人工核对。
            // 可选 SHARE_COUNT=<n>：控制上卡条数。Demo 待取不足 n 条时按序循环补齐
            // （只补渲染输入、不落库），用来验证多行版式与 >6 条的聚合版式。
            Task { @MainActor in
                let store = PickupStore.shared
                var list = store.pending
                let want = Int(ProcessInfo.processInfo.environment["SHARE_COUNT"] ?? "") ?? list.count
                if want > list.count, !list.isEmpty {
                    var pool = list
                    while pool.count < want {
                        pool.append(list[pool.count % list.count])
                    }
                    list = pool
                }
                list = Array(list.prefix(max(0, want)))
                guard !list.isEmpty else {
                    print("[allude-verify] shareMulti: no pending records")
                    return
                }
                let renderer = ImageRenderer(content: PickupShareCard(records: list))
                renderer.scale = 3
                if let image = renderer.uiImage, let data = image.pngData() {
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("share-multi-\(list.count).png")
                    try? data.write(to: url)
                    print("[allude-verify] share card => \(url.path) records=\(list.count)")
                } else {
                    print("[allude-verify] shareMulti: render failed")
                }
            }

        default:
            break
        }

        // 🔴 冷启动对齐一次实时活动（2026-09-25）—— 文件头契约里的第 4 条，
        //    此前只有注释、没有实现。
        //
        //    要覆盖的正是主人遇到的形态：**锁屏上已经挂着重复的卡**。
        //    这类残留不会因为「数据没变」而自行消失 —— `reloadFromStorage` 走的是
        //    内容签名比对（相同就不写 records），`records` 的 didSet 因此不会被触发，
        //    收敛链路永远等不到调用。这里在启动后主动跑一次 `sync`：
        //    `enforceSingle` 会把多余的活动收干净，恢复正常只需打开一次 App。
        //
        //    ⚠️ 必须延后到 UIScene 连上之后：`Activity.request` 要求 App 处于前台，
        //       在 init 期间发起会被系统拒绝（模拟器实测：探针 request 成功、
        //       但同一时刻由控制器发起的会被拒）。
        //    ⚠️ 唯一例外是**竞态取证**（`SCREEN=activityRace`）：它要读的是
        //       「启动瞬间的现场」，冷启动对齐会先把重复卡收掉，等于毁掉证据。
        //       其余模式（含只读体检 `activityAudit`）一律照常对齐 —— 让体检
        //       能观察到「对齐前后」的真实变化。
        if environment["SCREEN"] != "activityRace" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                // 2026-10-28：先结束在册活动再 sync —— 锁屏卡的视图会被系统缓存，
            // 只改代码不换活动实例，截图永远是旧渲染（这一轮踩了三次）。
            Task {
                for activity in Activity<PickupActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                try? await Task.sleep(for: .milliseconds(500))
                PickupActivityController.sync(pending: PickupStore.shared.pending)
            }
            }
        }
    }

    /// `SCREEN=detail` 的记录定位（2026-09-23 追加）：
    /// 可选 `DETAIL_MATCH=<码子串>` 从**全表**按码找记录 —— 要验证"15 位长运单号
    /// 在详情页不被复制按钮遮挡"这类特定记录的问题时，它不一定是待取第一条，
    /// 命令行又点不到卡片，只能靠注入定位。不注入时回落"待取第一条"。
    private static func detailScaffoldTarget(_ store: PickupStore) -> PickupRecord? {
        let needle = ProcessInfo.processInfo.environment["DETAIL_MATCH"]
        if let needle, !needle.isEmpty {
            return store.records.first {
                $0.code.localizedCaseInsensitiveContains(needle)
            }
        }
        return store.pending.first
    }

    var body: some Scene {
        WindowGroup {
            AppearanceHost {
            Group {
                // SCREEN 环境变量用于命令行截图验证（simctl launch 时以 SIMCTL_CHILD_SCREEN 注入）。
                // 不注入时走正常入口 RootView()，对正式运行无影响。
                // 旧脚手架名 `history` / `stats` 都指向浏览页（统计已并入，2026-10-08）。
                // 内测分发的 Release 包不带脚手架（见 BuildFlags）：少一处可被翻的内部入口。
                if BuildFlags.scaffoldsEnabled {
                    switch ProcessInfo.processInfo.environment["SCREEN"] {
                case "history", "stats", "browse":
                    // 统计页（2026-10-14 独立成第 3 个标签，旧脚手架名保留兼容）；
                    // StatsTabView 现已自带 NavigationStack，这里不再外包。
                    StatsTabView()
                case "settings", "profile":
                    // 设置页（原「我的」面板重构，见 ProfileView.swift）
                    NavigationStack { SettingsView() }
                case "about":
                    // 关于 Codelumi（2026-11-22 截图用：单列布局下 `SETTINGS_PANE`
                    // 只能改分栏选中项，进不了二级页，命令行点不到那一行）
                    NavigationStack { AboutAlludeView() }
                case "openSource":
                    // 关于 › 开源项目信息（2026-11-21 新增；2026-11-22 与上面的
                    // `case "about"` 放在一起，避免 switch 里出现重复 case）
                    NavigationStack { OpenSourceView() }
                case "settingsPush":
                    // 🔍 返回按钮排查脚手架：程序化 push 到使用教程，
                    // 复现「设置 → 使用教程」的真实导航栏形态（constant path 只看不点）。
                    NavigationStack(path: .constant(["guide"])) {
                        SettingsView()
                            .navigationDestination(for: String.self) { route in
                                switch route {
                                case "guide": UsageGuideView()
                                default: EmptyView()
                                }
                            }
                    }
                case "share":
                    // 分享预览面板**直接**渲染（2026-10-27）。
                    // 原来验证这个面板只能走 `SHARE_HIT`（长按卡片开菜单再"点"分享行），
                    // 那条链依赖手势时序，实测时灵时不灵、频繁截到列表页。
                    // 这里跳过菜单与手势，直接把面板本体摆出来 —— 布局验收用它。
                    SharePreviewSheet(records: Array(PickupStore.shared.pending.prefix(1)))
                        .ignoresSafeArea()
                case "aiCheck":
                    // 端侧 AI 辅助解析自检（2026-10-28）：真机跑一批语料，
                    // 把「正则 vs 模型」逐字段打到控制台。模拟器上模型不可用，
                    // 会直接打印不可用原因后退出（不影响 App 正常运行）。
                    RootView()
                        .task { if #available(iOS 26.0, *) { await PickupAICheck.run() } }
                case "onboardingGuide":
                    // 🔍 排查：引导语境（fullScreenCover 同构 —— 栈根挂 toolbar hidden）
                    // push 使用教程后，导航栏/返回按钮是否被根上的 hidden 传播吞掉。
                    NavigationStack(path: .constant(["guide"])) {
                        TabView {
                            AppTheme.pageBackground.ignoresSafeArea()
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .safeAreaInset(edge: .bottom) {
                            Text("引导底栏占位")
                                .font(.footnote)
                                .padding(.bottom, 20)
                        }
                        .navigationDestination(for: String.self) { _ in UsageGuideView() }
                    }
                case "credits":
                    // 关于 › 特别鸣谢（2026-11-21 新增）
                    NavigationStack { CreditsView() }
                case "versionHistory":
                    // 版本历史（「设置 › 关于 › 版本」push 进入），独立栈截图用。
                    NavigationStack { VersionHistoryView() }
                case "detail":
                    if let record = Self.detailScaffoldTarget(store) {
                        NavigationStack { RecordDetailView(record: record) }
                    } else {
                        RootView()
                    }
                case "detailPicked":
                    if let first = store.pickedUpRecords.first {
                        NavigationStack { RecordDetailView(record: first) }
                    } else {
                        RootView()
                    }
                case "pickedUp":
                    // 已取页（2026-10-14 新标签页）
                    PickedUpView()
                case "notify":
                    NavigationStack { NotificationSettingsView() }
                case "appicon":
                    NavigationStack { AppIconSettingsView() }
                // 2026-11-12 设置页改版：新二级页的独立截图入口（只给 Debug 脚手架用）
                case "appearanceGroup":
                    NavigationStack { AppearancePersonalizationView() }
                case "storageSpace":
                    NavigationStack { StorageSpaceView() }
                case "aboutAllude":
                    NavigationStack { AboutAlludeView() }
                case "encourage":
                    NavigationStack { EncourageView() }
                case "privacySimple":
                    NavigationStack { PrivacySimpleView() }
                case "icloudSync":
                    NavigationStack { ICloudSyncView() }
                case "termsMerged":
                    LegalDocumentView(document: .terms, extraHTML: StatementHTML.appended)
                case "confirmClear":
                    // 弹窗是 overlay 形式，得挂在一个宿主视图上才拍得到
                    AppTheme.pageBackground
                        .ignoresSafeArea()
                        .destructiveConfirm(
                            isPresented: .constant(true),
                            title: "清空已取件记录",
                            message: "记录只存在这台手机上，删除后无法恢复，也没有备份可以还原。"
                        ) {}
                case "version":
                    NavigationStack { VersionHistoryView() }
                case "icloud":
                    // iCloud 同步页（设置 › iCloud 同步）。命令行点不到那一行，
                    // 「开启同步」开关的 Pro 门验收靠这个入口直渲。
                    NavigationStack { ICloudSyncView() }
                case "consent":
                    LegalConsentView { }
                case "onboarding":
                    OnboardingView()
                case "contact":
                    NavigationStack { ContactView() }
                case "statement":
                    NavigationStack { StatementView() }
                case "help":
                    NavigationStack { HelpCenterView() }
                // ⚠️ 2026-11-22：原来这里还有一条 `case "about"` 指向旧 `AboutView`，
                //    与上面（设置 › 关于）那条同名，switch 只认第一条 —— 直接删掉。
                case "activation":
                    // 激活页（设备码 + 凭证输入）。设置里那一行命令行点不到，
                    // 逐页验收靠这个入口直渲。
                    NavigationStack { ActivationView() }
                case "legal":
                    // 法律文档页（隐私政策）。App 内 WebView 读打包的 HTML，
                    // 命令行点不到设置里的行，逐页验收只能靠这个入口。
                    NavigationStack { LegalDocumentView(document: .privacy) }
                case "license":
                    // 签名凭证页（设置 › 解锁 › 签名凭证）。命令行点不到设置里的行，
                    // 逐页验收只能靠这个入口。顺带验「未激活 / 已激活」两种状态。
                    NavigationStack { FullVersionView() }
                // ⚠️ 2026-09-23：`auth` / `phone` / `email` / `password` /
                //    `loginMethods` 五个截图分支随第三方登录体系一起删除。
                // ⚠️ 2026-10-14：`vip` / `premium` / `license` / `profilePushed` /
                //    `tabProfile` 随 VIP 体系与顶栏头像入口一起删除。
                case "widgetSettings":
                    NavigationStack { WidgetSettingsView() }
                case "gallery":
                    NavigationStack {
                        CourierGalleryView(
                            anchor: ProcessInfo.processInfo.environment["SEED"]
                        )
                    }
                case "courierGallery":
                    // 快递公司（原「快递管理」，2026-10-27 拆成两个模块）
                    NavigationStack {
                        CourierGalleryView(anchor: ProcessInfo.processInfo.environment["GALLERY_ANCHOR"])
                    }
                case "stationGallery":
                    // 驿站管理（拆出来的另一半）
                    NavigationStack {
                        CourierGalleryView(scope: .station,
                                           anchor: ProcessInfo.processInfo.environment["GALLERY_ANCHOR"])
                    }
                case "stationEdit":
                    // 自定义驿站编辑页（添加模式，2026-10-15 名称+图标同页）
                    // `STATION=名称` 可切到编辑态（2026-11-21：验证「驿站组」快速分组行）
                    NavigationStack {
                        if let name = ProcessInfo.processInfo.environment["STATION"], !name.isEmpty {
                            StationEditView(mode: .edit(name))
                        } else {
                            StationEditView(mode: .add)
                        }
                    }
                case "stationLocation":
                    // 驿站定位编辑页（2026-11-16 到达提醒；内置 / 自定义共用）
                    NavigationStack {
                        StationLocationEditor(stationName: "菜鸟驿站")
                    }
                case "stationLocationPicker":
                    // 创建驿站时的草稿选点页（2026-11-17：默认当前位置 + 手动点选）
                    NavigationStack {
                        StationLocationPickerPreview()
                    }
                case "stationGroups":
                    // 驿站管理页（2026-11-17 改成三段平铺：组 / 未归组 / 已归组成员）
                    NavigationStack {
                        CourierGalleryView(scope: .station,
                                           anchor: ProcessInfo.processInfo.environment["GALLERY_ANCHOR"])
                    }
                case "stationGroupEdit":
                    // 驿站组编辑页：给 `GROUP_ID` 进编辑态，不给则新建
                    if let gid = ProcessInfo.processInfo.environment["GROUP_ID"], !gid.isEmpty {
                        NavigationStack { StationGroupEditView(mode: .edit(gid)) }
                    } else {
                        NavigationStack { StationGroupEditView(mode: .create) }
                    }
                case "codeManagement":
                    // 取件码管理（2026-11-16；桌面小组件下面那一行）
                    NavigationStack { CodeManagementView() }

                case "automationShare":
                    // 🔍 2026-11-11：验证「一键导入自动化」的分享面板（内测反馈过打不开）。
                    //    跳过点击，启动后直接走首启引导里同一个入口，截图看面板是否弹出。
                    RootView()
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            guard let preset = ShortcutAutomation.presets.first,
                                  let url = ShortcutAutomation.preparedImportURL(for: preset) else { return }
                            ShareSheetPresenter.present([url])
                        }
                case "automation", "guide":
                    NavigationStack { UsageGuideView() }
                case "widgets":
                    NavigationStack { WidgetPreviewGallery() }
                case "widgetPreset":
                    // 款式详情页（设置 › 小组件 › 点某一张卡）。
                    // 命令行点不到网格里的卡片，逐页验收只能靠这个入口。
                    // `WIDGET_PRESET=<kind>` 指定哪一款，缺省给中尺寸「待取清单」。
                    NavigationStack {
                        WidgetPresetDetailView(
                            preset: WidgetPreset.preset(id: ProcessInfo.processInfo.environment["WIDGET_PRESET"] ?? "")
                                ?? WidgetPreset.all[3]
                        )
                    }
                case "activity":
                    NavigationStack { ActivityPreviewGallery() }
                case "permissions":
                    // 关于 › 使用权限（2026-11-22）
                    NavigationStack { PermissionsView() }
                case "appearance":
                    NavigationStack { AppearanceSettingsView() }
                case "personalization":
                    NavigationStack { AppearancePersonalizationView() }
                case "storage":
                    NavigationStack { StorageSpaceView() }
                case "aiCapability":
                    NavigationStack {
                        if #available(iOS 26.0, *) {
                            AICapabilityView()
                        } else {
                            AICapabilityUnsupportedView()
                        }
                    }
                case "autoRecord":
                    // 注意：`SCREEN=automation` 已被「使用教程」占用，这里换个名字
                    NavigationStack { AutoRecordSettingsView() }
                case "fontSize":
                    NavigationStack { FontSizeView() }
                case "language":
                    NavigationStack { AppLanguageView() }
                case "training":
                    NavigationStack { TrainingDataView() }
                case "colorCheck":
                    // 品牌取色体检（2026-10-28）：小组件里码的颜色与 App 不一致，
                    // 先把「每个品牌名解析到哪一条、最终色是多少」打成一份表，
                    // 判断是匹配失败（落进 fallbackPalette）还是渲染层问题。
                    ColorCheckView()

                case "lockPreview":
                    // 锁屏卡可读性预览（2026-10-28）。
                    //
                    // 为什么要这个脚手架：锁屏卡用的是**系统液态玻璃**，材质透过去是
                    // 用户的壁纸 —— 只有在「浅色花哨壁纸 + 深色文字 / 深色壁纸 + 白字」
                    // 这类极端组合下才看得出对比度是否够。真机截图要等到锁屏才看得到，
                    // 改一行就得解锁看一眼，成本太高。
                    //
                    // 这里把真实的 `ActivityLockScreenCard` 铺在两种模拟壁纸上，
                    // 用来验收「码能不能一眼读出来」，不追求复刻系统材质的像素细节。
                    LockCardPreview()
                case "add":
                    AddPickupSheet(initialText: ProcessInfo.processInfo.environment["SEED"] ?? "",
                                   onClose: {}, onAdded: { _ in })
                case "scan":
                    ScanPickupSheet(initialCaptured: ProcessInfo.processInfo.environment["SEED"] ?? "",
                                    onClose: {}, onAdded: { _ in })
                case "scanCapture":
                    ScanPickupSheet(initialCaptured: ProcessInfo.processInfo.environment["SEED"] ?? "",
                                    initialMode: .capture,
                                    onClose: {}, onAdded: { _ in })
                case "scanPhoto":
                    ScanPickupSheet(initialCaptured: ProcessInfo.processInfo.environment["SEED"] ?? "",
                                    initialMode: .photo,
                                    onClose: {}, onAdded: { _ in })
                default:
                    RootView()
                    }
                } else {
                    RootView()
                }
            }
            }
            .environmentObject(store)
            .tint(AppTheme.accent)
            // DARK=1 截图脚手架：模拟器 `simctl ui appearance dark` 在部分环境
            // 不传导给无头启动的 App（实测外观仍浅色），强制 colorScheme 才能拍到暗色。
            // 🔴 外观由根上的 AppearanceHost 统一管（`.preferredColorScheme`），
            //    这里**不能再设一次**：子层设 nil 会把父层的「深色」重置回跟随系统。
            // 🔴 2026-11-16 状态回滚专项：**冷启动也要对齐一次**。
            //    `.onChange(of: scenePhase)` 对**初始值**不触发 —— App 被杀之后
            //    从灵动岛进入时 scenePhase 一上来就是 .active，那条链完全不会跑。
            //    而桌面小组件可能刚刚改过共享文件，进程内存里若留着旧副本，
            //    界面就会显示旧的待取数、并在下一次写盘时把新状态盖掉。
            .task {
                store.reloadFromStorage()
                PickupActivityController.sync(pending: store.pending)
                // 冷启动同样要对齐重复提醒：从灵动岛进来时 scenePhase 一上来就是 .active，
                // 上面那条回前台链路根本不会跑（2026-11-16 状态回滚专项的同一处坑）。
                PickupNotifier.rescheduleRepeatReminder()
                // 冷启动也要按最新权益 / 位置重排围栏（回前台链路不覆盖初始 .active）
                StationLocationService.shared.syncRegions()
                #if DEBUG
                // 回归脚手架：SIMCTL_CHILD_ROLLBACK_PROBE=1
                // 模拟「小组件在别的进程写盘 + App 内存仍是旧副本」的完整竞态，
                // 把三端计数与增量日志耗时打到控制台（--console-pty 抓 stdout）。
                if ProcessInfo.processInfo.environment["ROLLBACK_PROBE"] == "1" {
                    runWidgetRollbackProbe(store: store)
                }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                // 桌面小组件的勾选框会在后台直接改共享文件，回前台时对齐一次
                if phase == .active {
                    store.reloadFromStorage()
                    // 🔴 权益跟着时间走（2026-11-15 主人：Pro 到期后自动回非 Pro）。
                    //    订阅到期是**纯时间事件**，不产生任何数据变化 —— 不主动重算的话
                    //    进程会一直停在旧档位：界面还写着「已开通」，可该拦的 Pro 功能
                    //    一个都没拦。放在 sync 之前，过期的实时活动紧接着就被收掉。
                    //    （冷启动本来就重算，这里补的是「后台放了一夜再回来」这条路。）
                    store.refreshEntitlement()
                    // iCloud 同步 2026-11-15 起并入 Pro：回前台时若已过期满，
                    // 顺手把它关掉，避免免费档继续往 iCloud 写。
                    ICloudSyncController.shared.disableIfNotPro()
                    // 🔴 实时活动**无条件**对齐一次（2026-09-25）。
                    //    `reloadFromStorage` 只在内容签名真的变了才写 records，
                    //    而「锁屏上多挂了一张重复卡」这件事**不改变任何数据** ——
                    //    没有下面这条，重复卡就永远等不到下一次收敛的机会，
                    //    会一直挂到用户把所有件取完才随 endAll 消失。
                    PickupActivityController.sync(pending: store.pending)
                    // 定期提醒的文案带「还有 N 件」快照 —— 回前台时重排，
                    // 避免隔了几天数据变了、提醒还在报旧数字。
                    PickupNotifier.rescheduleDailyReminder()
                    // 重复提醒的「还有 N 件」也是快照，回前台一并对齐
                    PickupNotifier.rescheduleRepeatReminder()
                    // 权益刚刷新过，按最新档位重排到达提醒围栏（降级即全撤）
                    StationLocationService.shared.syncRegions()
                    // 通知中心里超过 10 分钟的旧通知顺手清掉（2026-11-11 主人：
                    // 通知要过一会就消失，不能一直挂着）。iOS 没有自动过期 API，
                    // 只能把握「回前台」这个时机；更早的清理由取件/删除触发。
                    PickupNotifier.clearDelivered(olderThan: 10 * 60)
                    // iCloud 同步（2026-11-12）：开关打开时，回前台对齐一次
                    // （别的设备可能刚改过；控制器内部自己判断开关与可用性）
                    ICloudSyncController.shared.syncNow()
                }
            }
        }
    }

    /// 竞态取证的日志口径（见 `case "activityRace"`）。
    ///
    /// 🔴 **必须落盘**，不能只 `print`：`simctl launch --console` 在非交互 shell 里
    ///    拿不到 App 的 stdout（实测只回了 PID 一行），而这条取证的结论是
    ///    「在册活动数」，必须可信可复核。落盘 + `simctl get_app_container` 拷出来，
    ///    与 `shareMulti` 那条路同一个理由。
    static func raceLog(_ line: String) {
        print("[allude-verify] \(line)")
        guard ProcessInfo.processInfo.environment["SCREEN"] == "activityRace" else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("race-report.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (previous + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// 只读体检（`SCREEN=activityAudit`）的报数口径。
    ///
    /// 双通道输出，因为真机上 stdout 未必拿得到：
    ///   · stdout —— `devicectl device process launch --console` 直接看；
    ///   · 落盘  —— `Documents/activity-audit.txt`，用
    ///              `xcrun devicectl device copy from ...` 取回（append，可跨轮对比）。
    ///
    /// 判据与 `raceReport` 一致：`running <= 1` 为 PASS（待办清空时 0 也正确）。
    static func auditReport(_ tag: String) {
        let running = Activity<PickupActivityAttributes>.activities
        var lines = ["\(tag) running=\(running.count) "
                     + (running.count <= 1 ? "PASS" : "FAIL")
                     + " isPro=\(EntitlementSnapshot.licensedPro)"
                     + " sysEnabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)"
                     + " ourToggle=\(LiveActivitySetting.isEnabled)"]
        for activity in running {
            lines.append("    id=\(activity.id) code=\(activity.content.state.item.code)"
                         + " pending=\(activity.content.state.pendingCount)"
                         + " state=\(activity.activityState)")
        }
        lines.forEach { print("[allude-verify] \($0)") }

        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("activity-audit.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (previous + lines.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    /// 判定条件是 **running <= 1** 而不是 `== 1`：待办被清空时活动应全部收掉，
    /// 0 也是正确结果；`> 1` 才是缺陷。
    static func raceReport(_ tag: String) {
        let running = Activity<PickupActivityAttributes>.activities
        let ids = running.map(\.id).joined(separator: ",")
        raceLog("\(tag) running=\(running.count) "
                + (running.count <= 1 ? "PASS" : "FAIL") + " ids=[\(ids)]")
    }
}

// MARK: - 草稿选点页预览（脚手架，`SCREEN=stationLocationPicker`）
//
// 创建驿站 / 新建组时弹出的那个页面，平时是 sheet 里出现的，命令行点不到，
// 所以给一个能直接渲染的壳。

private struct StationLocationPickerPreview: View {
    @State private var coordinate: CLLocationCoordinate2D?

    var body: some View {
        StationLocationPicker(coordinate: $coordinate, stationName: "恒大御府驿站")
    }
}

// MARK: - 锁屏卡可读性预览（脚手架，`SCREEN=lockPreview`）

/// 把真实的 `ActivityLockScreenCard` 铺在「浅色花哨壁纸」与「深色壁纸」两种底上，
/// 用来判断取件码到底能不能一眼读出来。
///
/// 说明：这里用渐变 + 模糊**近似**壁纸，玻璃材质用 `.ultraThinMaterial` +
/// 与锁屏卡同一档的黑色染色 —— 不追求像素级复刻系统材质，
/// 只看「白字压在卡上、卡压在乱背景上」这一层的对比度是否成立。
struct LockCardPreview: View {

    private var state: PickupActivityAttributes.ContentState {
        .init(item: .init(id: "preview-1",
                          company: "韵达快递",
                          station: "欢猫驿站",
                          code: "7-4-2011",
                          address: "东瓜宇珠电路二街十号韵达超市店",
                          tint: 0xFABF01),
              pendingCount: 3)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                sample(title: "浅色花哨壁纸（原问题场景）",
                       background: lightWallpaper)
                sample(title: "深色壁纸",
                       background: darkWallpaper)
                sample(title: "中等亮度壁纸",
                       background: midWallpaper)
            }
            .padding(20)
        }
        .background(Color.black)
    }

    private func sample(title: String, background: some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.L)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            ZStack {
                background
                // 与真实活动同结构：玻璃在下、内容在上（分层）
                ZStack {
                    Color.clear
                        .appGlass(.rect(cornerRadius: 26))
                    ActivityLockScreenCard(state: state)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                    .padding(16)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private var lightWallpaper: some View {
        LinearGradient(colors: [Color(hex: 0xE8D3C4), Color(hex: 0xC9B4A8),
                                Color(hex: 0x8E7F7A)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var midWallpaper: some View {
        LinearGradient(colors: [Color(hex: 0x6E7F8D), Color(hex: 0x3E4A56)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var darkWallpaper: some View {
        LinearGradient(colors: [Color(hex: 0x1B1B1F), Color(hex: 0x0A0A0C)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 品牌取色体检（脚手架，`SCREEN=colorCheck`）

/// 逐个品牌名打印「命中了哪一条 / resolvedFrom / ink / brandColor」，
/// 用来定位「同一品牌在 App 与小组件里颜色不同」这类只看界面永远查不出的问题。
struct ColorCheckView: View {

    private static let names = ["韵达快递", "圆通快递", "中通快递", "申通快递",
                                "丰巢", "兔喜生活", "菜鸟驿站", "欢猫驿站", "妈妈驿站"]

    @EnvironmentObject private var store: PickupStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // ① 真实待取记录：company / courier / codeColor 三者对照
                Text("真实待取记录（company ｜ courier → 码色）")
                    .font(.headline)
                ForEach(store.pending.prefix(6)) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(record.codeColor)
                                .frame(width: 26, height: 26)
                            Text(record.code.L).font(.system(size: 14, weight: .semibold, design: .monospaced))
                            Spacer()
                            Text("卡面")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                // 2026-10-30 起卡面与码同源（都跟第一行第一个字段），
                                // 这里直接复用 codeColor，不再调已废弃的 brandColor
                                .fill(record.codeColor)
                                .frame(width: 26, height: 26)
                        }
                        Text("company=\(record.company) / courier=\(record.courier ?? "nil")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }

                Text("品牌名 → 命中条目 → resolved / ink")
                    .font(.headline)
                ForEach(Self.names, id: \.self) { name in
                    let info = CourierBrand.info(for: name)
                    // 判定「是否命中」：输入串里含表项的 key 即算命中
                    // （原来比 info.name == name，「圆通快递」对「圆通速递」会误报兜底）
                    let hit = !info.key.isEmpty && name.contains(info.key)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: info.ink))
                                .frame(width: 26, height: 26)
                            Text(name.L).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(hit ? "命中" : "⚠️ 兜底")
                                .font(.system(size: 11))
                                .foregroundStyle(hit ? Color.secondary : Color.red)
                        }
                        Text("→ \(info.name) / key=\(info.key) / resolved=#\(String(format: "%06X", info.resolvedFrom)) / ink=#\(String(format: "%06X", info.ink))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            .padding(20)
        }
    }
}

#if DEBUG
// MARK: - 小组件状态回滚回归探针（SIMCTL_CHILD_ROLLBACK_PROBE=1）
//
// 老大 2026-11-16 提的四项重点验证：写入耗时、三端计数、杀进程/重启不丢、
// 大列表无负担。这里在**真实 App 进程**里跑完整竞态：
//   ① 模拟小组件在另一个进程改共享文件 + 追加轻量标记（并计时）
//   ② 把一份「旧内存」交给日志重放，验证护栏本身生效
//   ③ 模拟主 App 后台持有旧副本并发生一次写盘 —— 这是原来回滚发生的地方
//   ④ 重新读盘 = 模拟杀进程 / 重启
//   ⑤ 临时铺 500 条记录测 load 平均耗时，测完恢复
// 只在 DEBUG + 环境变量下跑，不影响正式运行。
@MainActor
private func runWidgetRollbackProbe(store: PickupStore) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let before = store.pending.count
        guard let target = store.pending.first else {
            print("[rollback-probe] ❌ 没有待取记录，跳过")
            return
        }

        // ① 小组件在别的进程写盘
        var disk = PickupStorage.load()
        guard let di = disk.firstIndex(where: { $0.id == target.id }) else { return }
        let stamp = Date()
        disk[di].isPickedUp = true
        disk[di].pickedUpAt = stamp
        disk[di].updatedAt = stamp
        PickupStorage.save(disk)
        let t0 = CFAbsoluteTimeGetCurrent()
        WidgetToggleJournal.append(id: target.id, picked: true, at: stamp)
        let journalCost = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        // ② 纯函数：旧内存经日志重放后应变成已取
        var stale = disk
        stale[di].isPickedUp = false
        stale[di].pickedUpAt = nil
        stale[di].updatedAt = nil
        let replayed = WidgetToggleJournal.applying(to: stale)[di].isPickedUp

        // ②b 对照实验：**绕过** reconcile 直接盲写旧副本（等价于修复前的 App 写盘）。
        //     磁盘文件本身会变回 44 条，但任何一处 load() 都会把标记重放回 43 ——
        //     证明护栏独立于「写前对齐」存在，也反证了原来的回滚确实来自这次盲写。
        PickupStorage.save(stale)
        // 裸读必须沿用 records 文件的日期策略（iso8601），否则 Date 字段解不出来会误报 -1
        let rawDecoder = JSONDecoder()
        rawDecoder.dateDecodingStrategy = .iso8601
        let rawFileCount = (try? rawDecoder.decode([PickupRecord].self,
                                                  from: Data(contentsOf: PickupStorage.fileURL)))?
            .filter { !$0.isPickedUp }.count ?? -1
        let afterReplayCount = PickupStorage.load().filter { !$0.isPickedUp }.count
        print("[rollback-probe] ②b 盲写旧副本：裸文件=\(rawFileCount) 经日志重放=\(afterReplayCount)")

        // ②c 连续 10 次追加（同一 id 去重）的平均耗时 —— 快速响应看的是这个数
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10 { WidgetToggleJournal.append(id: target.id, picked: true, at: stamp) }
        let appendAvg = (CFAbsoluteTimeGetCurrent() - t1) / 10 * 1000
        print("[rollback-probe] ②c 连续追加平均耗时 = \(String(format: "%.3f", appendAvg)) ms")
        // 对照实验把磁盘写回了旧副本，这里恢复成小组件刚写的正确状态
        PickupStorage.save(disk)

        // ③ 主 App 内存仍是旧副本，且发生一次写盘（didSet → persistSideEffects）。
        //    整体替换一次，避免三行各触发一次 didSet 造成中间态反复写盘。
        if let si = store.records.firstIndex(where: { $0.id == target.id }) {
            var old = store.records[si]
            old.isPickedUp = false
            old.pickedUpAt = nil
            old.updatedAt = nil
            store.records[si] = old
        }
        let afterMemory = store.pending.count
        let afterDisk = PickupStorage.load().filter { !$0.isPickedUp }.count
        let journalLeft = WidgetToggleJournal.load().count

        // ④ 模拟杀进程 / 重启：全新读盘
        let afterReboot = PickupStorage.load().filter { !$0.isPickedUp }.count

        // ⑦ 三端计数：桌面小组件读 WidgetSnapshot.pendingTotal、App 主页读
        //    store.pending、灵动岛由 sync(pending:) 拿共享盘过滤结果。
        //    三条路径都经过同一个 PickupStorage.load()，必须给出同一个数。
        let widgetCount = WidgetSnapshot.load().pendingTotal
        let appCount = store.pending.count
        let islandCount = PickupStorage.load().filter { !$0.isPickedUp }.count

        print("[rollback-probe] ① 初始待取 = \(before)")
        print("[rollback-probe] ② 追加轻量标记耗时 = \(String(format: "%.3f", journalCost)) ms")
        print("[rollback-probe] ③ 旧内存经日志重放 isPickedUp = \(replayed)")
        print("[rollback-probe] ④ 写盘后 内存=\(afterMemory) 磁盘=\(afterDisk) 剩余标记=\(journalLeft)")
        print("[rollback-probe] ⑤ 模拟重启后待取 = \(afterReboot)")
        print("[rollback-probe] ⑦ 三端计数：小组件=\(widgetCount) App主页=\(appCount) 灵动岛输入=\(islandCount)")
        let ok = afterMemory == before - 1 && afterDisk == before - 1
            && afterReboot == before - 1 && replayed
            && widgetCount == before - 1 && appCount == before - 1 && islandCount == before - 1
        print("[rollback-probe] 结论 = \(ok ? "✅ 无回滚" : "❌ 仍有回滚")")

        // ⑤ 大列表性能
        let backup = PickupStorage.load()
        var bulk: [PickupRecord] = []
        for i in 0..<500 {
            var copy = backup[0]
            copy.id = UUID()
            copy.code = "BULK-\(i)"
            bulk.append(copy)
        }
        PickupStorage.save(bulk)
        let b0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<20 { _ = PickupStorage.load() }
        let avg = (CFAbsoluteTimeGetCurrent() - b0) / 20 * 1000
        print("[rollback-probe] ⑥ 500 条记录 load 平均耗时 = \(String(format: "%.2f", avg)) ms")
        PickupStorage.save(backup)
    }
}
#endif

