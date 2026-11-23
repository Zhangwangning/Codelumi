import UIKit
import UserNotifications

// MARK: ============================================================================
// 最小的 AppDelegate（2026-11-05）
//
// 为什么还要它：通知被点击时，如果 App 已经被系统终止，iOS 会**先**把 App
// 拉起来、再回调 `UNUserNotificationCenter` 的 delegate。SwiftUI 的 App.init
// 虽然也会跑，但它和"delegate 必须在启动早期就位"之间没有强保证 ——
// 实测出现过"点了通知，App 打开了但看不到跳转，甚至像没反应"。
//
// 现在把 delegate 挂到 didFinishLaunching 里（比任何 SwiftUI 视图都早），
// 并且把点击事件写进诊断日志，便于以后复现取证。
// ============================================================================

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                        [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 这里只设置 delegate，真正的处理逻辑仍收在 PickupNotificationPresenter，
        // 避免两处各写一套判定。
        PickupNotificationPresenter.shared.install()
        // 本地通知不需要读 launchOptions（`.remoteNotification` 在 iOS 26 已弃用）；
        // 点击事件的 userInfo 由 delegate 的 didReceive 统一处理。
        return true
    }
}
