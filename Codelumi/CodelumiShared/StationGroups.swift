import Foundation
import WidgetKit

// MARK: - 驿站 ID 登记表（2026-11-17 主人定稿：全驿站 ID 化）
//
// 老大定下的三种前缀：
// ```
// 内置驿站    NZYZ00001、NZYZ00002 ……
// 用户添加    DZYYZ00001、DZYYZ00002、DZYYZ00003 ……
// 分组驿站    FZYD00001、FZYD00002 ……
// ```
//
// 🔴 首次发号**落盘固化**，之后只往末尾追加。
//    为什么不能按数组下标实时算：内置清单是从 `CourierBrand.table` 过滤出来的，
//    中间插一个品牌会让后面所有驿站的 ID 整体后移，已经挂在这些 ID 上的组关系
//    会全部错位（表现为「组里换成了别的驿站」）。
//
// 表落在 **App Group 容器**里（不是 `UserDefaults.standard`）：桌面小组件与
// 灵动岛是两个独立扩展进程，都要按同一份映射做 resolve。

enum StationIdentity {

    /// 三类 ID 前缀
    enum Kind: String {
        case builtin = "NZYZ"
        case custom  = "DZYYZ"
        case group   = "FZYD"
    }

    struct File: Codable {
        /// 驿站名 → 驿站 ID（内置 + 自定义合并一张表）
        var names: [String: String] = [:]
        var nextBuiltin: Int = 1
        var nextCustom: Int = 1
        var nextGroup: Int = 1
    }

    private static let fileName = "station-identity.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    /// 内存快照。落盘一次读一次，之后走这个（列表渲染时 `displayName` 每条记录都要查）。
    private static var snapshot: File?

    // MARK: 读写

    static func current() -> File {
        if let snapshot { return snapshot }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(File.self, from: data) else {
            let empty = File()
            snapshot = empty
            return empty
        }
        snapshot = decoded
        return decoded
    }

    private static func write(_ file: File) {
        snapshot = file
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func invalidate() {
        snapshot = nil
    }

    // MARK: 查询

    /// 驿站名 → 驿站 ID。没登记过返回 nil（调用方应当回落「按名字处理」）
    static func id(for name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return current().names[key]
    }

    /// 驿站 ID → 驿站名
    static func name(for id: String) -> String? {
        current().names.first { $0.value == id }?.key
    }

    /// 全部登记项（名字 → ID），供上层做反查
    static func allNames() -> [String: String] {
        current().names
    }

    static func isGroupID(_ id: String) -> Bool {
        id.hasPrefix(Kind.group.rawValue)
    }

    // MARK: 发号

    /// 分配一个新的组 ID（每次调用都递增，即使中途放弃建组也不复用 —— 复用会让
    /// 已经删掉的组留下的位置 / 图标文件被新组认领）
    static func issueGroupID() -> String {
        var file = current()
        let id = String(format: "\(Kind.group.rawValue)%05d", file.nextGroup)
        file.nextGroup += 1
        write(file)
        return id
    }

    /// 把内置 / 自定义清单同步进登记表（**只在主 App 调用**，扩展进程只读）。
    ///
    /// · 内置：没 ID 的追加末尾；品牌表里删掉的名称**保留**登记（历史记录还能对上号）
    /// · 自定义：没 ID 的追加；已被用户删掉的**摘除**（避免幽灵条目占着号）
    static func sync(builtins: [String], customs: [String]) {
        var file = current()
        var changed = false

        for name in builtins where file.names[name] == nil {
            file.names[name] = String(format: "\(Kind.builtin.rawValue)%05d", file.nextBuiltin)
            file.nextBuiltin += 1
            changed = true
        }

        for name in customs where file.names[name] == nil {
            file.names[name] = String(format: "\(Kind.custom.rawValue)%05d", file.nextCustom)
            file.nextCustom += 1
            changed = true
        }

        // 自定义驿站被删 → 摘掉登记。先收集再删，别在遍历时改字典。
        let customSet = Set(customs)
        let stale = file.names.compactMap { name, id -> String? in
            (id.hasPrefix(Kind.custom.rawValue) && !customSet.contains(name)) ? name : nil
        }
        for name in stale {
            file.names.removeValue(forKey: name)
            changed = true
        }

        if changed { write(file) }
    }

    /// 自定义驿站改名：ID 跟着名字走，组关系（挂 ID）因此不会断
    static func rename(_ from: String, to: String) {
        let old = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty, old != new else { return }
        var file = current()
        guard let id = file.names.removeValue(forKey: old) else { return }
        file.names[new] = id
        write(file)
    }

    /// 自定义驿站删除
    static func remove(_ name: String) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var file = current()
        guard file.names.removeValue(forKey: key) != nil else { return }
        write(file)
    }
}

