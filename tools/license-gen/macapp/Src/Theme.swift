import AppKit

// MARK: - 应用内通知（不放在 main.swift —— harness 编译时会排除入口文件）

extension Notification.Name {
    /// 面板里的「打开主窗口」按钮用
    static let codelumiOpenMainWindow = Notification.Name("codelumiOpenMainWindow")
    /// 签发成功后通知台账页刷新
    static let codelumiLedgerChanged = Notification.Name("codelumiLedgerChanged")
}

// ============================================================================
// 设计常量：全部量化 —— 改版时只动这里，不散落在各视图里
// 风格口径：macOS 26/27 液态玻璃 · Apple HIG · 浅色/深色双外观自适应
// ============================================================================

enum T {
    // 间距
    static let pagePadding: CGFloat = 22
    static let cardPadding: CGFloat = 18
    static let blockGap: CGFloat = 14
    static let rowGap: CGFloat = 8
    static let tagGap: CGFloat = 6

    // 圆角（卡片 16 对齐 macOS 26 玻璃容器；胶囊取半高）
    static let cardRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 9
    static let pillRadius: CGFloat = 16
    static let chipRadius: CGFloat = 6

    // 高度（macOS regular 控件区间为 28~32）
    static let fieldHeight: CGFloat = 30
    static let buttonHeight: CGFloat = 32
    static let segmentHeight: CGFloat = 26

    /// 单行结果行的高度下限 = 行内按钮 26 + 上下内边距 8×2。
    /// 为什么要写死：横向 NSStackView 的拟合高度**只按文字算**（实测 8 + 15 + 8 = 31），
    /// 26pt 的按钮不参与计算 —— 结果按钮上下各剩 2pt，视觉上"顶格"。
    static let rowHeightInline: CGFloat = 42

    // 顶栏 / 底栏固定高度 = 内边距 + 内容高。
    //
    // 为什么不靠 Auto Layout 自动分配：AppKit 里凡是没有 intrinsicContentSize 的视图
    // （自定义 NSView、甚至 NSStackView 自身，实测 intrinsicContentSize 全是 -1×-1），
    // `setContentHuggingPriority` 压根不会生成约束，长度分配就成了无解方程 ——
    // 实测顶栏被分到 328pt、内容区只剩 350pt（结果区被压成 10px）。
    // 顶栏/底栏本来就是固定高度的工具栏，直接钉死最可预测。
    static let headerHeight: CGFloat = 64      // 内边距 14+12 + 标题两行 38
    static let footerHeight: CGFloat = 42      // 内边距 8+10 + 按钮 24

    // 字号
    static let h1: CGFloat = 19
    static let h2: CGFloat = 13.5
    static let body: CGFloat = 13
    static let caption: CGFloat = 11
    static let mono: CGFloat = 12.5
    static let monoSmall: CGFloat = 11

    // 尺寸
    static let panelWidth: CGFloat = 372          // 菜单栏弹出面板
    // 主窗口默认尺寸：主人主屏 1920×1080（可用高 976），取约 52% × 70%
    static let windowWidth: CGFloat = 1000
    static let windowHeight: CGFloat = 720
    static let windowMinWidth: CGFloat = 860
    static let windowMinHeight: CGFloat = 620
}

// ============================================================================
// 语义颜色 —— 全部随外观自适应
//
// ⚠️ 关键坑（实测）：`layer.backgroundColor = 动态色.cgColor` 会把**调用当时**的外观
//    颜色固化到 layer 上；之后系统切浅色/深色，layer 不会跟着变。
//    现象就是「浅色窗口 + 深灰卡片 + 近黑输入框」——非常难看。
//    → 凡是用 .cgColor 上 layer 的视图，都必须继承 ThemedView 并在 applyTheme() 里重设。
//    （NSTextField.textColor 不受影响：它是动态色，AppKit 每次绘制都重新解析。）
// ============================================================================

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// 造一个随外观切换的语义色
private func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
    NSColor(name: nil) { $0.isDark ? dark : light }
}

