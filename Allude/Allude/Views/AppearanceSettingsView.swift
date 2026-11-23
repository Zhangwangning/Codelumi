import SwiftUI
import UIKit

// MARK: ============================================================================
// 设置 › 外观 / 字体大小（2026-11-04 主人定）
//
// 外观：三档（自动 / 浅色 / 深色），存 App Group，根视图用 preferredColorScheme 生效。
// 字体大小：二级页 —— 预览区（照主人给的参考图）+「跟随系统」开关 + 底部字号滑块。
//
// 🔴 字号不是逐页改，而是**全局倍率**（`FontScale`），`AppTheme.TypeScale` 里每档都乘它。
// ============================================================================

// MARK: - 根视图外观宿主

/// 把外观与字号接到整棵视图树上的宿主。
///
/// 为什么要包一层：
///   · `preferredColorScheme` 必须在**根**上设，散在页面里会被系统覆盖；
///   · 字号是 static 倍率，SwiftUI 不会自动重算 body，只能靠 `.id` 重建一次整棵树。
struct AppearanceHost<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var settings = AppearanceSettings.shared

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            // DARK=1 是截图脚手架，优先级高于「自动」，方便拍暗色取证
            .preferredColorScheme(
                ProcessInfo.processInfo.environment["DARK"] == "1"
                ? .dark : settings.mode.colorScheme
            )
            // 字号通过 Dynamic Type 生效：只改环境值，**不会重建视图树**，
            // 所以拖滑块时不会把导航栈清掉、弹回首页。
            .environment(\.dynamicTypeSize,
                         settings.followSystem ? dynamicTypeSize : settings.step.dynamicTypeSize)
    }
}

// MARK: - 外观

struct AppearanceSettingsView: View {
    @State private var settings = AppearanceSettings.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { settings.mode = mode }
                        } label: {
                            HStack(spacing: 12) {
                                // 🔴 2026-11-22 主人：「标题清晰的就不要提示」。
                                //    原来每行带副标题（自动 / 跟随系统设置、浅色 / 始终使用浅色…），
                                //    后一句只是把前一句换个说法，一并删掉。
                                Text(mode.title.L)
                                    .font(AppTheme.TypeScale.rowTitle)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 0)
                                if settings.mode == mode {
                                    Image(systemName: "checkmark")
                                        .font(AppTheme.TypeScale.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        if index < AppearanceMode.allCases.count - 1 {
                            SettingsDivider()
                        }
                    }
                }
                .settingsCard()

                // 🔴 2026-11-22 主人：删掉「「自动」跟随系统…本 App 不再随系统切换。」
                //    三个选项名字本身就说明了行为，这行只是把「自动」翻译了一遍。
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 字体大小

struct FontSizeView: View {
    @State private var settings = AppearanceSettings.shared

    /// 预览用的示例文本：用**真实 App 文案**当样本，
    /// 用户拖动滑块时能直接看到「标题 / 正文 / 取件码」三档一起变。
    /// 🔴 2026-11-08 主人：原来的预览卡只有两行、下面一大片空白，像没做完。
    private let sampleStatus = "待取 44 件"
    private let sampleBody = "圆通速递 · 家佳福超市甘州院子店"
    private let sampleCode = "D-1-3516"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ── 预览卡：三段真实文案 ──
                VStack(alignment: .leading, spacing: 10) {
                    // ① 行标题档
                    Text(sampleStatus.L)
                        .font(AppTheme.TypeScale.rowTitle.weight(.semibold))

                    // ② 正文档
                    Text(sampleBody.L)
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(.secondary)

                    // ③ 取件码（等宽）—— 用户最关心的那一个
                    Text(sampleCode)
                        .font(.system(size: 30 * FontScale.value, weight: .bold,
                                      design: .rounded))
                        .monospaced()
                        .foregroundStyle(AppTheme.accent)
                        .padding(.top, 2)

                    // 🔴 2026-11-22 主人：原句「以上为示例，实际字号随滑块变化。」→ 两个字。
                    Text("示例")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .settingsCard()

                // ── 跟随系统 ──
                HStack {
                    Text("跟随系统")
                        .font(AppTheme.TypeScale.rowTitle)
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { settings.followSystem },
                        set: { settings.followSystem = $0 }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .settingsCard()

                // ── 滑块 ──
                VStack(spacing: 10) {
                    HStack {
                        Text("A")
                            .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(settings.followSystem ? "跟随系统" : settings.step.title)
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("A")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(settings.step.rawValue) },
                            set: { settings.step = FontSizeStep(rawValue: Int($0.rounded())) ?? .standard }
                        ),
                        in: 0...Double(FontSizeStep.allCases.count - 1),
                        step: 1
                    )
                    .tint(AppTheme.accent)
                    .disabled(settings.followSystem)
                    .opacity(settings.followSystem ? 0.45 : 1)

                    HStack {
                        Text(settings.followSystem ? "跟随系统字号" : "当前：\(settings.step.title)")
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(16)
                .settingsCard()

                // 🔴 2026-11-22 主人：只留用户猜不到的那半句（不动系统字号）。
                Text("只改本 App，不动系统字号。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("字体大小")
        .navigationBarTitleDisplayMode(.inline)
    }

}
