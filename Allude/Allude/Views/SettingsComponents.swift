import SwiftUI
import UIKit

// MARK: ============================================================================
// 设置行组件（Apple 设置风格）
//
// 2026-09-22 按主人给的 iOS 设置参考图重做版式。三条改动：
//
//  1) 图标从「浅色底 + 同色图标」改成 **实心彩色圆角方块 + 白色符号** ——
//     这是 iOS 的「设置」「Apple 账户」面板里唯一的图标样式；浅色底那种
//     更像 App 内部的功能标签，放进设置列表会显得轻、撑不起一行的视觉锚点。
//  2) 尺寸对齐系统口径：图标块 32×32（圆角 8.5 连续曲率）、标题 16pt、
//     行尾值 16pt 次级灰、chevron 13pt 四级灰。
//  3) 分隔线**缩进到图标右边缘之后**（`SettingsRow.dividerInset`）而不是从行首起 ——
//     系统就是这么缩的：让"图标列"成为一条与文字列分开的独立轴，
//     文字块的左边界在整组行里严格对齐。
//
// ⚠️ 缩进量必须由 `dividerInset` 统一给出，不要在调用点写死 ——
//    图标尺寸一改，所有分隔线要跟着走，写死就会出现"线没对齐图标"的裂缝。
//
// 旧的 `SettingsView` 页已撤下：「设置」现在是「我的」面板（右上角头像进入）
// 里的一组，导航角色不变，只是不再单独占一个标签位。
// ============================================================================

// MARK: - 设置项图标（唯一实现）

