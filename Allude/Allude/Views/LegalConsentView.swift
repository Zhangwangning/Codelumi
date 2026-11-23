import SwiftUI

// MARK: ============================================================================
// 首次启动的法律同意页
//
// 历史：2026-11-01 主人要求首启必须先读并同意《使用条款》《隐私政策》；2026-11-21
// 主人要求重做这一页 —— 年轻、干净、像 Apple 自家的欢迎页，并且**一眼讲清和
// 菜鸟裹裹 / 快递100 这类联网 App 的区别：本地、离线、没有账号**。
//
// 2026-11-21 两条行为（主人定的）：
//   ① 「同意并继续」**不再置灰**：没勾也能点。点了就替用户勾上「我已阅读并同意」，
//      并弹一次确认（确认框里能直接翻条款）。确认这层不能省 —— 它是"同意"这件事
//      的落点，去掉就成了静默同意。
//   ② 正文只留三句差异点 + 一句删除提醒，其余全删。文案口径见 AGENTS.md：
//      提示文字能少则少，非必要不提示。
// ============================================================================

struct LegalConsentView: View {
    /// 同意后回调（首启模式必传）
    var onAccept: () -> Void

    @State private var agreed = false
    @State private var showDeclineAlert = false
    /// 未勾选直接点「同意并继续」时的确认框
    @State private var showConfirm = false
    /// 确认框里点「查看条款」时用 sheet 打开（alert 里不能 push）
    @State private var readingDoc: LegalDocument?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        differentiators
                        keepSafeNotice
                        agreement
                    }
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: AppTheme.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity,
                           minHeight: proxy.size.height,
                           alignment: .center)
                }
                .background(AppTheme.pageBackground)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar(.hidden, for: .navigationBar)
            // 自绘确认框：原生 alert 会给「不同意」自动补一个多余的「取消」，
            // 也没法把某一个按钮染成系统红（2026-11-21 主人要求红色）。
            .overlay {
                if showConfirm { confirmDialog.transition(.opacity) }
            }
            // 截图脚手架：`CONSENT_CONFIRM=1` 启动即复现「未勾选点同意」的确认框
            // （simctl 点不了屏幕，这条路径只能靠这个入口验）
            .onAppear {
                guard BuildFlags.scaffoldsEnabled else { return }
                // 截图脚手架：`AUTO_ACCEPT_CONSENT=1` 自动走一遍「同意并继续」，
                // 用来在没有触摸注入通道的情况下验证「收起同意页 → 拉起引导页」这条链路
                if ProcessInfo.processInfo.environment["AUTO_ACCEPT_CONSENT"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onAccept() }
                    return
                }
                guard ProcessInfo.processInfo.environment["CONSENT_CONFIRM"] == "1" else { return }
                agreed = true
                // 视图还没挂稳就 present，alert 会静默不弹（踩过），延一拍
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showConfirm = true }
            }
        }
        .alert("需要同意后才能使用", isPresented: $showDeclineAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("《使用条款》与《隐私政策》说明了数据处理方式与使用规则。不同意的话，暂时无法使用Codelumi。")
        }
        .sheet(item: $readingDoc) { doc in
            NavigationStack {
                LegalDocumentView(document: doc)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { readingDoc = nil }
                        }
                    }
            }
        }
    }

    // MARK: 顶部：图标 + 一句话主张

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(AppIconStore.current.assetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 56 * 0.2237, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Codelumi")
                        .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
                    Text("取件码，只留在你手机上")
                        .font(AppTheme.TypeScale.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            // 与联网类 App 的区别，压成一行徽标
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text("全程离线 · 不需要账号")
                    .font(AppTheme.TypeScale.badge)
            }
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.accent.opacity(0.12), in: .capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 三句差异点

    private var differentiators: some View {
        VStack(spacing: 0) {
            point(symbol: "wifi.slash", tint: AppTheme.accent,
                  title: "不联网") {
                "不看你的短信内容，也不往外发一个字节。"
            }
            SettingsDivider()
            point(symbol: "icloud.slash", tint: AppTheme.violet,
                  title: "不上传") {
                "没有开发者服务器，没有云端备份。"
            }
            SettingsDivider()
            point(symbol: "person.crop.circle.badge.xmark", tint: AppTheme.doneTint,
                  title: "不用注册") {
                "打开就能用，没有手机号和密码。"
            }
        }
        .settingsCard()
    }

    private func point(symbol: String, tint: Color, title: String,
                       @ViewBuilder detail: () -> String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.TypeScale.rowTitle)
                Text(detail())
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: 唯一需要用户记住的代价

    private var keepSafeNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.pendingTint)

            Text("卸载 App 或删除记录后无法找回 —— 这份数据只在你自己手里。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.pendingTint.opacity(0.10),
                    in: .rect(cornerRadius: 14, style: .continuous))
    }

    // MARK: 条款链接 + 勾选

    private var agreement: some View {
        VStack(spacing: 0) {
            NavigationLink {
                LegalDocumentView(document: .terms)
            } label: {
                SettingsRow(symbol: "doc.text.fill", title: "使用条款",
                            tint: AppTheme.sky)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink {
                LegalDocumentView(document: .privacy)
            } label: {
                SettingsRow(symbol: "hand.raised.fill", title: "隐私政策",
                            tint: AppTheme.doneTint)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                withAnimation(.snappy(duration: 0.2)) { agreed.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(agreed ? AppTheme.accent : Color.secondary)

                    Text("我已阅读并同意以上条款")
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        // 🔴 2026-11-21 主人：首启页也要跟设置页一样 —— iOS 26+ 真液态玻璃，
        //    iOS 17–25 走系统毛玻璃/分组卡片（`settingsCard` 内部已分档）。
        .settingsCard()
    }

    // MARK: 确认框（未勾选直接点「同意并继续」时）

    /// 版式照系统 alert：标题 17 semibold / 说明 13 / 分隔线 + 42pt 行。
    /// 「不同意」用系统红（`Color(.systemRed)`），其余按钮系统蓝。
    private var confirmDialog: some View {
        ZStack {
            // 点空白＝取消：既然没同意，勾选状态要退回去
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture {
                    showConfirm = false
                    withAnimation(.snappy(duration: 0.2)) { agreed = false }
                }

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("确认同意")
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("已为你勾选「我已阅读并同意」。《使用条款》与《隐私政策》说明数据处理方式与使用规则。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 19)
                .padding(.bottom, 16)

                Divider()

                dialogRow("同意", tint: Color.accentColor) {
                    showConfirm = false
                    DiagnosticsLog.record("consent", "accepted")
                    onAccept()
                }
                Divider()
                dialogRow("查看条款", tint: Color.accentColor) {
                    showConfirm = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { readingDoc = .terms }
                }
                Divider()
                dialogRow("不同意", tint: Color(.systemRed)) {
                    showConfirm = false
                    // 🔴 2026-11-21 主人：取消 / 不同意都要把「我已阅读并同意」退回去
                    withAnimation(.snappy(duration: 0.2)) { agreed = false }
                    showDeclineAlert = true
                }
            }
            .frame(maxWidth: 300)
            // 弹窗也用同一条材质链：iOS 26+ 液态玻璃取样背后的页面，低版本毛玻璃
            .appGlass(.rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
        }
    }

    private func dialogRow(_ title: String, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部按钮

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                if agreed {
                    DiagnosticsLog.record("consent", "accepted")
                    onAccept()
                } else {
                    // 🔴 2026-11-21 主人：没勾也能点 —— 点了替用户勾上，并弹确认。
                    withAnimation(.snappy(duration: 0.2)) { agreed = true }
                    showConfirm = true
                }
            } label: {
                Text("同意并继续")
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent, in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                showDeclineAlert = true
            } label: {
                Text("不同意")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.hInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // ⚠️ 这里**不要**再垫一层背景（.bar / 玻璃都不行）：
        //    底栏是 `safeAreaInset(edge: .bottom)`，正文本来就不会滚到它下面，
        //    垫上材质只会得到一条突兀的白板（2026-11-21 主人当场指出）。
    }
}