// MARK: - 驿站组（2026-11-17 主人：组驿站 = 一个全新的驿站）
//
// 主人的原话拆成可执行的口径：
// ```
// ① 组是一个**一等公民驿站**，有自己的名称 / 图标 / 位置；
// ② 名称、图标、位置三项**各自独立**，可以自定义，也可以「只从某一个成员继承」；
// ③ 一个驿站只能进一个组；组不能套组；
// ④ 成员被归组后不再单独显示（待取 / 已取），但实体还在，随时可以退出；
// ⑤ 卡面副名显示「新组/原始匹配驿站」。
// ```
//
// 🔴 组关系挂 **成员 ID**，不挂名字 —— 成员改名（`StationIdentity.rename`）
//    会带着 ID 一起走，组里不会出现幽灵成员。

struct StationGroup: Codable, Identifiable, Hashable {
    var id: String
    /// 组名（全站唯一：不能与内置驿站、自定义驿站、其它组同名）
    var name: String
    /// 成员驿站 ID（`NZYZ…` / `DZYYZ…`）
    var memberIDs: [String]
    var createdAt: Date

    /// 图标来源：nil = 用组自己的（自定义图 / 名称首字兜底）；
    /// 非 nil = 继承该成员驿站的图标
    var iconInheritMemberID: String?

    /// 位置来源：nil = 用组自己的位置（存在 `StationLocationStore`，key = 组名）；
    /// 非 nil = 继承该成员驿站的位置
    var locationInheritMemberID: String?
}

enum StationGroupStore {

    private static let fileName = "station-groups.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    /// 成员名 → 组名 的内存索引。列表渲染会给每条记录查一次，必须缓存。
    private static var cachedMemberIndex: [String: String]?
    /// 成员名 → 所有包含它的组（多组共享时用）
    private static var cachedMemberGroups: [String: [StationGroup]]?

    /// `all()` 的缓存。
    /// 🔴 必须缓存：`StationLogo` 每画一个格子都会问「这是不是一个组」，
    ///    驿站管理页 30+ 个格子、待取页每张卡一个图标 —— 每次都读文件解码会直接卡成幻灯片。
    private static var cachedGroups: [StationGroup]?

    // MARK: 读写

