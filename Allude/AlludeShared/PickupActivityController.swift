import ActivityKit
import Foundation
import os

// MARK: ============================================================================
// 实时活动（锁屏 + 灵动岛）的生命周期控制
//
// 口径：开关打开时，实时活动**始终镜像当前待办**——有待办就起活动并更新，
// 一条不剩就结束；**不按单条待办去猜用户想不想看**。
//
// 🔴 **总开关（2026-09-23 主人要求新增）**：设置 → 实时活动页顶部一个开关。
//    默认**开启**（`LiveActivitySetting` 缺键即 true），老用户升级后行为不变。
//    关闭时：立刻收掉正在跑的活动，且此后不再起新的。
//    开关**必须同时在读侧门控**（`converge` 第 0 道门）—— 只在设置页隐藏入口
//    是不够的：勾选意图会在**扩展进程**里直接调本控制器，那里的界面根本没经过
//    设置页；漏掉读侧门控就等于「关了还在跑」。
//
// 更新时机（与桌面小组件的刷新触发点必须一致）：
//   1) `PickupStore.records` 写入（短信自动化 / 手动添加 / 勾选 / 删除）；
//   2) 桌面小组件勾选写回 —— App 回前台时走 store 的 `reloadFromStorage`；
//   3) **App 不在运行**时点了小组件的勾选框：由 `TogglePickupIntent` 直接调本控制器
//      （这就是本文件放在共享层而不是 App target 的原因：勾选动作在扩展进程里跑，
//       不把控制器共享出去，锁屏就会一直挂着那条已经被取走的码）；
//   4) App 冷启动时对齐一次（覆盖「活动还在、待办已被清空」这类残留）；
//   5) App 回前台时**无条件**对齐一次（2026-09-25 补）—— 见下方「单一性不变式」：
//      `reloadFromStorage` 只在内容签名真的变了才写 records，而「锁屏上多挂了一张
//      重复卡」这件事不改变任何数据，没有这一条就永远等不到收敛的机会。
//
// 🔴 **单一性不变式（2026-09-25）**：全系统内本类型的实时活动**恒为 0 或 1 个**。
//    · 写成 `0 或 1` 而不是 `1`：待办清空 / 开关关闭 / 非会员时本该是 0；
//    · 收敛链路本身必须串行（`sync` 的单飞 + 合并状态），否则「读列表 → 判断 → request」
//      这段非原子读-判-写会被两个重叠的调用各自执行一遍，**各起一张卡**；
//    · 每次收敛的出口都要 `enforceSingle` 清掉多余者 —— 这是唯一能同时兜住
//      「进程内重叠」「扩展进程与 App 各起一张」「App 被杀重启后账本未同步完」
//      这三类来源的手段。
//    · 回归取证：`SCREEN=activityRace`（模拟器，需同时注入 `PLAN=yearly` ——
//      实时活动是 VIP 权益，免费档会被第 1 道门 `endAll` 收掉，从而看不出问题）。
//
// ⚠️ 本文件在 App 与小组件扩展**两个 target** 里编译，因此只允许引用共享层类型
//    （PickupRecord / CourierBrand），不得引用 PickupStore。
//    ActivityKit 是扩展安全框架，`Activity.request` 在扩展进程里同样可用；
//    万一系统拒绝（例如从扩展里首启活动），下面有 catch 兜住，不影响勾选本身。
// ============================================================================

enum PickupActivityController {

    // MARK: - 进程内串行化（🔴 2026-09-25 主人反馈「锁屏有时出现两张卡」）

