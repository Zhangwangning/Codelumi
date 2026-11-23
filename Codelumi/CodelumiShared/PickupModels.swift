import Foundation
import SwiftUI

// MARK: ============================================================================
// 共享数据模型（App 与小组件扩展共同编译）
//
// 这里只放「纯数据 + 纯计算」：两端都要用来渲染的类型。
// 解析引擎（PickupParser）、全局状态（PickupStore）留在 App target —— 小组件
// 只读展示，不需要正则能力，也不应承担解析成本。
// ============================================================================

// MARK: - 取件信息类别（对应快捷指令 V7.3.0 的四级优先级链：取件码 → 运单号 → 尾号 → 特殊格式）

enum PickupKind: String, CaseIterable, Identifiable, Codable {
    case code
    case waybill
    case tail
    case special

    var id: String { rawValue }

    var label: String {
        switch self {
        case .code: "取件码"
        case .waybill: "运单号"
        case .tail: "尾号"
        case .special: "特殊取件码"
        }
    }

    var symbol: String {
        switch self {
        case .code: "shippingbox.fill"
        case .waybill: "doc.text.fill"
        case .tail: "number"
        case .special: "sparkles"
        }
    }

    /// 单字简写，**仅供极窄场景**（如锁屏 `accessoryRectangular`）与 `KindTag(compact:)` 使用。
    ///
    /// ⚠️ 首页 / 记录页 / 小组件一律用完整 `label`，不要退回单字：
    /// 「码」字同时命中取件码、取餐码、退货码，用户无法据此判断该报什么去取。
    var shortLabel: String {
        switch self {
        case .code: "码"
        case .waybill: "单"
        case .tail: "尾"
        case .special: "特"
        }
    }
}


// MARK: - 时间分组（首页与记录页共同使用，给列表一个稳定的骨架）

enum DayGroup: String, CaseIterable, Identifiable {
    case today = "今天"
    case yesterday = "昨天"
    case earlier = "更早"

    var id: String { rawValue }
}

// MARK: - 单条取件信息

struct PickupRecord: Identifiable, Hashable, Codable {
    var id = UUID()
    var company: String
    var code: String
    var kind: PickupKind
    var address: String
    var rawMessage: String
    var receivedAt: Date
    var isPickedUp: Bool = false

    /// **快递公司（承运方）**，与 `company`（平台）分开：
    /// 「【拼多多】您的圆通快递…」→ company=拼多多、courier=圆通快递。
    /// 🔴 Optional + 默认 nil：合成 Codable 走 decodeIfPresent，
    ///    旧版本 JSON 缺这些 key 也能正常解出（2026-09-23 扩展字段）。
    var courier: String? = nil
    /// 次要凭证：运单号（主凭证就是运单号时不重复存，为 nil）
    var waybill: String? = nil
    /// 次要凭证：尾号（主凭证就是尾号时不重复存，为 nil）
    var tail: String? = nil
    /// **货架号**（2026-10-14 参照「码上取」补的字段）：菜鸟驿站等场景下，
    /// 货架号比取件码更能直接定位包裹（「3号货架」「货架号：3-12」）。
    /// 🔴 Optional + 默认 nil：旧版本 JSON 缺这个 key 也能正常解码。
    var shelf: String? = nil

    /// **快递柜格口**（2026-10-27 从快捷指令 V8.0.2 移植）。
    /// 与 `shelf` 分开存：货架是驿站里自己找的货位，柜是机器弹门的格口，
    /// 到柜前必须先知道是几号柜 —— 小组件里紧跟取件码显示。
    /// 🔴 Optional + 默认 nil：旧数据没有这个 key，走 decodeIfPresent。
    var locker: String? = nil

    /// **驿站名（模型复核后的覆盖值）**（2026-11-14 接入第三方模型时新增）。
    ///
    /// `station` 本身是**派生值**：由 `CourierBrand.stationMatch` 在品牌词表里从原文匹配，
    /// 不落盘。第三方模型复核后如果给出更准确的驿站名，就存在这里；`station` 优先读它。
    /// 🔴 Optional + 默认 nil：旧版本 JSON 没有这个 key，`decodeIfPresent` 自动给 nil。
    var stationOverride: String? = nil

    /// **这条取件码被通知过的时间序列**（2026-10-30 主人定）。
    ///
    /// 同一个码第二次、第三次收到短信，不再新建一条重复记录，
    /// 而是**更新时间**并在这里留下历史：卡片显示最新一次（`history.last`），
    /// 详情页可以逐条列出「什么时候又提醒了一次」。
    ///
    /// - 首次入库时 = `[receivedAt]`，所以 `history.last` 恒等于「最后一次通知时间」；
    /// - 旧数据没有这个 key → nil，展示层回落成 `[receivedAt]`；
    /// - `receivedAt` 仍保持**首次**时刻不动，统计页的停留时长才不会被重复通知拉短。
    var history: [Date]? = nil