    static func all() -> [StationGroup] {
        if let cachedGroups { return cachedGroups }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StationGroup].self, from: data) else {
            cachedGroups = []
            return []
        }
        cachedGroups = decoded
        return decoded
    }

    static func save(_ groups: [StationGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        // 目录可能还不存在（首次建组 / 命令行工具里跑）：不建目录 write 会静默失败
        try? FileManager.default.createDirectory(at: PickupStorage.directory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        // 🔴 顺序不能反：先清派生索引，**再**落下新缓存。
        //    原来是「设缓存 → invalidateCache()」，等于把刚存的组从缓存里抹掉，
        //    下一次 `all()` 又从磁盘读 —— 磁盘写失败时组就凭空消失了。
        invalidateCache()
        cachedGroups = groups
    }

    static func invalidateCache() {
        cachedMemberIndex = nil
        cachedMemberGroups = nil
        cachedGroups = nil
    }

    // MARK: 派生索引

    /// 成员驿站名 → 所有包含它的组（**多组共享**，2026-11-21 主人定「组是地点」）。
    ///
    /// 走「成员 ID → 成员名」反查，所以成员改名后自动跟到新名字上，
    /// 不需要任何字符串迁移。
    ///
    /// 🔴 「丰巢」这种品牌在 A 小区和 B 小区都有 → 它可以是两个组的成员。
    ///    所以这里给的是**列表**；单值的 `memberIndex()` 只在恰好唯一时才有值。
    static func groupsByMember() -> [String: [StationGroup]] {
        if let cachedMemberGroups { return cachedMemberGroups }

        let names = StationIdentity.allNames()
        var idToName: [String: String] = [:]
        for (name, id) in names where idToName[id] == nil {
            idToName[id] = name
        }

        var map: [String: [StationGroup]] = [:]
        for group in all() {
            for memberID in group.memberIDs {
                if let memberName = idToName[memberID] {
                    map[memberName, default: []].append(group)
                }
            }
        }
        cachedMemberGroups = map
        return map
    }

    /// 成员驿站名 → 组名（**只在唯一归属时**给值；多组并存返回 nil，交给记录级覆盖去定）。
    static func memberIndex() -> [String: String] {
        if let cachedMemberIndex { return cachedMemberIndex }
        var map: [String: String] = [:]
        for (name, groups) in groupsByMember() where groups.count == 1 {
            map[name] = groups[0].name
        }
        cachedMemberIndex = map
        return map
    }

    /// 记录里的驿站名 → 该显示的名字（被归组就是组名，否则原名）。
    /// 空串原样返回（上层会换成「未标注驿站」）。
    static func displayName(for stationName: String) -> String {
        let name = stationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return name }
        return memberIndex()[name] ?? name
    }

    /// 若这个驿站已被归组，返回组名；否则 nil
    static func memberGroupName(for stationName: String) -> String? {
        let name = stationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return memberIndex()[name]
    }

    static func group(named name: String) -> StationGroup? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return all().first { $0.name == key }
    }

    static func group(id: String) -> StationGroup? {
        all().first { $0.id == id }
    }

    /// 某个成员驿站当前属于哪些组（可能多个：同一个品牌在不同小区）
    static func groups(containingMemberNamed name: String) -> [StationGroup] {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        return groupsByMember()[key] ?? []
    }

    /// 某个成员驿站当前属于哪个组（按成员 ID 查）
    static func group(containingMemberNamed name: String) -> StationGroup? {
        guard let memberID = StationIdentity.id(for: name) else { return nil }
        return all().first { $0.memberIDs.contains(memberID) }
    }

    /// 组内成员的驿站名（按成员 ID 反查，顺序与保存时一致）
    static func memberNames(of group: StationGroup) -> [String] {
        group.memberIDs.compactMap { StationIdentity.name(for: $0) }
    }

    /// 还没被任何组收编的驿站名
    static func ungroupedNames(in candidates: [String]) -> [String] {
        // 2026-11-21：判「有没有组」必须用 `groupsByMember()`（多组共享下
        // `memberIndex()` 对跨组成员给 nil，会把它当成没归组 → 网格里同一条
        // 既在主网格出现、又在「已归入驿站组」段出现两次）。
        let map = groupsByMember()
        return candidates.filter { (map[$0] ?? []).isEmpty }
    }

    /// 已被归组的驿站名
    static func groupedNames(in candidates: [String]) -> [String] {
        let map = groupsByMember()
        return candidates.filter { !(map[$0] ?? []).isEmpty }
    }

    // MARK: 校验

    /// 组名唯一性：不能与内置驿站 / 自定义驿站 / 其它组同名。
    /// `excluding` 传自己（改名时允许保留原名）。
    static func isValidGroupName(_ raw: String,
                                 excluding id: String?,
                                 builtinAndCustom names: [String]) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if names.contains(name) { return false }
        return !all().contains { $0.name == name && $0.id != id }
    }

    // MARK: 增删改

    @discardableResult
    static func create(name: String,
                       memberIDs: [String],
                       iconInheritMemberID: String? = nil,
                       locationInheritMemberID: String? = nil) -> StationGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var groups = all()
        guard !groups.contains(where: { $0.name == trimmed }) else { return nil }

        let group = StationGroup(id: StationIdentity.issueGroupID(),
                                 name: trimmed,
                                 memberIDs: memberIDs,
                                 createdAt: Date(),
                                 iconInheritMemberID: iconInheritMemberID,
                                 locationInheritMemberID: locationInheritMemberID)
        groups.append(group)
        // 2026-11-21 主人定：一个驿站**只属于一个组**（取件地点固定，多个组都收同一个品牌
        // 会让短信没法定组）。所以建组时把成员从别的组里摘掉，由调用方把旧记录钉在原组。
        for index in groups.indices where groups[index].id != group.id {
            groups[index].memberIDs.removeAll { memberIDs.contains($0) }
        }
        save(groups)
        StationGroupLocationBridge.syncRegions()
        return group
    }

    /// 更新组（同时把成员从别的组里摘掉 —— 一个驿站只能进一个组）
    static func update(_ group: StationGroup) {
        var groups = all()
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let members = Set(group.memberIDs)
        groups[index] = group
        for other in groups.indices where groups[other].id != group.id {
            groups[other].memberIDs.removeAll { members.contains($0) }
        }
        save(groups)
        // 组的名字 / 成员 / 位置来源任何一项变了，围栏都可能要重排
        StationGroupLocationBridge.syncRegions()
    }

    /// 把一个驿站放进某个组，并从原组移出（2026-11-21：一个驿站只属于一个组）。
    /// 返回它原来所在的组 ID —— 调用方用它把已有记录钉在原组。
    @discardableResult
    static func addMember(stationName: String, toGroup groupID: String) -> String? {
        guard let memberID = StationIdentity.id(for: stationName) else { return nil }
        var groups = all()
        var previous: String?
        for index in groups.indices where groups[index].id != groupID {
            if groups[index].memberIDs.contains(memberID) {
                if previous == nil { previous = groups[index].id }
                groups[index].memberIDs.removeAll { $0 == memberID }
            }
        }
        guard let target = groups.firstIndex(where: { $0.id == groupID }) else { return previous }
        if !groups[target].memberIDs.contains(memberID) {
            groups[target].memberIDs.append(memberID)
        }
        save(groups)
        StationGroupLocationBridge.syncRegions()
        return previous
    }

    /// 把一个驿站从所有组里移出（「不归组」）。
    static func removeMember(stationName: String) {
        guard let memberID = StationIdentity.id(for: stationName) else { return }
        dropMember(stationID: memberID)
    }

    /// 保存前先算一遍「这次保存会把哪些成员从哪个组里拿走」。
    /// 调用方拿到结果后把**已有记录**钉到原组（`PickupStore.pinRecords`），
    /// 否则一次移组会把历史记录一起改判到新组 —— 那批件当初是在老地方取的。
    /// 返回 memberID → 原组 ID。
    static func displacedMembers(_ memberIDs: [String], excluding groupID: String?) -> [String: String] {
        var out: [String: String] = [:]
        for group in all() where group.id != groupID {
            for member in group.memberIDs where memberIDs.contains(member) && out[member] == nil {
                out[member] = group.id
            }
        }
        return out
    }

    /// 某个成员驿站被删 / 被解除归组：从所有组里摘掉它。
    /// 不摘会留下一个「反查不到名字的 ID」—— 它不再影响显示，但会占着组的成员数。
    static func dropMember(stationID: String) {
        var groups = all()
        var changed = false
        for index in groups.indices {
            if groups[index].memberIDs.contains(stationID) {
                groups[index].memberIDs.removeAll { $0 == stationID }
                changed = true
            }
            if groups[index].iconInheritMemberID == stationID {
                groups[index].iconInheritMemberID = nil
                changed = true
            }
            if groups[index].locationInheritMemberID == stationID {
                groups[index].locationInheritMemberID = nil
                changed = true
            }
        }
        guard changed else { return }
        save(groups)
        StationGroupLocationBridge.syncRegions()
    }

    /// 解散组：成员原地恢复独立显示（`memberIndex` 里没有它们了，天然回落原名）。
    /// 组的自定义图标文件与位置一起清掉，别留孤儿。
    static func delete(id: String) {
        var groups = all()
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let removed = groups.remove(at: index)
        save(groups)
        StationGroupAppearanceBridge.cleanUp(removed)
        StationGroupLocationBridge.syncRegions()
    }

    // MARK: 图标 / 位置继承

    /// 组当前实际取图标的驿站名：继承成员优先，否则返回组名（组自己的自定义图 /
    /// 名称首字兜底都在 `StationLogo` 里处理）
    static func iconSourceName(for group: StationGroup) -> String {
        if let memberID = group.iconInheritMemberID,
           let memberName = StationIdentity.name(for: memberID) {
            return memberName
        }
        return group.name
    }

    /// 组当前实际读位置的 key：继承成员优先，否则组名
    static func locationSourceName(for group: StationGroup) -> String {
        if let memberID = group.locationInheritMemberID,
           let memberName = StationIdentity.name(for: memberID) {
            return memberName
        }
        return group.name
    }
}