    /// 最近一次请求的待办快照，以及「是否已有收敛任务在跑」。
    ///
    /// 🔴 **为什么必须有这两个状态**：`sync` 原本每次调用都新起一个独立 Task，
    ///    而 `converge` 的「读活动列表 → 判断有没有 → request/update」是**非原子**的
    ///    读-判-写。两次 sync 重叠时（真实形态：一条短信到达时 `records` 的 `didSet`
    ///    与 App 被静默拉起后 `scenePhase` 转 `.active` 的 `reloadFromStorage`
    ///    挤在同一秒里），两边**都会读到空列表**，于是各 request 一张 ——
    ///    锁屏上就是并列两张卡。
    ///
    ///    模拟器实测（`SCREEN=activityRace`，账本清空后 24 个并发 sync）
    ///    **稳定复现出 3 张**；修复后恒为 1 张。
    ///
    /// 这两个状态放 `@MainActor` 而不是加锁：所有调用点本来就在主 actor 上
    /// （records 的 `didSet`、App Intent 的 `perform`、设置页开关），
    /// 用 actor 隔离既省掉一把锁，又让「读判写」天然串行。
    @MainActor private static var latest: [PickupRecord]?
    @MainActor private static var converging = false

    /// 是否运行在**主 App 进程**（小组件 / 锁屏扩展里恒为 false）。
    ///
    /// 🔴 2026-11-16 状态回滚专项：扩展进程**不能** `Activity.request`
    ///    （系统直接拒），却可以 `end` 掉 App 起的那张。下面 `apply` 的
    ///    「进程首帧强制重建」原本在两个进程都会跑，于是用户在桌面小组件
    ///    点一下勾选 → 扩展 endAll → request 被拒 → 灵动岛要么消失、要么
    ///    停在旧数量。只有 App 进程有权重建；扩展只做 `update`。
    ///    App 启动时注入 true（见 `AlludeApp.init`）。
    nonisolated(unsafe) static var isAppProcess = false

    /// 🔴 **进程内首次收敛强制 update 一次**（2026-10-28）。
    ///
    /// 为什么必须有：`apply` 原本「内容与目标一致就跳过 update」是为了省 ActivityKit
    /// 的更新预算，可它也把**视图代码的改动**一起挡掉了 —— 重装 / 升级 App 之后
    /// widget extension 换了新代码，但 `content.state` 一个字节都没变，
    /// 于是系统认为"无事发生"、不重新渲染，灵动岛和锁屏卡会**一直停在旧样式**上。
    /// 主人 2026-10-28 连续两轮反馈「这不是还是没改吗」「图标和待取数量被遮挡」，
    /// 看到的其实都是重装前的旧画面 —— 就是这个判断造成的。
    ///
    /// 每个进程只强刷一次：App 每次冷启动/被系统拉起都会重置它，
    /// 而同一进程内的后续调用仍走"内容一致就不刷"的省预算路径。
    ///
    /// ⚠️ `nonisolated(unsafe)` 的理由：只有 `converge` 这条链读写它，
    ///    而 `sync` 的单飞保证同一时刻只有一条收敛链在跑（见上方注释），
    ///    因此不存在并发写。标成 `@MainActor` 反而编译不过 ——
    ///    `apply` 是 nonisolated 的 async 函数。
    nonisolated(unsafe) private static var needsForcedRender = true

    /// 当前待办变化时调用。内部起 Task 收敛，调用方（store 的 didSet / 勾选意图）不等待。
    ///
    /// 🔴 **单飞 + 合并**：已有收敛在跑时，本次只把最新待办记下就返回 ——
    ///    正在跑的那一轮收尾前会拿最新值再跑一遍。于是无论调用多密集，
    ///    任一时刻**只有一条收敛链**在动，`converge` 不可能与另一个自己重叠。
    /// 待办列表的提供者（App 侧注入）。锁屏卡翻页要用它按当前顺序取上/下一条。
    /// 共享层拿不到 `PickupStore`（在 App target），所以走注入，与
    /// `stationResolver` 同一套路；扩展进程里为 nil，翻页自然变成空操作。
    nonisolated(unsafe) static var pendingProvider: (() -> [PickupRecord])?

