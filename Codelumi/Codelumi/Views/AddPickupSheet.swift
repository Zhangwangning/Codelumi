import SwiftUI
import UIKit

// MARK: ============================================================================
// 手动添加取件信息
//
// 设计原则：手动添加与快捷指令自动化**共用同一个解析入口**
// （PickupParser → PickupStore.ingest），因此同一套去重指纹、同一套类别判定，
// 不会出现「自动收的能去重、手动加的不能」这类两套逻辑的问题。
//
// 只有在「整段文本解析不出任何凭证」时才降级：把那串输入直接当作取件码写入。
// 这条兜底是必要的 —— 用户手上可能只有一个码，没有短信原文。
// ============================================================================

// MARK: - 裸码判据

/// 这段输入是不是「本身就是一个取件码」。
///
/// 2026-11-22 语音录入整块删除后，这个判据只剩文本录入与照片录入两处使用 ——
/// 之前放在已删除的语音页里，跟着一起丢过，别再挪回去。
///
/// 判据刻意保守：宁可让用户多点一次「作为取件码添加」，也不能把**半条短信**
/// 当成码塞进列表（那会生成「您的圆通快递包裹已…」这种垃圾记录）。
enum BareCodeHeuristic {
    static func isLikely(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...48).contains(t.count) else { return false }
        guard !t.contains("\n") else { return false }
        // 纯码里不该出现空格或句读，否则更像是被截断的短信
        guard t.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        let punctuation = CharacterSet(charactersIn: "。，,、；;！!？?")
        return t.rangeOfCharacter(from: punctuation) == nil
    }
}

final class AddPickupModel: ObservableObject {
    @Published var text: String = "" {
        didSet { reparse() }
    }

    /// 实时解析结果（输入即算）。**可能是多条** ——
    /// 从短信 App 多选复制一次粘进来，常常就是好几行。
    @Published private(set) var parsedList: [PickupParseResult] = []

    /// 首条结果（供「只关心有没有识别到」的场景，如按钮可用性判断）
    var parsed: PickupParseResult? { parsedList.first }

    /// 添加成功后的收尾态：显示绿色反馈再自动关闭
    @Published var addedMessage: String?

    /// 预填内容（仅供命令行截图验证注入，生产路径不传）
    init(seed: String = "") {
        // init 中的赋值不触发 didSet，需显式解析一次
        text = seed
        reparse()
    }

    private func reparse() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 走 OCR 专用入口：短信原文本身可能带换行（在「取件码」与数字之间断行），
        // 会切断定长 lookbehind 锚点。该入口同时负责「一次多条」的切段。
        parsedList = trimmed.isEmpty
            ? []
            : PickupParser.parseAll(trimmed, ocrSource: true).map(\.normalized)
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasInput: Bool { !trimmed.isEmpty }

    /// 输入只有一行且不含空白/中文时，才认为「可以当作一个纯码」
    var looksLikeBareCode: Bool { BareCodeHeuristic.isLikely(text) }

    func pasteFromClipboard() {
        if let value = UIPasteboard.general.string, !value.isEmpty { text = value }
    }

    func clear() { text = "" }
}