// MARK: - 与 App 层（图标 / 位置 / 围栏）的桥
//
// `StationDirectory`、`StationLocationStore`、`StationLocationService` 都在 App target，
// 而本文件要给小组件一起编译 —— 所以只留协议式的挂点，App 启动时把实现塞进来。

enum StationGroupAppearanceBridge {
    /// 由 App 启动时注册：删组后清掉该组自己的图标文件与位置
    static var cleanUp: (StationGroup) -> Void = { _ in }
}

enum StationGroupLocationBridge {
    /// 由 App 启动时注册：组的位置来源变了要重排围栏
    static var syncRegions: () -> Void = {}
}

// MARK: - 驿站内排序（2026-11-17 主人定稿）
//
// 「根据取件码的大小排序，如果取件码存在英文，则由 A-Z / Z-A，数字 0-9 / 9-0，
//   就从取件码的从左至右一位一位去比较排序」
//
// 即**逐字符字典序**，不是数值序：
//   `8-4-1005` < `8-4-3019` < `8-4-999`
// Swift 的 `String <` 正好符合需要的字符权重（`-` 0x2D < `0` 0x30 < `A` 0x41），
// 前缀相同时短的在前 —— 直接用即可，不必自己写比较器。
//
// ⚠️ 只在「按快递驿站」分组模式下起作用（老大明确过）。

