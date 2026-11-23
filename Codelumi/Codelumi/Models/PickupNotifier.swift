import Foundation
import UserNotifications

// MARK: ============================================================================
// 添加取件信息后的本地通知
//
// 场景：快捷指令自动化把短信写进Codelumi时，用户多半**不在Codelumi里** —— 正在微信聊天、
// 正在刷别的 App。写进去了却没人知道，等于白收。所以每次真的新写入就发一条本地通知，
// 锁屏上一眼能读到取什么、去哪取。
//
// 版式口径（2026-09-21）
// ----------------------
// · **一条记录一条通知**，不做「已添加 N 条」的摘要。摘要把最该看的东西（取件码）
//   压成一句话，用户还得点开 App 才知道取什么 —— 通知的意义就没了。
//   一次来 5 条就发 5 条，靠 `threadIdentifier` 在通知中心折叠成一组，不会刷屏。
// · **三个字段占两行**（iOS 通知天然是「标题 + 正文」，正好一一对应）：
//       标题 = 「取件码 C-4082」              ← 重点，字最大
//       正文 = 「兔喜生活 | 舜耕中路…3栋104号」 ← 平台与地址**同一行**，用英文管道符分隔
//   标题**带上类别前缀**（取件码 / 运单号 / 尾号 / 特殊取件码）而不是只给一串数字：
//   「尾号 8823」和「取件码 8823」在驿站是两种报法，只给数字会让人报错。
//
// 🔴 **平台+地址为什么放正文、不放副标题**（实测结论，别改回去）：
//   副标题在通知里**只有一行且会截断**，实测「兔喜生活 | 舜耕中路恒大御府南门西侧3栋104号惠鲜果蔬店」
//   被砍成「兔喜生活 | 舜耕中路恒大御府南门西侧3栋…」—— 地址只剩一半，
//   等于没满足「通知要包含取件地址」。正文放得下就一行、放不下会自动折到第二行，
//   长地址（例子里 25 字）能完整显示。**宁可折行，不能丢字。**
// · **前台不弹横幅**：见同目录 `PickupNotificationPresenter.swift`。
//
// ⚠️ 本文件**刻意不 import UIKit** —— 这样 `tools/notify-check/` 才能在 macOS 上
// 直接编译它、断言三层文案的映射（通知在模拟器里没法自动点权限弹窗，只能靠脚本兜住）。
// 涉及 UIApplication 的呈现策略全部隔离在 `PickupNotificationPresenter`。
// ============================================================================

enum PickupNotifier {

    /// 同批通知的归组标识。多条一起进来时折叠成一组，而不是刷满通知中心。
    static let threadID = "com.jikezhang.codelumi.pickup"

    private static let enabledKey = "codelumi.notifyOnAdd"

    /// 是否在添加后发通知。默认开 —— 这是本 App 的核心闭环（人在别的 App 里也能收到）。
    ///
    /// 存 `UserDefaults.standard` 而不是 App Group：这是**表现层偏好**，小组件不读它；
    /// AppIntent 跑在 App 同一进程内，读到的也是同一份。
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // MARK: 权限闸门（2026-11-22，「关于 › 使用权限」）

    /// 用户**允许 App 用通知**吗。
    ///
    /// 语义比 `isEnabled` 高一层：`isEnabled` 管「添加后要不要弹一条」，
    /// 这里管「整个 App 允不允许用通知」。关掉后不再申请、不再排期、不再发送。
    static var isPermitted: Bool { PermGate.storedIsOn(.notifications) }

    /// 关掉通知权限时的收尾：把本 App 待发与已发的通知全部清掉。
    ///
    /// 🔴 只加 guard 不清场是不够的 —— 用户昨天排好的「超时未取」还会照常响，
    ///    关开关等于没关。
    static func suspendAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: 文案映射（纯函数，可被自检脚本直接调用）

    /// 取件平台与取件地址之间的分隔符。**英文管道符**（主人指定）。
    static let fieldSeparator = " | "

