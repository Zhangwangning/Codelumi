import Foundation
import UIKit

// MARK: ============================================================================
// 诊断日志（2026-10-31 主人要求：反馈时自动打包日志一起发过来）
//
// 设计约束（很重要，改之前先读）：
//   🔴 **绝不记录短信原文、取件码、地址、电话、设备 UUID**。
//      这是本 App 唯一对外传输的数据，必须只含"发生了什么"，不含"内容是什么"。
//      记的是：版本、系统、解析出几条、哪一步失败、错误码、耗时。
//   🔴 日志只在本机循环写入，用户点「反馈」并确认后才会被附加到邮件里发出去。
//   🔴 环形缓冲：超过 256 KB 就把旧的挪到 log.1.txt（只留一代），不会无限长大。
// ============================================================================

enum DiagnosticsLog {
    private static let queue = DispatchQueue(label: "com.jikezhang.codelumi.diagnostics",
                                             qos: .utility)
    private static let maxBytes = 256 * 1024
    private static let stampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// 日志目录（放在 Application Support，不进 iCloud 备份也无妨，体积很小）
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("log.txt") }
    private static var rotatedURL: URL { directory.appendingPathComponent("log.1.txt") }

    // MARK: 写入

    /// 记一条事件。`event` 用短标签（launch / parse / activate / purchase…），
    /// `detail` 只放结构化、无隐私的补充信息。
    static func record(_ event: String, _ detail: String = "") {
        let line = "\(stampFormatter.string(from: Date())) [\(event)] \(detail)"
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        rotateIfNeeded(manager)

        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 超过上限就把当前文件滚成 log.1.txt（只留一代，够定位最近的问题）
    private static func rotateIfNeeded(_ manager: FileManager) {
        guard let attributes = try? manager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int, size > maxBytes else { return }
        try? manager.removeItem(at: rotatedURL)
        try? manager.moveItem(at: fileURL, to: rotatedURL)
    }

    // MARK: 读取

    /// 等待队列写完（导出前调用，避免最后几条丢失）
    static func flush() {
        queue.sync {}
    }

    /// 直接给用户看/发出去的内容 = 环境摘要 + 日志正文。
    ///
    /// 摘要部分不依赖日志文件，即使日志被清空也能定位"哪台机器、什么版本、什么权益"。
    static func exportText() -> String {
        flush()
        var parts = [summary()]
        if let old = try? String(contentsOf: rotatedURL, encoding: .utf8), !old.isEmpty {
            parts.append("===== 上一份日志（滚动保留） =====")
            parts.append(old)
        }
        let current = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        parts.append("===== 当前日志 =====")
        parts.append(current.isEmpty ? "（暂无记录）" : current)
        return parts.joined(separator: "\n")
    }

    /// 环境摘要：定位问题必需，且全部与用户内容无关
    static func summary() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = UIDevice.current.systemVersion
        let model = UIDevice.current.model
        let snapshot = EntitlementSnapshot.load()
        let plan: String
        switch snapshot.plan {
        case .none: plan = "free"
        case .trial: plan = "trial"
        case .lifetime: plan = "lifetime"
        }
        let expiry = snapshot.expiresAt.map { stampFormatter.string(from: $0) } ?? "none"
        let logSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0

        // 「已解锁」必须取 `licensedPro`：快照里的 `isPro` 只是个缓存布尔值，
        // 订阅到期后它仍是 true（没人会去改文件），照它写会让诊断信息说谎。
        return """
        ===== Codelumi诊断信息 =====
        版本：\(version) (\(build))
        系统：iOS \(system) · \(model)
        权益：\(plan) · 已解锁 \(EntitlementSnapshot.licensedPro ? "是" : "否") · 到期 \(expiry)
        日志大小：\(logSize / 1024) KB
        时间：\(stampFormatter.string(from: Date()))
        """
    }

    /// 清空日志（设置里给一个出口，符合"数据可删"的承诺）
    static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: rotatedURL)
        }
    }
}