enum StationInnerOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case codeAsc
    case codeDesc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:   "收到时间 · 新→旧"
        case .oldest:   "收到时间 · 旧→新"
        case .codeAsc:  "取件码 · 0→9、A→Z"
        case .codeDesc: "取件码 · 9→0、Z→A"
        }
    }

    private static let key = "codelumi.station.innerOrder"

    static var current: StationInnerOrder {
        let raw = PickupStorage.sharedDefaults.string(forKey: key)
        return raw.flatMap(StationInnerOrder.init(rawValue:)) ?? .newest
    }

    static func set(_ order: StationInnerOrder) {
        PickupStorage.sharedDefaults.set(order.rawValue, forKey: key)
        // 待取页、桌面小组件、灵动岛都按这套排，写完立刻重画
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 驿站**内部**的先后判定（外部由调用方按驿站名分桶）。
    ///
    /// `moment` 让调用方决定「时间」用哪个时刻：待取页一直按 `lastNotifiedAt`
    /// （最后一次通知）排，已取页与小组件按 `receivedAt`（收到时间）排 ——
    /// 两套口径本来就有，这里不强行统一，由调用方传。
    func isOrderedBefore(_ a: PickupRecord,
                         _ b: PickupRecord,
                         moment: (PickupRecord) -> Date = { $0.receivedAt }) -> Bool {
        switch self {
        case .newest:
            // 时间相同必须走确定性兜底：批量导入的短信大量并列在同一秒，
            // `sorted` 又不稳定，不兜底就会「App 一个顺序、小组件另一个顺序」。
            let ma = moment(a), mb = moment(b)
            if ma != mb { return ma > mb }
            return PickupSortLogic.tieBreak(a, b)
        case .oldest:
            let ma = moment(a), mb = moment(b)
            if ma != mb { return ma < mb }
            return PickupSortLogic.tieBreak(a, b)
        case .codeAsc, .codeDesc:
            switch PickupCodeOrder.compare(a.code, b.code) {
            case .before: return self == .codeAsc
            case .after:  return self == .codeDesc
            // 同码（或空码）回落确定性兜底，保证排序稳定、不会每帧跳
            case .same:   return PickupSortLogic.tieBreak(a, b)
            }
        }
    }
}

// MARK: - 取件码的自然排序（2026-11-17 主人）