struct AddPickupSheet: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model: AddPickupModel
    /// 键盘焦点：点空白 / 往下拖页面都能收起（2026-11-22 起不再挂键盘上方的「完成」）
    @FocusState private var editorFocused: Bool

    /// 关闭回调（由父视图控制呈现状态，避免依赖 dismiss 环境值）
    let onClose: () -> Void
    /// 添加成功后的回调，用于让列表把新条目显现出来
    let onAdded: (IngestOutcome) -> Void

    init(initialText: String = "",
         onClose: @escaping () -> Void,
         onAdded: @escaping (IngestOutcome) -> Void) {
        _model = StateObject(wrappedValue: AddPickupModel(seed: initialText))
        self.onClose = onClose
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let message = model.addedMessage {
                        successBanner(message)
                    } else {
                        inputCard
                        resultSection
                    }
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, minHeight: 1, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { editorFocused = false }
            }
            // 手指往下拖列表就把键盘收起来（系统标准行为）
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.sheetSurface)   // 半屏面板 = 比页面亮一档
            .navigationTitle("添加取件信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") { submit() }
                        .fontWeight(.semibold)
                        .disabled(!model.hasInput || model.addedMessage != nil)
                }
                // 🔴 这里原来挂着一个 `placement: .keyboard` 的「完成」按钮（收键盘用）。
                //    2026-11-22 老大截图问「屏幕右下角为啥有个完成按钮」—— iOS 26 把它当作
                //    浮动工具条渲染，键盘没弹出来时它就孤零零悬在右下角，既不属于导航栏
                //    也不属于页面内容，纯噪音。收键盘本就有两条更自然的路：
                //    点空白（`onTapGesture`）+ 下拖页面（`scrollDismissesKeyboard`），
                //    所以整块删掉，不再给它安排位置。
            }
        }
    }

    // MARK: 输入区

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题行：图标 + 标题 + 字数
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("粘贴短信内容")
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Spacer(minLength: 0)
                if model.hasInput {
                    Text("\(model.trimmed.count) 字")
                        .font(AppTheme.TypeScale.badge)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.text)
                    .font(AppTheme.TypeScale.body)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 168)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                if model.text.isEmpty {
                    Text("把整条快递短信粘贴进来")
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            // 编辑区用系统填充色：玻璃卡里再套一层玻璃会互相吃掉对比度
            .background(Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 10) {
                smallButton(title: "粘贴", symbol: "doc.on.clipboard",
                            enabled: UIPasteboard.general.hasStrings) {
                    model.pasteFromClipboard()
                }
                smallButton(title: "清空", symbol: "xmark.circle",
                            enabled: model.hasInput) {
                    model.clear()
                }
                // 🔴 2026-11-22 主人：「语音输入不要和粘贴解析添加放在一起」。
                //    2026-11-22 晚语音录入整块删除，本页只剩「贴一段文字」这一件事。
                Spacer(minLength: 0)
            }

            // 原来单独一张「会自动识别」卡，并进来 —— 少一张卡，少一层视觉噪音
            Text("会自动识别取件码、平台、快递公司与地址；识别不出就留空。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private func smallButton(title: String, symbol: String,
                             enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.accent.opacity(enabled ? 0.13 : 0.05), in: .capsule)
                .foregroundStyle(enabled ? AppTheme.accent : Color.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 解析结果 / 引导

    @ViewBuilder
    private var resultSection: some View {
        if !model.hasInput {
            EmptyView()
        } else if !model.parsedList.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.doneTint)
                    Text(model.parsedList.count > 1
                         ? "已识别 \(model.parsedList.count) 条"
                         : "已识别")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                // 多条时逐张列出，添加前能核对到每一条
                // （序号已去掉：待取卡没有序号，预览卡照它排版，条数由上面的「已识别 N 条」交代）
                ForEach(Array(model.parsedList.enumerated()), id: \.offset) { _, parsed in
                    ParsePreviewCard(parsed: parsed)
                }
            }
        } else if model.looksLikeBareCode {
            VStack(alignment: .leading, spacing: 12) {
                hintCard(symbol: "lightbulb.fill", tint: AppTheme.pendingTint,
                         title: "没有短信可解析",
                         detail: "看起来这串内容本身就是一个取件码。可以直接把它加进待取件列表。")

                Button {
                    submitBareCode()
                } label: {
                    Label("作为取件码添加", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppTheme.pendingTint, in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        } else {
            hintCard(symbol: "exclamationmark.triangle.fill", tint: AppTheme.amber,
                     title: "没识别到取件信息",
                     detail: "请确认粘贴的是**快递短信全文**。若只想记录一个取件码，单独输入那一串码即可。")
        }
    }

    private func hintCard(symbol: String, tint: Color,
                          title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.L)
                    .font(.subheadline.weight(.semibold))
                Text(detail.richText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private func successBanner(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.doneTint)
                .padding(.top, 36)

            Text(message.L)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 提交

    private func submit() {
        guard model.hasInput else { return }
        // 文本/拍照/相册录入都在 App 内、用户亲手确认 → 不弹通知
        var outcome = store.ingestOCR(model.trimmed, source: .inApp)

        // 🔴 解析器一条都没认出来时，兜底把整段输入当取件码（2026-10-25 审查修）。
        // 以前这里只走 `ingestOCR`：用户手输「A128」这种短信正则认不出、但明显是
        // 取件码的内容，点右上「添加」会弹**绿色对勾** +「没识别到取件信息，已忽略」，
        // 1 秒后自动关闭、什么都没存 —— 成功视觉配失败结果，而且「添加」是这个页面
        // 最顺手的主按钮。页面下方本来就有「作为取件码添加」的兜底按钮，主按钮更该兜住。
        // 🔴 2026-10-30 修：只有「解析器一条都没认出来」且「输入确实像一个裸码」
        //    才走兜底。原来的判断是 `outcome.added.isEmpty` —— 而 2026-10-30 起
        //    同码重复短信**不再新建**（只更新时间），`added` 同样是空，
        //    于是「粘贴一条已经存在的短信」会被当成裸码，把**整段短信原文**
        //    塞进取件码字段，列表里出现「手动添加 / 快递超市 / 您的圆通快递包裹已…」
        //    这种垃圾记录（真机实证）。
        let recognized = !PickupParser.parseAll(model.trimmed, ocrSource: true).isEmpty
        if !recognized, model.looksLikeBareCode {
            outcome = store.addManual(code: model.trimmed)
        }

        finish(with: outcome)
    }

    /// 兜底路径：把输入直接当作一个取件码
    private func submitBareCode() {
        let outcome = store.addManual(code: model.trimmed)
        finish(with: outcome)
    }

    private func finish(with outcome: IngestOutcome) {
        onAdded(outcome)

        // 文案统一取 `outcome.dialog` —— App 内所有入口（粘贴 / 拍照 / 相册）
        // 共用同一口径，不会出现"这个入口说 3 条、那个入口说 5 条"这种两套说法。
        withAnimation(.snappy) { model.addedMessage = outcome.dialog }

        // 短暂展示结果后自动收尾，不需要用户再点一次
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            onClose()
        }
    }
}

// MARK: - 解析结果预览（添加页与扫描页共用）

/// 用户点「添加」之前，先看到这条记录**将会长成什么样**。
///
/// 🔴 2026-11-22 老大：「手工录入时这里的卡片保持和待取页面的卡片样式一样」。
///    以前这里是录入页自创的第二套版式（左图标 22 + 主名 15 + 右上角大码 + 四行字段表），
///    待取卡是另一套（主名 15.5 ｜ 副名 13 → 地址 12.5 → 虚线 → 图标 26 + 大码 30 → 右端勾选圈）。
///    既然规矩是「一条短信在哪个页面都长一样」，预览卡就该是**待取卡的预览**，不是另一张卡片。
///
/// 字段口径不变：取件码 / 快递公司 / 短信平台 / 地址都会出现，只是改由卡面本身表达 ——
/// 主名行 = 「快递公司 ｜ 平台」，地址行 = 地址，大码 = 取件码。
/// 运单号、尾号照旧不单独成行（绝大多数短信里是空的），数据本身仍完整入库。
struct ParsePreviewCard: View {
    let parsed: PickupParseResult

    /// 主凭证 —— 不论解析时走的是哪条公式，到界面上一律叫「取件码」
    private var code: String { parsed.value }

    /// 卡面命名 —— **与落库后的 `record.naming(...)` 完全同口径**：
    /// 快递公司先归一到标准名（「圆通快递」→「圆通速递」），没有公司就退到短信平台。
    /// 以前这里直接传原始的 `parsed.courier`，于是预览写「圆通快递」、存进列表变「圆通速递」，
    /// 同一个件两个名字（2026-11-22 并掉）。
    private var naming: PickupNaming {
        PickupNaming(courier: parsed.courier.isEmpty
                     ? nil
                     : CourierBrand.canonicalName(for: parsed.courier),
                     platform: parsed.company,
                     station: nil)
    }

    /// 配色 = **图标主题色**，即第一行第一个字段（快递公司优先）的颜色
    private var tint: Color { CourierBrand.color(for: naming.iconSource) }

    private var address: String {
        parsed.address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 行 1：主名（快递公司 > 平台）｜ 副名 —— 字号与待取卡同一串（15.5 / 13）
            HStack(spacing: 6) {
                Text(naming.primary.L)
                    .font(.system(size: 15.5, weight: .semibold))
                    .lineLimit(1)

                if let secondary = naming.secondary {
                    Text("|")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.45))

                    Text(secondary.L)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)
            }

            // 行 2：取件地址（识别不出就整行不出现，不留空占位）
            if !address.isEmpty {
                Text(address.L)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 4)
            }

            // 分界虚线：位置与留白都照待取卡（上 8 / 右 2）
            DashedDivider()
                .padding(.top, 8)
                .padding(.trailing, 2)

            // 行 3：图标（26，与码视觉居中）+ 大码 30 + 右端勾选圈占位
            HStack(alignment: .center, spacing: 8) {
                PickupIcon(naming: naming, size: 26)

                PickupCodeEmphasis.text(code, tint: tint)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Spacer(minLength: 6)

                // 右端照待取卡摆一个勾选圈：**纯静态图形**（还没入库，没有可标记的对象）。
                // 尺寸/线宽与 `CompleteButton` 的空态完全一致（27pt 圈 / 1.8 描边 / 44 热区），
                // 但画成 Circle 而不是 Button —— 不假装能点，点了也不会毫无反馈。
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.8)
                    .frame(width: 27, height: 27)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            .padding(.top, 7)
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(tint: tint)
    }
}
