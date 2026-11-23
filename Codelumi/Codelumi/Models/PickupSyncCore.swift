import Foundation

// MARK: - iCloud 同步：文件格式与合并规则
//
// 2026-11-12 主人要求加 iCloud 同步。
//
// 设计口径（**先把话说清楚，写代码才有边界**）：
//  1. 只走**用户自己的 iCloud**（iCloud Drive 里的一个 JSON 文件），
//     不经开发者服务器、不建账号、不收集任何数据 —— 和「数据只在本机」的承诺不冲突，
//     只是把「本机」扩展成「你的设备们」。
//  2. 同步是**可选开关**，默认关闭；关闭时 App 与从前完全一样（纯本地）。
//  3. 合并粒度是**单条记录**：同一 `id` 取 `updatedAt` 新的那条；
//     删除用 tombstone（墓碑）表达，避免「A 机删了、B 机又把它同步回来」。
//  4. 冲突不弹窗、不打断用户：同步是后台行为，UI 只显示「上次同步时间 / 失败原因」。
//
// 本文件刻意**只依赖 Foundation + PickupRecord**，不碰 UIKit / FileManager：
// 合并规则可以用命令行 harness 直接跑（见 tools/sync-check），不必开模拟器。

/// iCloud Drive 上的同步文件（一个 JSON）。
struct PickupSyncFile: Codable, Equatable {
    /// 文件格式版本。未来若字段不兼容，读到更大的版本号就**只读不写**，
    /// 免得旧版本把新版本的数据覆盖掉。
    var version: Int = PickupSyncCore.currentVersion
    /// 最后写入时间，仅用于展示与调试。
    var updatedAt: Date = Date()
    var records: [PickupRecord] = []
    /// 删除墓碑：`id.uuidString -> 删除时间`。
    /// 没有墓碑就表达不了删除 —— 记录从文件里消失会被另一台设备当成「它没同步过」。
    var tombstones: [String: Date] = [:]
}

enum PickupSyncCore {
    static let currentVersion = 1
    /// 墓碑保留期：90 天后清掉，避免文件无限增长。
    /// 取 90 天是因为「一台设备超过三个月没打开过 App」这时同步本来也不重要了。
    static let tombstoneTTL: TimeInterval = 90 * 24 * 60 * 60

    /// 合并时用的「这条记录什么时候变的」：优先 `updatedAt`，旧数据回落 `receivedAt`。
    static func changedAt(_ record: PickupRecord) -> Date {
        record.updatedAt ?? record.receivedAt
    }

    struct MergeResult: Equatable {
        var records: [PickupRecord]
        var tombstones: [String: Date]
        /// 合并结果是否与**本机**不同（不同才需要写回本机、刷新界面）
        var changedLocal: Bool
        /// 合并结果是否与**远端文件**不同（不同才需要写回 iCloud）
        var changedRemote: Bool
        /// 远端文件格式版本高于本机 → 只读不写
        var remoteTooNew: Bool
    }

    /// 把「本机记录 + 本机墓碑」与「远端文件」合并成一份新状态。
    ///
    /// 规则（两条，避免歧义）：
    ///  · 记录：同一 id 取 `changedAt` 更大的；时间完全相同时**保留本机**（本机是用户眼前看到的那份）；
    ///  · 删除：墓碑时间 >= 记录的 `changedAt` 才算删除生效；否则保留记录
    ///    （用户先在 A 机删、又在 B 机改了这条，那应该保留 B 机的修改）。
    static func merge(localRecords: [PickupRecord],
                      localTombstones: [String: Date],
                      remote: PickupSyncFile,
                      now: Date = Date()) -> MergeResult {
        var tombstones = localTombstones
        for (id, date) in remote.tombstones {
            tombstones[id] = max(tombstones[id] ?? .distantPast, date)
        }
        // 过期墓碑清掉（两机都没有更早的删除需要传播了）
        tombstones = tombstones.filter { now.timeIntervalSince($0.value) < tombstoneTTL }

        func isDeleted(_ record: PickupRecord) -> Bool {
            guard let deletedAt = tombstones[record.id.uuidString] else { return false }
            return deletedAt >= changedAt(record)
        }

        var merged: [PickupRecord] = []
        var index: [UUID: PickupRecord] = [:]

        // 先放本机（保持用户熟悉的顺序），顺便按墓碑过滤
        for record in localRecords where !isDeleted(record) {
            merged.append(record)
            index[record.id] = record
        }

        // 再并远端：没有的追加；都有的取更新的
        for record in remote.records where !isDeleted(record) {
            if let local = index[record.id] {
                if changedAt(record) > changedAt(local),
                   let position = merged.firstIndex(where: { $0.id == record.id }) {
                    merged[position] = record
                    index[record.id] = record
                }
            } else {
                merged.append(record)
                index[record.id] = record
            }
        }

        // 本机有、但已被墓碑判死的记录不参与比较（上面已过滤）

        // 与远端比较（远端记录里可能含墓碑判死但文件还没清掉的旧记录）
        let remoteRecords = remote.records.filter { !isDeleted($0) }
        let changedRemote = !sameRecords(remoteRecords, merged)
            || remote.tombstones != tombstones

        let changedLocal = !sameRecords(localRecords, merged)
            || localTombstones != tombstones

        return MergeResult(records: merged,
                           tombstones: tombstones,
                           changedLocal: changedLocal,
                           changedRemote: changedRemote,
                           remoteTooNew: remote.version > currentVersion)
    }

    /// 记录列表是否等价：只比「同步真正关心」的字段？
    /// 不 —— 整条 `PickupRecord` 是 `Codable & Hashable`，直接比最严格、也最简单；
    /// 顺序也算（顺序变了说明有插入，写回一次没坏处）。
    static func sameRecords(_ lhs: [PickupRecord], _ rhs: [PickupRecord]) -> Bool {
        lhs == rhs
    }

    // MARK: 编解码（iCloud 文件与本地墓碑共用）

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // 🔴 用带小数秒的 ISO8601：默认 `.iso8601` 会把毫秒抹掉，而合并是比
        //    `updatedAt` 大小的 —— 抹掉之后同一份记录每次读回来都比本机「旧」
        //    或「新」一点点，会造成「刚写完又判定有变化」的来回同步。
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        // 兼容两种写法：带小数秒（本版本写的）与纯秒（早期/外部工具写的）
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "无法解析时间：\(text)"
            ))
        }
        return decoder
    }

    static func encode(_ file: PickupSyncFile) throws -> Data {
        try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> PickupSyncFile {
        try decoder.decode(PickupSyncFile.self, from: data)
    }
}
