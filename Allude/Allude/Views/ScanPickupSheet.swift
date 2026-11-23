import SwiftUI
import PhotosUI
import UIKit
import Vision
import AVFoundation

// MARK: ============================================================================
// 识别添加（拍照 / 相册）
//
// 两条入口，同一个出口：
//   · 拍照识别 —— 现拍一张（朋友转发的聊天截图、驿站小票、面单）
//   · 相册识别 —— 从相册里挑图（截图一般先存在相册里）
//
// 🔴 2026-11-16 主人：「扫码添加就不要了，软件本身不联网，扫码添加根本就无法使用，
//    到时候可以拍照识别添加，这样就和从相册选择图片是一样的原理了」——
//    原来的「扫一扫」走的是条码识别，二维码内容多半是需要联网兑换的链接，
//    离线状态下等于废的。现在两个入口都只做**端侧 OCR**，拿到一段文本后
//    统一交给 PickupParser —— 与快捷指令自动化、手动粘贴完全同一条链路。
// ============================================================================

enum ScanMode: String, CaseIterable, Identifiable {
    case capture = "拍照识别"
    case photo = "相册识别"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .capture: "camera.fill"
        case .photo: "photo.on.rectangle.angled"
        }
    }
}

/// 确认页上的一条**可编辑草稿**。
///
/// 识别结果一旦落成草稿，就与人手输入同等对待 —— 后续入库不再经过正则，
/// 否则用户改过的字会被重新解析覆盖（见 `PickupStore.commitEdited`）。
/// `rawText` 保留该条所在的原文片段，记录详情页仍能回看来源短信/截图。
struct ScanDraft: Identifiable, Equatable {
    let id = UUID()
    var kind: PickupKind
    var value: String
    var company: String
    var address: String
    var rawText: String
}

final class ScanPickupModel: ObservableObject {
    @Published var mode: ScanMode = .capture

    /// 识别到的原始文本（非空即进入「确认」态）
    @Published var captured: String?
    /// 识别失败的中性提示
    @Published var errorMessage: String?
    @Published var isRecognizing = false
    /// 多图批量识别：相册一次可选中多张（2026-09-23）
    @Published var pickedItems: [PhotosPickerItem] = []
    /// 本轮识别一共处理了几张图（用于文案「已识别 N 张图」；1 张时不显示）
    @Published var photoCount = 0
    @Published var addedMessage: String?
    /// 快门信号：每自增一次，取景控制器就拍一张（见 `CameraPhotoView`）
    @Published var shutterToken = UUID()
    /// 拍照/识别失败的中性提示（与 `errorMessage` 同一条展示位）
    @Published var captureFailed = false

    /// 确认页的可编辑草稿（每个字段都能当场改）
    @Published var drafts: [ScanDraft] = []
    /// 草稿来自「没识别到 → 手动核对」，不是机器识别出来的（表头文案要用）
    @Published var isManualDraft = false

    /// 预置状态（仅供命令行截图验证注入，生产路径不传）
    init(seed: String = "", mode: ScanMode = .capture) {
        self.mode = mode
        if !seed.isEmpty {
            captured = seed
            rebuildDrafts()
        }
    }

    /// 识别结果。**可能是多条** —— 一张截图里常有 2–4 条短信，
    /// 一张面单照片也可能同时拍到两个码。
    var parsedList: [PickupParseResult] {
        guard let captured, !captured.isEmpty else { return [] }
        // 走 OCR 专用入口：OCR 的换行是视觉折行，会切断定长 lookbehind 锚点；
        // 该入口同时负责「一次多条」的切段。
        return PickupParser.parseAll(captured, ocrSource: true).map(\.normalized)
    }

    /// 从解析结果重建草稿。**只在「刚识别完」时调用** —— 确认页上用户
    /// 正在改的字不能被任何一次重算冲掉，所以它不挂在 computed 属性上。
    func rebuildDrafts() {
        drafts = parsedList.map {
            ScanDraft(kind: $0.kind,
                      value: $0.value,
                      company: $0.company,
                      address: $0.address,
                      rawText: $0.rawText)
        }
    }