enum C {
    static var accent: NSColor { .controlAccentColor }
    static var label: NSColor { .labelColor }
    static var secondary: NSColor { .secondaryLabelColor }
    static var tertiary: NSColor { .tertiaryLabelColor }
    static var separator: NSColor { .separatorColor }
    static var ok: NSColor { .systemGreen }
    static var warn: NSColor { .systemOrange }
    static var bad: NSColor { .systemRed }

    /// 输入框底：浅色下提亮成白（在灰窗口上"浮起来"），深色下是微亮白
    static var fieldFill: NSColor {
        dynamic(NSColor.white.withAlphaComponent(0.88),
                NSColor.white.withAlphaComponent(0.06))
    }
    /// 次级容器底（结果行 / chip）：浅色下压暗一点点，深色下提亮一点点
    static var subtleFill: NSColor {
        dynamic(NSColor.black.withAlphaComponent(0.035),
                NSColor.white.withAlphaComponent(0.055))
    }
    /// 细描边
    static var hairline: NSColor {
        dynamic(NSColor.black.withAlphaComponent(0.10),
                NSColor.white.withAlphaComponent(0.13))
    }
    /// 玻璃质感按钮底（浅色下是半透明白，深色下是半透明白）
    static func glassFill(hovering: Bool) -> NSColor {
        dynamic(NSColor.white.withAlphaComponent(hovering ? 0.98 : 0.86),
                NSColor.white.withAlphaComponent(hovering ? 0.15 : 0.10))
    }
    /// 悬停微底（quiet 按钮）
    static var hoverFill: NSColor {
        dynamic(NSColor.black.withAlphaComponent(0.06),
                NSColor.white.withAlphaComponent(0.09))
    }
    /// 嵌在结果行里的展开详情底：比结果行再压暗一档，做出"凹陷"的层级感
    static var detailFill: NSColor {
        dynamic(NSColor.black.withAlphaComponent(0.055),
                NSColor.black.withAlphaComponent(0.28))
    }

    // 旧名兼容
    static var cardBg: NSColor { subtleFill }
    static var fieldBg: NSColor { fieldFill }
}

// MARK: - 字体

enum F {
    static func system(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    static func monoBold(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }
}

// ============================================================================
// 外观感知基类：把 layer 颜色刷新收敛到一处
//
// 同一陷阱的另一面：`动态色.cgColor` 按「当前绘制外观」解析。视图刚 init、
// 还没进窗口层级时，effectiveAppearance 可能还是系统外观甚至是错的值 —— 直接取
// .cgColor 会把颜色固化错。所以一律用 resolvedCGColor() 在视图自身外观下解析。
// ============================================================================

class ThemedView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }
    /// 子类覆写：重设所有依赖外观的 layer 颜色，务必配合 `resolvedCGColor(_:)`
    func applyTheme() {}

    /// 在视图自身外观下解析动态色
    func resolvedCGColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            result = color.cgColor
        }
        return result
    }
}

// ============================================================================
// 液态玻璃（macOS 26 引入的 NSGlassEffectView）
// ============================================================================

/// 造一块液态玻璃。`cornerRadius` 要与内容圆角一致，否则玻璃边缘会露出直角。
/// 玻璃会自动跟随系统外观与背后内容，天然免疫「颜色固化」问题。
func makeGlass(cornerRadius: CGFloat,
               style: NSGlassEffectView.Style = .regular,
               interactive: Bool = false) -> NSGlassEffectView {
    let glass = NSGlassEffectView()
    glass.cornerRadius = cornerRadius
    glass.style = style
    // macOS 27 起支持交互反馈（指针经过/按下时玻璃有动态响应）
    if interactive { glass.effectIsInteractive = true }
    return glass
}

/// 玻璃卡片容器。
/// 内容必须加进 `content`。
/// 实现取舍：玻璃只当「同级背景层」，content 直接挂在卡片上（不塞进 glass.contentView）。
/// 实测：把 content 设成 glass.contentView 后再约束到玻璃四边，会与 AppKit 内部的
/// contentView 布局打架 —— 卡片在垂直栈里彻底失去伸展能力，被压成 10px。
/// 同级背景层则完全不影响布局链（glass 先 addSubview 所以在下层）。
final class CardView: ThemedView {
    let content = NSView()
    private let glass: NSGlassEffectView