    /// **记录级手工指定的驿站组**（2026-11-21 主人定「加」）。
    ///
    /// 存的是组的 **ID**（`FZYD…`）而不是组名：组可以改名，ID 跟名字无关。
    /// 只有「同一个品牌出现在两个组」这类分不清的情况才需要用它 ——
    /// 解析入口（`StationResolver`）把它的优先级排在所有自动识别之上。
    ///
    /// 🔴 Optional + 默认 nil：旧 JSON 没这个 key，合成 Codable 走 `decodeIfPresent`。
    var stationGroupOverride: String? = nil

    /// 最后一次被通知的时间（卡片右上角那个时间戳用它）
    var lastNotifiedAt: Date { history?.last ?? receivedAt }

    /// 这条记录的驿站 / 组结论（与列表、小组件、围栏同一份）
    var stationResolution: StationResolution { StationResolver.resolve(self) }

    /// **本机最后一次改动这条记录的时间**（2026-11-12 加 iCloud 同步）。
    ///
    /// 只给同步合并用：两台设备的同一条记录（同 `id`）冲突时，取 `updatedAt` 新的那条。
    /// 没有单独的时间戳就只能比 `receivedAt`，会把「A 机勾了已取、B 机没勾」判平。
    ///
    /// 🔴 Optional + 默认 nil：旧 JSON 没这个 key，合成 Codable 走 `decodeIfPresent`，
    ///    解码成 nil，合并时按 `receivedAt` 兜底，不会因为升级 App 就解不出旧数据。
    var updatedAt: Date? = nil

    /// 取件发生的时刻（勾选「已取」的那一下），未取件时为 nil。
    ///
    /// 与 `receivedAt`（短信到达 = 入库时刻）配对，才能回答统计页里两个真问题：
    ///   · 「取件频率」—— 用户实际是在哪几天去取的（只看 receivedAt 只能得到「收短信的频率」）；
    ///   · 「平均停留」—— 从收到通知到取走平均花了多久，这是这个 App 最有价值的自省指标。
    ///
    /// ⚠️ 声明为 **Optional** 而非给一个默认时间：`Codable` 合成的解码对可选字段走
    /// `decodeIfPresent`，**旧版本写下的 JSON 缺这个 key 也能正常解码**（读到 nil），
    /// 不会因为升级 App 就让整份取件记录解不出来。历史数据没有这个值，
    /// 统计侧统一以 `pickedUpAt ?? receivedAt` 兜底，不会出现空洞。
    var pickedUpAt: Date? = nil

    /// 「取件发生时间」的统一读取口径：老数据没记 `pickedUpAt` 时回退到入库时间。
    var pickupMoment: Date { pickedUpAt ?? receivedAt }