    /// 通知的文案。**取件码独占标题**，这是本功能唯一的硬要求。
    ///
    /// 返回 `(title, body)` 两段，对应通知的两行；平台与地址合并在 `body` 里，
    /// 用 `fieldSeparator` 分隔 —— 为什么不放副标题见文件头说明。
    ///
    /// 单独抽成纯函数而不是塞在 `makeRequest` 里，就是为了让 `tools/notify-check/`
    /// 能断言「三个字段有没有串位」。串位是这类通知最典型也最隐蔽的错误 ——
    /// UI 上完全看不出来，只有真收到通知才发现标题写着地址。
    static func notificationCopy(for record: PickupRecord) -> (title: String, body: String) {
        // 🔴 2026-10-28 主人：「所有地方都不再显示取件码信息的类型」——
        //    标题就是**码本身**，前面不加任何字（原来写「取件码 199480」，
        //    「取件码」三个字既是类型名之一、也是这张卡上根本不需要的解释）。
        //    通知头部的 App 名已经说明了这是什么东西，标题再把话说一遍就是噪音。
        //
        // 🔴 同日追加：「取件码后面如果有快递柜信息就加上，没有就空着」——
        //    到柜那一刻要知道去几号柜，这段跟着码走、不另起一行；
        //    柜位与货架取**先出现的那个**（柜优先，与小组件 `widgetLockerLabel` 同口径）。

        // 🔴 2026-10-28 主人定：**没识别到地址就不显示地址**。
        // 原来这里兜底成「未识别到取件地址」，等于把一句"我们失败了"钉在锁屏上 ——
        // 用户要的是取件码，缺字段就该整段消失，不是拿占位文案凑行。
        // 平台也空时正文留空，系统只显示标题（码），不留空行。
        let body: String = [record.company, record.address]
            .filter { !$0.isEmpty }
            .joined(separator: fieldSeparator)

        let locker = [record.locker, record.shelf]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? ""

        return (
            // 标题 = 码（+ 有就带的柜位/货架）。整条通知唯一被放大显示的一行。
            title: locker.isEmpty ? record.code : "\(record.code) \(locker)",
            body: body
        )
    }

    // MARK: 权限