    init(radius: CGFloat = T.cardRadius, interactive: Bool = false) {
        glass = makeGlass(cornerRadius: radius, interactive: interactive)
        super.init(frame: .zero)

        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)          // 后添加 → 在玻璃之上

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),

            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ============================================================================
// 胶囊按钮
//
// 背景走自绘（override draw），画在 super.draw 之前 —— 这样系统画的标题仍在最上层。
// （不能把背景做成 subview/layer 的 sublayer：sublayer 会盖在 layer.contents 之上，
//   把标题糊掉。）
// 形态语言参照 Apple 自家 App 的主操作按钮：强调色渐变 + 顶部高光 + 轻投影。
// ============================================================================

final class PillButton: NSButton {
    enum Kind { case primary, secondary, quiet, danger }

    var kind: Kind = .primary { didSet { restyle() } }

    private var hovering = false
    private var trackingArea: NSTrackingArea?

    convenience init(_ title: String, kind: Kind = .primary, target: AnyObject?, action: Selector?) {
        self.init(title: title, target: target, action: action)
        self.kind = kind
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.focusRingType = .none
        self.setButtonType(.momentaryChange)
        restyle()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; restyle() }

    override var isEnabled: Bool { didSet { restyle() } }

    // ── 即时反馈 ──────────────────────────────────────────────
    // 拷拷贝类操作必须给视觉反馈：静默复制在界面上等于「按钮坏了」。
    // 实测主人反馈：「凭证」按钮点了没反应 —— 其实复制成功了，只是没任何提示。
    private var flashWorkItem: DispatchWorkItem?
    private var titleBeforeFlash: String?