    /// 待入库的结果：以草稿为准，用户没动过的字段原样保留。
    var editedResults: [PickupParseResult] {
        drafts.map {
            PickupParseResult(kind: $0.kind,
                              value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines),
                              company: $0.company.trimmingCharacters(in: .whitespacesAndNewlines),
                              address: $0.address.trimmingCharacters(in: .whitespacesAndNewlines),
                              rawText: $0.rawText)
        }
    }

    /// 有没有识别到东西（判空口径从 `parsedList` 换成草稿，因为后者才是真相）
    var hasResult: Bool { !drafts.isEmpty }

    /// 识别到的那串内容本身是否像一个可直接使用的取件码
    var looksLikeBareCode: Bool {
        guard let captured else { return false }
        let t = captured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...48).contains(t.count), !t.contains("\n") else { return false }
        guard t.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        let punctuation = CharacterSet(charactersIn: "。，,、；;！!？?")
        return t.rangeOfCharacter(from: punctuation) == nil
    }

    /// 识别不到任何凭证时，给一条**手动核对**的出路。
    ///
    /// 聊天截图常只有「8-4-2019 菜鸟驿站」这种没有标签的一行 —— 正则无从下手，
    /// 而原来的确认页在 `parsedList` 为空时只给「重新识别」，用户在这个 sheet 里
    /// 没有补救路径，只能退出去换「文本录入」。这里改成：把文字里**唯一一个**
    /// 像取件码的片段预填进可编辑草稿，用户改对了再添加。
    ///
    /// 保守规则：只认「含数字、4–24 字符」的独立片段；11 位手机号、日期形态不算；
    /// 片段多于一个（分不清哪个是码）就留空让用户自己填 —— 宁可不猜，绝不静默写错码。
    func startManualDraft() {
        let text = captured ?? ""
        drafts = [ScanDraft(kind: .code,
                            value: Self.guessBareCode(in: text),
                            company: "",
                            address: "",
                            rawText: text)]
        isManualDraft = true
    }

    private static func guessBareCode(in text: String) -> String {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || "，,。.；;：:！!？?（）()「」【】".contains($0) })
            .map(String.init)
        let candidates = tokens.filter { token in
            guard (4...24).contains(token.count),
                  token.contains(where: \.isNumber) else { return false }
            // 手机号 / 纯日期 / 纯数字长串（更可能是运单号或订单号）都不预填
            if token.count == 11, token.allSatisfy(\.isNumber) { return false }
            if token.filter({ $0 == "-" || $0 == "—" }).count >= 2,
               token.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "—" }) { return true }
            return token.contains(where: { $0 == "-" || $0 == "—" })
                || (token.contains(where: \.isLetter) && token.contains(where: \.isNumber))
                || (5...8).contains(token.count) && token.allSatisfy(\.isNumber)
        }
        return candidates.count == 1 ? candidates[0] : ""
    }

    func reset() {
        captured = nil
        errorMessage = nil
        addedMessage = nil
        photoCount = 0
        drafts = []
        isManualDraft = false
        captureFailed = false
        shutterToken = UUID()
    }
}

