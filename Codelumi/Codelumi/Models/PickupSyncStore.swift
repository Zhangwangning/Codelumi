import Foundation
import Combine
import Network

// MARK: - iCloud 同步：本机墓碑落盘 + 同步控制器
//
// 与 `PickupSyncCore`（纯合并规则）分开：
// 这一层碰 FileManager / iCloud Drive / 通知 UI，合并逻辑仍然只有一份。
//
// 文件位置：
//  · iCloud Drive：`<iCloud 容器>/Documents/records.json`
//    （容器 ID 仍是 `iCloud.com.jikezhang.codelumi`；「文件」App 里显示的文件夹名
//      取 Info.plist 的 `NSUbiquitousContainerName`，2026-11-21 起显示 Codelumi。
//      🔴 容器 ID 与 Documents 路径都不能改，改了老用户云端记录就读不到。）
//  · 本机墓碑：App Group 的 `Library/Application Support/pickup-sync-tombstones.json`
//    （和取件记录同目录，卸载 App 一起没；iCloud 里的副本仍会被另一台设备用到）

// MARK: 墓碑（删除标记）落盘

enum PickupTombstones {
    static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent("pickup-sync-tombstones.json")
    }

    static func load() -> [String: Date] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? PickupSyncCore.decoder.decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    @discardableResult
    static func save(_ tombstones: [String: Date]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: PickupStorage.directory,
                                                    withIntermediateDirectories: true)
            let data = try PickupSyncCore.encoder.encode(tombstones)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// 给 `PickupStore`（非 @MainActor）用的桥：把「排一次同步」转回主线程。
enum PickupSyncBridge {
    static func schedule() {
        Task { @MainActor in ICloudSyncController.shared.scheduleSync() }
    }
}

// MARK: - 同步控制器

/// iCloud 同步的**唯一入口**（开关状态、远端读写、合并、状态展示都走这里）。
///
/// 设计取舍：
///  · 同步是**可选**的，默认关闭；关闭时不读写 iCloud 一个字节。
///  · 不做后台常驻监听：App 启动、回前台、每次数据改动后 1.5 秒各同步一次。
///    对「一天收几条短信」的 App 足够，也省电、省 iCloud 配额。
///  · 失败不打断用户：记录下来显示在「iCloud 同步」页，下次自动重试。
@MainActor
final class ICloudSyncController: ObservableObject {
    static let shared = ICloudSyncController()

    enum Status: Equatable {
        case disabled
        case unavailable          // 没有 iCloud 容器（未登录 / 未开通 iCloud / 模拟器）
        case idle
        case syncing
        case failed(String)

        var text: String {
            switch self {
            case .disabled:    return "已关闭，数据只保存在这台设备上"
            case .unavailable: return "没有找到 iCloud，请在系统设置里登录 iCloud"
            case .idle:        return "待同步"
            case .syncing:     return "正在同步…"
            case .failed(let message): return message
            }
        }
    }

    /// 开关存 App Group：小组件不需要同步，但换 App 重启后状态要还在。
    /// 用 UserDefaults 而不是文件：一个布尔值，不值得再建一份文件。
    private static let enabledKey = "codelumi.icloudSync.enabled"
    private static let lastSyncKey = "codelumi.icloudSync.lastSync"

    @Published private(set) var status: Status = .disabled
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isEnabled: Bool
    /// 网络是否可用（只做展示 + 决定发哪种失败通知，不阻断同步逻辑）。
    @Published private(set) var networkAvailable = true

