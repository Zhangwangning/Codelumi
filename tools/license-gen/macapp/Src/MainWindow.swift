import AppKit

// ============================================================================
// 主窗口：批量签发 / 凭证验签 / 签发台账
// 「单条签发」不在这里重复 —— 那是菜单栏面板的活，避免两处同一功能
// ============================================================================

final class MainWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: T.windowWidth, height: T.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codelumi · 发码工具"
        window.minSize = NSSize(width: T.windowMinWidth, height: T.windowMinHeight)
        self.init(window: window)
        window.contentViewController = MainViewController()
        // 🔴 尺寸必须在设置 contentViewController **之后**定：
        //    否则窗口会被压到内容视图的 fittingSize（实测启动后缩成 700×520 = minSize）
        window.setContentSize(NSSize(width: T.windowWidth, height: T.windowHeight))
        window.center()
        // autosave 放最后：首次启动用上面的设计尺寸，之后恢复用户自己调过的尺寸
        window.setFrameAutosaveName("CodelumiIssuerMainWindow")
        // 兜底：autosave 偶尔恢复出非法尺寸（实测 open 启动路径下出现过 0×0），此时回设计尺寸
        if window.frame.width < T.windowMinWidth || window.frame.height < T.windowMinHeight {
            window.setContentSize(NSSize(width: T.windowWidth, height: T.windowHeight))
            window.center()
        }
    }
}

final class MainViewController: NSViewController {

    private let core = LicenseCore.shared

    private let segment = NSSegmentedControl(labels: ["批量签发", "凭证验签", "签发台账"],
                                             trackingMode: .selectOne,
                                             target: nil, action: nil)
    private let content = NSView()
    private let keyStatus = makeLabel("", size: T.caption, color: C.tertiary)
    private let keyPathLabel = makeLabel("", size: T.caption, color: C.tertiary, mono: true, compressible: true)
    private var importButton: PillButton!

    private var pages: [NSViewController] = []
    private var current: NSViewController?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        // ── 顶部：标题 + 分段导航
        let title = makeLabel("Codelumi · 发码工具", size: T.h1, weight: .semibold)
        let subtitle = makeLabel("设备码 → 激活凭证 · 纯离线签发", size: T.caption, color: C.tertiary)
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        segment.target = self
        segment.action = #selector(segmentChanged)
        segment.selectedSegment = 0
        segment.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let header = NSStackView(views: [titleStack, makeSpacer(), segment])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = T.rowGap
        header.edgeInsets = NSEdgeInsets(top: 14, left: T.pagePadding, bottom: 12, right: T.pagePadding)

        // ── 底部：私钥状态
        // 「导入私钥…」只在缺失时露出；「来源目录…」平时是安静的次要动作
        let sourceButton = PillButton("来源目录…", kind: .quiet, target: self, action: #selector(chooseSourceDir))
        sourceButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let importButton = PillButton("导入私钥…", kind: .primary, target: self, action: #selector(chooseKeyFile))
        importButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        self.importButton = importButton

        let footer = NSStackView(views: [keyStatus, keyPathLabel, makeSpacer(), sourceButton, importButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = T.rowGap
        footer.edgeInsets = NSEdgeInsets(top: 8, left: T.pagePadding, bottom: 10, right: T.pagePadding)

        let lineTop = makeSeparator()
        let lineBottom = makeSeparator()
        for sub in [header, lineTop, content, lineBottom, footer] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            lineTop.topAnchor.constraint(equalTo: header.bottomAnchor),
            lineTop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            lineTop.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            content.topAnchor.constraint(equalTo: lineTop.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: lineBottom.topAnchor),

            lineBottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            lineBottom.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            lineBottom.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        // ── 顶栏 / 底栏钉死高度，剩余空间全部归内容区
        //
        // 不靠 hugging 分配：这条约束链（header → lineTop → content → lineBottom → footer）
        // 全是等式约束，高度解不唯一。而 AppKit 里没有 intrinsicContentSize 的视图
        // 不会生成 hugging 约束（实测 header / content / NSStackView 自身 intrinsicContentSize
        // 全是 -1×-1），设了 hugging 也没用 —— 实测顶栏被分到 328pt、结果区被压成 10px。
        // 顶栏/底栏本就是固定高度工具栏，直接钉死最可预测。
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: T.headerHeight),
            footer.heightAnchor.constraint(equalToConstant: T.footerHeight),
        ])

        view = root

        pages = [BatchPageController(), VerifyPageController(), LedgerPageController()]
        segmentChanged()
        refreshKeyStatus()      // 只读本机容器，安全；跨卷导入在 viewDidAppear 里异步发起

        NotificationCenter.default.addObserver(self, selector: #selector(refreshKeyStatus),
                                               name: .codelumiLedgerChanged, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nil)
        startAutoImportIfNeeded()       // 窗口已在屏上，此时再发起可能阻塞的跨卷读
    }