struct ScanPickupSheet: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model: ScanPickupModel
    @Environment(\.scenePhase) private var scenePhase

    /// 相机可用性**缓存成状态**，不再每次 body 求值现算（2026-10-25 审查修）。
    /// 现算的写法不监听权限变化：首次进入弹「允许使用相机？」→ 点不允许后，
    /// 界面会停在黑屏取景 + 「把短信放进取景框」，既没有提示也没有去设置的入口；
    /// 反过来在系统设置里打开相机再回来，界面也还是「没有相机权限」，只能退出重进。
    @State private var availability = CameraAvailability.current()

    let onClose: () -> Void
    let onAdded: (IngestOutcome) -> Void

    /// 相册一次最多选几张。取件场景一趟十几件是极少数的极端情况，
    /// 9 张足够覆盖「一次帮家人取几件」；再多则识别耗时与确认页长度都失控。
    static let photoLimit = 9

    init(initialCaptured: String = "",
         initialMode: ScanMode = .capture,
         onClose: @escaping () -> Void,
         onAdded: @escaping (IngestOutcome) -> Void) {
        _model = StateObject(wrappedValue: ScanPickupModel(seed: initialCaptured,
                                                           mode: initialMode))
        self.onClose = onClose
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.addedMessage != nil {
                    successBanner
                } else if model.captured != nil {
                    reviewPane
                } else {
                    modePicker
                        .padding(.horizontal, AppTheme.hInset)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                    Group {
                        switch model.mode {
                        case .capture: capturePane
                        case .photo: photoPane
                        }
                    }
                }
            }
            .background(AppTheme.sheetSurface)   // 半屏面板 = 比页面亮一档
            .navigationTitle("识别添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.captured == nil ? "取消" : "重来") {
                        if model.captured == nil { onClose() } else { withAnimation(.snappy) { model.reset() } }
                    }
                }
            }
            .onChange(of: model.pickedItems) { _, items in
                guard !items.isEmpty else { return }
                recognize(items)
            }
            // 首次进入主动请求相机权限；请求一结束就刷新可用性，
            // 否则「拒绝」之后界面会一直停在黑屏取景框（2026-10-25 审查修）
            .task {
                // 「关于 › 使用权限」里关掉相机 → 连系统授权都不问，
                // 直接把用户送到相册（那一路还能用）。
                if !PermGate.storedIsOn(.camera), PermGate.storedIsOn(.photos) {
                    model.mode = .photo
                } else if !PermGate.storedIsOn(.photos), PermGate.storedIsOn(.camera) {
                    model.mode = .capture
                }
                await refreshAvailability()
                // 截图脚手架：`SIMCTL_CHILD_MANUAL_DRAFT=1` 直接走一次
                // 「没识别到 → 手动核对后添加」的兜底，验可编辑草稿卡能正常出来。
                if ProcessInfo.processInfo.environment["MANUAL_DRAFT"] == "1",
                   model.captured != nil, model.drafts.isEmpty {
                    model.startManualDraft()
                }
            }
            // 从系统设置授权后回到 App → 立刻刷新，不用退出重进
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshAvailability() }
            }
        }
    }

    /// 读相机权限并落到 `availability`（必要时先触发系统授权弹窗）
    @MainActor
    private func refreshAvailability() async {
        // 「关于 › 使用权限」里关掉相机 → 不申请系统授权，直接按不可用处理
        if !PermGate.storedIsOn(.camera) {
            availability = CameraAvailability.current()
            return
        }
        // 截图脚手架下不必真去要权限：那个系统弹窗会盖住整块取景区，
        // 弹窗本身又点不掉（simctl 没有点击通道），拍出来什么也看不到。
        if ProcessInfo.processInfo.environment["FAKE_CAMERA"] == "1" {
            availability = .ready
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        availability = CameraAvailability.current()
    }

    // MARK: 模式切换

    private var modePicker: some View {
        Picker("识别方式", selection: $model.mode) {
            ForEach(ScanMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: 拍照识别

    /// 生效中的相机可用性。
    ///
    /// 截图脚手架：`SIMCTL_CHILD_FAKE_CAMERA=1` 让取景页在**没有摄像头**的模拟器上
    /// 也渲染出来（黑底 + 快门条 + 提示）。模拟器压根没有相机设备，快门条那套布局
    /// 没有别的取证手段 —— 这个开关只改这一处判定，不伪造拍摄结果。
    private var effectiveAvailability: CameraAvailability {
        ProcessInfo.processInfo.environment["FAKE_CAMERA"] == "1" ? .ready : availability
    }

    @ViewBuilder
    private var capturePane: some View {
        switch effectiveAvailability {
        case .ready:
            VStack(spacing: 0) {
                ZStack {
                    CameraPhotoView(captureToken: model.shutterToken,
                                    onCaptured: handleCapturedImage,
                                    onFailed: { model.captureFailed = true })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    // 取景提示：拍的是「有字的东西」，不是二维码 ——
                    // 文案要直接讲清对什么、拍什么。
                    VStack {
                        Spacer()
                        Text("把取件短信、聊天截图或面单放进取景框")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.black.opacity(0.5), in: .capsule)
                            .padding(.bottom, 14)
                    }
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                shutterBar
            }

        case .denied:
            fallbackCard(
                symbol: "camera.metering.unknown",
                tint: AppTheme.amber,
                title: "没有相机权限",
                detail: "在「设置 → 隐私与安全性 → 相机」中允许Codelumi使用相机，然后重新进入本页。",
                primary: ("去设置", openSettings)
            )

        case .unsupported:
            fallbackCard(
                symbol: "iphone.slash",
                tint: AppTheme.sky,
                title: "当前设备没有可用相机",
                detail: "模拟器没有摄像头。可以改用「相册识别」，效果与拍照完全一样。",
                primary: ("改用相册识别", { withAnimation(.snappy) { model.mode = .photo } })
            )
        }
    }

    /// 快门条 —— 大圆钮，与系统相机同一个位置感（拇指够得到）。
    private var shutterBar: some View {
        VStack(spacing: 8) {
            Button {
                model.captureFailed = false
                model.shutterToken = UUID()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 68, height: 68)
                    Circle()
                        .fill(.white)
                        .frame(width: 56, height: 56)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isRecognizing)
            .opacity(model.isRecognizing ? 0.5 : 1)

            if model.isRecognizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("正在识别…").font(.footnote).foregroundStyle(.white)
                }
            } else if model.captureFailed {
                // 拍失败 / OCR 没读出文字是两回事，提示要分清（相册页有独立文案，
                // 这里只有这一行，所以把 `errorMessage` 也带出来）。
                Text(model.errorMessage ?? "这一张没拍成，再按一次试试")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.amber)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else {
                Text("识别在本机完成，照片不出设备")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .background(Color.black)
    }

    private func fallbackCard(symbol: String, tint: Color, title: String,
                              detail: String, primary: (String, () -> Void)) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)

            IconBadge(symbol: symbol, tint: tint, size: 56)

            Text(title.L)
                .font(.headline)

            Text(detail.L)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            Button(primary.0, action: primary.1)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(AppTheme.accent, in: .capsule)
                .foregroundStyle(.white)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 相册识别

    private var photoPane: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)

            IconBadge(symbol: "text.viewfinder", tint: AppTheme.violet, size: 56)

            Text("从图片里读文字")
                .font(.headline)

            Text("短信截图、取件小票、快递面单照片都可以，会自动识别其中的取件码与地址。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            PhotosPicker(selection: $model.pickedItems,
                         maxSelectionCount: Self.photoLimit,
                         matching: .images) {
                Label("选择图片", systemImage: "photo.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent, in: .capsule)
                    .foregroundStyle(.white)
            }

            Text("可一次选多张，最多 \(Self.photoLimit) 张")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if model.isRecognizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在识别…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let error = model.errorMessage {
                Text(error.L)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.pendingTint)
                    .padding(.horizontal, 30)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 确认态

    private var reviewPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                rawCard

                if model.hasResult {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.doneTint)
                            Text(resultSummary.L)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text("可直接修改")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        ForEach(model.drafts.indices, id: \.self) { index in
                            EditableParseCard(
                                draft: $model.drafts[index],
                                index: model.drafts.count > 1 ? index + 1 : nil,
                                // `_ =` 是必要的：`withAnimation` 会把闭包的返回值
                                // （这里是 `remove(at:)` 吐出的那条草稿）原样传出来，
                                // 不显式丢弃就会报 "result of call is unused"。
                                onDelete: model.drafts.count > 1
                                    ? { _ = withAnimation(.snappy) { model.drafts.remove(at: index) } }
                                    : nil
                            )
                        }
                    }
                } else if model.looksLikeBareCode {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "lightbulb.fill", tint: AppTheme.pendingTint, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("识别到的是一个单独的码")
                                    .font(.subheadline.weight(.semibold))
                                Text("读到的内容本身就是取件码，直接加进待取件列表即可。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()

                        primaryButton(title: "作为取件码添加", tint: AppTheme.pendingTint) {
                            finish(with: store.addManual(code: model.captured ?? ""))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "exclamationmark.triangle.fill", tint: AppTheme.amber, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("没识别到取件信息")
                                    .font(.subheadline.weight(.semibold))
                                Text("这段内容里没有取件码、运单号或尾号。可以拍得清楚些再试，或用「添加」手动粘贴短信全文。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()

                        // OCR 读到了字、但没带任何「取件码」标签时（朋友聊天截图常见），
                        // 让用户当场核对/补一个码，不必退出本页重来。
                        primaryButton(title: "手动核对后添加", tint: AppTheme.accent) {
                            withAnimation(.snappy) { model.startManualDraft() }
                        }
                    }
                }

                if model.hasResult {
                    // 走结构化入口：用户在卡上改过的字必须原样落库，
                    // 不能再拿原文跑一遍正则（那会把改动覆盖回去）
                    primaryButton(title: model.drafts.count > 1
                                  ? "全部添加 · \(model.drafts.count) 条"
                                  : "添加",
                                  tint: AppTheme.accent,
                                  enabled: model.drafts.allSatisfy {
                                      !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  }) {
                        finish(with: store.commitEdited(model.editedResults))
                    }
                }

                Button {
                    withAnimation(.snappy) { model.reset() }
                } label: {
                    Text("重新识别")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.cardSurface, in: .capsule)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
    }

    /// 确认区标题。多图时把「几张图」也讲清楚 —— 否则用户看到一长串条目，
    /// 不知道它们是从几张图里来的，也无从判断是不是漏识别了某一张。
    private var resultSummary: String {
        // 手动核对的草稿不是「识别」出来的，别让人以为机器已经确认过了
        if model.isManualDraft { return "请核对取件码" }
        let count = model.drafts.count
        if model.photoCount > 1 { return "已识别 \(count) 条 · 来自 \(model.photoCount) 张图" }
        return count > 1 ? "已识别 \(count) 条" : "已识别"
    }

    private var rawCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: model.mode == .capture ? "camera.fill" : "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(model.mode == .capture ? "拍到的文字" : "识别出的文字")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(model.captured ?? "")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func primaryButton(title: String, tint: Color,
                               enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.L)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? tint : Color(.systemGray4), in: .capsule)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var successBanner: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.doneTint)
            Text(model.addedMessage ?? "")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 动作

    /// 拍照 → 端侧 OCR → 与相册选图**完全同一条链路**。
    ///
    /// 不做「拍完先给你看一眼原图再确认」的两步：取件场景下多一步就是多一次等待，
    /// 而确认页本来就把识别出的文字原样摊开（`rawCard`），看错了当场能改。
    private func handleCapturedImage(_ image: UIImage) {
        model.isRecognizing = true
        model.errorMessage = nil

        Task { @MainActor in
            let text = await Task.detached(priority: .userInitiated) {
                PickupOCR.recognize(image)
            }.value
            model.isRecognizing = false

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                model.captureFailed = true
                model.errorMessage = "这张图里没读出文字，把字拍清楚一点再试"
                return
            }
            withAnimation(.snappy) {
                model.photoCount = 1
                model.captured = trimmed
                model.rebuildDrafts()
            }
        }
    }

    /// 多图批量识别（2026-09-23）。
    ///
    /// 逐张串行 OCR 后**拼成一段文本**，再整体走一次 `parseAll` —— 而不是
    /// 每张图各自解析、各自弹一次确认页：用户一次圈了 5 张图，应该看到
    /// 一张合并后的确认清单；逐张确认就是 5 次交互，比逐张选图还累。
    ///
    /// 串行而非并发：Vision 是 CPU 密集的同步调用，同时跑多张只会互相抢核，
    /// 总耗时基本不变，峰值内存却按张数翻倍（一张截图解码后可达数十 MB）。
    private func recognize(_ items: [PhotosPickerItem]) {
        model.isRecognizing = true
        model.errorMessage = nil

        Task { @MainActor in
            defer {
                model.isRecognizing = false
                model.pickedItems = []
            }

            var texts: [String] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }

                // OCR 是 CPU 密集的同步调用，放到后台（UIImage 本身即 Sendable）
                let text = await Task.detached(priority: .userInitiated) {
                    PickupOCR.recognize(image)
                }.value

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { texts.append(trimmed) }
            }

            guard !texts.isEmpty else {
                model.errorMessage = items.count > 1
                    ? "这 \(items.count) 张图里都没读出文字，换更清晰的试试"
                    : "这张图里没读出文字，换一张更清晰的试试"
                return
            }

            let merged = texts.joined(separator: "\n")
            withAnimation(.snappy) {
                model.photoCount = texts.count
                model.captured = merged
                model.rebuildDrafts()
            }
        }
    }

    private func finish(with outcome: IngestOutcome) {
        onAdded(outcome)

        // 文案统一取 `outcome.dialog` —— App 内所有入口（粘贴 / 拍照 / 相册）
        // 共用同一口径，不会出现"这个入口说 3 条、那个入口说 5 条"这种两套说法。
        withAnimation(.snappy) { model.addedMessage = outcome.dialog }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            onClose()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 可编辑识别结果卡

/// 与 `ParsePreviewCard` 的分工：这张**每个字段都能当场改**。
///
/// 为什么必须可编辑（2026-09-23）：OCR 认错一个字符（`8`↔`B`、`0`↔`O`、
/// `l`↔`1`）在取件现场是致命的 —— 报一个错码比没识别更糟，用户白跑一趟。
/// 而原版确认页只能看，发现错了唯一出路是整张重拍，多数人会直接放弃这条路。
///
/// 与 `AddPickupSheet` 里那张只读卡的区别：那边是「手动输入后确认」，字是
/// 用户自己打的，不需要再改；这边是「机器识别后确认」，出错概率高，必须给
/// 一条修的路。
///
/// 三个几何约定：取件码单独一行且字号最大（最常改的就是它）、其余字段
/// 统一「40pt 标签 + 淡色填充输入框」，与二级设置页的输入行同一种手感。
struct EditableParseCard: View {
    @Binding var draft: ScanDraft
    /// 一次识别多条时在卡头显示序号，单条时为 nil（不占位）
    var index: Int? = nil
    /// 只有多条时才给删除入口 —— 单条删掉等于什么都没识别到，
    /// 那种情况用户要的是「重新识别」，而不是留下一个空确认页。
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            DashedDivider()
                .padding(.vertical, 11)

            codeRow
            inputRow(label: "平台", placeholder: "快递公司", text: $draft.company)
            inputRow(label: "地址", placeholder: "未识别到", text: $draft.address)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(tint: tint)
    }

    /// 卡片配色 = 品牌色（2026-10-28 取消凭证类型后，不再按类型取色）
    private var tint: Color { CourierBrand.color(for: draft.company) }

    private var header: some View {
        HStack(spacing: 8) {
            if let index {
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(tint, in: .circle)
            }

            // 平台名一改，图标跟着换 —— 这是"我改对了"最直接的反馈
            CourierLogo(company: draft.company, size: 22)

            Spacer(minLength: 8)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var codeRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("取件码")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            TextField("取件码", text: $draft.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospaced()
                .foregroundStyle(tint)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        }
        .padding(.bottom, 10)
    }

    private func inputRow(label: String, placeholder: String,
                          text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            rowLabel(label)

            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        }
        .padding(.bottom, 6)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text.L)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(width: 40, alignment: .leading)
    }
}

// MARK: - 中文 OCR

enum PickupOCR {
    /// 对一张图片做文字识别，按视觉上的「从上到下」顺序拼成多行文本。
    ///
    /// 同步实现（调用方负责放到后台线程）：`perform` 的同步版本返回后
    /// `request.results` 即已就绪，比走 completion handler + continuation
    /// 少一层并发状态，也不会出现「perform 抛错导致 continuation 永不 resume」。
    static func recognize(_ image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // 取件码是数字串，语言纠正会把它「纠」成看似合理的词，必须关闭
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let observations = request.results else { return "" }

        return observations
            // Vision 坐标系原点在左下角，midY 越大越靠上
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