    /// 地址字段是否**只**是货架描述（「3号货架」「货架5-12」这类），而不是真实地址。
    ///
    /// 为什么需要这个判断：解析器从「您的包裹在3号货架」里会把「3号货架」当成
    /// 取件地址锚出来，可它是货架号本身 —— 卡面会同时出现「3号货架」（地址行）
    /// 和「货架3」（货架标签）两份重复信息；更麻烦的是详情页地图卡片会拿它去做
    /// 地理编码，必然解析失败、导航按钮形同虚设。
    ///
    /// 解析期拦截与存量数据清洗**共用这一份口径**，避免两处规则漂移。
    static func addressIsShelfOnly(_ address: String, shelf: String?) -> Bool {
        guard let shelf, !shelf.isEmpty else { return false }
        let compact = address.replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return false }
        let forms = ["\(shelf)号货架", "货架\(shelf)", "货架号\(shelf)",
                     "货架号：\(shelf)", "货架号:\(shelf)"]
        return forms.contains(compact)
    }

    /// 去重指纹：同一类别 + 同一凭证 + 同一地址视为同一条
    var fingerprint: String {
        "\(kind.rawValue)|\(code)|\(address)"
    }

    /// 快递公司的**标准名**（「申通」→「申通快递」）。
    /// 卡面主名、详情页字段、小组件统一用它，别再直接读 `courier`。
    var courierDisplay: String? {
        guard let courier, !courier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return CourierBrand.canonicalName(for: courier)
    }

    /// ⚠️ 已废弃（2026-10-30）：**不要再按「平台优先」取色**。
    /// 全 App 统一规则是「图标 = 第一行第一个字段，卡面与取件码 = 该图标的主题色」，
    /// 对应实现是各视图自己的 `iconBrand` / `codeColor`（快递公司 > 驿站 > 平台）。
    /// 这个属性当年是「拼多多发的就染成拼多多红」的入口，正是
    /// 「紫图标 + 粉色卡面」这类割裂的来源，保留只为兼容，新代码不要用。
    @available(*, deprecated, message: "改用 codeColor 或视图内的 iconBrand（第一行第一个字段优先）")
    var brandColor: Color { CourierBrand.color(for: company.isEmpty ? (courier ?? "") : company) }

    /// **取件码的颜色**（2026-10-28 修「小组件码色与 App 不一致」）。
    ///
    /// 口径与 App 待取卡的主名同源：**快递公司优先**，没有才回落短信平台。
    /// 之前小组件直接用了 `brandColor`（平台优先），于是同一条记录在 App 里
    /// 码是「韵达深金」、在桌面上变成「欢猫驿站青绿」—— 一个品牌两种颜色。
    /// 🔴 卡面底仍用 `brandColor`（跟平台走），只有**码**用这个，两者不要混。
    var codeColor: Color {
        let carrier = (courier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return CourierBrand.color(for: carrier.isEmpty ? company : carrier)
    }

    /// 全局搜索命中判断（取件码 / 快递公司 / 平台 / 地址 / 运单号 / 尾号 / 原文）
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return code.localizedCaseInsensitiveContains(q)
            || company.localizedCaseInsensitiveContains(q)
            || address.localizedCaseInsensitiveContains(q)
            || rawMessage.localizedCaseInsensitiveContains(q)
            || (courier?.localizedCaseInsensitiveContains(q) ?? false)
            || (waybill?.localizedCaseInsensitiveContains(q) ?? false)
            || (tail?.localizedCaseInsensitiveContains(q) ?? false)
    }

    /// 分组用的时刻 = **最后一次被通知的时间**（`lastNotifiedAt`）。
    ///
    /// 🔴 2026-10-30：以前用 `receivedAt`（首次入库），于是卡面明明写着
    /// 「10月30日 00:31」，却因为首次入库在昨天而被归进「昨天」——
    /// 用户看到的是"时间在右边、分组说昨天"，自相矛盾（真机实证）。
    /// 卡面显示什么时间，分组就按什么时间算，两者必须同一个来源。
    var dayGroup: DayGroup {
        let calendar = Calendar.current
        if calendar.isDateInToday(lastNotifiedAt) { return .today }
        if calendar.isDateInYesterday(lastNotifiedAt) { return .yesterday }
        return .earlier
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 卡片右上角时间 = **最后一次被通知的时刻**（重复短信只更新时间，不再新建卡片）
    var shortTime: String { Self.shortTimeFormatter.string(from: lastNotifiedAt) }

    /// 只显示时:分的紧凑时间（同一天内使用）
    var clockTime: String { Self.clockFormatter.string(from: receivedAt) }

    var relativeTime: String {
        let interval = Date().timeIntervalSince(receivedAt)
        if interval < 60 { return "刚刚" }
        // 数字与单位之间不留空格：卡片第一行横向预算只有约 190pt，
        // 每处省下的 3~4pt 都直接决定「取件码 + 标签 + 时间」能否同排显示。
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3600))小时前" }
        if interval < 172_800 { return "昨天" }
        return shortTime
    }

    /// 地址过长时截断，供小组件单行展示
    func trimmedAddress(_ limit: Int = 14) -> String {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    // MARK: 快递驿站（2026-10-18 主人定稿）

    /// **快递驿站** = 短信原文里命中的实在驿站品牌名（菜鸟驿站 / 兔喜生活 / 丰巢…）。
    ///
    /// 数据源**仅短信原文（rawMessage）**——驿站是发件方在短信里明确的品牌，
    /// 不是用户手填的取件地址（两者必须解耦：地址是「去哪取」，驿站是「谁发的」）。
    /// 用 `CourierBrand.stationMatch` 在品牌词表里做包含匹配，命中即用规范名，
    /// 未命中返回空串。该匹配是纯函数、不依赖 UIKit，App 与 Widget 共用同一张词表。
    var station: String {
        // 模型复核过的值优先（用户可在「扩展」里开启 AI 参与解析）；
        // 空串/纯空白一律视为没有，回落到品牌词表匹配。
        if let override = stationOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        return CourierBrand.stationMatch(in: [rawMessage])?.name ?? ""
    }

    // MARK: 小组件二级信息行

    /// 按显示配置拼出小组件的第二行；**没有任何内容可显示时返回 nil**（该行整行不画）。
    ///
    /// 🔴 **三项互相独立**（2026-10-27 主人指正：「取件地址和驿站不是一个值」）：
    ///   公司 = 谁承运；驿站 = 谁保管（短信原文里的品牌名）；地址 = 去哪取。
    ///   三者是不同字段、不同含义，**不做互斥、不互相顶替** —— 曾把驿站与地址写成
    ///   「同开时以地址为准」，等于拿地址冒充驿站，是错的。
    /// · 驿站匹配不到（`station` 为空）时**这一项就不显示**，不再回落成地址：
    ///   回落会把两项画成同一段字，用户根本分不清哪项是驿站。
    /// · 地址仍按 12/16 字截断：第二行只有一行宽，三项同显示时先让地址让位（纯宽度取舍）。
    /// `addressLimit` 留空时按是否同行显示站名自动取值；小尺寸（允许折两行）
    /// 显式传更宽的上限，那里有第二行的预算。
    func widgetSubtitle(_ options: WidgetDisplayOptions,
                        addressLimit: Int? = nil) -> String? {
        let limit = addressLimit ?? (options.showsStation ? 12 : 16)
        var parts: [String] = []

        // 来源方（2026-10-27 主人定）：**快递公司优先，平台兜底** ——
        // 与卡面主名同一个规则（`PickupNaming.primary`），不再各写一版。
        if options.showsCompany {
            let source = naming(station: station).primary
            if !source.isEmpty { parts.append(source) }
        }

        // 货架号**不再**在这里出现：它与快递柜一起挪到取件码后面那一位
        // （2026-10-27 主人：「取件码后面有就显示快递柜信息，没有则为空」）。
        // 放在码后面比埋在第二行更有用 —— 它是到店/到柜那一刻要用的信息。

        // 驿站：**独立一项**，只在短信原文里匹配到驿站品牌名时才显示
        // （`station` 走 CourierBrand 词表，与「取件地址」是两件事）。
        // 🔴 不再与地址互斥、也不再用地址回落（2026-10-27 主人指正）。
        if options.showsStation {
            let name = station
            if !name.isEmpty { parts.append(truncated(name, limit: limit)) }
        }

        if options.showsAddress {
            let text = trimmedAddress(limit)
            if !text.isEmpty { parts.append(text) }
        }

        // 去重：平台名与站名撞车是常事（「菜鸟驿站」既是平台也是站点，
        // 兔喜生活、妈妈驿站同理），不去重就会渲染成「菜鸟驿站｜菜鸟驿站」。
        var unique: [String] = []
        for part in parts where !unique.contains(part) {
            unique.append(part)
        }

        return unique.isEmpty ? nil : unique.joined(separator: "｜")
    }

    /// 取件码后面紧跟的「现场定位信息」：快递柜优先，没柜退回货架；两者都没有返回 nil。
    ///
    /// 主人 2026-10-27 口径：「取件码后面有就显示快递柜信息，快递柜信息没有则为空」。
    /// 2026-10-27 晚加开关：`options.showsLocker` 关掉后这一位不显示。
    /// 退回货架是有意的 —— 驿站场景没有柜，但「3号货架」同样是他到店要用的那条信息，
    /// 空着纯属浪费。两者语义都属「去哪一格」，放同一位置不算混搭。
    func widgetLockerLabel(_ options: WidgetDisplayOptions) -> String? {
        guard options.showsLocker else { return nil }
        if let locker, !locker.isEmpty { return locker }
        if let shelf, !shelf.isEmpty { return "货架\(shelf)" }
        return nil
    }

    /// 按指定上限截断任意文本（站名复用地址那一套截断口径）
    private func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

}

