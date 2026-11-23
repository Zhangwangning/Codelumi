import Foundation
import SwiftUI
import UIKit
import UserNotifications

// MARK: ============================================================================
// 通知点击 → 打开对应记录（2026-10-25）
//
// 背景：`PickupNotifier` 早就在通知的 `userInfo` 里写了 `recordID`
// （入库通知与「N 小时未取」提醒都有），注释也写着「点通知直接打开这条记录」，
// 但**全工程没有 `didReceive` 实现、也没有 URL Scheme** —— 点通知只会回到
// 首屏，`recordID` 是个从头到尾没人读的死字段，记录一多用户还得自己再找一遍。
//
// 这里补上闭环：
//   · `PickupNotificationPresenter.didReceive` 解析出 id → 写进 `NotificationRouter`；
//   · `RootView` 监听它，切到记录所在的标签（待取 / 已取）；
//   · 列表页监听它，把那条记录推进自己的导航栈并清空，避免重复触发。
//
// 为什么用单例 + @Published 而不是 delegate 闭包：通知点击可能发生在 App
// 还没启动完的时候（冷启动），delegate 回调早于视图构建，必须先落状态、
// 由视图起来后再消费。
// ============================================================================

final class NotificationRouter: ObservableObject {

    static let shared = NotificationRouter()

    /// 待消费的记录 id。列表页处理完必须置 nil。
    @Published var pendingRecordID: UUID?
    /// 通知没有具体记录（例如每日提醒）时，也要把界面切回「待取」
    @Published var shouldShowPendingTab = false

    private init() {}

    /// 没有具体记录的通知被点击 → 请求切到待取标签
    func requestPendingTab() {
        shouldShowPendingTab = true
    }

    /// 冷启动时 delegate 已经把 id 存下了，视图首帧就该消费它
    func takePendingRecordID() -> UUID? {
        defer { pendingRecordID = nil }
        return pendingRecordID
    }
}
