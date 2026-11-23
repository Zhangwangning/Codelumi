import AppKit

// ============================================================================
// 主窗口的三个页面
//   ① 批量签发 —— 每行一个设备码，一次出多张（单条也能用）
//   ② 凭证验签 —— 粘贴任意文本，自动抠出凭证并验签
//   ③ 签发台账 —— 读 issued-ledger.md，支持拷贝历史凭证
// ============================================================================

// MARK: - 多行输入框

final class MultilineField: ThemedView {
    let textView = NSTextView()
    private let scroll = NSScrollView()
    private let placeholderLabel: NSTextField

    init(placeholder: String, height: CGFloat = 140) {
        placeholderLabel = makeLabel(placeholder, size: T.body, color: C.tertiary, compressible: true)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = T.fieldRadius
        layer?.borderWidth = 1

        textView.font = F.mono(T.mono)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.string = ""

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        // 空态提示（NSTextView 没有 placeholder，自己叠一层）
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: height),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -13),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(textChanged),
                                               name: NSText.didChangeNotification, object: textView)
        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func textChanged() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    override func applyTheme() {
        layer?.backgroundColor = resolvedCGColor(C.fieldFill)
        layer?.borderColor = resolvedCGColor(C.hairline)
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            placeholderLabel.isHidden = !newValue.isEmpty
        }
    }
}

// MARK: - 结果行（批量签发 / 台账共用样式）

/// 多行自动换行标签。
/// macOS 上 NSTextField 的经典坑：`preferredMaxLayoutWidth` 不跟着实际宽度更新，
/// Auto Layout 算出的高度就是错的（表现为文字被截一行、或展开区高度塌陷）。
final class WrappingLabel: NSTextField {
    override func layout() {
        super.layout()
        if preferredMaxLayoutWidth != bounds.width {
            preferredMaxLayoutWidth = bounds.width
            super.layout()
        }
    }
}

final class ResultRowView: ThemedView {
    private let icon = makeLabel("", size: 12, weight: .bold)
    private let primary = makeLabel("", size: T.body, weight: .medium, mono: true)
    private let secondary = makeLabel("", size: T.caption, color: C.tertiary)
    private let trailing = makeLabel("", size: T.caption, color: C.tertiary)

    /// 拷贝回调。可展开的行由详情区里的「拷贝」触发它；不可展开的行由主按钮直接触发。
    var onCopy: (() -> Void)?

    private let expandable: Bool
    private let actionTitle: String

    private var outer: NSStackView!
    private var actionButton: PillButton?
    private var detailBox: NSView?
    private var detailLabel: WrappingLabel?
    private var detailCopyButton: PillButton?
    private var detail: String?
    private var expanded = false