// MARK: - 卡面命名口径（整个Codelumi唯一真源 · 2026-10-28 主人定）
//
// 主人原话：「整个Codelumi遵循一套逻辑，而不是东一套西一套的」。
// 于是**所有出现「快递公司 ｜ 快递驿站」的地方都从这里取值**：
//   待取卡 · 已取卡 · 详情页 · 分享卡 · 锁屏卡 · 灵动岛 · 小组件
// 各视图只负责排版（字号/间距/胶囊样式），不许再各写一遍优先级 ——
// 之前就是四处各写一版，才出现「列表写韵达快递｜兴裕隆超市、详情页写
// 兴裕隆超市｜韵达快递、分享卡又写第三套」的自相矛盾。
//
// 规则（优先级逐字对应主人 2026-10-28 口径）：
// ```
// 第一段 = 快递公司（courier）→ 没有则短信平台（company）→ 都没有才用驿站
// 第二段 = 快递驿站（station）→ 没有则短信平台（company），且不得与第一段重复
// 图标 / 主题色匹配串 = 第一段（「图标以第一行第一个字段为准」）
// ```
// 快递柜不参与取名，它是跟在第二段后面的标签（见 `PickupRecord.locker`）。
struct PickupNaming: Equatable {
    /// 第一段：谁承运 / 谁发的
    let primary: String
    /// 第二段：管道符后面的驿站或平台；没有则整段不出现（不留孤立「｜」）
    let secondary: String?
    /// 传入的驿站名（保留下来供「主名本身就是驿站」判定用）
    let station: String?
    /// 这个驿站若已归入某个**驿站组**，这里是组名（2026-11-17 主人）。
    /// `station` 仍是原始匹配到的成员驿站名 —— 两者都要，卡面才写得出「新组/原名」。
    let stationGroup: String?

