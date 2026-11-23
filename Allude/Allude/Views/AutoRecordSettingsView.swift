import SwiftUI
import AVKit
import SafariServices
import UIKit

// MARK: ============================================================================
// 设置 › 快捷指令自动化（2026-11-05 重构）
//
// 版式按主人给的清单做：一行一个关键词，右侧「添加」，点开是弹出菜单：
//   · iCloud 链接（推荐，填了才有）
//   · 用文件导入（App 内自带已签名的文件）
//
// 🔴 **不显示「已导入」状态**：用户可能在快捷指令里删掉，App 无从得知，
//    显示状态只会制造"明明显示已导入却没生效"的误会。
//
// 🔴 自定义关键词仍不可行：未签名文件导入失败（已实测），
//    导入时询问（WFWorkflowImportQuestions）对触发器不生效（B1/B2 实测无弹窗），
//    所以只能提供预设关键词。
//
// 🔴 2026-11-11 主人：**一键添加（iCloud 链接 / 文件导入）只在 iOS 27+ 可用**；
//    iOS 26 及更早的系统不支持导入带触发器的自动化，只能照下面「手动配置」
//    的步骤在「快捷指令」里自己新建一条。本页按系统版本分流，不给无用的按钮。
// ============================================================================

/// App 内打开网页（SFSafariViewController），不跳出 App
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        return vc
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct AutoRecordSettingsView: View {
    @State private var linkURL: URL?

    /// 一键添加快捷指令（分享 .shortcut / 打开 iCloud 链接）只在 iOS 27+ 可用；
    /// iOS 26 及更早只能手动新建自动化（2026-11-11 主人定）。
    private var quickImportAvailable: Bool {
        // 截图/验收脚手架：本机只有 iOS 27 运行时，用 FORCE_MANUAL_SHORTCUT=1
        // 模拟 iOS 26 及更早（Release 不含脚手架）。
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_MANUAL_SHORTCUT"] != nil { return false }
        #endif
        if #available(iOS 27.0, *) { return true } else { return false }
    }

    /// 页内播放器（2026-11-15 主人：直接在页面里播，不要全屏弹出）
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0          // 0…1，拖动进度条用
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                stepsRow
                videoCard
                optionalKeywords
                footnote
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 16)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("快捷指令")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { linkURL.map(WebLink.init) },
            set: { linkURL = $0?.url }
        )) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
    }

    // MARK: 主卡片（图标 + 两行字 + 主按钮）

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text("收到短信，自动收码")
                        .font(AppTheme.TypeScale.rowTitle)
                    Text("不用手动粘贴，装一次就行")
                        .font(AppTheme.TypeScale.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if quickImportAvailable {
                addMenu(ShortcutAutomation.presets[0], wide: true)
            } else {
                Text("这个系统版本不支持一键导入，照下面的步骤手动建一条。")
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    // MARK: 三步（一条卡里的三行，带序号）

    // MARK: 视频教程（页内播放）

    private var videoCard: some View {
        VStack(spacing: 8) {
            ZStack {
                if let player {
                    PlayerSurface(player: player)
                        .aspectRatio(1350.0 / 2760.0, contentMode: .fit)
                        .frame(height: 400)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .onTapGesture { togglePlayback() }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .aspectRatio(1350.0 / 2760.0, contentMode: .fit)
                        .frame(height: 400)
                        .overlay {
                            Text("视频缺失")
                                .font(AppTheme.TypeScale.note)
                                .foregroundStyle(.secondary)
                        }
                }

                if !isPlaying {
                    Button { togglePlayback() } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("播放")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if player != nil {
                HStack(spacing: 10) {
                    Button { togglePlayback() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(isPlaying ? "暂停" : "播放")

                    Slider(value: Binding(
                        get: { progress },
                        set: { newValue in
                            progress = newValue
                            guard let player, let duration = player.currentItem?.duration.seconds,
                                  duration.isFinite, duration > 0 else { return }
                            player.seek(to: CMTime(seconds: duration * newValue, preferredTimescale: 600))
                        }
                    ), in: 0...1) { editing in
                        isScrubbing = editing
                        if !editing { player?.play(); isPlaying = true }
                    }
                    .tint(AppTheme.accent)
                }
                .padding(.horizontal, 4)
            }
        }
        .settingsCard()
        .onAppear { preparePlayer() }
        .onDisappear {
            player?.pause()
            isPlaying = false
            if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
        }
    }

    private func preparePlayer() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "ShortcutAutomation", withExtension: "mp4")
        else { return }
        let p = AVPlayer(url: url)
        player = p
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
                                                queue: .main) { time in
            guard !isScrubbing,
                  let duration = p.currentItem?.duration.seconds,
                  duration.isFinite, duration > 0 else { return }
            progress = min(max(time.seconds / duration, 0), 1)
            if time.seconds >= duration - 0.15 {
                isPlaying = false          // 播完回到暂停态，播放键重新出现
            }
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if player.currentItem?.duration.seconds ?? 0 > 0,
               player.currentTime() >= (player.currentItem?.duration ?? .zero) {
                player.seek(to: .zero)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    private var stepsRow: some View {
        VStack(spacing: 0) {
            if quickImportAvailable {
                stepRow(index: 1, title: "点上面的按钮添加", detail: "走 iCloud 链接或文件导入", showsDivider: true)
                stepRow(index: 2, title: "打开自动化开关", detail: "快捷指令 › 自动化", showsDivider: true)
                stepRow(index: 3, title: "以后自动收码", detail: "短信进来直接进列表", showsDivider: false)
            } else {
                // iOS 26 及更早：系统不支持导入带触发器的自动化，只能手动新建
                stepRow(index: 1, title: "新建一条自动化", detail: "快捷指令 › 自动化 › 新建", showsDivider: true)
                stepRow(index: 2, title: "触发条件选「信息」", detail: "包含「【」，立即运行", showsDivider: true)
                stepRow(index: 3, title: "动作选 Codelumi", detail: "「添加到 Codelumi」", showsDivider: true)
                stepRow(index: 4, title: "关掉运行前询问", detail: "以后自动收码，不用点确认", showsDivider: false)
            }
        }
        .settingsCard()
    }

    private func stepRow(index: Int, title: String, detail: String, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(AppTheme.TypeScale.badge)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(.tertiarySystemFill)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.TypeScale.body)
                    Text(detail)
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if showsDivider { SettingsDivider() }
        }
    }

    // MARK: 可选关键词

    private var optionalKeywords: some View {
        VStack(alignment: .leading, spacing: 8) {
            if quickImportAvailable {
                SectionHeader(title: "换个关键词也行")
                HStack(spacing: 8) {
                    ForEach(Array(ShortcutAutomation.presets.dropFirst().prefix(3))) { preset in
                        keywordChip(preset)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func keywordChip(_ preset: ShortcutAutomation.Preset) -> some View {
        Menu {
            if let link = ShortcutAutomation.icloudURL(for: preset.keyword) {
                Button { linkURL = link } label: { Label("iCloud 链接（推荐）", systemImage: "link") }
            }
            Button {
                guard let url = ShortcutAutomation.preparedImportURL(for: preset) else { return }
                ShareSheetPresenter.present([url])
            } label: { Label("用文件导入", systemImage: "square.and.arrow.down") }
        } label: {
            Text(preset.keyword)
                .font(AppTheme.TypeScale.rowSubtitle)
                .foregroundStyle(AppTheme.accent)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(Capsule().fill(AppTheme.accent.opacity(0.10)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        Text("每多一条自动化，就多一条系统通知；默认只加「【」就够。")
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    /// 右侧「添加」：点开是弹出菜单（iCloud 链接 / 文件）
    private func addMenu(_ preset: ShortcutAutomation.Preset, wide: Bool) -> some View {
        Menu {
            if let link = ShortcutAutomation.icloudURL(for: preset.keyword) {
                Button {
                    linkURL = link
                } label: {
                    Label("iCloud 链接（推荐）", systemImage: "link")
                }
            }
            Button {
                // 与首启引导同一个修法：分享面板直接挂最上层控制器
                guard let url = ShortcutAutomation.preparedImportURL(for: preset) else { return }
                ShareSheetPresenter.present([url])
            } label: {
                Label("用文件导入", systemImage: "square.and.arrow.down")
            }
        } label: {
            // 主按钮铺满一行；可选关键词是小胶囊。
            HStack(spacing: 6) {
                if wide {
                    Image(systemName: "plus.circle.fill")
                    Text("添加「\(preset.keyword)」自动化")
                } else {
                    Text(preset.keyword)
                }
            }
            .font(AppTheme.TypeScale.bodyMedium)
            .foregroundStyle(.white)
            .frame(maxWidth: wide ? .infinity : nil)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .appGlass(.capsule, tint: AppTheme.accent, interactive: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: 说明

    private var note: some View {
        // 🔴 2026-11-22 主人：与上方预设脚注**去重** —— 那句「每多一条自动化就多一条通知」
        //    已经写在上面的脚注里，这里只留用户一定会踩的那一步（开关默认是关的）。
        Text("加完请到「快捷指令 › 自动化」把开关打开（默认是关的）。")
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// 让 URL 能作为 sheet(item:) 的标识
private struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}


/// 只做画面输出的播放层：`AVPlayerLayer`，不带任何系统控件。
/// 需要播放/暂停/拖进度条各一个自绘控件（主人 2026-11-15：不要系统播放器 UI）。
private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

private final class PlayerSurfaceView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