    /// 短暂换标题再复原（如「拷贝」→「已拷贝」）。连续点击不会把复原值串味。
    func flashTitle(_ text: String, restoreAfter: TimeInterval = 1.6) {
        if titleBeforeFlash == nil { titleBeforeFlash = title }
        title = text
        flashWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.title = self.titleBeforeFlash ?? self.title
            self.titleBeforeFlash = nil
        }
        flashWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter, execute: item)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    /// 宽度按文字自适应（+ 水平内边距），避免固定宽把标题截断
    /// （实测：「主窗口」标题需要 74pt，写死 66pt 就被切了）
    override var intrinsicContentSize: NSSize {
        let textWidth = (title as NSString).size(withAttributes: [.font: F.system(T.body, .medium)]).width
        let base = super.intrinsicContentSize
        return NSSize(width: ceil(max(textWidth, base.width)) + 34,
                      height: max(base.height, T.buttonHeight))
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        layer?.shadowPath = CGPath(roundedRect: bounds,
                                   cornerWidth: bounds.height / 2,
                                   cornerHeight: bounds.height / 2,
                                   transform: nil)
    }

    // ── 自绘背景 ─────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        drawCapsule(in: bounds)
        super.draw(dirtyRect)        // 标题由系统画在背景之上
    }

    private func capsulePath(_ rect: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: rect,
                     xRadius: rect.height / 2,
                     yRadius: rect.height / 2)
    }

    private func drawCapsule(in rect: NSRect) {
        let enabled = isEnabled
        let path = capsulePath(rect)

        switch kind {
        case .primary:
            let base = C.accent
            var top = base.blended(withFraction: hovering ? 0.18 : 0.10, of: .white) ?? base
            var bottom = base.blended(withFraction: 0.10, of: .black) ?? base
            if !enabled {
                top = base.withAlphaComponent(0.32)
                bottom = base.withAlphaComponent(0.26)
            }
            // 纵向渐变：上亮下深，制造"受光"的立体感
            NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

            // 顶部高光：只在胶囊上半部叠一层白，模仿玻璃的掠射反光
            if enabled {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                let glossRect = NSRect(x: rect.minX, y: rect.midY,
                                       width: rect.width, height: rect.height / 2)
                NSGradient(starting: NSColor.white.withAlphaComponent(0.26),
                           ending: NSColor.white.withAlphaComponent(0.0))?
                    .draw(in: glossRect, angle: -90)
                NSGraphicsContext.restoreGraphicsState()
            }

        case .secondary:
            C.glassFill(hovering: hovering && enabled).setFill()
            path.fill()
            C.hairline.setStroke()
            path.lineWidth = 1
            path.stroke()

        case .quiet:
            if hovering && enabled {
                C.hoverFill.setFill()
                path.fill()
            }

        case .danger:
            C.bad.withAlphaComponent(hovering && enabled ? 0.20 : 0.13).setFill()
            path.fill()
            C.bad.withAlphaComponent(0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func restyle() {
        let enabled = isEnabled
        layer?.cornerRadius = bounds.height / 2

        // 阴影：主按钮有明显投影（强调"可点"），其余按钮极淡或不加
        switch kind {
        case .primary where enabled:
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.22
            layer?.shadowRadius = hovering ? 5 : 3.5
            layer?.shadowOffset = CGSize(width: 0, height: -1)
        case .secondary where enabled:
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.07
            layer?.shadowRadius = 2
            layer?.shadowOffset = CGSize(width: 0, height: -1)
        default:
            layer?.shadowOpacity = 0
        }

        // 文字色：主按钮白字，其余按语义
        let color: NSColor
        switch kind {
        case .primary:   color = .white
        case .secondary: color = C.label
        case .quiet:     color = C.secondary
        case .danger:    color = C.bad
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: F.system(T.body, .medium),
            .foregroundColor: enabled ? color : color.withAlphaComponent(0.45),
            .paragraphStyle: paragraph,
        ])
        needsDisplay = true
    }

    /// 标题变化后由外部调用刷新（`title` 的 attributedTitle 需要重建）
    func restylePublic() { restyle() }
}

// ============================================================================
// 输入框外壳：自绘圆角背景 + 聚焦描边
// 直接给 NSTextField 设 layer 会被系统 bezel 干扰，所以外面包一层
// ============================================================================

final class FieldBox: ThemedView {
    let field: NSTextField
    private var focused = false
    private var onEnter: (() -> Void)?

    init(placeholder: String, monospaced: Bool = false, onEnter: (() -> Void)? = nil) {
        field = NSTextField()
        super.init(frame: .zero)

        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = monospaced ? F.mono(T.mono) : F.system(T.body)
        field.lineBreakMode = .byTruncatingTail
        if onEnter != nil { field.target = self; field.action = #selector(handleEnter) }
        self.onEnter = onEnter

        wantsLayer = true
        layer?.cornerRadius = T.fieldRadius
        layer?.borderWidth = 1

        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: T.fieldHeight),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(beginEditing),
                                               name: NSControl.textDidBeginEditingNotification, object: field)
        NotificationCenter.default.addObserver(self, selector: #selector(endEditing),
                                               name: NSControl.textDidEndEditingNotification, object: field)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleEnter() { onEnter?() }
    @objc private func beginEditing() { focused = true; applyTheme() }
    @objc private func endEditing() { focused = false; applyTheme() }

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    func setEnabled(_ on: Bool) {
        field.isEnabled = on
        field.textColor = on ? C.label : C.tertiary
        applyTheme()
    }

    override func applyTheme() {
        layer?.backgroundColor = resolvedCGColor(C.fieldFill)
        layer?.borderColor = resolvedCGColor(focused ? C.accent : C.hairline)
    }

    /// 供测试脚本直接写入（不经过 UI 交互）
    func write(_ text: String) { field.stringValue = text }
}

// MARK: - 文本便捷构造

func makeLabel(_ text: String,
               size: CGFloat = T.body,
               weight: NSFont.Weight = .regular,
               color: NSColor = C.label,
               mono: Bool = false,
               compressible: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = mono ? F.mono(size) : F.system(size, weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    if compressible {
        // 只有长文本（路径、备注）才允许被压缩；普通标签必须按内容定宽，
        // 否则在 NSStackView 里会被挤成几个像素（实测：「档位」只剩 4px）
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    return label
}

/// 弹性占位：吸收行内多余空间。
///
/// 三个坑都踩过才知道：
/// ① 水平方向：默认 hugging 250 与标签同值，NSStackView 判定不出谁该伸缩，
///    需要显式压到最低，否则标签会被挤成几像素（实测「档位」只剩 4px）。
/// ② 垂直方向**不能靠 hugging 锁**：空 NSView 没有 intrinsicContentSize，
///    Auto Layout 的 hugging / compression 约束根本不会生成 ——
///    设成 required 也拦不住它。必须用显式高度约束锁 0。
/// ③ 不锁会怎样：水平栈里 spacer 会被拉伸到填满可用高度，把整个容器一起拉高。
///    实测 header 的 fittingSize 只有 52，实得高度却是 328pt，直接把内容区挤扁、
///    结果区压成 10px —— 表现就是「窗口下方一大片空白」。
func makeSpacer() -> NSView {
    let low = NSLayoutConstraint.Priority(1)
    let view = NSView()
    view.setContentHuggingPriority(low, for: .horizontal)
    view.setContentCompressionResistancePriority(low, for: .horizontal)
    view.heightAnchor.constraint(equalToConstant: 0).isActive = true
    return view
}

func makeWrapLabel(_ text: String,
                   size: CGFloat = T.body,
                   weight: NSFont.Weight = .regular,
                   color: NSColor = C.label,
                   mono: Bool = false) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = mono ? F.mono(size) : F.system(size, weight)
    label.textColor = color
    label.isSelectable = true
    return label
}

// MARK: - 水平分隔线

final class HairlineView: ThemedView {
    override func applyTheme() {
        layer?.backgroundColor = resolvedCGColor(C.hairline.withAlphaComponent(0.55))
    }
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: 1).isActive = true
        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError() }
}

