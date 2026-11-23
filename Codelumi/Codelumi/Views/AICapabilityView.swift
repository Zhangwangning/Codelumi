import SwiftUI
import FoundationModels

// MARK: ============================================================================
// 设置 › AI 能力检测（2026-11-05）
//
// 主人问过两次「我的 iPhone 到底能不能用端侧 AI」。答案只能从系统那里读：
// `SystemLanguageModel.default.availability`，以及它给出的具体原因。
//
// 这个页面的价值：
//   · 不用连电脑也能看，不用每次让开发者远程跑脚本；
//   · 换系统版本 / 换地区后，一眼能看出有没有放开；
//   · 「写作工具能用但这里不行」这种奇怪组合，页面上能直接对照出来。
//
// 🔴 不记录任何用户内容：只有机型、系统、地区、语言、可用性枚举。
// ============================================================================

@available(iOS 26.0, *)
struct AICapabilityView: View {
    @State private var refreshToken = 0
    /// 检测中的状态（2026-11-05 主人：点了没反应，以为没生效）
    @State private var isChecking = false
    /// 检测完成后短暂闪一下，让用户知道"刷新了"
    @State private var justChecked = false

    /// 「打开 Apple 智能」总开关（2026-11-22 主人：页面顶部要一个开关）。
    @State private var aiEnabled = AISettings.isEnabled
    private var availability: SystemLanguageModel.Availability {
        _ = refreshToken
        return SystemLanguageModel.default.availability
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                masterCard
                // 🔴 2026-11-22 主人：「如果设备支持，检测的卡片就不要了」。
                //    能用的时候还摆一个「重新检测」按钮，等于让人怀疑「是不是没检测到」。
                //    所以检测这一整张卡只在**用不了**的时候出现。
                if !isAvailable {
                    statusCard
                }
                aboutCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("Apple 智能")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: logOnce)
    }

    // MARK: 总开关

    /// 页首「打开 Apple 智能」。
    ///
    /// 🔴 2026-11-22 主人两次强调：「功能标题不要提示」。
    ///    所以这里**只有一行标题 + 开关**，标题下面不挂任何说明文字。
    ///    设备不支持时的处理也不靠文字交代 —— 开关直接置灰，点不动本身就是答案。
    private var masterCard: some View {
        Toggle(isOn: Binding(
            get: { aiEnabled },
            set: { newValue in
                aiEnabled = newValue
                AISettings.setEnabled(newValue)
                // 只写这一个键：本页不再有任何联动开关
                // （语音录入 2026-11-22 整块删除，这里不剩可联动的东西）。
                DiagnosticsLog.record("aiCapability", "aiEnabled=\(newValue)")
            }
        )) {
            Text("打开 Apple 智能")
                .font(AppTheme.TypeScale.rowTitleMedium)
        }
        .tint(AppTheme.accent)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.55)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    // MARK: 结论（仅不可用时出现）

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.accent)
                } else {
                    Image(systemName: "xmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.pendingTint)
                }
                Text(isChecking ? "正在检测…" : "暂时用不了")
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Spacer(minLength: 0)
            }

            // 🔴 2026-11-08 主人：用户只关心「能不能用」，不关心枚举。
            //    2026-11-22 再收一遍：一句话说完，不铺排。
            Text(isChecking ? "查询中…" : "本机未开放端侧智能，解析仍走正则，收码正常。")
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard !isChecking else { return }
                Task { await recheck() }
            } label: {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.accent)
                    } else if justChecked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isChecking ? "检测中…" : (justChecked ? "已检测" : "检测 Apple 智能"))
                        .font(AppTheme.TypeScale.bodyMedium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.accent.opacity(isChecking ? 0.20 : 0.13))
                )
                .foregroundStyle(AppTheme.accent)
                .scaleEffect(isChecking ? 0.98 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isChecking)
            .animation(AppMotion.quick, value: isChecking)
            .animation(AppMotion.quick, value: justChecked)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
        .opacity(isChecking ? 0.55 : 1)
        // 🔴 2026-11-22 主人：「检测时不要蓝色的边框」——
        //    原来这里在检测成功后套了一圈 `accent` 描边，看着像输入框获得焦点。
        //    现在反馈只靠按钮自身的文案（检测中 / 已检测），不再描边。
        .animation(AppMotion.standard, value: isChecking)
        .animation(AppMotion.standard, value: justChecked)
    }

    /// 真正"重新检测"：给一点可见的耗时，否则瞬间返回用户无法感知
    private func recheck() async {
        isChecking = true
        justChecked = false
        defer { isChecking = false }
        try? await Task.sleep(for: .milliseconds(700))
        refreshToken &+= 1
        logOnce()
        withAnimation(AppMotion.standard) { justChecked = true }
        try? await Task.sleep(for: .milliseconds(1200))
        withAnimation(AppMotion.standard) { justChecked = false }
    }

    // MARK: 关于

    /// 🔴 2026-11-22 主人：「下面的卡片标题改成关于Codelumi中Apple智能，内容优化一下，
    ///    明确说明此功能无需互联网，端侧运行，辅助增强，App 解析功能主要是正则表达式等」
    ///    —— 后半句「要精则精，不要说废话」：每条只留一句，不重复解释。
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("关于 Codelumi 中 Apple 智能")
                .font(AppTheme.TypeScale.rowTitleMedium)

            bullet("wifi.slash", "无需互联网，端侧运行，断网可用。")
            bullet("iphone.gen3", "短信原文不出本机。")
            bullet("text.alignleft", "主解析是正则，不依赖模型。")
            bullet("wand.and.stars", "智能只补缺失字段，不覆盖已有结果。")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.sky)
                .frame(width: 18)
            Text(text.richText)
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 工具

    private var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    private var rawReason: String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "deviceNotEligible（系统判定本机不符合条件）"
            case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled（未开启 Apple 智能）"
            case .modelNotReady: return "modelNotReady（模型未就绪，通常在后台下载）"
            @unknown default: return "未知原因"
            }
        }
    }

    /// 每次进页面记一条（只有设备与枚举，不含任何用户内容）
    private func logOnce() {
        DiagnosticsLog.record("aiCapability",
                              "machine=\(DeviceProfile.machineID) "
                              + "os=\(ProcessInfo.processInfo.operatingSystemVersionString) "
                              + "region=\(Locale.current.region?.identifier ?? "-") "
                              + "available=\(isAvailable) reason=\(rawReason)")
    }
}

// MARK: - 低版本占位（iOS 18）

/// 系统低于 iOS 26 时没有端侧模型框架，这一页只说明情况。
struct AICapabilityUnsupportedView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.seal.fill")
                        .foregroundStyle(AppTheme.pendingTint)
                    Text("本机系统版本不支持端侧模型")
                        .font(AppTheme.TypeScale.rowTitle)
                }

                Text("端侧模型（Apple 智能）需要 iOS 26 或更高版本。\n当前系统的Codelumi使用纯正则 + 系统分词解析，收码功能不受影响。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 16)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("Apple 智能")
        .navigationBarTitleDisplayMode(.inline)
    }
}
