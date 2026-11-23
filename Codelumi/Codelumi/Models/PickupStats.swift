import Foundation
import SwiftUI

// MARK: ============================================================================
// 取件统计（「统计」页的唯一数据来源）
//
// 一份纯计算：输入全部记录 + 参考时间，输出页面需要的一切派生量。
// 放在这里而不是散在 View 里的理由：
//   · 口径集中一处 —— 「取件频率」到底按什么时间算，只有这里说了算；
//   · 可单独验证 —— 页面渲染与数字计算解耦，改版式不会顺手改错口径。
//
// ── 口径（关键，不要在其他地方另立一套） ──────────────────────────────────
//  · **入库** 一律用 `receivedAt`（短信到达时刻）；
//  · **取件** 一律用 `pickupMoment` = `pickedUpAt ?? receivedAt`
//    —— 只有从更早版本升级上来的记录才会走到回退分支（那时还没有时间戳字段），
//    回退值虽然粗糙，但好过让这批记录在统计里凭空消失；
//  · **平均停留** 只统计**真有 `pickedUpAt`** 的记录。若拿回退值去算，
//    分子分母同时退化成 0，会得出「平均 0 分钟取件」这种假数据 ——
//    宁可显示「暂无数据」，也不能编一个数字出来。
// ============================================================================

struct PickupStats {

    // MARK: 图表数据点

    struct DayPoint: Identifiable {
        let date: Date
        /// 当天取走几件
        let picked: Int
        /// 当天入库几条
        let received: Int

        var id: Date { date }

        var isToday: Bool { Calendar.current.isDateInToday(date) }

        /// 柱状图横轴标签（今天标「今」，其余标星期）
        var axisLabel: String {
            if isToday { return "今" }
            return Self.weekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
        }

        /// 完整日期，如「9月22日」
        var dayLabel: String {
            let calendar = Calendar.current
            return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
        }

        /// 星期几的完整名称
        var weekdayName: String {
            Self.weekdayNames[Calendar.current.component(.weekday, from: date) - 1]
        }

        private static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
        private static let weekdayNames = ["星期日", "星期一", "星期二", "星期三",
                                          "星期四", "星期五", "星期六"]
    }

    struct CompanyPoint: Identifiable {
        let name: String
        /// 该公司累计入库条数
        let total: Int
        let picked: Int
        let pending: Int

        var id: String { name }
        var tint: Color { CourierBrand.color(for: name) }
    }

    // MARK: 总览

    /// 累计入库（含已取与待取）
    let receivedTotal: Int
    /// 累计已取
    let pickedTotal: Int
    /// 当前待取
    let pendingTotal: Int

    let pickedToday: Int
    let receivedToday: Int
    let pickedThisWeek: Int
    let pickedThisMonth: Int

    // MARK: 频率

    /// 近 `window` 天（含今天），按日期升序
    let daily: [DayPoint]
    /// 统计窗口天数
    let window: Int
    /// 窗口内有取件动作的天数
    let activeDays: Int
    /// 窗口内最忙的一天的取件数（柱状图归一化基准）
    let busiestDayCount: Int

    // MARK: 时段

    /// 24 个小时桶，索引 = 小时，值 = 该时段取走几件
    let hourly: [Int]

    // MARK: 分组

    let companies: [CompanyPoint]
    // 🔴 2026-10-28 主人：删掉「凭证类别」维度（`kinds` / `KindPoint`）。
    //    Codelumi不再区分取件码信息的类型 —— 取件码、运单号、尾号在界面上是一个东西，
    //    所以统计页也不该把它们拆成四行占比。

    // MARK: 效率

    /// 平均停留（收到 → 取走）。**仅统计有 `pickedUpAt` 的记录**，无数据时 nil。
    let averageStay: TimeInterval?
    /// 最快一次取件耗时
    let fastestStay: TimeInterval?
    /// 参与停留统计的样本数
    let staySampleCount: Int

    /// 连续取件天数（从今天/昨天往前数）
    let streak: Int

    // MARK: - 构造

    init(records: [PickupRecord],
         now: Date = Date(),
         window windowDays: Int = 14,
         calendar: Calendar = .current) {
        let days = max(1, windowDays)
        let windowStart = calendar.startOfDay(for: calendar.date(byAdding: .day,
                                                                value: -(days - 1),
                                                                to: now) ?? now)

        receivedTotal = records.count
        pickedTotal = records.filter(\.isPickedUp).count
        pendingTotal = records.filter { !$0.isPickedUp }.count

        let pickedUp = records.filter(\.isPickedUp)

        pickedToday = pickedUp.filter { calendar.isDateInToday($0.pickupMoment) }.count
        receivedToday = records.filter { calendar.isDateInToday($0.receivedAt) }.count
        pickedThisWeek = pickedUp.filter {
            calendar.isDate($0.pickupMoment, equalTo: now, toGranularity: .weekOfYear)
        }.count
        pickedThisMonth = pickedUp.filter {
            calendar.isDate($0.pickupMoment, equalTo: now, toGranularity: .month)
        }.count

        // ── 按天分桶（近 window 天）
        var pickedByDay: [Date: Int] = [:]
        var receivedByDay: [Date: Int] = [:]

        for record in records {
            let receivedDay = calendar.startOfDay(for: record.receivedAt)
            if receivedDay >= windowStart { receivedByDay[receivedDay, default: 0] += 1 }

            guard record.isPickedUp else { continue }
            let pickedDay = calendar.startOfDay(for: record.pickupMoment)
            if pickedDay >= windowStart { pickedByDay[pickedDay, default: 0] += 1 }
        }

        var points: [DayPoint] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else { continue }
            points.append(DayPoint(date: day,
                                   picked: pickedByDay[day] ?? 0,
                                   received: receivedByDay[day] ?? 0))
        }
        daily = points
        self.window = days
        activeDays = points.filter { $0.picked > 0 }.count
        busiestDayCount = points.map(\.picked).max() ?? 0

