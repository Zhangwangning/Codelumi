import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 取件码管理（设置 › 桌面小组件下面那一行）
//
// 2026-11-16 主人：「在设置页面中的桌面小组件的下面增加一个取件码管理，其二级页面中
//    可以设置取件码卡片中取件码的颜色……也可以设置一条取件码的透明度保持一个就行的，
//    还有一张卡片多个取件码的设置」。
//
// 四项设置，**全端统一**（待取 / 已取 / 详情 / 桌面小组件 / 灵动岛 / 分享卡）：
//   ① 取件码颜色：七档色板，默认「跟随品牌色」＝升级前观感；
//   ② 整码透明度：整条取件码只用一个透明度，不再前后段不一致；
//   ③ 末四位强调：保留原习惯（默认开），关掉后整串一个色一个透明度；
//      开的时候另有一档「前段透明度」可调；
//   ④ 一张卡片多个取件码：同一条短信拆出的多个码回到一张卡上，关掉立刻拆回一码一卡。
//
// 🔴 ④ 只改**显示层**：数据仍是一码一 `PickupRecord`（见 `PickupRecordGrouping`），
//    因此切换开关立即对全部历史生效，且不碰件数、去重、勾选、iCloud 同步。
//
// ⚠️ 所有值落在 App Group `UserDefaults`（`CodeAppearanceSettings`），
//    改完统一 `notifyChange()` 重画桌面时间线，再 `refreshRendering()` 重画实时活动 ——
//    ActivityKit 的活动不归 WidgetCenter 管，少这一步灵动岛要等下一条快递才变。
//
// 🔴 2026-11-20 主人：「开关开着，为啥上面的预览是一个颜色……开关点击后预览要及时响应，
//    再把这个页面的布局优化一下，提示文字能少则少」。
//    根因有两层，都改在这里：
//      ① 预览原先读的是**存储里的** `CodeAppearanceStyle.current`。SwiftUI 先按新的
//         `@State` 重画一次，`onChange` 才把值写进 UserDefaults —— 于是预览永远慢一拍，
//         拨开关看到的还是上一档样式。现在预览直接用 `@State` 拼一份 `style` 传进去，
//         开关 / 色板 / 滑杆一动就同步重画。
//      ② 预览原来拿 `AppTheme.accent` 冒充品牌色，和真机上圆通的紫对不上。
//         现在走 `CourierBrand.color(for:)` + `CourierLogo`，与列表卡片同源。
//    文案按「非必要不提示」收口：只剩分组标题和行标题，说明一律删掉。
// ============================================================================

struct CodeManagementView: View {
    @State private var colorRaw = CodeAppearanceSettings.colorRaw
    @State private var opacity = CodeAppearanceSettings.opacity
    @State private var headOpacity = CodeAppearanceSettings.headOpacity
    @State private var emphasis = CodeAppearanceSettings.emphasisEnabled
    @State private var groupMultiple = CodeAppearanceSettings.groupsMultipleCodes

    @State private var showOpacityMenu = false
    @State private var showHeadMenu = false

    private var choice: CodeColorChoice {
        CodeColorChoice(rawValue: colorRaw) ?? .brand
    }

    /// 预览专用样式：来源是视图状态，不是存储 —— 这样开关一动预览立刻跟上。
    private var previewStyle: CodeAppearanceStyle {
        CodeAppearanceStyle(choice: choice,
                            opacity: opacity,
                            headOpacity: headOpacity,
                            emphasisEnabled: emphasis)
    }

    private var brandColor: Color {
        CourierBrand.color(for: Self.previewCompany)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                previewSection
                colorSection
                styleSection
                groupingSection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("取件码管理")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 实时预览

    /// 用**真实的** `PickupCodeEmphasis.text` 渲染，所见即九个渲染面所取。
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "效果预览")
            previewCard
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewCodes: [String] {
        groupMultiple ? ["8-4-3019", "8-4-3020"] : ["8-4-3019"]
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(Self.previewCompany.L)
                    .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
                Text("|")
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(Color.secondary.opacity(0.45))
                Text("菜鸟驿站")
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("今天 14:32")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
            }