    /// - Parameters:
    ///   - showCopy: 是否显示行尾按钮
    ///   - copyTitle: 按钮标题（可展开的行建议用「查看」）
    ///   - expandable: true = 按钮切换展开凭证全文；false = 按钮直接拷贝
    ///   - inline: true = 全部信息横向排成**一行**（主信息 + 明细 + 时间）。
    ///     窗口宽度本就富余，主/副信息堆成上下两行只会显得挤。
    ///     空态提示这类副文案很长的场景仍用默认的 stacked（false）。
    init(showCopy: Bool = true, copyTitle: String = "拷贝",
         expandable: Bool = false, inline: Bool = false) {
        self.expandable = expandable
        self.actionTitle = copyTitle
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = T.cardRadius

        let textStack = NSStackView(views: [primary, secondary])
        textStack.orientation = inline ? .horizontal : .vertical
        textStack.alignment = inline ? .centerY : .leading
        textStack.spacing = inline ? T.rowGap : 2

        if inline {
            // 设备码 / 凭证这类主信息必须完整，明细可以让位被截断
            primary.setContentCompressionResistancePriority(.required, for: .horizontal)
            secondary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            secondary.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 38).isActive = true   // 要装得下台账序号「0002」，16pt 会截成「…」
        trailing.setContentHuggingPriority(.required, for: .horizontal)

        var views: [NSView] = [icon, textStack, makeSpacer(), trailing]
        if showCopy {
            let button = PillButton(copyTitle, kind: .secondary, target: self, action: #selector(actionTapped))
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            button.setContentHuggingPriority(.required, for: .horizontal)
            actionButton = button
            views.append(button)
        }

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = T.rowGap
        // 单行时上下收紧到 8（行高由按钮 26 决定 → 42）；两行时留 10
        let vPad: CGFloat = inline ? 8 : 10
        row.edgeInsets = NSEdgeInsets(top: vPad, left: 14, bottom: vPad, right: 14)
        if inline {
            // 见 T.rowHeightInline 的说明：横向栈不会因按钮变高，得显式给下限
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: T.rowHeightInline).isActive = true
        }

        // 外层改垂直栈：行内容 + 可展开的详情区。
        // 不能继续把 row 直接钉在 self 上 —— 详情区得插在行下面。
        outer = NSStackView(views: [row])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.widthAnchor.constraint(equalTo: outer.widthAnchor),
        ])
        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func applyTheme() {
        layer?.backgroundColor = resolvedCGColor(C.subtleFill)
        guard let box = detailBox else { return }
        box.layer?.backgroundColor = resolvedCGColor(C.detailFill)
        box.layer?.borderWidth = 1
        box.layer?.borderColor = resolvedCGColor(C.hairline)
    }

    // MARK: 展开 / 拷贝

    /// 设置可展开的详情文本（凭证全文）。传 nil 时行尾按钮隐藏。
    func setDetail(_ text: String?) {
        detail = text
        actionButton?.isHidden = (text == nil)
        if text == nil { setExpanded(false) }
    }

    private func setExpanded(_ on: Bool) {
        guard expandable, detail != nil else { return }
        if on { ensureDetailBox() }
        expanded = on
        detailLabel?.stringValue = detail ?? ""
        detailBox?.isHidden = !on
        actionButton?.title = on ? "收起" : actionTitle
    }

    private func ensureDetailBox() {
        guard detailBox == nil else { return }

        let label = WrappingLabel(labelWithString: "")
        label.font = F.mono(T.monoSmall)
        label.textColor = C.secondary
        label.isSelectable = true
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.usesSingleLineMode = false
        label.lineBreakMode = .byCharWrapping      // 凭证是无空格长串，必须按字符断行
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        // 关键（实测坑）：多行 NSTextField 的 intrinsicContentSize.width 是**单行全宽**
        // （这条凭证 237 字符 ≈ 1616pt）。若不放开 CompressionResistance，
        // 它会顶着约束链把 ScrollPane 乃至窗口一起撑宽到 1704pt。
        // 宽度必须只由容器决定，文本自己不许有任何话语权。
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailLabel = label

        let hint = makeLabel("凭证全文 · 可拖选，或直接拷贝", size: T.caption, color: C.tertiary,
                             compressible: true)
        let copy = PillButton("拷贝", kind: .secondary, target: self, action: #selector(copyDetailTapped))
        copy.heightAnchor.constraint(equalToConstant: 24).isActive = true
        copy.setContentHuggingPriority(.required, for: .horizontal)
        detailCopyButton = copy

        let head = NSStackView(views: [hint, makeSpacer(), copy])
        head.orientation = .horizontal
        head.alignment = .centerY
        head.spacing = T.rowGap

        // 内边距走外层约束常量，不用 NSStackView.edgeInsets ——
        // edgeInsets 会让栈的 fittingSize 把内边距算进固有宽度，又是一条撑宽的来源。
        let stack = NSStackView(views: [head, label])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = T.fieldRadius
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            head.widthAnchor.constraint(equalTo: stack.widthAnchor),
            label.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        outer.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        box.isHidden = true
        detailBox = box
        applyTheme()
    }

    @objc private func actionTapped() {
        if expandable, detail != nil {
            setExpanded(!expanded)
        } else {
            onCopy?()
        }
    }

    @objc private func copyDetailTapped() {
        guard let text = detail else { return }
        copyToPasteboard(text)
        detailCopyButton?.flashTitle("已拷贝")     // 没有这个反馈，用户会以为按钮没生效
    }

    func configure(iconText: String, iconColor: NSColor,
                   primaryText: String, secondaryText: String,
                   trailingText: String, trailingColor: NSColor = C.tertiary) {
        icon.stringValue = iconText
        icon.textColor = iconColor
        primary.stringValue = primaryText
        secondary.stringValue = secondaryText
        // 单行模式下明细可能被截断，挂 tooltip 兜底（不占视觉空间）
        secondary.toolTip = secondaryText.isEmpty ? nil : secondaryText
        trailing.stringValue = trailingText
        trailing.textColor = trailingColor
        actionButton?.isHidden = expandable ? (detail == nil) : (onCopy == nil)
    }
}