    /// 图标与主题色的匹配串 —— **恒等于第一段**
    var iconSource: String { primary }

    /// 主名本身就是驿站（快递公司与短信平台都空）—— 只有这种情况图标才用驿站图标。
    /// 🔴 各视图一律读这个布尔，别再各自写 `if let station, primary == station`。
    var isStationPrimary: Bool {
        guard let station, !station.isEmpty else { return false }
        return station == primary
    }

    /// 卡面第二段**实际要显示**的字符串。
    ///
    /// 归组后是「新组/原始匹配驿站」（老大 2026-11-17 定稿），没归组就是原来的驿站名。
    /// 分组键用组名（`PickupSortLogic.stationName`），显示层用这个 —— 两者刻意分开：
    /// 组名短、能一眼认出是哪个取件点；原始成员名留在斜杠后面，用户仍知道是哪家。
    var secondaryLabel: String? {
        guard let secondary else { return nil }
        guard let stationGroup, !stationGroup.isEmpty, stationGroup != secondary else {
            return secondary
        }
        return "\(stationGroup)/\(secondary)"
    }

    /// 走单一解析入口的构造器（App / 小组件 / 分享卡 / 灵动岛都该用它）。
    ///
    /// 与下面的 `init(courier:platform:station:)` 的区别只有一个：
    /// 驿站**与组**同时由 `StationResolver` 给出 —— 手动指定的组、
    /// 自定义驿站、多组不猜这些规则都包含在内。
    init(courier: String?, platform: String, resolution: StationResolution) {
        let station = resolution.hasStation ? resolution.stationName : nil
        self.init(courier: courier, platform: platform, station: station,
                  group: (resolution.groupName?.isEmpty == false) ? resolution.groupName : nil)
    }