    /// 申请通知权限。系统只会弹一次，之后再调是静默返回当前状态。
    ///
    /// 刻意**不在冷启动那一刻**弹：用户还没见过一条取件记录，不知道为什么要给通知权限，
    /// 弹出来只会被随手拒掉。调用点放在「看到待取件列表之后」（`PickupListView.onAppear`）
    /// 与设置页打开开关时。
    static func requestAuthorizationIfNeeded() {
        guard isEnabled, isPermitted else { return }
        // 截图脚手架：`SIMCTL_CHILD_SKIP_PERM=1` 一律不弹系统授权。
        // 以前只在 `PickupListView` 的调用点判断，可是首帧会先渲染待取页
        // （之后才按 `SCREEN=` 跳走），于是拍设置页时弹窗照样糊在屏幕上、
        // 又没有触摸注入通道能点掉。判断收到这里，任何调用路径都挡住。
        // 有 SCREEN 脚手架时也一律不弹：否则系统授权弹窗会盖住要截的页面
        let env = ProcessInfo.processInfo.environment
        guard env["SKIP_PERM"] == nil, env["SCREEN"] == nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    print("[codelumi] 通知授权失败：\(error.localizedDescription)")
                } else {
                    print("[codelumi] 通知授权 = \(granted)")
                }
            }
        }
    }

    /// 供设置页展示：系统层面的通知权限到底给没给。
    ///
    /// ⚠️ 必须有这条 —— App 内开关开着、系统权限却是关的，是这类功能最典型的
    /// 静默失效：用户以为通知坏了，其实就是被系统拦了。
    static func queryAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: 发送

    /// 新写入的记录 → 逐条发通知。
    ///
    /// 只在**真的新写入**时调用；被去重拦下的不发（否则用户会收到一条
    /// 「又收到一个已经存在的码」的通知，毫无价值）。
    static func notifyAdded(_ records: [PickupRecord]) {
        guard isEnabled, isPermitted, !records.isEmpty else {
            // 记一行「为什么没发」：排查「外部入库没收到通知」时，
            // 先看这里就知道是开关、权限，还是压根没调用（App 内录入不会调到这）。
            DiagnosticsLog.record("notify",
                                  "skip added=\(records.count) enabled=\(isEnabled) permitted=\(isPermitted)")
            return
        }
        DiagnosticsLog.record("notify", "added=\(records.count)")

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            // .provisional = 安静推送（不弹横幅、只进通知中心），也算能发
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            for record in records {
                center.add(makeRequest(for: record)) { error in
                    if let error {
                        print("[codelumi] 通知发送失败：\(error.localizedDescription)")
                    }
                }
                // 「入库 N 小时未取」的提醒**不在这里排** —— 它由
                // PickupStore.records didSet 的 diff 统一驱动（见 Models.swift
                // 的 syncReminders），增删改与撤销共用一条链路，不会漏也不会叠。
            }
        }
    }

    private static func makeRequest(for record: PickupRecord) -> UNNotificationRequest {
        let copy = notificationCopy(for: record)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        // 平台与地址合并成一行写在正文；**不要**再塞一个 subtitle ——
        // 副标题只有一行且会截断，会把地址吃掉（见文件头说明）。
        content.body = copy.body
        content.sound = .default
        // 同批折叠成一组（多条一起进来时不会刷满通知中心）
        content.threadIdentifier = threadID
        // ⚠️ 不要再设 `summaryArgument` —— 自 iOS 15 起系统已忽略它（会报 deprecation 警告），
        // 分组摘要现在由 `threadIdentifier` + 系统自身逻辑决定。
        // 点通知 → 直接打开这条记录的详情
        content.userInfo = ["recordID": record.id.uuidString]
        // trigger = nil → 立即送达
        return UNNotificationRequest(identifier: record.id.uuidString,
                                     content: content,
                                     trigger: nil)
    }

    // MARK: 已送达通知的清理
    //
    // 2026-11-11 主人：「通知要过一会就消失，而不是一直在通知栏中」。
    //
    // ⚠️ iOS **没有**「已送达通知到期自动消失」的公开 API —— `UNNotificationContent`
    //    没有 expiration，系统只会在用户手动清、或 App 主动 `removeDeliveredNotifications`
    //    时移除。所以能做的只有两件事：
    //      1. 回前台时清掉已经过时的（用户都在看列表了，通知中心不该再挂一串）；
    //      2. 记录被取走 / 删除时，立刻撤掉那一条。
    //    后台期间的通知只能等 App 下次前台才清 —— 这是系统限制，不是没做。

    /// 回前台调用：移除送达时间早于 `seconds` 的通知。
    static func clearDelivered(olderThan seconds: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let cutoff = Date().addingTimeInterval(-seconds)
            let stale = delivered.filter { $0.date < cutoff }.map(\.request.identifier)
            guard !stale.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    /// 记录被取走 / 删除时调用：撤掉这些记录对应的已送达通知。
    ///
    /// 两种标识都要撤：入库通知（= `recordID`）与「入库 N 小时未取」的提醒
    /// （= `pickupReminderPrefix + recordID`）。
    static func clearDelivered(for recordIDs: [UUID]) {
        guard !recordIDs.isEmpty else { return }
        let identifiers = recordIDs.flatMap { recordID in
            [recordID.uuidString, pickupReminderPrefix + recordID.uuidString]
        }
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - 取件提醒（定期 / 不定期）
    //
    // 两类提醒回答两个不同的问题：
    //   · **定期**（每天固定时间）——「今天还有没取的吗？」与单条记录无关，
    //     注册时数一遍当前待取件，0 条就不发（提醒人取空气是骚扰）。
    //   · **不定期**（入库 N 小时未取）——「这条怎么还没取？」与单条记录绑定，
    //     入库时按 N 小时排一条延时通知，标记已取 / 删除时撤掉。
    //
    // ⚠️ 延时通知排出去之后系统代管，App 内改数据时**必须主动撤**，
    //    否则会出现「已经取完了还收到催取提醒」的鬼故事。

    /// 定期提醒的通知标识（每次重排都用同一个，天然覆盖旧的那条）。
    private static let dailyReminderID = "com.jikezhang.codelumi.reminder.daily"

    /// 不定期提醒的通知标识前缀（完整标识 = 前缀 + recordID）。
    private static let pickupReminderPrefix = "com.jikezhang.codelumi.reminder.pickup."

    private static let dailyEnabledKey = "codelumi.reminderDailyEnabled"
    private static let dailyHourKey = "codelumi.reminderDailyHour"
    private static let dailyMinuteKey = "codelumi.reminderDailyMinute"
    private static let pendingEnabledKey = "codelumi.reminderPendingEnabled"
    private static let pendingHoursKey = "codelumi.reminderPendingHours"
    private static let repeatEnabledKey = "codelumi.reminderRepeatEnabled"
    private static let repeatHoursKey = "codelumi.reminderRepeatHours"
    private static let repeatSignatureKey = "codelumi.reminderRepeatSignature"
    /// 重复提醒**全局只有一条**（不是每条记录一条）；同 identifier 重排即覆盖。
    private static let repeatReminderID = "com.jikezhang.codelumi.reminder.repeat"

    /// 是否开启每天固定时间的取件提醒。默认关 —— 提醒是打扰性功能，让用户主动要。
    static var isDailyReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: dailyEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: dailyEnabledKey) }
    }

    /// 定期提醒的触发时刻（24 小时制）。默认 20:00 —— 晚饭后是收拾快递的高峰。
    static var dailyReminderHour: Int {
        get { UserDefaults.standard.object(forKey: dailyHourKey) as? Int ?? 20 }
        set { UserDefaults.standard.set(newValue, forKey: dailyHourKey) }
    }

    static var dailyReminderMinute: Int {
        get { UserDefaults.standard.object(forKey: dailyMinuteKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: dailyMinuteKey) }
    }

    /// 是否开启「入库 N 小时未取」提醒。默认关 —— 提醒是打扰性功能，让用户主动要。
    static var isPendingReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: pendingEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: pendingEnabledKey) }
    }

    /// 不定期提醒的等待时长（小时）。默认 24 —— 入库一整天没取，多半是真忘了。
    static var pendingReminderHours: Int {
        get { UserDefaults.standard.object(forKey: pendingHoursKey) as? Int ?? 24 }
        set { UserDefaults.standard.set(newValue, forKey: pendingHoursKey) }
    }

    /// 重复提醒（2026-11-16 主人新增）：开启后按「重复间隔」持续催，
    /// **直到所有待取件都取完自动停**。
    ///
    /// 与「超时未取」相互独立：超时那条只催一次，这条是周期性汇总提醒。
    /// 放在同一分组里只是位置上的从属，逻辑上不依赖超时开关是否打开。
    static var isRepeatReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: repeatEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: repeatEnabledKey) }
    }

    /// 重复间隔（小时）。默认 4；可选档位见 `NotificationSettingsView.repeatHourOptions`。
    static var repeatReminderHours: Int {
        get { UserDefaults.standard.object(forKey: repeatHoursKey) as? Int ?? 4 }
        set { UserDefaults.standard.set(newValue, forKey: repeatHoursKey) }
    }

    /// 重排（或撤销）每天固定时间的提醒。
    ///
    /// 调用时机：设置页改开关 / 改时间，以及 **App 每次进前台** ——
    /// 文案里「还有 N 件」是注册那一刻的快照，只有勤重排才能跟上数据。
    static func rescheduleDailyReminder() {
        let center = UNUserNotificationCenter.current()
        guard isDailyReminderEnabled, isPermitted else {
            center.removePendingNotificationRequests(withIdentifiers: [dailyReminderID])
            return
        }

        // 0 件待取就不排了：「今天没有待取件」不是提醒，是废话。
        // 已取的、被免费版裁掉的都不算 —— 与桌面小组件同一份底稿口径。
        let pending = PickupStorage.load().filter { !$0.isPickedUp }
        guard !pending.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: [dailyReminderID])
            return
        }

        var components = DateComponents()
        components.hour = dailyReminderHour
        components.minute = dailyReminderMinute

        let content = UNMutableNotificationContent()
        content.title = "还有 \(pending.count) 件待取件"
        // 正文点名最新那条 —— 提醒的价值在于让人不用打开 App 就知道去哪。
        let newest = pending.max { $0.receivedAt < $1.receivedAt }
        if let newest {
            // 空字段直接不出现（同 notificationCopy 口径）：不拼、也不留孤立分隔符
            let where_ = [newest.company, newest.address]
                .filter { !$0.isEmpty }
                .joined(separator: fieldSeparator)
            content.body = where_.isEmpty ? "打开Codelumi查看取件码" : "最新：\(where_)"
        } else {
            content.body = "打开Codelumi查看取件码"
        }
        content.sound = .default
        content.threadIdentifier = threadID

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: dailyReminderID,
                                         content: content,
                                         trigger: trigger))
    }

    // MARK: - 重复提醒（全局一条，直到全部取完）

    /// 重排「重复提醒」——全局一条 `repeats: true` 通知，按间隔催「还有 N 件待取」。
    ///
    /// 🔴 老大 2026-11-16 定的口径：**全局一条，直到全部取完自动停**，
    ///    不是每条记录各排一条（那样后台续排容易漏、取件后也撤不干净）。
    ///    数据变化 / 回前台都会调到这里，但只有「内容签名变了」才真的重排 ——
    ///    `repeats: true` 的 trigger 每次 add 都会重置计时，无脑重排会让提醒永远不触发。
    static func rescheduleRepeatReminder() {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        // 与超时提醒同属 Codelumi Pro；降级后下一次数据变化/回前台就撤干净
        guard isPermitted, isRepeatReminderEnabled, EntitlementSnapshot.licensedPro else {
            center.removePendingNotificationRequests(withIdentifiers: [repeatReminderID])
            defaults.removeObject(forKey: repeatSignatureKey)
            return
        }

        let pending = PickupStorage.load().filter { !$0.isPickedUp }
        guard !pending.isEmpty else {
            // 全部取完 = 自动停，不再排下一次
            center.removePendingNotificationRequests(withIdentifiers: [repeatReminderID])
            defaults.removeObject(forKey: repeatSignatureKey)
            return
        }

        let hours = repeatReminderHours
        let newest = pending.max { $0.receivedAt < $1.receivedAt }
        // 签名只含会改变通知内容/节奏的量：间隔、件数、最新一条的身份。
        // 单纯回前台时签名不变 → 不重置计时器。
        let signature = "\(hours)|\(pending.count)|\(newest?.id.uuidString ?? "")"
        guard defaults.string(forKey: repeatSignatureKey) != signature else { return }

        let content = UNMutableNotificationContent()
        content.title = "还有 \(pending.count) 件待取件"
        let where_ = [newest?.company ?? "", newest?.address ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: fieldSeparator)
        content.body = where_.isEmpty ? "打开Codelumi查看取件码" : "最新：\(where_)"
        content.sound = .default
        content.threadIdentifier = threadID
        content.userInfo = ["kind": "repeatReminder"]

        // repeats:true 最小间隔 60 秒；档位最小 1 小时，不会踩线
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600),
                                                        repeats: true)
        center.add(UNNotificationRequest(identifier: repeatReminderID,
                                         content: content,
                                         trigger: trigger))
        defaults.set(signature, forKey: repeatSignatureKey)
    }

    /// 给待取记录排（或重排）「N 小时未取」的提醒。
    ///
    /// 由 `PickupStore.records` didSet 的 diff 统一驱动（含本方法），
    /// 增删改与撤销共用一条链路。设置页改开关 / 改时长后调用
    /// `rescheduleAllPendingReminders` 全量对齐。
    static func schedulePendingReminder(for record: PickupRecord) {
        // 超时未取提醒是 **Codelumi Pro** 功能（2026-11-08 主人定）：
        // 非 Pro 一律不排期，并把已排的全部撤掉（降级后下一次进前台就清干净）。
        guard isPermitted, isPendingReminderEnabled, EntitlementSnapshot.licensedPro else { return }
        let hours = pendingReminderHours
        let content = UNMutableNotificationContent()
        content.title = "\(record.code) 还没取"
        // 空字段直接不出现（同 notificationCopy 口径）
        let where_ = [record.company, record.address]
            .filter { !$0.isEmpty }
            .joined(separator: fieldSeparator)
        content.body = where_.isEmpty
            ? "入库 \(hours) 小时了，记得去取"
            : "入库 \(hours) 小时了，记得去 \(where_)"
        content.sound = .default
        content.threadIdentifier = threadID
        content.userInfo = ["recordID": record.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600),
                                                        repeats: false)
        // 标识带 recordID：同一条记录重复入库（合并场景）时天然覆盖旧的那条。
        let request = UNNotificationRequest(identifier: pickupReminderPrefix + record.id.uuidString,
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// 记录被标记已取 / 删除时，撤掉它对应的「未取提醒」。
    static func cancelPendingReminder(for recordID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [pickupReminderPrefix + recordID.uuidString])
    }

    /// 不定期提醒设置变更后全量对齐：把当前所有待取记录的提醒按新配置重排。
    /// 关掉开关时撤掉全部在排的提醒。
    static func rescheduleAllPendingReminders() {
        let center = UNUserNotificationCenter.current()
        // 超时未取提醒是 **Codelumi Pro** 功能（2026-11-08 主人定）：
        // 非 Pro 一律不排期，并把已排的全部撤掉（降级后下一次进前台就清干净）。
        guard isPermitted, isPendingReminderEnabled, EntitlementSnapshot.licensedPro else {
            center.getPendingNotificationRequests { requests in
                let ids = requests.map(\.identifier).filter { $0.hasPrefix(pickupReminderPrefix) }
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
            rescheduleRepeatReminder()
            return
        }
        for record in PickupStorage.load().filter({ !$0.isPickedUp }) {
            schedulePendingReminder(for: record)
        }
        rescheduleRepeatReminder()
    }
}