// MARK: - 通用工具

enum DeviceCodeParser {
    /// 从任意文本里解析设备码：优先按行归一化，兜底全局扫 32 位 HEX
    static func parse(_ text: String) -> [String] {
        var found: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let code = LicenseCore.normalizeDevice(line)
            if LicenseCore.isValidDevice(code) { found.append(code) }
        }
        if found.isEmpty {
            let pattern = "[0-9A-Fa-f]{32}"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                for match in regex.matches(in: text, range: range) {
                    if let r = Range(match.range, in: text) {
                        found.append(LicenseCore.normalizeDevice(String(text[r])))
                    }
                }
            }
        }
        // 去重但保持顺序
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }
}

func copyToPasteboard(_ text: String) {
    let board = NSPasteboard.general
    board.clearContents()
    board.setString(text, forType: .string)
}

/// 空态提示行（避免大片留白看不出这里会发生什么）
func makeEmptyHint(_ text: String) -> ResultRowView {
    let row = ResultRowView(showCopy: false)
    row.configure(iconText: "·", iconColor: C.tertiary,
                  primaryText: text, secondaryText: "", trailingText: "")
    return row
}

// MARK: ============================================================================
// ① 批量签发
// ============================================================================

final class BatchPageController: NSViewController {

    private let core = LicenseCore.shared

    private let segment = NSSegmentedControl(labels: LicenseService.allCases.map(\.title),
                                             trackingMode: .selectOne, target: nil, action: nil)
    private let daysField = FieldBox(placeholder: "天数")
    private let noteField = FieldBox(placeholder: "只给你自己对账用，可留空")
    private let devices = MultilineField(placeholder: "每行一个设备码，可直接粘贴整列", height: 104)
    private let issueButton = PillButton("签发全部", kind: .primary, target: nil, action: nil)
    private let summary = makeLabel("", size: T.body, color: C.secondary)
    private let resultStack = NSStackView()
    private var issued: [(device: String, code: String)] = []

    private var selectedService: LicenseService {
        LicenseService.allCases[max(0, min(segment.selectedSegment, LicenseService.allCases.count - 1))]
    }

