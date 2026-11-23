import AppKit

// ============================================================================
// 菜单栏弹出面板：随手签一张
// 流程：粘贴设备码 → 选档位 → 点「签发并拷贝」
// 面板宽度固定 T.panelWidth，高度由内容撑开（viewDidLayout 里同步给 popover）
// ============================================================================

final class SignPanelController: NSViewController {

    private let core = LicenseCore.shared

    private let deviceField = FieldBox(placeholder: "粘贴买家设备码（32 位十六进制）", monospaced: true)
    private let daysField = FieldBox(placeholder: "按档位默认")
    private let noteField = FieldBox(placeholder: "备注（可选，只给你自己对账用）")
    private let serviceSegment = NSSegmentedControl(labels: LicenseService.allCases.map(\.title),
                                                    trackingMode: .selectOne,
                                                    target: nil, action: nil)
    private let deviceHint = makeLabel("", size: T.caption, color: C.tertiary)
    private let statusLabel = makeLabel("", size: T.body, color: C.secondary)
    private let codeLabel = makeWrapLabel("", size: T.monoSmall, color: C.tertiary, mono: true)
    private let issueButton = PillButton("签发并拷贝", kind: .primary, target: nil, action: nil)
    private let daysRow = NSStackView()

    private var selectedService: LicenseService {
        let index = max(0, min(serviceSegment.selectedSegment, LicenseService.allCases.count - 1))
        return LicenseService.allCases[index]
    }

    // MARK: 视图

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = T.blockGap
        stack.edgeInsets = NSEdgeInsets(top: T.cardPadding, left: T.cardPadding,
                                        bottom: T.cardPadding, right: T.cardPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: T.panelWidth),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        // ── 标题行
        let title = makeLabel("签发凭证", size: T.h1, weight: .semibold)
        let openWindow = PillButton("主窗口", kind: .quiet, target: self, action: #selector(openMainWindow))
        openWindow.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let titleRow = NSStackView(views: [title, makeSpacer(), openWindow])
        titleRow.orientation = .horizontal
        titleRow.spacing = T.tagGap
        stack.addArrangedSubview(titleRow)
        titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true

        // ── 设备码
        sectionLabel("设备码", in: stack)
        stack.addArrangedSubview(deviceField)
        deviceField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true
        stack.addArrangedSubview(deviceHint)
        deviceField.field.delegate = self

        // ── 档位
        sectionLabel("档位", in: stack)
        serviceSegment.target = self
        serviceSegment.action = #selector(serviceChanged)
        serviceSegment.selectedSegment = 0
        stack.addArrangedSubview(serviceSegment)
        serviceSegment.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true

        // ── 天数（永久档隐藏）
        let daysLabel = sectionLabel("天数（留空按档位默认）", in: stack)
        daysRow.orientation = .horizontal
        daysRow.spacing = T.tagGap
        daysField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        daysRow.addArrangedSubview(daysField)
        daysRow.addArrangedSubview(makeSpacer())
        stack.addArrangedSubview(daysRow)
        daysRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true
        daysLabelHolder = daysLabel

        // ── 备注（placeholder 已说明用途，不再重复加标签）
        stack.addArrangedSubview(noteField)
        noteField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true

        // ── 动作
        stack.addArrangedSubview(issueButton)
        issueButton.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true
        issueButton.heightAnchor.constraint(equalToConstant: T.buttonHeight).isActive = true
        issueButton.target = self
        issueButton.action = #selector(issueLicense)

        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(codeLabel)
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true
        codeLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true
        codeLabel.isHidden = true

        view = root
        refreshForService()
        refreshDeviceHint()
    }

    private var daysLabelHolder: NSView?

    /// 段落小标题：自己加进 stack 并约束到 stack 宽
    /// ⚠️ 不能引用 `self.view` —— loadView 期间 view 尚未赋值，访问会递归触发 loadView 直接爆栈
    @discardableResult
    private func sectionLabel(_ text: String, in stack: NSStackView) -> NSTextField {
        let label = makeLabel(text, size: T.caption, weight: .medium, color: C.secondary)
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -T.cardPadding * 2).isActive = true
        return label
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let fitting = view.fittingSize
        if abs(preferredContentSize.height - fitting.height) > 0.5 {
            preferredContentSize = NSSize(width: T.panelWidth, height: fitting.height)
        }
    }

    func focusDeviceField() {
        view.window?.makeFirstResponder(deviceField.field)
    }

    // MARK: 交互

    @objc private func openMainWindow() {
        NotificationCenter.default.post(name: .codelumiOpenMainWindow, object: nil)
    }

    @objc private func serviceChanged() {
        refreshForService()
    }

    private func refreshForService() {
        let service = selectedService
        let isLifetime = service == .lifetime
        daysRow.isHidden = isLifetime
        daysLabelHolder?.isHidden = isLifetime
        daysField.stringValue = isLifetime ? "" : String(service.defaultDays)
        issueButton.title = isLifetime ? "签发永久凭证并拷贝" : "签发并拷贝"
        issueButton.restylePublic()
    }

    private func refreshDeviceHint() {
        let normalized = LicenseCore.normalizeDevice(deviceField.stringValue)
        if normalized.isEmpty {
            deviceHint.stringValue = ""
        } else if LicenseCore.isValidDevice(normalized) {
            deviceHint.stringValue = "✓ \(normalized)"
            deviceHint.textColor = C.ok
        } else {
            deviceHint.stringValue = "归一化后 \(normalized.count) 位，应为 32 位（当前：\(normalized)）"
            deviceHint.textColor = C.warn
        }
    }

    @objc private func issueLicense() {
        let service = selectedService
        let days: Int
        if service == .lifetime {
            days = 0
        } else {
            let typed = daysField.stringValue.trimmingCharacters(in: .whitespaces)
            days = Int(typed) ?? service.defaultDays
        }
        let note = noteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let license = try core.issue(rawDevice: deviceField.stringValue,
                                         service: service,
                                         days: days,
                                         note: note.isEmpty ? nil : note)
            copyToPasteboard(license.code)

            var message = "已拷贝到剪贴板"
            if let expires = license.expiresAt {
                message += " · 至 \(core.dayString(expires))"
            } else {
                message += " · 永久有效"
            }
            do {
                let index = try core.appendLedger(license)
                message += " · 已记账 \(String(format: "#%04d", index))"
                NotificationCenter.default.post(name: .codelumiLedgerChanged, object: nil)
            } catch {
                message += " · ⚠️ 台账写入失败"
            }

            statusLabel.stringValue = message
            statusLabel.textColor = C.ok
            codeLabel.stringValue = license.code
            codeLabel.isHidden = false
            deviceField.stringValue = license.device      // 回填归一化结果
            refreshDeviceHint()
        } catch {
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = C.bad
            codeLabel.isHidden = true
        }
        view.needsLayout = true
    }

    private func copyToPasteboard(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

// MARK: - 输入联动

extension SignPanelController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        refreshDeviceHint()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            issueLicense()
            return true
        }
        return false
    }
}