    private var pendingTask: Task<Void, Never>?
    /// 合并写回本机后要压住的「自触发同步」窗口（见 `scheduleSync`）。
    private var suppressScheduleUntil: Date = .distantPast
    private let fileManager = FileManager.default
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "codelumi.sync.network")

    private init() {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        var initial = defaults.bool(forKey: Self.enabledKey)
        #if DEBUG
        // 截图/自测脚手架：模拟器没登录 iCloud，用环境变量把开关打开，
        // 配合 ALLUDE_SYNC_REMOTE 指到本机目录就能跑完整合并链路。
        if ProcessInfo.processInfo.environment["ALLUDE_SYNC_ENABLED"] == "1" { initial = true }
        #endif
        isEnabled = initial
        if let stamp = defaults.object(forKey: Self.lastSyncKey) as? Date {
            lastSyncedAt = stamp
        }
        status = isEnabled ? .idle : .disabled
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.networkAvailable = available }
        }
        pathMonitor.start(queue: pathQueue)
    }

    /// 设置页「同步状态」一行用的短文案（详细失败原因仍显示在页面底部红字）。
    var statusSummary: String {
        switch status {
        case .disabled:     return "已关闭"
        case .unavailable:  return "iCloud 不可用"
        case .syncing:      return "正在同步…"
        case .failed:       return "同步失败"
        case .idle:         return lastSyncedAt == nil ? "待同步" : "同步成功"
        }
    }

    var isSyncing: Bool { status == .syncing }

    // MARK: 开关

    func setEnabled(_ enabled: Bool) {
        // 🔴 2026-11-15 主人：iCloud 同步并入 Codelumi Pro。
        //    非 Pro 一律不许开启（入口处已经弹订阅页，这里是第二道门，
        //    挡住「Pro 到期时页面还开着」这类绕过入口的情况）。
        guard !enabled || EntitlementSnapshot.licensedPro else { return }
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults(suiteName: PickupStorage.appGroupID)?.set(enabled, forKey: Self.enabledKey)
        if enabled {
            syncNow()
        } else {
            pendingTask?.cancel()
            status = .disabled
        }
    }

    /// Pro 失效后自动关掉同步（记录留在各设备本机，不会继续往 iCloud 写）。
    ///
    /// 只在「真的该关」时才动偏好：`isEnabled` 已经是 false 就直接返回，
    /// 因此这个方法是幂等的，可以放在回前台、每分钟对表这类高频路径上。
    func disableIfNotPro() {
        guard isEnabled, !EntitlementSnapshot.licensedPro else { return }
        setEnabled(false)
    }

    /// 远端是否可用（未登录 iCloud / 模拟器没登录时拿不到容器 URL）。
    var isAvailable: Bool { remoteDirectoryURL != nil }

    // MARK: 同步

    /// 数据改动后调用：1.5 秒内的连续改动只同步一次。
    func scheduleSync() {
        guard isEnabled else { return }
        // 合并写回本机时会触发一次「数据变了 → 再排一次同步」。
        // 用一个小窗口挡住它，避免「同步→写回→再同步」的循环。
        guard Date() >= suppressScheduleUntil else { return }
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// 立即同步（开关打开、回前台、用户点「立即同步」时调用）。
    ///
    /// 真正干活放到 `Task` 里：文件读写和 JSON 解码都在异步任务中完成，
    /// 主线程不会被 iCloud IO 卡住 —— 否则页面上的「正在同步…」转圈会一起冻住。
    func syncNow() {
        guard isEnabled else { status = .disabled; return }
        guard !isSyncing else { return }
        Task { await performSync() }
    }

    private func performSync() async {
        guard let directory = remoteDirectoryURL else {
            status = .unavailable
            return
        }

        status = .syncing
        #if DEBUG
        // 截图脚手架：ALLUDE_SYNC_HOLD=秒数 时把「正在同步」状态多留一会儿，方便截动画。
        if let hold = ProcessInfo.processInfo.environment["ALLUDE_SYNC_HOLD"],
           let seconds = Double(hold), seconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(min(seconds, 10) * 1_000_000_000))
        }
        #endif
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let remoteURL = directory.appendingPathComponent("records.json")

            let remote: PickupSyncFile
            if let data = try? Data(contentsOf: remoteURL) {
                remote = try PickupSyncCore.decode(data)
            } else {
                // 第一次同步：以本机为准建立远端文件
                remote = PickupSyncFile(records: [], tombstones: [:])
            }

            let store = PickupStore.shared
            let local = PickupSyncCore.merge(localRecords: store.records,
                                             localTombstones: store.syncTombstones,
                                             remote: remote)

            if local.remoteTooNew {
                status = .failed("iCloud 里是更新版本 Codelumi 写的记录，本版本只读不写")
                return
            }

            if local.changedLocal {
                suppressScheduleUntil = Date().addingTimeInterval(3)
                store.applySynced(records: local.records, tombstones: local.tombstones)
            }
            if local.changedRemote || local.changedLocal {
                let merged = PickupSyncFile(records: local.records,
                                            tombstones: local.tombstones)
                let data = try PickupSyncCore.encode(merged)
                try data.write(to: remoteURL, options: .atomic)
            }

            // 墓碑已由 `applySynced`（changedLocal 时）写回本机与落盘；
            // 这里只补「没有记录变化、只修剪了过期墓碑」的情况。
            if !local.changedLocal {
                PickupTombstones.save(local.tombstones)
            }
            lastSyncedAt = Date()
            UserDefaults(suiteName: PickupStorage.appGroupID)?.set(lastSyncedAt, forKey: Self.lastSyncKey)
            status = .idle
        } catch {
            status = .failed("同步失败：\(error.localizedDescription)")
        }
    }



    // MARK: iCloud 容器

    /// iCloud Drive 里给同步用的目录。
    ///
    /// - Debug 可用 `ALLUDE_SYNC_REMOTE=<目录>` 指到本机任意目录（模拟器没登录 iCloud 时，
    ///   用它跑合并逻辑；两台模拟器指同一个目录就等于「两台设备」）。
    /// - 正式环境用 iCloud Documents 容器；没登录 iCloud 时返回 nil。
    private var remoteDirectoryURL: URL? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["ALLUDE_SYNC_REMOTE"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        guard let container = fileManager.url(forUbiquityContainerIdentifier: "iCloud.com.jikezhang.codelumi")
        else { return nil }
        return container.appendingPathComponent("Documents", isDirectory: true)
    }

    /// 设置页展示用：上次同步时间的文案
    var lastSyncedDescription: String {
        guard let lastSyncedAt else { return "还没同步过" }
        // 「刚刚」单独处理：RelativeDateTimeFormatter 对「几秒前」会输出
        // 「0 秒后」这类怪话（它按未来/过去取整），读起来像出错。
        let elapsed = Date().timeIntervalSince(lastSyncedAt)
        if elapsed < 60 { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSyncedAt, relativeTo: Date())
    }
}