        // ── 时段分布
        var buckets = Array(repeating: 0, count: 24)
        for record in pickedUp {
            let hour = calendar.component(.hour, from: record.pickupMoment)
            if (0..<24).contains(hour) { buckets[hour] += 1 }
        }
        hourly = buckets

        // ── 各快递
        var companyCounter: [String: (total: Int, picked: Int)] = [:]
        for record in records {
            var entry = companyCounter[record.company] ?? (0, 0)
            entry.total += 1
            if record.isPickedUp { entry.picked += 1 }
            companyCounter[record.company] = entry
        }

        companies = companyCounter
            .map { CompanyPoint(name: $0.key,
                                total: $0.value.total,
                                picked: $0.value.picked,
                                pending: $0.value.total - $0.value.picked) }
            // 件数降序；同件数按名称升序，保证同样的数据每次排出来一致
            .sorted { ($0.total, $1.name) > ($1.total, $0.name) }

        // ── 停留时长（**只用真时间戳**，见文件头口径说明）
        let stays: [TimeInterval] = pickedUp.compactMap { record in
            guard let stamp = record.pickedUpAt else { return nil }
            let interval = stamp.timeIntervalSince(record.receivedAt)
            // 负数（时钟回拨 / 数据被手工改过）与超过 30 天的值按脏数据处理，
            // 否则一条异常记录就能把平均值拖到没有意义的地方。
            guard interval >= 0, interval <= 30 * 86_400 else { return nil }
            return interval
        }
        staySampleCount = stays.count
        averageStay = stays.isEmpty ? nil : stays.reduce(0, +) / Double(stays.count)
        fastestStay = stays.min()

        // ── 连续取件天数：今天有就算从今天起，否则从昨天起（避免"今天还没取"就断签）
        var run = 0
        var cursor = 0
        let todayHasPicked = (pickedByDay[calendar.startOfDay(for: now)] ?? 0) != 0
        // 用全量已取件判断（不受窗口限制），但窗口只有 14 天，长连续会被截到这里
        let allPickedDays = Set(pickedUp.map { calendar.startOfDay(for: $0.pickupMoment) })
        if !todayHasPicked { cursor = 1 }
        while true {
            guard let day = calendar.date(byAdding: .day, value: -cursor, to: calendar.startOfDay(for: now)),
                  allPickedDays.contains(day) else { break }
            run += 1
            cursor += 1
        }
        streak = run
    }

    // MARK: - 派生摘要

    var topCompany: CompanyPoint? { companies.first }

    /// 取件最多的时段，格式「17:00 – 19:00」（把相邻高峰合并成一段）
    var busiestHourRange: String? {
        let peak = hourly.max() ?? 0
        guard peak > 0, let peakHour = hourly.firstIndex(of: peak) else { return nil }
        // 从峰值小时向后扩展连续非零时段
        var end = peakHour
        while end + 1 < 24, hourly[end + 1] > 0, end - peakHour < 3 { end += 1 }
        // 向前扩展一格，让区间更像人读的"傍晚"而不是"18点整"
        let start = max(0, peakHour - (peakHour > 0 && hourly[peakHour - 1] > 0 ? 1 : 0))
        return String(format: "%02d:00 – %02d:00", start, min(23, end + 1))
    }

    /// 近窗口内取件最多的星期几（如「星期五」）
    var busiestWeekday: String? {
        var counter: [Int: Int] = [:]
        for point in daily where point.picked > 0 {
            let weekday = Calendar.current.component(.weekday, from: point.date)
            counter[weekday, default: 0] += point.picked
        }
        guard let best = counter.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }) else { return nil }
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[(best.key - 1) % 7]
    }

    /// 窗口内日均取件（保留一位小数）
    var dailyAverage: Double {
        guard window > 0 else { return 0 }
        let total = daily.reduce(0) { $0 + $1.picked }
        return Double(total) / Double(window)
    }

    /// 是否有任何可用于展示的数据
    var isEmpty: Bool { receivedTotal == 0 }
}

// MARK: - 时长格式化

extension PickupStats {
    /// 把时间间隔说成「3 小时 12 分」这类人话。用于平均停留 / 最快取件。
    static func durationText(_ interval: TimeInterval?) -> String {
        guard let interval else { return "—" }
        let minutes = Int(interval / 60)
        if minutes < 1 { return "不到 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }

        let hours = minutes / 60
        let rest = minutes % 60
        if hours < 24 {
            return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
        }
        let days = hours / 24
        let restHours = hours % 24
        return restHours == 0 ? "\(days) 天" : "\(days) 天 \(restHours) 小时"
    }
}