func makeSeparator() -> NSView { HairlineView() }

// MARK: - 小标签（chip）

final class ChipView: ThemedView {
    private let label: NSTextField
    private var tint: NSColor

    init(text: String, color: NSColor = C.secondary) {
        label = makeLabel(text, size: T.caption, weight: .medium, color: color)
        tint = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = T.chipRadius

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func applyTheme() {
        layer?.backgroundColor = resolvedCGColor(tint.withAlphaComponent(0.14))
    }

    func set(text: String, color: NSColor) {
        label.stringValue = text
        label.textColor = color
        tint = color
        applyTheme()
    }
}

// MARK: - 可滚动容器（内容高度由内容决定）

/// 翻转的 NSStackView：作为 NSScrollView 的 documentView 时必须用这个。
/// 实测：非翻转的 NSStackView 放进 NSScrollView，内容不足一屏时会贴到底部、
/// 且垂直排列方向与直觉相反（`stack.isFlipped` 实测为 false）。
/// NSTextView 这类标准 documentView 本身就是 flipped 的，跟着做即可。
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class ScrollPane: NSView {
    let stack = FlippedStackView()
    let scroll = NSScrollView()
    private let contentInset: CGFloat

    /// - Parameter inset: 内容四周留白。独立使用时用默认的 pagePadding；
    ///   放进玻璃卡片里时应调小（卡片自身已有边界，再留大边距会显得空）
    init(spacing: CGFloat = T.blockGap, inset: CGFloat = T.pagePadding) {
        contentInset = inset
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        // 关键（实测坑）：documentView 必须约束到 clipView，否则高度恒为 0、内容不可见
        let clip = scroll.contentView
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])

        // 关键（实测坑）：本视图在垂直 NSStackView 里必须"能吃剩余空间"。
        // 三个 arrangedSubview 的 hugging 都是默认 250 时，NSStackView 无法判断该伸缩谁，
        // 结果 ScrollPane 被压到最小、窗口下方留出大片空白。
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 往栈里加一行，并显式约束到栈宽（NSStackView 的 alignment=.width 不可靠）
    func addRow(_ view: NSView, inset: CGFloat = 0) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                    constant: -(contentInset * 2) - inset).isActive = true
    }
}