/// 取件码排序的**唯一口径**。
///
/// 🔴 以前是把码大写后直接做字符串比较 —— 逐字符比，于是：
/// ```
///   8-4-1005  <  8-4-999     ← 因为 '1' < '9'，但 1005 明显大于 999
///   110226    <  90050       ← 同理，'1' < '9'
/// ```
/// 主人 2026-11-17 指正：数字就该按数值比，一段一段比。
///
/// 规则（三种形态统一成一套）：
/// · 纯数字 `110226`：一个数字段，比数值；
/// · 带连接符 `8-4-1005`：数字段 `8` / `4` / `1005`，从左到右逐段比数值；
/// · 带字母 `YT169555`：字母段 `YT` 比字典序，再比后面的数字段 `169555`。
///
/// 分隔符（`-` `_` `/` 空格…）**只起分段作用，不参与比较** ——
/// `8-4-1005` 与 `8 4 1005` 视为同形。数字段排在字母段之前
/// （与 ASCII 里数字小于大写字母一致），所以 `8-4-1005` 会排在 `YT169555` 前面。
enum PickupCodeOrder {

    /// 三态比较结果。自带一个而不用 `ComparisonResult` —— 这个类型要被
    /// App 与 Widget 两个 target 共用，不依赖 Foundation 的桥接类型更省心。
    enum Order {
        case before, same, after
    }

    private enum Piece: Equatable {
        case digits(String)
        case letters(String)
    }

    /// 把码切成「字母段 / 数字段」交替的序列。
    ///
    /// ⚠️ 只用 ASCII 的 `isNumber` / `isLetter` 判断：`Character.isNumber` 对
    /// 罗马数字、全角数字也返回 true，会把它们混进数字段算出奇怪的顺序。
    private static func pieces(_ code: String) -> [Piece] {
        var out: [Piece] = []
        var buffer = ""
        var bufferIsDigits: Bool?

        func flush() {
            guard !buffer.isEmpty, let isDigits = bufferIsDigits else { return }
            out.append(isDigits ? .digits(buffer) : .letters(buffer))
            buffer = ""
        }

        for ch in code.uppercased() {
            let isDigits = ch.isASCII && ch.isNumber
            let isLetters = ch.isASCII && ch.isLetter
            if isDigits || isLetters {
                if let current = bufferIsDigits, current != isDigits { flush() }
                bufferIsDigits = isDigits
                buffer.append(ch)
            } else {
                // 分隔符：把当前段收尾，自己丢掉
                flush()
                bufferIsDigits = nil
            }
        }
        flush()
        return out
    }

    /// 数字段比较：**去前导零后先比位数、再比字典序**。
    /// 这样既等价于比数值，又不会在超长数字上溢出 Int。
    private static func compareDigits(_ x: String, _ y: String) -> Order {
        let a = x.drop(while: { $0 == "0" })
        let b = y.drop(while: { $0 == "0" })
        if a.count != b.count { return a.count < b.count ? .before : .after }
        if a == b { return .same }
        return a < b ? .before : .after
    }

    static func compare(_ lhs: String, _ rhs: String) -> Order {
        let a = pieces(lhs)
        let b = pieces(rhs)

        for index in 0..<min(a.count, b.count) {
            switch (a[index], b[index]) {
            case let (.digits(x), .digits(y)):
                let result = compareDigits(x, y)
                if result != .same { return result }
            case let (.letters(x), .letters(y)):
                if x != y { return x < y ? .before : .after }
            case (.digits, .letters):
                return .before
            case (.letters, .digits):
                return .after
            }
        }

        if a.count != b.count {
            return a.count < b.count ? .before : .after
        }
        // 分段后完全同形（例如仅分隔符不同）：回落原文，保证全序、排序稳定
        if lhs == rhs { return .same }
        return lhs < rhs ? .before : .after
    }
}

// MARK: - 驿站解析：单一入口（2026-11-21 主人定）
//
// 🔴 背景：识别与「归组」原先散在三处 —— App 用 `StationDirectory.matchedName`
//    （内置 + 自定义），小组件用 `record.station`（只有内置），分组键又各算各的。
//    结果：用户在 App 里用自定义驿站建的组，桌面上掉进「未标注驿站」。
//    现在**所有消费端只调 `StationResolver.resolve(_:)`**，识别源与组归属只有一份答案。
//
// 优先级（主人 2026-11-21 定：①组是地点 ②加手工指定 ③组名不参与识别）：
//   1. 记录级「指定了驿站组」→ 直接用该组
//   2. 记录级「指定了驿站」→ 用它
//   3. 内置词表（`record.station`）
//   4. 自定义驿站名单（跨进程副本，见 `StationCatalog`）
//   5. 驿站名 → 组的唯一归属；出现在多个组时**不猜**，把候选留给界面