    /// 两段命名的唯一装配点：组名可直接给（`stationGroup` 是 `let`，
    /// 不能在委托 init 之后再赋值 —— Swift 只允许在**同一个** init 里初始化 let）。
    private init(courier: String?, platform: String, station: String?, group: String?) {
        func clean(_ raw: String?) -> String {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let carrier = clean(courier)
        let platformName = clean(platform)
        let stationName = clean(station)

        var main = carrier.isEmpty ? platformName : carrier
        if main.isEmpty { main = stationName }
        self.primary = main
        self.station = stationName.isEmpty ? nil : stationName
        self.stationGroup = clean(group).isEmpty ? nil : clean(group)

        var suffix: String?
        for candidate in [stationName, platformName] where !candidate.isEmpty && candidate != main {
            suffix = candidate
            break
        }
        self.secondary = suffix
    }

    init(courier: String?, platform: String, station: String?) {
        // 传入的 courier 由调用方给 `record.courierDisplay`（已归一成标准名）
        func clean(_ raw: String?) -> String {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let carrier = clean(courier)
        let platformName = clean(platform)
        let stationName = clean(station)
        // 组归属：成员唯一归属时才认（多组并存交给 `StationResolver` 判，
        // 那条路走下面的 `resolution:` 重载，不会到这里）
        let resolvedGroup = stationName.isEmpty
            ? nil
            : StationGroupStore.memberGroupName(for: stationName)

        // 第一段：快递公司 → 短信平台 → 驿站（三者全空才落到空串）
        var main = carrier.isEmpty ? platformName : carrier
        if main.isEmpty { main = stationName }
        self.primary = main
        self.station = stationName.isEmpty ? nil : stationName
        // 组关系统一在这里解析：App / 小组件 / 分享卡都走同一个 init，
        // 不必让每个调用方各传一次（漏一处就会出现「这页显示组名、那页显示成员名」）。
        self.stationGroup = resolvedGroup

        // 第二段：驿站 → 短信平台，取第一个「非空且不等于第一段」的
        var suffix: String?
        for candidate in [stationName, platformName] where !candidate.isEmpty && candidate != main {
            suffix = candidate
            break
        }
        self.secondary = suffix
    }
}

extension PickupRecord {
    /// 取本记录的卡面命名。⚠️ `station` 必须由调用方给：
    /// App 侧传 `StationDirectory.shared.matchedName(in: [rawMessage])`（含用户自定义驿站），
    /// Widget / 实时活动侧传 `record.station`（纯词表匹配，无 UserDefaults 依赖）。
    /// 数据源不同，**规则相同** —— 这才是「一套逻辑」。
    func naming(station: String?) -> PickupNaming {
        PickupNaming(courier: courierDisplay, platform: company, station: station)
    }

    /// 走单一解析入口的卡面命名（2026-11-21 起 App 侧统一用这个）。
    var namingResolved: PickupNaming {
        PickupNaming(courier: courierDisplay, platform: company, resolution: stationResolution)
    }
}

// MARK: - 取件码末四位强调（2026-10-14，参照上岛记「快递末四位」可读性优化）
//
// 用户在驿站真正用到的只有最后几位：报给店员、输进柜机的都是那一小段。
// 全码同权重渲染时，长码（15 位运单号）的重点被淹没 —— 这里把**前段弱化、
// 末四位保持全色**，视线自然落在该看的地方。
//
// 返回 `Text` 而非 View：九个渲染面（首页卡 / 浏览卡 / 详情 / 分享卡 /
// 小组件 / 灵动岛）各自控制字号与版式，此处不锁死任何排版参数。
//
// 🔴 做成**吃 code 字符串**的独立构造器而非只扩展 PickupRecord：
//    灵动岛的状态里跑的是轻量副本 `PickupActivityAttributes.Item`，
//    它不是 PickupRecord —— 挂在字符串上，两种状态模型都能用。

enum PickupCodeEmphasis {

    /// 取件码前段（去掉末四位）
    static func head(_ code: String) -> String {
        code.count > 4 ? String(code.dropLast(4)) : code
    }

    /// 取件码末四位 —— 报取件时真正念的那一段
    static func tail(_ code: String) -> String {
        String(code.suffix(4))
    }

    /// 取件码 `Text`：颜色 / 整码透明度 / 末四位强调三个设置**全端统一**在这里收口。
    ///
    /// 🔴 2026-11-16 主人：「可以设置取件码卡片中取件码的颜色……也可以设置一条
    ///    取件码的透明度保持一个就行的」。此前前段写死 `0.45`、整串恒不透明，
    ///    而且灵动岛另传 `0.78` —— 现在全部读 `CodeAppearanceStyle.current`：
    ///      · `tint` 参数降级为「跟随品牌色」时的回落值（各视图原本的品牌色口径不变）；
    ///      · 用户在色板里选了固定色，则九个渲染面一起换色；
    ///      · 关掉「末四位强调」后整串只剩一个颜色、一个透明度。
    ///    `headOpacity` 仍保留为可覆盖参数，但 App 内已无调用点传它。
    ///
    /// 已取态整串转次级色（划线仍由调用处叠），不随色板染色 —— 别让"已取"看着还像待取。
    /// 码长 ≤ 4 时不拆分，整串全色。
    ///
    /// 2026-10-20：iOS 26 起 `Text + Text` 已弃用（' + ' was deprecated in iOS 26.0），
    /// 改用 `AttributedString` 承载分段着色；返回值仍为 `Text`，
    /// 因此所有调用处的 `.font/.monospaced/.strikethrough` 链式修饰完全不受影响。
    /// - Parameter style: 显式样式。默认读存储里的当前值（所有真实渲染面都不传）；
    ///   「取件码管理」的效果预览传的是**视图状态**拼出来的样式 —— 否则预览要等
    ///   `onChange` 写完 UserDefaults 才更新，拨开关永远慢一拍（2026-11-20 主人反馈）。
    static func text(_ code: String,
                     isDone: Bool = false,
                     tint: Color,
                     headOpacity: Double? = nil,
                     style explicitStyle: CodeAppearanceStyle? = nil) -> Text {
        let style = explicitStyle ?? CodeAppearanceStyle.current
        let base = isDone ? Color.secondary : style.resolve(tint)
        let whole = base.opacity(style.opacity)
        guard style.emphasisEnabled, code.count > 4 else {
            return Text(code.L).foregroundColor(whole)
        }
        var attributed = AttributedString(code)
        attributed.foregroundColor = whole              // 默认整串 = 末四位色
        if let range = attributed.range(of: head(code)) {
            let headAlpha = style.opacity * (headOpacity ?? style.headOpacity)
            attributed[range].foregroundColor = isDone
                ? Color.secondary
                : base.opacity(headAlpha)
        }
        return Text(attributed)   // AttributedString，不查表
    }
}

// MARK: - 取件码外观（色板 / 透明度 / 强调）

/// 取件码的七档颜色。`.brand` = 跟随快递公司品牌色（升级前的观感，默认）。
///
/// 🔴 全部用**具体色值**而非 `.primary` / `.secondary` 这类语义色：灵动岛与锁屏
///    卡是恒黑底，语义色在浅色外观下会解析成深灰，落在黑底上直接消失。
enum CodeColorChoice: String, CaseIterable, Identifiable {
    case brand
    case blue
    case violet
    case orange
    case green
    case red
    case ink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brand:   return "跟随品牌色"
        case .blue:    return "蓝色"
        case .violet:  return "紫色"
        case .orange:  return "橙色"
        case .green:   return "绿色"
        case .red:     return "红色"
        case .ink:     return "主文字色"
        }
    }