    /// 把一条记录装配成活动状态（原 converge 里的映射，抽出来给翻页复用）
    static func state(for record: PickupRecord,
                      pendingCount: Int,
                      items: [PickupActivityAttributes.Item]? = nil) -> PickupActivityAttributes.ContentState {
        let stationName = stationResolver?(record)
        let nameSource = PickupNaming(courier: record.courierDisplay,
                                      platform: record.company,
                                      station: stationName).iconSource
        return PickupActivityAttributes.ContentState(
            item: .init(id: record.id.uuidString,
                        company: record.company,
                        courier: record.courier,
                        station: stationName,
                        code: record.code,
                        address: record.address,
                        tint: CourierBrand.info(for: nameSource).inkOnDark,   // 深色玻璃底 → 用提亮版（2026-11-22）
                        locker: record.widgetLockerLabel(WidgetDisplayOptions.full)),
            pendingCount: pendingCount,
            items: items,
            // App 图标的选择随状态一起过进程边界（详见 `ContentState.appIconRaw`）
            appIconRaw: AppIconStore.current.rawValue
        )
    }

    /// 单条记录 → 活动条目（与 `state(for:)` 同一口径，翻页时复用）
    static func mapToItem(_ record: PickupRecord) -> PickupActivityAttributes.Item {
        let stationName = stationResolver?(record)
        let nameSource = PickupNaming(courier: record.courierDisplay,
                                      platform: record.company,
                                      station: stationName).iconSource
        return PickupActivityAttributes.Item(
            id: record.id.uuidString,
            company: record.company,
            courier: record.courier,
            station: stationName,
            code: record.code,
            address: record.address,
            tint: CourierBrand.info(for: nameSource).inkOnDark,   // 深色玻璃底 → 用提亮版（2026-11-22）
            locker: record.widgetLockerLabel(WidgetDisplayOptions.full))
    }

    /// 锁屏卡的「上一页 / 下一页」：一页三条，整页整页地翻。
    ///
    /// 由 App Intent 在**后台**调用（App 不必打开）。只允许一个活动实例，
    /// 所以直接 update 当前那张，不新建。
    static func cycle(offset: Int) async {
        // 🔴 不依赖 App 进程：翻页 Intent 可能跑在**小组件扩展**里（那里没有 PickupStore）。
        //    共享层本来就能读 App Group 里的记录文件，直接用它兜底。
        let all = pendingProvider?() ?? PickupStorage.load().filter { !$0.isPickedUp }
        let pending = all
        guard pending.count > 1 else { return }
        // 🔴 2026-11-23 老大：「锁屏卡片的顺序和待取页面保持一致」。
        //    以前这里自己按 `receivedAt` 排，和待取页（`lastNotifiedAt` + 分组口径）
        //    是两套。直接复用页面那套 `PickupSortLogic.sort`，读同一个排序设置 ——
        //    用户在待取页选「按驿站」，锁屏卡也按驿站；选「最近收到」，就按最近收到。
        let sorted = PickupSortLogic.sort(pending, mode: PickupStorage.listSort)
        guard sorted.count > 1 else { return }
        guard let current = Activity<PickupActivityAttributes>.activities.first else { return }

        // 🔴 2026-11-23 老大：「在取件码信息下方增加切换按钮，可以切换上一个/下一个，
        //    **不是循环切换**」。所以这里一次走一条、到头就停，不再整页翻、也不回绕。
        let anchorID = current.content.state.item.id
        let index = sorted.firstIndex { $0.id.uuidString == anchorID } ?? 0
        let target = min(max(index + offset, 0), sorted.count - 1)
        guard target != index else { return }

        // 卡片底部要显示「第几件 / 共几件」，把有序列表整份带过去（与首次构建同口径）。
        let records = sorted.prefix(12).map { mapToItem($0) }
        let head = records[target]
        let newState = PickupActivityAttributes.ContentState(
            item: head, pendingCount: sorted.count, items: Array(records),
            // 翻页可能跑在扩展进程里，那里读不到 App 的偏好 ——
            // 优先**沿用当前活动里已经带着的**那套图标，别在翻页时把它翻回默认值。
            appIconRaw: current.content.state.appIconRaw ?? AppIconStore.current.rawValue)
        guard newState != current.content.state else { return }
        await current.update(ActivityContent(state: newState, staleDate: nil))
    }