    override func loadView() {
        let root = NSView()

        // ── 参数条
        let card = CardView()
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = T.rowGap
        cardStack.edgeInsets = NSEdgeInsets(top: T.cardPadding, left: T.cardPadding,
                                            bottom: T.cardPadding, right: T.cardPadding)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.content.addSubview(cardStack)      // 必须挂到 content —— 才会浮在玻璃之上
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.content.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.content.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: card.content.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.content.bottomAnchor),
        ])

        segment.target = self
        segment.action = #selector(serviceChanged)
        segment.selectedSegment = 0
        daysField.widthAnchor.constraint(equalToConstant: 88).isActive = true
        noteField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let paramRow = NSStackView(views: [
            makeLabel("档位", size: T.caption, weight: .medium, color: C.secondary),
            segment,
            makeLabel("天数", size: T.caption, weight: .medium, color: C.secondary),
            daysField,
            makeLabel("备注", size: T.caption, weight: .medium, color: C.secondary),
            noteField,
            makeSpacer(),
        ])
        paramRow.orientation = .horizontal
        paramRow.alignment = .centerY
        paramRow.spacing = T.rowGap
        cardStack.addArrangedSubview(paramRow)
        paramRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor,
                                        constant: -T.cardPadding * 2).isActive = true

        // ── 输入 + 动作
        let inputCard = CardView()
        let inputStack = NSStackView()
        inputStack.orientation = .vertical
        inputStack.alignment = .leading
        inputStack.spacing = T.rowGap
        inputStack.edgeInsets = NSEdgeInsets(top: T.cardPadding, left: T.cardPadding,
                                             bottom: T.cardPadding, right: T.cardPadding)
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        inputCard.content.addSubview(inputStack)
        NSLayoutConstraint.activate([
            inputStack.leadingAnchor.constraint(equalTo: inputCard.content.leadingAnchor),
            inputStack.trailingAnchor.constraint(equalTo: inputCard.content.trailingAnchor),
            inputStack.topAnchor.constraint(equalTo: inputCard.content.topAnchor),
            inputStack.bottomAnchor.constraint(equalTo: inputCard.content.bottomAnchor),
        ])

        inputStack.addArrangedSubview(makeLabel("设备码（每行一个）",
                                                size: T.caption, weight: .medium, color: C.secondary))
        inputStack.addArrangedSubview(devices)
        devices.widthAnchor.constraint(equalTo: inputStack.widthAnchor,
                                       constant: -T.cardPadding * 2).isActive = true

        issueButton.target = self
        issueButton.action = #selector(issueAll)
        issueButton.heightAnchor.constraint(equalToConstant: T.buttonHeight).isActive = true

        let pasteHint = makeLabel("提示：从聊天记录整段复制也行，会自动挑出所有 32 位设备码",
                                  size: T.caption, color: C.tertiary)
        let actionRow = NSStackView(views: [issueButton, summary, makeSpacer(), pasteHint])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = T.rowGap
        inputStack.addArrangedSubview(actionRow)
        actionRow.widthAnchor.constraint(equalTo: inputStack.widthAnchor,
                                         constant: -T.cardPadding * 2).isActive = true

        // ── 结果
        resultStack.orientation = .vertical
        resultStack.alignment = .leading
        resultStack.spacing = T.tagGap

        let pane = ScrollPane(spacing: T.tagGap, inset: 10)
        let resultCard = CardView()
        resultCard.content.addSubview(pane)
        pane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: resultCard.content.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: resultCard.content.trailingAnchor),
            pane.topAnchor.constraint(equalTo: resultCard.content.topAnchor),
            pane.bottomAnchor.constraint(equalTo: resultCard.content.bottomAnchor),
        ])
        // 结果区是"吃掉剩余高度"的那一块：hugging 压到最低，否则窗口下方会留大片空白
        resultCard.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        resultCard.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)

        // ── 总装
        // distribution 必须显式设 .fill：NSStackView 默认是 .gravityAreas，
        // 该模式把剩余空间分给「gravity 之间的间距」而不是视图 ——
        // 结果区 hugging 压到 1 也不会伸展（实测：被压成 10px，窗口下方留大片空白）。
        let column = NSStackView(views: [card, inputCard, resultCard])
        column.orientation = .vertical
        column.alignment = .leading
        column.distribution = .fill
        column.spacing = T.blockGap
        column.edgeInsets = NSEdgeInsets(top: T.pagePadding, left: T.pagePadding,
                                         bottom: T.pagePadding, right: T.pagePadding)
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        for sub in [card, inputCard, resultCard] {
            sub.widthAnchor.constraint(equalTo: column.widthAnchor,
                                       constant: -T.pagePadding * 2).isActive = true
        }
        // 参数卡与输入卡锁死自然高度，多出来的高度全归结果区
        for fixed in [card, inputCard] {
            fixed.setContentHuggingPriority(.required, for: .vertical)
            fixed.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        view = root
        _ = resultStack        // 结果行直接加进 pane 的 stack
        resultPane = pane
        pane.stack.addArrangedSubview(makeEmptyHint("签发结果会逐条显示在这里（设备码 · 档位 · 到期 · 是否已记账）"))
        serviceChanged()
    }

    private var resultPane: ScrollPane?

    @objc private func serviceChanged() {
        let service = selectedService
        daysField.stringValue = service == .lifetime ? "" : String(service.defaultDays)
        daysField.setEnabled(service != .lifetime)
    }

    @objc private func issueAll() {
        let codes = DeviceCodeParser.parse(devices.text)
        guard !codes.isEmpty else {
            summary.stringValue = "没找到合法设备码"
            summary.textColor = C.bad
            return
        }

        let service = selectedService
        let typedDays = daysField.stringValue.trimmingCharacters(in: .whitespaces)
        let days = service == .lifetime ? 0 : (Int(typedDays) ?? service.defaultDays)
        let note = noteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        resultPane?.stack.arrangedSubviews.forEach {
            resultPane?.stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        issued.removeAll()

        var okCount = 0
        for code in codes {
            let row = ResultRowView(inline: true)
            row.onCopy = { [weak self] in
                guard let self else { return }
                if let hit = self.issued.first(where: { $0.device == code }) {
                    copyToPasteboard(hit.code)
                    self.summary.stringValue = "已拷贝 \(code) 的凭证"
                    self.summary.textColor = C.secondary
                }
            }
            do {
                let license = try core.issue(rawDevice: code, service: service, days: days,
                                             note: note.isEmpty ? nil : note)
                let index = try? core.appendLedger(license)
                issued.append((device: code, code: license.code))
                let expiresText = license.expiresAt.map { core.dayString($0) } ?? "永久"
                let ledgerText = index.map { "已记账 \(String(format: "#%04d", $0))" } ?? "台账未写"
                row.configure(iconText: "✓", iconColor: C.ok,
                              primaryText: code,
                              secondaryText: "\(service.ledgerTitle(days: license.days)) · 至 \(expiresText) · \(ledgerText)",
                              trailingText: "\(license.code.count) 字符")
                okCount += 1
            } catch {
                row.configure(iconText: "✗", iconColor: C.bad,
                              primaryText: code,
                              secondaryText: error.localizedDescription,
                              trailingText: "")
                row.onCopy = nil
            }
            resultPane?.addRow(row)
        }

        summary.stringValue = "成功 \(okCount) / 共 \(codes.count) 张"
        summary.textColor = okCount == codes.count ? C.ok : C.warn
        if okCount > 0 { NotificationCenter.default.post(name: .codelumiLedgerChanged, object: nil) }
    }
}

// MARK: ============================================================================
// ② 凭证验签
// ============================================================================

final class VerifyPageController: NSViewController {

    private let core = LicenseCore.shared
    private let input = MultilineField(placeholder: "粘贴凭证，或直接粘贴买家的整条消息（会自动抠出凭证）", height: 124)
    private let verifyButton = PillButton("验签", kind: .primary, target: nil, action: nil)
    private let summary = makeLabel("", size: T.body, color: C.secondary)
    private var pane: ScrollPane?

    override func loadView() {
        let root = NSView()

        let inputCard = CardView()
        let inputStack = NSStackView()
        inputStack.orientation = .vertical
        inputStack.alignment = .leading
        inputStack.spacing = T.rowGap
        inputStack.edgeInsets = NSEdgeInsets(top: T.cardPadding, left: T.cardPadding,
                                             bottom: T.cardPadding, right: T.cardPadding)
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        inputCard.content.addSubview(inputStack)
        NSLayoutConstraint.activate([
            inputStack.leadingAnchor.constraint(equalTo: inputCard.content.leadingAnchor),
            inputStack.trailingAnchor.constraint(equalTo: inputCard.content.trailingAnchor),
            inputStack.topAnchor.constraint(equalTo: inputCard.content.topAnchor),
            inputStack.bottomAnchor.constraint(equalTo: inputCard.content.bottomAnchor),
        ])

        inputStack.addArrangedSubview(makeLabel("待验凭证 / 聊天消息", size: T.caption, weight: .medium, color: C.secondary))
        inputStack.addArrangedSubview(input)
        input.widthAnchor.constraint(equalTo: inputStack.widthAnchor, constant: -T.cardPadding * 2).isActive = true

        verifyButton.target = self
        verifyButton.action = #selector(runVerify)
        verifyButton.heightAnchor.constraint(equalToConstant: T.buttonHeight).isActive = true

        let hint = makeLabel("验签只读，不会签发任何东西；有效期与绑定设备会一并给出",
                             size: T.caption, color: C.tertiary)
        let actionRow = NSStackView(views: [verifyButton, summary, makeSpacer(), hint])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = T.rowGap
        inputStack.addArrangedSubview(actionRow)
        actionRow.widthAnchor.constraint(equalTo: inputStack.widthAnchor, constant: -T.cardPadding * 2).isActive = true

        let pane = ScrollPane(spacing: T.tagGap, inset: 10)
        self.pane = pane

        let resultCard = CardView()
        resultCard.content.addSubview(pane)
        pane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: resultCard.content.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: resultCard.content.trailingAnchor),
            pane.topAnchor.constraint(equalTo: resultCard.content.topAnchor),
            pane.bottomAnchor.constraint(equalTo: resultCard.content.bottomAnchor),
        ])
        resultCard.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        resultCard.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)

        let column = NSStackView(views: [inputCard, resultCard])
        column.orientation = .vertical
        column.alignment = .leading
        column.distribution = .fill
        column.spacing = T.blockGap
        column.edgeInsets = NSEdgeInsets(top: T.pagePadding, left: T.pagePadding,
                                         bottom: T.pagePadding, right: T.pagePadding)
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        for sub in [inputCard, resultCard] {
            sub.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -T.pagePadding * 2).isActive = true
        }
        inputCard.setContentHuggingPriority(.required, for: .vertical)
        inputCard.setContentCompressionResistancePriority(.required, for: .vertical)

        view = root
        pane.addRow(makeEmptyHint("验签结果会显示在这里（签名是否有效 · 绑定设备 · 到期时间）"))
    }

    @objc private func runVerify() {
        guard let pane else { return }
        pane.stack.arrangedSubviews.forEach {
            pane.stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let raw = input.text
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            summary.stringValue = "没有内容"
            summary.textColor = C.bad
            return
        }

        // 从文本里抠出所有凭证（支持一次粘多条）
        var codes: [String] = []
        let pattern = "CLIP1\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            for match in regex.matches(in: raw, range: range) {
                if let r = Range(match.range, in: raw) { codes.append(String(raw[r])) }
            }
        }
        if codes.isEmpty { codes = [raw.trimmingCharacters(in: .whitespacesAndNewlines)] }

        var validCount = 0
        for code in codes {
            let result = core.verify(code)
            if result.valid { validCount += 1 }

            var details: [String] = []
            if let service = result.service { details.append("档位 \(service)") }
            if let issued = result.issuedAtText { details.append("签发 \(issued)") }
            if let expires = result.expiresAtText {
                let expiredTag = result.expired ? "（已过期）" : ""
                details.append("到期 \(expires)\(expiredTag)")
            } else {
                details.append("永久有效")
            }
            if let note = result.note { details.append("备注 \(note)") }

            let row = ResultRowView(inline: true)
            let codeSnapshot = code
            row.onCopy = { copyToPasteboard(codeSnapshot) }
            row.configure(
                iconText: result.valid ? "✓" : "✗",
                iconColor: result.valid ? C.ok : C.bad,
                primaryText: result.device ?? "（无绑定设备）",
                secondaryText: details.joined(separator: " · "),
                trailingText: result.failure ?? (result.expired ? "已过期" : "有效"),
                trailingColor: result.valid ? (result.expired ? C.warn : C.ok) : C.bad
            )
            pane.addRow(row)

            if !result.valid, let failure = result.failure {
                let reason = ResultRowView(showCopy: false)
                reason.configure(iconText: "↳", iconColor: C.tertiary,
                                 primaryText: failure,
                                 secondaryText: "凭证：\(code.prefix(48))…",
                                 trailingText: "")
                pane.addRow(reason)
            }
        }

        summary.stringValue = "有效 \(validCount) / 共 \(codes.count) 张"
        summary.textColor = validCount == codes.count ? C.ok : C.warn
    }
}

