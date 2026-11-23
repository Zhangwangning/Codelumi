import AppIntents
import ActivityKit
import WidgetKit
import Foundation

// MARK: ============================================================================
// 锁屏卡的「上一件 / 下一件」（2026-11-05）
//
// Live Activity 从 iOS 17 起支持交互：卡面上的 `Button(intent:)` 被点后，
// 系统会**在后台**执行这个 App Intent，不需要打开 App，也不需要解锁。
//
// 🔴 必须实现 **`LiveActivityIntent`**（不是普通 `AppIntent`）：
//    苹果对「实时活动里的按钮」有专门约束 —— 只有实现该协议的意图，
//    系统才会在点击时把请求交给 App 执行。用普通 AppIntent 时按钮可点、
//    但 `perform()` 永远不会被调用（2026-11-05 真机实测：App Group 里
//    连一条诊断记录都写不出来）。
//
// 放在 shared 层：卡面视图（编译进小组件扩展）要能引用到这两个类型。
// 真正干活的数据（PickupStore）在 App target，控制器通过 `pendingProvider`
// 注入 —— 扩展进程里没有这份数据，点了就是空操作，不会崩。
// ============================================================================

/// 临时诊断：翻页 Intent 到底有没有被调用、跑在哪个进程（写 App Group，App 与扩展都能读）
enum IntentDebug {
    private static let file = "intent-debug.log"
    private static var url: URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PickupStorage.appGroupID) else { return nil }
        return base.appendingPathComponent(file)
    }
    static func trace(_ line: String) {
        guard let url else { return }
        let text = "[\(ISO8601DateFormatter().string(from: Date()))] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct NextPickupIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "显示下一件待取" }
    static var description: IntentDescription {
        IntentDescription("在锁屏实时活动里切换到下一件待取快递。")
    }
    // 🔴 不要在这里写 `supportedModes = .background`：
    //    真机实测（2026-11-05，build 107）锁屏卡上的按钮点了**完全没反应**，
    //    诊断文件里连一条记录都没写 —— 说明 Intent 根本没被执行。
    //    小组件/实时活动里的交互按钮要求 Intent 处于可交互执行目标，
    //    声明 background-only 会被系统静默忽略。这里保持默认。

    func perform() async throws -> some IntentResult {
        IntentDebug.trace("next tapped; provider=\(PickupActivityController.pendingProvider != nil) "
                          + "activities=\(Activity<PickupActivityAttributes>.activities.count)")
        await PickupActivityController.cycle(offset: 1)
        return .result()
    }
}

/// 锁屏卡上「取件码右侧那个圆圈」：点一下把当前这件标记为已取。
///
/// 🔴 2026-11-23 老大：「取件码的右侧添加一个圆圈，点击可完成取件」。
///    走的是和桌面小组件同一套「状态回滚日志」（`WidgetToggleJournal`）——
///    扩展进程改不了主 App 的内存数据，只能往共享日志里记一笔，
///    主 App 下次读盘时合并。这样锁屏上点一下，进 App 里就是已取状态。
struct CompletePickupIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "标记为已取" }
    static var description: IntentDescription {
        IntentDescription("在锁屏实时活动里把当前取件码标记为已取。")
    }

    @Parameter(title: "记录")
    var recordID: String

    init() {}

    init(recordID: String) {
        self.recordID = recordID
    }

    func perform() async throws -> some IntentResult {
        IntentDebug.trace("complete tapped id=\(recordID.prefix(8))")
        if let id = UUID(uuidString: recordID) {
            WidgetToggleJournal.append(id: id, picked: true, at: .now)
        }
        // 记完立刻按最新状态重算锁屏卡，用户不用等下一次刷新
        let pending = PickupStorage.load().filter { !$0.isPickedUp }
        PickupActivityController.sync(pending: pending)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PreviousPickupIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "显示上一件待取" }
    static var description: IntentDescription {
        IntentDescription("在锁屏实时活动里切换到上一件待取快递。")
    }
    func perform() async throws -> some IntentResult {
        IntentDebug.trace("prev tapped; provider=\(PickupActivityController.pendingProvider != nil) "
                          + "activities=\(Activity<PickupActivityAttributes>.activities.count)")
        await PickupActivityController.cycle(offset: -1)
        return .result()
    }
}
