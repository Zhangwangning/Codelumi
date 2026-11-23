import SwiftUI

// MARK: ============================================================================
// 统计组件库
//
// 🔴 2026-10-08 结构重构：统计页已与浏览页合并（`BrowseView`，见 HistoryView.swift），
// 独立的 `StatsView` 页面退役。本文件只保留统计**组件** —— StatCard / StatTriple /
// DailyBarChart / HourlyBarChart / CompanyRow / KindRow / RatioBar，由 BrowseView 引用。
//
// 数字全部来自 `PickupStats`（口径集中在那一个文件里，页面只负责画）。
// 版式沿用全站的内容层口径：实体卡片（`cardSurface`）+ 内容内着色，
// 导航层之外的任何位置都不叠玻璃。
// ============================================================================

// MARK: ============================================================================
// 页面组件
// ============================================================================

/// 统计卡外壳：卡外标题 + 卡体，成组出现，与「我的」面板的分组同一节奏。
struct StatCard<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.L)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note.L)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 4)

            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }
    }
}

// MARK: - 三格总和卡

/// 三格等分卡：等分三格、0.5pt 竖直分隔线、品牌色数字 —— 三张卡并排出现时才不会打架。
///
/// ⚠️ 它与 `HeroStatsCard`（待取页 / 已取页顶部那张 46pt 大数字卡）**不是同一张**：
///    这里是统计页用的三格等分版式，尺寸按 22pt 数字收紧。
struct StatTriple: View {
    struct Item {
        let title: String
        let value: String
        let tint: Color
        let symbol: String
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { divider }
                cell(item)
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 0.5, height: 34)
    }

    private func cell(_ item: Item) -> some View {
        VStack(spacing: 3) {
            Text(item.value.L)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(item.tint)

            HStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 9, weight: .medium))
                Text(item.title.L)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 近 N 天柱状图

struct DailyBarChart: View {
    let points: [PickupStats.DayPoint]
    /// 峰值（归一化基准）。0 表示窗口内一件都没取。
    let peak: Int

    private let barArea: CGFloat = 88

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(points) { point in
                VStack(spacing: 6) {
                    // 柱体：按峰值等比。0 件时留一根 3pt 的灰墩，
                    // 让那天在轴上仍然有位置感 —— 空白柱会让人以为图表缺了一格。
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fill(for: point))
                        .frame(height: height(for: point))

                    Text(point.axisLabel.L)
                        .font(.system(size: 9, weight: point.isToday ? .bold : .regular))
                        .foregroundStyle(point.isToday ? AppTheme.accent : Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: barArea + 20, alignment: .bottom)
    }

    private func height(for point: PickupStats.DayPoint) -> CGFloat {
        guard peak > 0, point.picked > 0 else { return 3 }
        let ratio = CGFloat(point.picked) / CGFloat(peak)
        return max(6, barArea * ratio)
    }

    private func fill(for point: PickupStats.DayPoint) -> AnyShapeStyle {
        if point.picked == 0 {
            return AnyShapeStyle(Color.secondary.opacity(0.16))
        }
        return AnyShapeStyle(
            LinearGradient(colors: [AppTheme.accentLight, AppTheme.accent],
                           startPoint: .top, endPoint: .bottom)
                .opacity(point.isToday ? 1 : 0.72)
        )
    }
}

// MARK: - 24 小时分布

struct HourlyBarChart: View {
    let buckets: [Int]

    var body: some View {
        let peak = buckets.max() ?? 0

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { hour, count in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(barStyle(hour: hour, count: count))
                        .frame(height: height(count: count, peak: peak))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56, alignment: .bottom)

            // 轴刻度只标四个点：0 / 6 / 12 / 18 —— 24 个数字在手机宽度下读不出来
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18, 23], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity,
                               alignment: hour == 0 ? .leading : (hour == 23 ? .trailing : .center))
                }
            }
        }
    }

    private func height(count: Int, peak: Int) -> CGFloat {
        guard peak > 0, count > 0 else { return 2 }
        return max(5, 56 * CGFloat(count) / CGFloat(peak))
    }

    /// 早 7 点 – 晚 22 点是取件的活跃时段，用主色；其余时段用更淡的灰蓝，
    /// 这样一眼能看出「取件集中在白天」而不是把 24 根柱平均看待。
    private func barStyle(hour: Int, count: Int) -> AnyShapeStyle {
        let isAwake = (7...21).contains(hour)
        if count == 0 { return AnyShapeStyle(Color.secondary.opacity(0.14)) }
        return AnyShapeStyle(isAwake ? AppTheme.accent : AppTheme.indigo.opacity(0.55))
    }
}

// MARK: - 公司行

struct CompanyRow: View {
    let point: PickupStats.CompanyPoint
    let total: Int

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return Double(point.total) / Double(total)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                CourierLogo(company: point.name, size: 22)

                Text(point.name.L)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(point.total)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(point.tint)

                Text("件")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                RatioBar(ratio: ratio, tint: point.tint)

                Text(percentText.L)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.vertical, 9)
    }

    private var percentText: String {
        String(format: "%.0f%%", ratio * 100)
    }
}

// MARK: - 占比条

struct RatioBar: View {
    let ratio: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    // 极小占比也留 4pt，否则「1 件」会画成一条看不见的线
                    .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, ratio)))))
            }
        }
        .frame(height: 5)
    }
}