/// 设置项图标：实心彩色圆角方块 + 顶部渐浅 + 白色线性符号。
///
/// 🔴 2026-10-25 主人指出「设置页面各个图标怎么在 Duo 上就变了」——
/// 原因是长页（`SettingsRow`，32pt / 圆角 8.5 / 渐变）与分栏侧栏
/// （`settingsSidebarRow`，当时另写的 22pt / 圆角 5.5 / 纯色）各画了一套。
/// 现在只有这一个组件，尺寸由 `size` 决定，圆角与符号字号按比例派生，
/// 两处视觉必然一致。
struct SettingsGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 32

    /// 圆角 / 符号字号都按 32pt 基准等比缩放（32→8.5、32→15）
    private var radius: CGFloat { size * (8.5 / 32) }
    private var glyphSize: CGFloat { size * (15.0 / 32) }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(colors: [tint.opacity(0.82), tint],
                               startPoint: .top,
                               endPoint: .bottom)
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct SettingsRow: View {
    let symbol: String
    /// 有值时用**图片**当行首图标（平台品牌图标），否则用 `symbol` 的 SF Symbol。
    /// 2026-11-01 联系方式页需要展示小红书/微信/抖音的官方图标。
    var imageAsset: String? = nil
    let title: String
    var subtitle: String? = nil
    /// 副标题强制单行（2026-10-31，UUID 这类定长标识用）。
    /// 宽度不够时按比例缩字，而不是折成两行 —— 折行会把整行撑高、
    /// 第二段还会越过图标列，看着像排版坏了。
    var subtitleOneLine: Bool = false
    var detail: String? = nil
    var showsChevron: Bool = true
    var tint: Color = AppTheme.accent
    /// 行尾自定义控件（例如开关）。擦除成 `AnyView`，免得给整个结构体加泛型参数
    /// 而牵动已有的几十处调用点。
    var trailing: AnyView? = nil
    /// 会员专属且**当前未解锁** → 行尾挂一把小锁。
    ///
    /// 2026-09-23 主人要求：不要单独做一个"高级功能"介绍页让人点进去才知道要钱，
    /// 而是**在功能自己所在的那一行直接标明**。
    /// 🔴 挂锁时**不再画 chevron** —— 「🔒 ›」并排语义打架（既然点了也用不了，
    /// 就不该暗示"可以进去操作"）。行仍可点，进去是 VIP 页/预览。
    var locked: Bool = false

    // MARK: 尺寸口径
    static let iconSize: CGFloat = 32
    static let hPadding: CGFloat = 16
    static let iconGap: CGFloat = 12
    /// 分隔线起点 = 左内边距 + 图标宽 + 图标与文字的间距
    static var dividerInset: CGFloat { hPadding + iconSize + iconGap }

    var body: some View {
        HStack(spacing: Self.iconGap) {
            icon
            labels
            Spacer(minLength: 10)
            if let detail { detailText(detail) }
            if let trailing { trailing }
            if locked { lockGlyph } else if showsChevron { chevron }
        }
        .padding(.horizontal, Self.hPadding)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    /// 实心彩色方块：顶部稍浅、底部到本色，与系统设置的图标块同一观感。
    @ViewBuilder private var icon: some View {
        if let imageAsset {
            Image(imageAsset)
                .resizable()
                .interpolation(.high)
                // 与 SettingsGlyph 的观感对齐：同一尺寸、同一连续圆角比例
                .frame(width: Self.iconSize, height: Self.iconSize)
                .clipShape(.rect(cornerRadius: Self.iconSize * 0.29, style: .continuous))
        } else {
            SettingsGlyph(symbol: symbol, tint: tint, size: Self.iconSize)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 标题多为动态 String（来自枚举），必须显式查表才会跟随语言
            Text(title.L)
                .font(AppTheme.TypeScale.rowTitle)
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle.L)
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(.tertiary)
                    .lineLimit(subtitleOneLine ? 1 : nil)
                    .minimumScaleFactor(subtitleOneLine ? 0.72 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func detailText(_ text: String) -> some View {
        Text(text.L)
            .font(AppTheme.TypeScale.rowTitle)
            .foregroundStyle(.secondary)
            // 行尾值不允许被压成两行：它多是「关闭 / 80% / 顶部」这类短词，
            // 一旦换行会与左侧标题错位得非常明显。
            .fixedSize(horizontal: true, vertical: false)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
            .foregroundStyle(.quaternary)
    }

    /// 会员专属的锁：用金色（`amber`）而不是灰 —— 灰色在这一列里与
    /// 行尾值、chevron 混成一片，扫一眼分不出来；金色是"这是 VIP 的"的标记色，
    /// 与用户名旁边那枚 VIP 徽章同色，两处互相对得上。
    private var lockGlyph: some View {
        Image(systemName: "lock.fill")
            .font(AppTheme.TypeScale.note.weight(.semibold))
            .foregroundStyle(AppTheme.amber)
    }
}

// MARK: - 组内分隔线

/// 设置卡内的行间分隔线。
///
/// 缩进分两档，取决于这一组行**有没有图标**：
///   · `.withIcon`（默认）—— 对齐到图标右缘（一级菜单里的入口行都是这个）；
///   · `.plain` —— 从行首内边距起（二级设置页的开关行/值行没有图标，
///     这时再缩到 60pt 会留下一段莫名其妙的空白）。
struct SettingsDivider: View {
    enum Style {
        case withIcon
        case plain
    }

    var style: Style = .withIcon

    var body: some View {
        Divider()
            .padding(.leading, style == .withIcon
                     ? SettingsRow.dividerInset
                     : SettingsRow.hPadding)
    }
}

// MARK: ============================================================================
// 二级设置页的行 / 卡（iOS 设置的「开关页」形态）
//
// 与 `SettingsRow`（带彩色图标的入口行）分工明确：
//   · **入口行**（`SettingsRow`）：一级菜单里"点进去某个功能"，带图标、带副标题；
//   · **开关行 / 值行**（本节的 `SettingsPlainRow`）：二级页里"就地改一个值"，
//     **不带图标**、不带副标题 —— 说明文字放到卡片外下方。
//
// 依据是 iOS 自己的设置页（图例：辅助功能 › 触控 / 悬停文本）：
//   ① 二级页的行几乎都没有图标；带图标的只有"又是一个功能入口"那种行；
//   ② 标题与说明**分离**：标题留在卡内（17pt），说明落到卡外（13pt 灰），
//      缩进与卡内文字对齐 —— 卡里塞两行字会让每一行都变高、整页像一堵墙；
//   ③ 值是行尾灰字 + `›`，点了弹选择；开关在行尾，不额外配文案。
// ============================================================================

/// 分组卡：卡外可挂一段说明文字（在卡的下方、缩进对齐）。
struct SettingsCard<Content: View>: View {
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(spacing: 0) { content }
                // 设置类页面统一卡片：iOS 26+ 玻璃胶囊 / iOS 18 系统卡片
                .settingsCard()

            if let note {
                Text(note.L)
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 带分组标题的一组设置（标题在卡外，iOS 设置页的标准节奏）。
struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String? = nil
    /// 分组标题挂「实验室」徽章（统一标记，见 `LabBadge`）
    var isLab: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题为空时**整行不渲染**（Text("") 仍会占一行高度，上方会多出空白）。
            if !title.isEmpty {
                SectionHeader(title: title, isLab: isLab)
            }
            SettingsCard(note: note) { content }
        }
    }
}

/// 二级页里的一行：标题在左，控件/值在右。**不带图标**（见上方说明）。
struct SettingsPlainRow<Trailing: View>: View {
    let title: String
    /// 标题后挂「实验室」徽章（2026-11-22：徽章要跟着**功能本体**这一行走，
    /// 不能孤零零躺在页面底部的说明旁边 —— 那样看不出它在标哪一项）
    var isLab: Bool = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            // 标题多为动态 String（来自枚举），必须显式查表才会跟随语言
            Text(title.L)
                .font(AppTheme.TypeScale.rowTitle)
                .fixedSize(horizontal: false, vertical: true)

            if isLab {
                LabBadge()
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .contentShape(.rect)
    }
}

/// 行尾的值：灰字 + `›`。点击弹出菜单（`Menu` 的 label 用它）。
///
/// 🔴 值必须是**普通 `Text`**，不能用 `Picker(.menu)` 直接把选项文字摆出来 ——
///    菜单样式的 Picker 在行内是可压缩的，宽度一紧就把「24 小时」折成
///    「24 / 小时」两行（真机上就是"时间错位"）。这里值是自己写的 Text，
///    加 `fixedSize` 后永远单行。
struct SettingsValueLabel: View {
    let text: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Text(text.L)
                .font(AppTheme.TypeScale.rowTitle)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
        }
    }
}
