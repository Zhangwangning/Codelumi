import SwiftUI

// MARK: ============================================================================
// 设置 › 帮助与反馈 › 帮助改进Codelumi（2026-11-05 主人 A+B 方案）
//
// 用户手动提供短信样本 → 存本地 → 用户主动导出（分享 / 邮件）给开发者，
// 开发者在 Mac 上重训分类器，发新版本。
//
// 🔴 页面顶部**强制提醒**：导出内容包含哪些、不包含哪些，用户看过再操作。
// ============================================================================

struct TrainingDataView: View {
    @State private var samples: [TrainingSample] = []
    @State private var showComposer = false
    /// 正在编辑的样本（nil = 新增）
    @State private var editingSample: TrainingSample?
    @State private var showClearConfirm = false
    @State private var pendingMail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                noticeCard
                addCard
                listCard
                exportCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 16)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("帮助改进Codelumi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            samples = TrainingSampleStore.load()
            // 截图脚手架：TRAINING_ADD_DEMO=1 直接展开「添加样本」
            if ProcessInfo.processInfo.environment["TRAINING_ADD_DEMO"] == "1" {
                showComposer = true
            }
        }
        .sheet(isPresented: $showComposer) {
            TrainingSampleComposer { reload() }
        }
        // 编辑已有样本（2026-11-08 主人：已添加的也要能改）
        .sheet(item: $editingSample) { sample in
            TrainingSampleComposer(editing: sample) { reload() }
        }
        .sheet(isPresented: $pendingMail) {
            MailComposeView(
                subject: "Codelumi · 训练样本（\(samples.count) 条）",
                body: "开发者你好，附件是我手动提供的短信样本，用于改进识别。\n\n"
                    + "说明：样本由我手动添加，手机号/身份证/邮箱已脱敏。",
                attachment: ("codelumi-training.jsonl", TrainingSampleStore.exportData())
            ) { pendingMail = false }
        }
        .destructiveConfirm(
            isPresented: $showClearConfirm,
            title: "清空训练样本",
            message: "样本只存在这台手机上，清空后无法恢复。"
        ) {
            TrainingSampleStore.clear()
            samples = []
        }
    }

    // MARK: 强制提醒

    private var noticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                    .foregroundStyle(AppTheme.pendingTint)
                // 🔴 2026-11-22 主人：标题只说到「这是导出内容」，下面四条是实质条款，不动。
                Text("导出内容")
                    .font(AppTheme.TypeScale.rowTitleMedium)
            }
            Text("· 导出内容 = 你手动添加的短信样本 + App 诊断日志，仅此两项。\n"
                 + "· 训练样本由你主动提供并授权使用；手机号、身份证、邮箱会自动脱敏。\n"
                 + "· 不含：你的全部取件记录、位置、通讯录、相册、设备码、账号信息。\n"
                 + "· App 不会自动上传：只有你点「导出」或「邮件发送」时，数据才离开这台手机。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private func reload() {
        samples = TrainingSampleStore.load()
    }

    // MARK: 添加

    private var addCard: some View {
        VStack(spacing: 0) {
            Button { showComposer = true } label: {
                SettingsRow(symbol: "plus.circle.fill", title: "添加一条样本",
                            showsChevron: false,
                            tint: AppTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .settingsCard()
    }

    // MARK: 列表

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已添加 \(samples.count) 条")
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Spacer(minLength: 0)
                if !samples.isEmpty {
                    Button("清空") { showClearConfirm = true }
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(AppTheme.pendingTint)
                        .buttonStyle(.plain)
                }
            }
            if samples.isEmpty {
                Text("还没有样本。添加后可以导出给开发者，用于提升识别准确率。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(samples) { sample in
                    Button { editingSample = sample } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(sample.label == "pickup" ? "快递" : "非快递")
                                .font(AppTheme.TypeScale.badge)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.accent.opacity(0.14)))
                                .foregroundStyle(AppTheme.accent)
                            if let code = sample.code, !code.isEmpty {
                                Text("码 \(code)").font(AppTheme.TypeScale.badge)
                                    .foregroundStyle(.secondary)
                            }
                            if let platform = sample.platform, !platform.isEmpty {
                                Text(platform).font(AppTheme.TypeScale.badge)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                TrainingSampleStore.delete(id: sample.id)
                                samples = TrainingSampleStore.load()
                            } label: {
                                Image(systemName: "trash")
                                    .font(AppTheme.TypeScale.note)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(sample.text)
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if sample.id != samples.last?.id { SettingsDivider() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    // MARK: 导出

    private var exportCard: some View {
        VStack(spacing: 0) {
            ShareLink(item: TrainingExportFile.url()) {
                SettingsRow(symbol: "square.and.arrow.up.fill", title: "导出样本",
                            showsChevron: false,
                            tint: AppTheme.sky)
            }
            .buttonStyle(.plain)
            .disabled(samples.isEmpty)

            SettingsDivider()

            Button { pendingMail = true } label: {
                SettingsRow(symbol: "envelope.fill", title: "用邮件发送",
                            showsChevron: false,
                            tint: AppTheme.doneTint)
            }
            .buttonStyle(.plain)
            .disabled(samples.isEmpty)
        }
        .settingsCard()
    }
}

// MARK: 分享用的临时文件

enum TrainingExportFile {
    /// 写到缓存目录，交给系统分享（微信 / AirDrop / 文件 App 都能收）
    static func url() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("codelumi-training.jsonl")
        try? TrainingSampleStore.exportData().write(to: url, options: .atomic)
        return url
    }
}

// MARK: 添加 / 编辑样本（解析结果直接可改，2026-11-08 重构）

/// 一个表单搞定：原文 → 解析 → **在解析结果上直接改** → 保存。
/// 不再有「用解析结果填充下方标注」这一步，也没有第二块标注区。
struct TrainingSampleComposer: View {
    @Environment(\.dismiss) private var dismiss

    /// nil = 新增；非 nil = 编辑这条
    let editing: TrainingSample?
    var onDone: () -> Void

    @State private var text: String
    @State private var label: String
    @State private var code: String
    @State private var address: String
    @State private var locker: String
    @State private var courier: String
    @State private var platform: String
    @State private var station: String
    @State private var note: String
    @State private var showPicker = false
    @State private var didParse = false

    init(editing: TrainingSample? = nil, onDone: @escaping () -> Void) {
        self.editing = editing
        self.onDone = onDone
        _text = State(initialValue: editing?.text ?? "")
        _label = State(initialValue: editing?.label ?? "pickup")
        _code = State(initialValue: editing?.code ?? "")
        _address = State(initialValue: editing?.address ?? "")
        _locker = State(initialValue: editing?.locker ?? "")
        _courier = State(initialValue: "")
        _platform = State(initialValue: editing?.platform ?? "")
        _station = State(initialValue: "")
        _note = State(initialValue: editing?.note ?? "")
        _didParse = State(initialValue: editing != nil)
    }

    private var isEditing: Bool { editing != nil }
    private var canSave: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    sourceCard
                    pickCard
                    resultCard
                    noteCard
                    privacyNote
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.vertical, 16)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle(isEditing ? "编辑样本" : "添加样本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPicker) {
                TrainingRecordPickerView { record in
                    text = record.rawMessage
                    parse()
                    showPicker = false
                }
            }
        }
    }

    // MARK: 原文

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("短信原文")
                .font(AppTheme.TypeScale.rowTitleMedium)

            TextEditor(text: $text)
                .font(AppTheme.TypeScale.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button { parse() } label: {
                Label("解析这条短信", systemImage: "sparkle.magnifyingglass")
                    .font(AppTheme.TypeScale.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .appGlass(.capsule, tint: AppTheme.accent, interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private var pickCard: some View {
        Button { showPicker = true } label: {
            SettingsRow(symbol: "list.bullet.rectangle", title: "从已有短信挑选",
                        tint: AppTheme.indigo)
        }
        .buttonStyle(.plain)
        .settingsCard()
    }

    // MARK: 解析结果（= 标注表单）

    @ViewBuilder
    private var resultCard: some View {
        if didParse {
            VStack(alignment: .leading, spacing: 12) {
                Picker("这是快递短信吗", selection: $label) {
                    Text("是（取件通知）").tag("pickup")
                    Text("不是").tag("other")
                }
                .pickerStyle(.segmented)

                if label == "pickup" {
                    editableRow("快递公司", $courier, placeholder: "可空")
                    SettingsDivider()
                    // 有些短信没有快递公司，只有平台（拼多多 / 菜鸟 …）
                    editableRow("短信平台", $platform, placeholder: "可空")
                    SettingsDivider()
                    editableRow("取件码", $code, placeholder: "可空")
                    SettingsDivider()
                    editableRow("地址", $address, placeholder: "可空")
                    SettingsDivider()
                    editableRow("驿站", $station, placeholder: "可空")
                    SettingsDivider()
                    // 快递柜：解析到才显示；人工也可以自己填（可空）
                    editableRow("快递柜柜位", $locker, placeholder: "可空，如 A-12")
                } else {
                    Text("判定为「不是取件通知」，下面字段不用填。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCard()
        }
    }

    private func editableRow(_ title: String,
                             _ binding: Binding<String>,
                             placeholder: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            TextField(placeholder, text: binding)
                .font(AppTheme.TypeScale.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注（可空）")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
            TextField("例如：这条实际是京东快递", text: $note)
                .font(AppTheme.TypeScale.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private var privacyNote: some View {
        Text("手机号、身份证、邮箱会自动脱敏。若原文含姓名，请自行改成「张三」这类占位。")
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: 动作

    private func parse() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return }
        didParse = true
        guard let result = PickupParser.parse(trimmed) else {
            label = "other"
            return
        }
        label = "pickup"
        code = result.value
        address = result.address
        courier = result.courier.isEmpty ? result.company : result.courier
        platform = result.company
        station = StationDirectory.shared.matchedName(in: [trimmed]) ?? ""
        locker = result.locker
    }

    private func save() {
        // 🔴 2026-11-17：判「不是取件通知」时必须把解析结果一起清掉。
        //    否则会写出 `label=other` 却 `code=glm-5`、`platform=华为云` 这种
        //    自相矛盾的样本 —— 等于在训练集里告诉模型「这条不是快递，
        //    但它的取件码是 glm-5」，正负样本的边界被自己搅浑。
        //    （实况来源：华为云那条推广短信，用户把判定切成「不是」后字段仍留着。）
        let isPickup = label == "pickup"
        if let editing {
            _ = TrainingSampleStore.update(id: editing.id, text: text, label: label,
                                           code: isPickup ? code : nil,
                                           address: isPickup ? address : nil,
                                           platform: isPickup ? platform : nil,
                                           locker: isPickup ? locker : nil,
                                           note: note)
        } else {
            _ = TrainingSampleStore.add(text: text, label: label,
                                        code: isPickup ? code : nil,
                                        address: isPickup ? address : nil,
                                        platform: isPickup ? platform : nil,
                                        locker: isPickup ? locker : nil,
                                        note: note)
        }
        onDone()
        dismiss()
    }
}

// MARK: 取件卡片列表（整屏挑选）

struct TrainingRecordPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (PickupRecord) -> Void

    private var records: [PickupRecord] {
        let sorted = PickupStore.shared.records.sorted { $0.receivedAt > $1.receivedAt }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.rawMessage.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField("搜索短信内容", text: $query)
                        .font(AppTheme.TypeScale.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color(.tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if records.isEmpty {
                        Text("没有匹配的短信。")
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { SettingsDivider() }
                                Button { onPick(record) } label: { row(record) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .settingsCard()
                    }
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.vertical, 16)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle("选择一条短信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func row(_ record: PickupRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(record.courierDisplay ?? record.company)
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Text(record.code)
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                    .monospaced()
                Spacer(minLength: 0)
                Text(record.isPickedUp ? "已取" : "待取")
                    .font(AppTheme.TypeScale.badge)
                    .foregroundStyle(.secondary)
            }
            if !record.address.isEmpty {
                Text(record.address)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(record.rawMessage)
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