// MARK: ============================================================================
// ③ 签发台账
// ============================================================================

final class LedgerPageController: NSViewController {

    private let core = LicenseCore.shared
    private let pane = ScrollPane(spacing: T.tagGap, inset: 10)
    private let countLabel = makeLabel("", size: T.caption, color: C.tertiary)

    override func loadView() {
        let root = NSView()

        let refresh = PillButton("刷新", kind: .primary, target: self, action: #selector(refreshTapped(_:)))
        refresh.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let reveal = PillButton("在 Finder 中显示", kind: .secondary, target: self, action: #selector(revealFile))
        reveal.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let header = NSStackView(views: [
            makeLabel("签发台账", size: T.h2, weight: .semibold),
            countLabel,
            makeSpacer(),
            reveal,
            refresh,
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = T.rowGap
        header.edgeInsets = NSEdgeInsets(top: T.pagePadding, left: T.pagePadding, bottom: 0, right: T.pagePadding)
        header.translatesAutoresizingMaskIntoConstraints = false
        // 页头高度钉死（= 上内边距 + 按钮 28）—— 同顶栏那个坑：
        // 没有 intrinsicContentSize 的 NSStackView 会抢走全部剩余高度，把列表压扁
        header.heightAnchor.constraint(equalToConstant: T.pagePadding + 28).isActive = true

        let resultCard = CardView()
        resultCard.content.addSubview(pane)
        pane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: resultCard.content.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: resultCard.content.trailingAnchor),
            pane.topAnchor.constraint(equalTo: resultCard.content.topAnchor),
            pane.bottomAnchor.constraint(equalTo: resultCard.content.bottomAnchor),
        ])

        resultCard.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        root.addSubview(resultCard)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            resultCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: T.blockGap),
            resultCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: T.pagePadding),
            resultCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -T.pagePadding),
            resultCard.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -T.pagePadding),
        ])

        view = root
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .codelumiLedgerChanged, object: nil)
        reload()
    }

    @objc private func reload() {
        pane.stack.arrangedSubviews.forEach {
            pane.stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows = core.loadLedger()
        countLabel.stringValue = rows.isEmpty ? "" : "共 \(rows.count) 张"

        guard !rows.isEmpty else {
            let empty = ResultRowView(showCopy: false)
            empty.configure(iconText: "·", iconColor: C.tertiary,
                            primaryText: "台账还没有记录",
                            secondaryText: "签发任意一张凭证后，这里会自动追加（文件：\(core.ledgerURL.lastPathComponent)）",
                            trailingText: "")
            pane.addRow(empty)
            return
        }
        for row in rows.reversed() {
            // 「查看」= 行内展开凭证全文（可选中 + 一键拷贝）。
            // 原先这里是「凭证」按钮直接静默复制 —— 点了看不到任何东西，观感上就是按钮坏了。
            let view = ResultRowView(copyTitle: "查看", expandable: true, inline: true)
            view.setDetail(row.code)
            if let code = row.code {
                view.onCopy = { copyToPasteboard(code) }
            }
            let expiresText = row.expiresText.isEmpty ? "永久" : row.expiresText
            view.configure(iconText: String(format: "%04d", row.index),
                           iconColor: C.secondary,
                           primaryText: row.device,
                           secondaryText: "\(row.serviceText) · 至 \(expiresText) · \(row.note)",
                           trailingText: row.issuedAtText)
            pane.addRow(view)
        }
    }

    @objc private func refreshTapped(_ sender: PillButton) {
        reload()
        // 台账没变化时，重载本身看不出任何动静，容易被当成按钮失灵
        sender.flashTitle("已刷新", restoreAfter: 1.0)
    }

    @objc private func revealFile() {
        NSWorkspace.shared.activateFileViewerSelecting([core.ledgerURL])
    }
}