/// 自定义驿站名单的**跨进程副本**。
///
/// 权威写入方是 App 的 `StationDirectory`（那里管理改名 / 删除 / 图标），
/// 它每次落盘顺手同步到这里；小组件与实时活动进程只读这里，
/// 这样「自定义驿站建的组」在桌面上也不会掉进「未标注驿站」。
enum StationCatalog {

    /// App Group 里的键。刻意与 `StationDirectory` 自己的 `station.customNames`
    /// （`UserDefaults.standard`，App 私有）分开：扩展读不到 standard。
    static let key = "codelumi.station.customNames"

    static var customNames: [String] {
        (PickupStorage.sharedDefaults.stringArray(forKey: key) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func save(_ names: [String]) {
        PickupStorage.sharedDefaults.set(names, forKey: key)
    }

    /// 在文本里找命中的自定义驿站名（最长优先）。
    /// 与内置词表同一口径：**只用名字**，不用短 key —— 否则「中邮大厦」会被判成「中邮」。
    static func match(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        return customNames
            .filter { text.localizedStandardContains($0) }
            .max { $0.count < $1.count }
    }
}

/// 一条记录解析出来的驿站 / 驿站组。
///
/// 分组键、卡面副名、围栏匹配、详情页显示**都读这一份**，
/// 任何地方想加规则都改 `StationResolver`，不要在消费端各写一遍。
struct StationResolution: Hashable {

    enum Source: String {
        case groupOverride   // 记录里指定了组
        case stationOverride // 记录里指定了驿站
        case builtin         // 内置词表命中
        case custom          // 自定义驿站命中
        case none
    }

    var stationName: String = ""
    var groupID: String? = nil
    var groupName: String? = nil
    /// 同一驿站出现在多个组时的候选组名（不自动归属，等用户在详情页指定）
    var candidateGroups: [String] = []
    var source: Source = .none

    var hasStation: Bool { !stationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 分组键 / 卡面副名：组名 > 驿站名 > 未标注驿站
    var displayName: String {
        if let groupName, !groupName.isEmpty { return groupName }
        return hasStation ? stationName : PickupSortLogic.noStation
    }

    /// 出现在多个组（需要用户指定）—— 界面据此提示，不要自己挑一个
    var isAmbiguous: Bool { candidateGroups.count > 1 }

    /// 结论来自用户在记录上的指定（不是自动识别）
    var isManual: Bool { source == .groupOverride || source == .stationOverride }
}

enum StationResolver {

    static func resolve(_ record: PickupRecord) -> StationResolution {
        var out = StationResolution()

        // ① 记录级指定的组（最高优先：用户说了算，识别再准也不覆盖它）
        let overrideID = (record.stationGroupOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !overrideID.isEmpty,
           let group = StationGroupStore.all().first(where: { $0.id == overrideID }) {
            out.groupID = group.id
            out.groupName = group.name
            out.source = .groupOverride
        }

        // ② 驿站名：记录覆盖 → 内置词表 → 自定义名单
        let manual = (record.stationOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let builtin = record.station.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            out.stationName = manual
            if out.source == .none { out.source = .stationOverride }
        } else if !builtin.isEmpty {
            out.stationName = builtin
            if out.source == .none { out.source = .builtin }
        } else if let custom = StationCatalog.match(in: record.rawMessage) {
            out.stationName = custom
            if out.source == .none { out.source = .custom }
        }

        // ③ 没被手工指定组时按成员归属推：唯一才认，多个组不猜
        if out.groupID == nil, out.hasStation {
            let candidates = StationGroupStore.groups(containingMemberNamed: out.stationName)
            if candidates.count == 1 {
                out.groupID = candidates[0].id
                out.groupName = candidates[0].name
            } else if candidates.count > 1 {
                out.candidateGroups = candidates.map(\.name)
            }
        }

        return out
    }
}