    // MARK: 导航

    @objc private func segmentChanged() {
        let index = max(0, min(segment.selectedSegment, pages.count - 1))
        let page = pages[index]

        current?.view.removeFromSuperview()
        current?.removeFromParent()

        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(page.view)
        NSLayoutConstraint.activate([
            page.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            page.view.topAnchor.constraint(equalTo: content.topAnchor),
            page.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        current = page
    }

    // MARK: 私钥状态
    //
    // 三种状态：已就位 / 正在导入 / 缺失待导入。
    // 读本机容器（毫秒级）可以同步；跨卷导入一律后台 + 看门狗 —— 见 LicenseCore 注释。

    private var autoImportStarted = false

    @objc private func refreshKeyStatus() {
        if core.keyExists, core.publicKeyBase64 != nil {
            keyStatus.stringValue = "✓ 私钥已载入"
            keyStatus.textColor = C.ok
            importButton?.isHidden = true
        } else {
            keyStatus.stringValue = "✗ 未导入私钥"
            keyStatus.textColor = C.bad
            importButton?.isHidden = false
        }
        keyPathLabel.stringValue = Self.abbreviate(core.keyURL.path)
        keyPathLabel.toolTip = core.keyURL.path
    }

    /// 家目录缩写成 `~`：完整路径 68 字符，页脚放不下且挤掉状态文字
    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// 首次上屏后自动从来源目录导入一次。跨卷读被系统拦下时不会报错只会挂起，
    /// 由核心层的 3 秒看门狗判定超时，再引导用户手动导入。
    private func startAutoImportIfNeeded() {
        guard !autoImportStarted else { return }
        autoImportStarted = true
        guard !core.keyExists else { return }

        keyStatus.stringValue = "正在从来源目录导入…"
        keyStatus.textColor = C.secondary
        keyPathLabel.stringValue = core.sourceDir.path

        core.importFromSource { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .alreadyReady:
                self.refreshKeyStatus()
            case .imported(let items):
                self.refreshKeyStatus()
                self.keyStatus.stringValue = "✓ 已导入\(items.joined(separator: " · "))"
                NotificationCenter.default.post(name: .codelumiLedgerChanged, object: nil)
            case .failed(let reason):
                self.keyStatus.stringValue = "✗ 自动导入失败 — 请点「导入私钥…」手动选择"
                self.keyStatus.textColor = C.bad
                self.keyPathLabel.stringValue = reason
            case .timedOut:
                self.keyStatus.stringValue = "✗ 来源目录被系统拦截 — 请点「导入私钥…」手动选择"
                self.keyStatus.textColor = C.bad
                self.keyPathLabel.stringValue = "来源：\(self.core.sourceDir.path)"
            }
            self.importButton?.isHidden = self.core.keyExists
        }
    }

    /// 手动导入私钥：走系统文件选择器，用户选中即等于授权该文件可读
    @objc private func chooseKeyFile() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 private-key.pem（P-256 私钥）"
        panel.prompt = "导入"
        panel.nameFieldStringValue = "private-key.pem"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.keyStatus.stringValue = "正在导入…"
            self.keyStatus.textColor = C.secondary
            self.keyPathLabel.stringValue = url.path
            self.core.importKey(from: url) { result in
                switch result {
                case .success:
                    self.refreshKeyStatus()
                    NotificationCenter.default.post(name: .codelumiLedgerChanged, object: nil)
                case .failure(let error):
                    self.keyStatus.stringValue = "✗ 导入失败"
                    self.keyStatus.textColor = C.bad
                    self.keyPathLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func chooseSourceDir() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择包含 private-key.pem 的目录（通常是 tools/license-gen）"
        panel.prompt = "选择"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.core.setSourceDir(url)
            self.autoImportStarted = false      // 换了来源，允许再自动导入一次
            self.startAutoImportIfNeeded()
            self.refreshKeyStatus()
            NotificationCenter.default.post(name: .codelumiLedgerChanged, object: nil)
        }
    }
}
