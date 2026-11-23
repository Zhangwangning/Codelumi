import Foundation
import UserNotifications

// MARK: ============================================================================
// iOS 签名到期前提醒（2026-11-05）
//
// 免费 Apple ID 的描述文件 7 天到期后，App 直接打不开（系统拒绝启动）。
// 与其让用户某天突然发现"点不开了"，不如提前一天用本地通知提醒重装。
//
// 只做一件事：每次启动时把「到期前一天」的那条通知重排一次。
// 用固定 identifier，重复启动不会堆一堆提醒。
//
// ⚠️ 只有侧加载的包才有 embedded.mobileprovision；App Store 版返回 nil，
//    这里什么都不做。
// ============================================================================

enum SigningExpiryNotifier {

    private static let identifier = "codelumi.signingExpiry"
    /// 提前多久提醒
    private static let leadTime: TimeInterval = 24 * 3600

    /// 冷启动调用一次。没有描述文件 / 没授权 / 已过期 → 不做任何事。
    static func reschedule() {
        guard let expiry = SigningProfile.expirationDate else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let now = Date()
        guard expiry > now else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        // 到期前 24 小时；如果已经进入最后 24 小时，就 10 分钟后再提醒
        var fireDate = expiry.addingTimeInterval(-leadTime)
        if fireDate <= now {
            fireDate = now.addingTimeInterval(10 * 60)
        }

        let content = UNMutableNotificationContent()
        content.title = "Codelumi的 iOS 签名明天到期"
        content.body = "重新安装一次即可继续使用，取件记录不会丢。"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request) { error in
            DiagnosticsLog.record("signingNotify",
                                  error == nil
                                  ? "scheduled at=\(ISO8601DateFormatter().string(from: fireDate))"
                                  : "failed \(error!.localizedDescription)")
        }
    }
}