    /// 固定色档的实际颜色；`.brand` 不会被当固定色用（`resolve` 会改用调用方传来的品牌色）。
    var color: Color {
        switch self {
        case .brand:   return AppTheme.accent
        case .blue:    return AppTheme.accent
        case .violet:  return AppTheme.violet
        case .orange:  return AppTheme.todayTint
        case .green:   return AppTheme.doneTint
        case .red:     return Color.adaptive(light: 0xDC2626, dark: 0xF87171)
        case .ink:     return Color.adaptive(light: 0x1C1C1E, dark: 0xF2F2F7)
        }
    }

    /// 设置页色板圆点用的颜色（`.brand` 单独画多色环，这里给个中性回落）。
    var swatch: Color { color }
}

/// 一次渲染读一份快照，避免同一个 `Text` 里多次读偏好域出现半新半旧。
struct CodeAppearanceStyle {
    let choice: CodeColorChoice
    let opacity: Double
    let headOpacity: Double
    let emphasisEnabled: Bool

    static var current: CodeAppearanceStyle {
        CodeAppearanceStyle(
            choice: CodeColorChoice(rawValue: CodeAppearanceSettings.colorRaw) ?? .brand,
            opacity: CodeAppearanceSettings.opacity,
            headOpacity: CodeAppearanceSettings.headOpacity,
            emphasisEnabled: CodeAppearanceSettings.emphasisEnabled)
    }

    /// 选了固定色就用固定色；否则沿用调用方原本的品牌色。
    func resolve(_ brandFallback: Color) -> Color {
        choice == .brand ? brandFallback : choice.color
    }
}

// MARK: - 一张卡片多个取件码（显示层同源分组）
//
// 🔴 2026-11-16 主人：「有些短信一条短信有两个取件码」，希望开一个开关就能
//    让它们回到同一张卡上，关掉再拆回一码一卡，**切换立即对全部历史生效**。
//
// 为什么不合并数据：`PickupParser.parseAll` 一码一条 `PickupRecord`，件数统计、
// 去重指纹、勾选状态、iCloud 同步、小组件勾选日志全都以「一条记录」为单位。
// 真去合并/拆分记录，等于让一次显示设置改写用户数据，还会和云端其它设备打架。
// 这里只做**显示层分组**：同源短信的记录只渲染第一条（代表），其余码挂到同一张卡上，
// 勾选 / 复制 / 删除 / 分享则对整组生效。关掉开关立刻恢复原样，零数据迁移。
enum PickupRecordGrouping {

    /// 同源指纹 = 取件状态 + 短信原文。
    /// 🔴 空原文（手动添加、快捷指令没带短信）**不合并** —— 否则所有手动记录会粘成一张卡。
    /// 取件状态也进 key：待取和已取不能出现在同一张卡上。
    static func key(_ record: PickupRecord) -> String? {
        let raw = record.rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return "\(record.isPickedUp ? 1 : 0)|\(raw)"
    }

    static var isEnabled: Bool { CodeAppearanceSettings.groupsMultipleCodes }

    /// 需要**画出来**的记录集合：每组只留列表里排最前的那一条。
    /// 基于全量列表算，再拿去过滤各个分组 Section —— 同一组即使跨 Section 也只出现一次。
    static func representativeIDs(_ records: [PickupRecord]) -> Set<UUID> {
        guard isEnabled else { return Set(records.map(\.id)) }
        var seen = Set<String>()
        var ids = Set<UUID>()
        for record in records {
            guard let groupKey = key(record) else {
                ids.insert(record.id)
                continue
            }
            if seen.insert(groupKey).inserted { ids.insert(record.id) }
        }
        return ids
    }

    /// 同一组的全部记录（含代表自己），顺序沿用传入数组。
    static func siblings(of record: PickupRecord,
                         in records: [PickupRecord]) -> [PickupRecord] {
        guard isEnabled, let groupKey = key(record) else { return [record] }
        return records.filter { Self.key($0) == groupKey }
    }

    /// 代表记录之外的其它取件码：去重、排除与代表相同的码、保持原顺序。
    static func extraCodes(for record: PickupRecord,
                           in records: [PickupRecord]) -> [String] {
        guard isEnabled else { return [] }
        var codes: [String] = []
        for sibling in siblings(of: record, in: records) where sibling.id != record.id {
            if sibling.code != record.code, !codes.contains(sibling.code) {
                codes.append(sibling.code)
            }
        }
        return codes
    }
}

extension PickupRecord {

    /// 取件码前段（去掉末四位）
    var codeHead: String { PickupCodeEmphasis.head(code) }

    /// 取件码末四位 —— 报取件时真正念的那一段
    var codeTail: String { PickupCodeEmphasis.tail(code) }

    /// 末四位强调的取件码 `Text`（详见 `PickupCodeEmphasis.text`）
    func emphasizedCodeText(isDone: Bool = false,
                            tint: Color,
                            headOpacity: Double? = nil) -> Text {
        PickupCodeEmphasis.text(code, isDone: isDone, tint: tint,
                                headOpacity: headOpacity)
    }
}