            Text("幸福里小区 3 号楼东侧门店")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)

            DashedDivider()
                .padding(.top, 8)

            HStack(alignment: .center, spacing: 8) {
                CourierLogo(company: Self.previewCompany, size: 26)

                VStack(alignment: .leading, spacing: previewCodes.count > 1 ? 1 : 0) {
                    ForEach(previewCodes, id: \.self) { code in
                        PickupCodeEmphasis.text(code,
                                                tint: brandColor,
                                                style: previewStyle)
                            .font(.system(size: previewCodes.count > 1 ? 24 : 30,
                                          weight: .bold, design: .rounded))
                            .monospaced()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 7)
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        .cardSurface(tint: brandColor)
        .frame(maxWidth: 360)
    }

    private static let previewCompany = "圆通速递"

    // MARK: 颜色

    private var colorSection: some View {
        SettingsGroup(title: "取件码颜色") {
            HStack(spacing: 0) {
                ForEach(CodeColorChoice.allCases) { item in
                    Button {
                        CodeAppearanceSettings.setColorRaw(item.rawValue)
                        colorRaw = item.rawValue
                        refreshLiveActivity()
                    } label: {
                        swatch(item)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func swatch(_ item: CodeColorChoice) -> some View {
        let selected = item == choice
        ZStack {
            // 「跟随品牌色」画成多色环，一眼区别于六个固定色
            if item == .brand {
                Circle()
                    .fill(AngularGradient(colors: [.red, .orange, .yellow, .green,
                                                   AppTheme.accent, AppTheme.violet, .red],
                                          center: .center))
                    .frame(width: 30, height: 30)
            } else {
                Circle()
                    .fill(item.swatch)
                    .frame(width: 30, height: 30)
            }

            if selected {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 2)
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
            }
        }
        .frame(height: 40)
        .contentShape(.rect)
    }

    // MARK: 显示方式

    private var styleSection: some View {
        SettingsGroup(title: "显示方式") {
            SettingsPlainRow(title: "整码透明度") {
                Button {
                    showOpacityMenu = true
                } label: {
                    SettingsValueLabel(text: Self.percent(opacity))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOpacityMenu, arrowEdge: .top) {
                    valueMenu(options: CodeAppearanceSettings.opacityOptions,
                              current: opacity,
                              label: Self.percent) { picked in
                        CodeAppearanceSettings.setOpacity(picked)
                        opacity = picked
                        refreshLiveActivity()
                        showOpacityMenu = false
                    }
                    .presentationCompactAdaptation(.popover)
                }
            }

            SettingsDivider(style: .plain)

            SettingsPlainRow(title: "末四位强调") {
                Toggle("", isOn: $emphasis)
                    .labelsHidden()
                    .tint(AppTheme.accent)
                    .onChange(of: emphasis) { _, newValue in
                        CodeAppearanceSettings.setEmphasisEnabled(newValue)
                        refreshLiveActivity()
                    }
            }

            if emphasis {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "前段透明度") {
                    Button {
                        showHeadMenu = true
                    } label: {
                        SettingsValueLabel(text: Self.percent(headOpacity))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHeadMenu, arrowEdge: .top) {
                        valueMenu(options: CodeAppearanceSettings.headOpacityOptions,
                                  current: headOpacity,
                                  label: Self.percent) { picked in
                            CodeAppearanceSettings.setHeadOpacity(picked)
                            headOpacity = picked
                            refreshLiveActivity()
                            showHeadMenu = false
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }

    // MARK: 卡片

    private var groupingSection: some View {
        SettingsGroup(title: "卡片") {
            SettingsPlainRow(title: "一张卡片多个取件码") {
                Toggle("", isOn: $groupMultiple)
                    .labelsHidden()
                    .tint(AppTheme.accent)
                    .onChange(of: groupMultiple) { _, newValue in
                        CodeAppearanceSettings.setGroupsMultipleCodes(newValue)
                        refreshLiveActivity()
                    }
            }
        }
    }

    // MARK: 工具

    /// 自绘选单（不用系统 `Menu`：它会把值染成蓝色，破坏「灰字 + chevron」口径）。
    private func valueMenu(options: [Double],
                           current: Double,
                           label: @escaping (Double) -> String,
                           pick: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    pick(option)
                } label: {
                    HStack(spacing: 12) {
                        Text(label(option))
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 20)
                        if abs(option - current) < 0.001 {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(.systemBlue))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 168, height: 42)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// `WidgetCenter` 的重画已在各 setter 里做过；这里补 ActivityKit 那一半。
    private func refreshLiveActivity() {
        Task { await PickupActivityController.refreshRendering() }
    }
}