    /// 用户换了 App 图标之后，让灵动岛 / 锁屏**立刻**跟着换（2026-11-15）。
    ///
    /// 图标本身是 App 调 `UIApplication.setAlternateIconName` 换掉的（桌面、多任务、
    /// 通知一起变），但实时活动的画面由 **widget 扩展**独立绘制 —— 只有
    /// `ContentState` 变了系统才会重绘。所以这里把新选择塞进现有活动再 update 一次。
    ///
    /// 只在 **App 进程**调用（`AppIconSettingsView.apply`）；扩展进程不需要这条路。
    static func refreshForAppIconChange() async {
        let raw = AppIconStore.current.rawValue
        for activity in Activity<PickupActivityAttributes>.activities {
            var state = activity.content.state
            guard state.appIconRaw != raw else { continue }
            state.appIconRaw = raw
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// 取件码**外观**变了，重画所有在跑的实时活动（灵动岛 / 锁屏卡）。
    ///
    /// 🔴 外观设置存在 App Group 里、由小组件扩展渲染，**不在 `ContentState` 中**；
    ///    `WidgetCenter.reloadAllTimelines()` 管不到 ActivityKit 的活动，而
    ///    `sync(pending:)` 看的是待取件列表，列表没变会被"内容一致就跳过"挡掉。
    ///    所以这里直接对每张活动调一次 update —— state 原样回传，只为触发视图重建。
    ///    ⚠️ 只在 **App 进程**调用（设置页）；扩展进程不要走这条路。
    static func refreshRendering() async {
        guard isAppProcess else { return }
        for activity in Activity<PickupActivityAttributes>.activities {
            await activity.update(ActivityContent(state: activity.content.state,
                                                  staleDate: nil))
        }
    }

    static func sync(pending: [PickupRecord]) {
        Task { @MainActor in
            latest = pending
            // 已有收敛在跑：它会在 while 循环里消费这个最新值，这里直接返回
            guard !converging else { return }

            converging = true
            while let next = latest {
                latest = nil
                await converge(to: next)
            }
            converging = false
        }
    }

    /// 收掉当前所有活动（最多只有一个，但按集合写更耐改）。
    ///
    /// 🔴 三处调用点共用：开关关闭、非会员、待办清空 —— 之前是三段重复代码，
    ///    将来再加一道门时容易漏掉其中一处。
    private static func endAll() async {
        for activity in Activity<PickupActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 🔴 **单一性不变式**：全系统内只允许存在一个实时活动。
    ///
    /// 保留优先级：① 内容与目标 `state` 一致的 → ② 列表里第一个；其余一律
    /// `.immediate` 收掉。多个待收时必须逐个 `await`（`Activity.end` 是异步的，
    /// 并发调用会撞 ActivityKit 的内部状态）。
    ///
    /// 为什么「收敛成功」还不够、非要每次出口都清一遍：
    ///   · 修复前的实测（`SCREEN=activityRace` 阶段 D）：**重复卡一旦产生就永不消失**
    ///     —— `converge` 只 `update(activities.first)`，其余活动既不会被更新、
    ///     也不会被收掉，会一直挂在锁屏上直到用户把件取完才随 `endAll` 一起退场。
    ///   · 这条清理由此成为**兜底**：无论重复来自进程内重叠、扩展进程与 App 各起
    ///     一张、还是 App 被杀重启后 ActivityKit 账本尚未同步完（读到空列表于是
    ///     又 request 一张），任何一次 sync 都会把它收敛回 1 张。
    ///
    /// ⚠️ 已知边角（**刻意不处理**）：两个进程若几乎同时 request 又同时清理，
    ///    理论上可能各自收掉对方那张、最终变成 0 张。要做到绝对互斥需要跨进程
    ///    文件锁（`O_CREAT|O_EXCL` + 过期时间），代价是一把锁的全部风险
    ///    （陈旧锁、死锁、扩展进程被杀）。权衡结果：**「两张卡」是主人明确投诉的
    ///    问题，必须彻底收掉**；而 0 张的窗口极短且下次 sync（回前台/数据变动）
    ///    会立刻重建，用户几乎无感 —— 何况下面新增了回前台的无条件对齐入口。
    /// 驿站名解析器 —— 由 App 启动时注入。
    ///
    /// `StationDirectory` 住在 App target（扩展进程里没有那份数据），
    /// 而 ContentState 要在共享层构造，所以用闭包把能力传进来。
    /// App 没注入时恒为 nil：卡面首行只显示快递公司，不会崩、不会显示空。
    nonisolated(unsafe) static var stationResolver: ((PickupRecord) -> String?)?

    private static func enforceSingle(preferring state: PickupActivityAttributes.ContentState) async {
        let list = Activity<PickupActivityAttributes>.activities
        guard list.count > 1 else { return }

        let keeper = list.first { $0.content.state == state } ?? list[0]
        for activity in list where activity.id != keeper.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 🔴 **延迟复查**（2026-09-25 补，针对主人截图里两张卡**取件码不同**这一现场证据）。
    ///
    /// 截图放大读出来的两张卡是 `118-5-6178` 与 `110-5-6178` —— **号码不同**，
    /// 说明它们不是「同一刻并发起的两张」，而是**两次不同时刻各起一张**：
    /// 第一条短信起了活动 A；第二条短信到达时，App 走到了一个**账本还没同步完
    /// 的进程**里（被系统回收后重新拉起 / 扩展进程），`Activity.activities`
    /// 读到空列表 → 于是又 request 出活动 B。A 冻结在旧内容上，就成了那张
    /// 「停在 118-5-6178 的幽灵卡」。
    ///
    /// 这类「迟到的旧活动」有个要命的特点：**刚 request 完立刻查账本往往还看不到
    /// 它**（同步延迟），于是 `enforceSingle` 当场查不出多余者。所以必须在
    /// 一个心跳之后**再查一次** —— 否则两张卡要等到用户下一次操作（新短信 /
    /// 勾选 / 回前台 / 冷启动）才会被收敛，而他很可能就停在那两张卡上不动了。
    ///
    /// 延迟期间本进程的收敛链保持忙碌，这没问题：`sync` 的「单飞 + 合并」会把
    /// 期间到达的调用折叠成最新值，等下一轮消费（见 `sync` 的注释）。
    private static func settle(_ state: PickupActivityAttributes.ContentState) async {
        await enforceSingle(preferring: state)
        try? await Task.sleep(for: .milliseconds(1200))
        await enforceSingle(preferring: state)
    }

    private static func converge(to pending: [PickupRecord]) async {
        Logger(subsystem: "com.jikezhang.allude", category: "liveActivity")
            .notice("converge pending=\(pending.count, privacy: .public) enabled=\(LiveActivitySetting.isEnabled, privacy: .public) pro=\(EntitlementSnapshot.licensedPro, privacy: .public) auth=\(ActivityAuthorizationInfo().areActivitiesEnabled, privacy: .public)")
        // 🔴 第 0 道门 = **用户自己的总开关**（设置 → 实时活动）。
        //    放在 VIP 判定之前：这是用户意志，优先级高于会员权益 ——
        //    一个主动关掉实时活动的年费会员，不该因为"他是会员"又被起一张卡。
        guard LiveActivitySetting.isEnabled else {
            await endAll()
            return
        }

        // 🔴 实时活动 / 灵动岛是 **Codelumi Pro 权益**，免费版不支持。
        //    免费版口径：有活动在跑也一律收掉，且不再起新的 ——
        //    升级 / 降级后下一次数据同步自动对齐，不需要专门的开关刷新。
        //
        // 🔴🔴 必须用 `licensedPro`（2026-11-15 修）：它会把 `expiresAt` 算进去，
        //     `load().isPro` **只看快照里那个布尔值、不看到期时间** ——
        //     订阅到期后快照仍写着 true，卡片就会一直挂着，
        //     用户看到的是「Pro 已经过期了，锁屏/灵动岛还在给完整版服务」。
        guard EntitlementSnapshot.licensedPro else {
            await endAll()
            return
        }

        // 用户可能在系统设置里关掉了实时活动，此时任何 request 都会抛错，
        // 先看一眼开关，避免每次数据变动都去撞一次错误。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // 一条待办都没有 → 收掉活动，别让锁屏挂着一张过期的取件码
        // 🔴 2026-11-23 老大：「锁屏卡片的顺序和待取页面保持一致」。
        //    以前这里自己按 `receivedAt` 排，和待取页（`lastNotifiedAt` + 分组口径）
        //    是两套。直接复用页面那套 `PickupSortLogic.sort`，读同一个排序设置 ——
        //    用户在待取页选「按驿站」，锁屏卡也按驿站；选「最近收到」，就按最近收到。
        let sorted = PickupSortLogic.sort(pending, mode: PickupStorage.listSort)
        guard let newest = sorted.first else {
            await endAll()
            return
        }

        // 驿站名由 App 侧注入的解析器给出（StationDirectory 在 App target，
        // 共享层拿不到）。取不到就为 nil，卡面首行自然只剩「快递公司」。
        let stationName = stationResolver?(newest)

        // 取色来源必须与卡面主名**完全同源**（统一走 PickupNaming）：
        // 图标与取件码都用这个色，两处不同源就会「图标是圆通橙、码却是拼多多红」。
        let nameSource = PickupNaming(courier: newest.courierDisplay,
                                      platform: newest.company,
                                      station: stationName).iconSource

        let state = PickupActivityAttributes.ContentState(
            item: .init(id: newest.id.uuidString,
                        company: newest.company,
                        // 承运方一起送过去：锁屏 / 灵动岛的主名与取色都按
                        // 「快递公司 > 短信平台」取，与 App 内卡面同口径（2026-10-25 修）
                        courier: newest.courier,
                        // 首行「快递公司｜快递驿站」的右半边（2026-10-28）
                        station: stationName,
                        code: newest.code,
                        address: newest.address,
                        tint: CourierBrand.info(for: nameSource).inkOnDark,   // 深色玻璃底 → 用提亮版（2026-11-22）
                        // 柜位 / 货架：跟随用户在小组件里选的显示设置
                        // （关掉「显示快递柜/货架」时这一位不出现，两处口径一致）
                        locker: newest.widgetLockerLabel(WidgetDisplayOptions.full)),
            // 锁屏卡要一页三条、右侧翻页（2026-11-08 主人定）：
            // 一次性送最近 12 条（四页），翻页在扩展里本地完成，不必再唤醒 App。
            pendingCount: pending.count,
            items: Array(sorted.prefix(12)).map { mapToItem($0) },
            // App 图标的选择随状态一起过进程边界：扩展进程不再自己去读偏好域，
            // 从根上杜绝「桌面换成了快递箱、灵动岛还是 C 标」（2026-11-15 修）。
            appIconRaw: AppIconStore.current.rawValue
        )

        await apply(state)
        await settle(state)
    }

    /// 把活动调整到目标 `state`（不负责清理多余者 —— 那是 `settle` 的活）。
    private static func apply(_ state: PickupActivityAttributes.ContentState) async {
        // 🔴 本进程第一次收敛：**结束旧活动、整张重建**。
        //
        // 为什么不是 update：`update` 只改数据，系统会用**已缓存的视图快照**
        // 重画；widget extension 换了代码（重装/升级 App）时它照样拿旧快照，
        // 于是"改了没生效"。主人 2026-10-28 连问三次「还是没变」，全程都是这个原因。
        // `end + request` 会走一遍全新的视图构建，是唯一能保证换代码就换画面的路径。
        //
        // 每进程只做一次：`needsForcedRender` 用完即置 false，之后的调用
        // 仍走原来省预算的 update 路径，不会频繁重建。
        // 🔴 2026-11-16：强制重建**只允许 App 进程**做。
        //    扩展里 endAll 会把灵动岛收掉、随后的 request 又会被系统拒绝，
        //    结果就是「小组件显示 4、灵动岛还挂着 5」甚至整张卡消失。
        let force = needsForcedRender && isAppProcess
        needsForcedRender = false
        if force, !Activity<PickupActivityAttributes>.activities.isEmpty {
            await endAll()
            // ActivityKit 的 end 是异步的，账本要一点时间才反映出来；
            // 不等就 request，会撞上"已有活动"而被系统拒。
            try? await Task.sleep(for: .milliseconds(500))
        }

        // 🔴 保留策略的顺序很重要：**先认「内容已经对上的那张」**。
        //    并发产生的重复里，可能有一张是更新过的、一张停在旧内容上；
        //    若一律保留 `activities.first`，就会把内容正确的那张收掉、
        //    留下一张过期卡（锁屏上显示的还是旧取件码）。
        let list = Activity<PickupActivityAttributes>.activities

        if list.contains(where: { $0.content.state == state }) {
            // 内容已经一致：不重复 update（ActivityKit 的更新有预算，省着用）
            await enforceSingle(preferring: state)
            return
        }

        if let existing = list.first {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            await enforceSingle(preferring: state)
            return
        }

        // 扩展进程不负责起活动：ActivityKit 只允许主 App `request`。
        // 这里直接交回给 App（回前台时 `sync` 会重建），避免白撞一次系统拒绝。
        guard isAppProcess else { return }

        // 一个都没有 → 起一个（本 App 的语义就是「一个取件码待办清单」，
        // 全系统只允许存在一个活动）
        do {
            let activity = try Activity.request(attributes: PickupActivityAttributes(),
                                                content: ActivityContent(state: state, staleDate: nil),
                                                pushType: nil)
            Logger(subsystem: "com.jikezhang.allude", category: "liveActivity")
                .notice("requested id=\(activity.id.prefix(8), privacy: .public)")
            await enforceSingle(preferring: state)
        } catch {
            // 起不来不该影响主流程（数据已落库、通知已发），只记一笔。
            // 🔴 必须带**错误原文**：ActivityKit 对 request 有频率节流，被拒时若只记
            //    「没起来」，排查时会把它误读成"收敛生效了"。走 `os.Logger` 而不是
            //    裸 `print` —— 真机上 print 只有在 Xcode 挂着时才看得到，而现场
            //    （锁屏重复卡）恰恰发生在没连调试器的时候：
            //      log stream --predicate 'subsystem == "com.jikezhang.allude"'
            Logger(subsystem: "com.jikezhang.allude", category: "liveActivity")
                .error("live activity request failed: \(error, privacy: .public)")
            Logger(subsystem: "com.jikezhang.allude", category: "liveActivity")
                .error("request-failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - 总开关

/// 「实时活动」的总开关（设置 → 实时活动页顶部）。
///
/// 存 **App Group**，理由是读侧在**两个进程**里都要成立：
///   · App 进程：设置页改了开关要立刻生效；
///   · 扩展进程：`TogglePickupIntent`（桌面/锁屏小组件上勾选）会直接调
///     `PickupActivityController.sync` —— 那条路径完全不经设置页，
///     若开关只存在 App 的 standard defaults 里，关闭后小组件一勾选
///     又会把活动起回来。
///
/// 🔴 缺键 = **开启**：老用户升级到本版本时 App Group 里没有这个键，
///    必须保持"始终镜像待办"的原有行为，不能因为读不到就静默关掉。
///    因此这里用 `object(forKey:) as? Bool` 判空，而不是 `bool(forKey:)`
///    （后者对缺键返回 `false`，会把所有老用户的实时活动关掉）。
enum LiveActivitySetting {

    private static let key = "allude.liveActivity.enabled"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    /// 🔴 实时活动是 **Codelumi Pro** 功能：非订阅用户一律读作关闭
    /// （即使文件里还留着 true —— 降级后进前台，控制器第 0 道门会当场收掉卡片）。
    static var isEnabled: Bool {
        get {
            guard EntitlementSnapshot.licensedPro else { return false }
            return (defaults.object(forKey: key) as? Bool) ?? true
        }
        set { defaults.set(newValue, forKey: key) }
    }
}
