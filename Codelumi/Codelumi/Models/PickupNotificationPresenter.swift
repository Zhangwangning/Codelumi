import Foundation
import UIKit
import UserNotifications

// MARK: ============================================================================
// 通知的前台呈现策略
//
// **前台一律不弹横幅**：App 就在眼前、列表实时更新了，再叠一条横幅是重复打扰
// （添加成功的反馈在 App 内已经有浮层提示）。真正需要横幅的是**后台**场景 ——
// 快捷指令自动化 / 截图动作被系统静默拉起时，用户正在别的 App 里。
//
// ⚠️ 与 `PickupNotifier` 分开放的原因：那边刻意不 import UIKit，好让
// `tools/notify-check/` 能在 macOS 上直接编译它做文案断言。UIApplication 只在这里用。
//
// ⚠️ 必须尽早 `install()`（见 `CodelumiApp.init`）：自动化触发时 App 是被系统
// **静默拉起**的，若 delegate 还没挂上，`willPresent` 不会被回调，前台抑制就失效了。
// ============================================================================

final class PickupNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = PickupNotificationPresenter()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler:
                                   @escaping (UNNotificationPresentationOptions) -> Void) {
        // applicationState 必须在主线程读
        DispatchQueue.main.async {
            let isForeground = UIApplication.shared.applicationState == .active
            // 前台：完全抑制（App 就在眼前，列表已更新）。
            // 非前台：只弹横幅 + 声音，**不加 `.list`** —— 加了会把通知塞进
            // 通知中心一直挂着（2026-11-11 主人：「过一会就消失」）。
            completionHandler(isForeground ? [] : [.banner, .sound])
        }
    }

    /// 用户点了通知 → 把 `recordID` 交给 `NotificationRouter`，由视图去打开详情
    /// （2026-10-25 补：此前只有 `willPresent`，`recordID` 写了却没人读）。
    ///
    /// 异步版本：iOS 15+ 若实现了 `didReceive ... async`，系统优先走它，
    /// 不必再写 completionHandler 那版。
    /// 🔴 用**闭包版**而不是 async 版：async 版本会被 Swift 并发桥接成 Task，
    ///    真机崩溃栈显示它是在 UIKit `_updateSnapshotAndStateRestoration…` 期间被调起的，
    ///    任何后续工作都会撞上事务断言（SIGABRT，用户看到"点通知黑屏/回桌面"）。
    ///    闭包版可以先调用 completionHandler 让 UIKit 收尾，再在下一轮主线程做跳转。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let raw = info["recordID"] as? String

        // 🔴 2026-11-05 真机崩溃（build 98）：
        //    在 didReceive 里**同步**改 @Published → 触发 UI 更新，
        //    而此刻 UIKit 正在做 `_updateSnapshotAndStateRestoration…`，
        //    于是抛出 NSAssertion 并 SIGABRT —— 用户看到的就是"点了通知，
        //    桌面一闪又回到主屏幕"。
        //    修法：**先返回、下一轮主线程再改状态**，绝不插进 UIKit 的恢复事务。
        let pendingID: UUID? = raw.flatMap(UUID.init(uuidString:))
        DiagnosticsLog.record("notify",
                              pendingID.map { "tapped record=\($0.uuidString.prefix(8))" }
                              ?? "tapped without recordID")

        // 先交还控制权，让 UIKit 走完状态恢复
        completionHandler()

        // 再跳到主线程、下一轮 runloop 改路由状态
        // 主人定稿（2026-11-05）：点通知只进「待取」列表，**不**自动弹某条卡片详情。
        // 锁屏上看完码就走的人，被推进详情页反而多一步返回。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationRouter.shared.requestPendingTab()
        }
    }
}