// MARK: - 合并策略（同码再进 → 自动完成旧条 + 新增新条）

/// 一批新记录与既有列表的合并规则。
///
/// **语义（2026-09-21 定案）**：收到**同一件包裹**的再次通知（同类别 + 同取件码 +
/// 同地址）时，说明上一条的使命已经结束 —— 把旧条**自动标记为已取**，
/// 本次短信作为**新的一条**写入。
///
/// 典型场景：同一件包裹先收到「已到站」，几小时后又收到「滞留 1 天未取，请尽快取件」，
/// 两条取件码相同。旧行为是把后一条当重复**直接丢弃**，结果是用户**看不到最新一条**
/// （新短信里的地址、时限、状态更准），而旧条永远停在待取列表里。
///
/// 与「去重」的分工：过滤的是**重复的短信**，保留的是**同一件的状态演进**。
///
/// 🔴 2026-10-30 主人改口径：同码重复短信**不再「旧条转已取 + 新条入列」** ——
///    那等于替用户宣布「这件取了」，统计里平白多一次已取、停留时长被算成 0。
///    现在走「**更新时间 + 记入 history**」：卡片还是那一张，右上角时间刷成最新，
///    详情页能看到「这个码被通知过几次、分别是什么时候」。
///
/// ⚠️ 只在**未取件**的记录里找同码旧条：已取件的是历史，不该被再次翻动。
enum PickupMerge {
    struct Result {
        /// 合并后的完整列表（顺序 = 既有顺序 + 新写入顺序）
        var records: [PickupRecord]
        /// 本次真正新建的记录
        var added: [PickupRecord]
        /// 因同码再进而被自动标记为已取的旧取件码（旧口径，保留字段兼容调用方）
        var completed: [String]
        /// 被「重复通知」顺带刷新了时间的既有待取条（2026-10-30 新增）
        var updated: [PickupRecord] = []
    }

    static func merge(_ existing: [PickupRecord],
                      with candidates: [PickupRecord]) -> Result {
        var working = existing
        var added: [PickupRecord] = []
        var updated: [PickupRecord] = []
        /// 本批已入库的指纹 —— 用来挡住**批内重复**
        var seenInBatch = Set<String>()

        for candidate in candidates {
            // 🔴 批内重复直接丢掉（2026-10-25 审查修）。
            // 以前只跟 `working` 里的**旧条**比指纹，但每个候选处理完又会 `append`
            // 回 `working`，所以第二条重复短信会匹配上「刚由第一条建出来的那条」，
            // 把它当场标成已取并写 `pickedUpAt`。用户只收到一条通知，
            // 却得到「1 条待取 + 1 条刚取走（停留 0 分钟）」两条记录，
            // 统计页「今日已取」还会 +1、平均停留被拉低。
            guard seenInBatch.insert(candidate.fingerprint).inserted else { continue }

            // 🔴 2026-11-23 老大定：**已取过的件再次收到短信 / 再被录入 → 自动恢复待取，
            //    并刷新时间戳**（"又到了一个"）。以前这里只匹配待取记录，
            //    已取的那条匹配不上，于是新建一条 —— 同一件在已取和待取里各留一份。
            if let index = working.firstIndex(where: {
                $0.isPickedUp && $0.fingerprint == candidate.fingerprint
            }) {
                working[index].pickedUpAt = nil              // 回到待取
                working[index].receivedAt = candidate.receivedAt   // 新时间戳（排序用它）
                working[index].history = (working[index].history ?? [])
                    + [candidate.receivedAt]
                updated.append(working[index])
                continue
            }

            if let index = working.firstIndex(where: {
                !$0.isPickedUp && $0.fingerprint == candidate.fingerprint
            }) {
                // 🔴 2026-10-30 主人改口径：同码重复短信 = **同一件还在待取、又被提醒了一次**，
                //    不是一件新包裹。以前这里把旧条标成「已取」再插一条新的，结果：
                //      · 待取页看起来只多一条，但统计里平白多出一次「已取」；
                //      · 用户根本没取，记录却被判成取了，停留时长被算成 0；
                //      · 万一 merge 没拦住（历史数据 / 并发写入），就会出现两条一模一样的待取。
                //    现在只做两件事：**更新时间 + 记进历史**，不新建、不改已取状态。
                working[index].history = (working[index].history ?? [working[index].receivedAt])
                    + [candidate.receivedAt]
                updated.append(working[index])
                continue
            }
            working.append(candidate)
            added.append(candidate)
        }

        // `completed` 是旧口径（自动替用户标已取）的产物，2026-10-30 起恒为空，
        // 保留字段只为兼容既有调用方，将来可一并删除。
        return Result(records: working, added: added,
                      completed: [], updated: updated)
    }
}

