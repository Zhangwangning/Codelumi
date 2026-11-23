import SwiftUI
import UIKit

// MARK: ============================================================================
// 取件码分享卡片（#51）
//
// 主人指定：分享出去的是**一张卡片图片**，不是链接 —— 收到的人一眼看到
// 平台、取件码、地址，不需要点开任何东西。落地方式：
//   · `PickupShareCard` 用固定浅色版式画卡（分享图固定浅色，无论收发双方
//     各自的外观设置，白底黑字在聊天流里都可读）；
//   · `ImageRenderer` 按 3x 渲染成 UIImage；
//   · 分享面板统一为 `SharePreviewSheet`（**先看图，再分享**）—— 长按菜单、
//     详情页工具栏、多选分享三个入口共用同一个面板，口径完全一致；
//     面板里的「更多分享」再交系统（UIActivityViewController）给微信 / QQ /
//     抖音 / 支付宝，分享的是图片本体，渠道不受本 App 控制。
//   · ⚠️ 面板**必须挂在页面层**，不能挂进长按浮层：菜单一收，条件渲染的浮层
//     连同其中的呈现者一起销毁，面板根本弹不出来（踩坑记录见 CardMenu.swift）。
//
// 多码分享（2026-09-23 主人定，当晚修订）：
//   · 列表页进入多选模式，可一次分享多条 —— 一张图上多个取件码；
//   · **版式取舍**：多码卡不再逐条铺全部信息，每行 = 图标 + 快递公司 +
//     取件码 + **该条自己的地址** —— 分享的多条不一定在同一个地方，
//     地址必须跟着各自的记录走，不能用第一条的糊弄全部（主人指认）；
//   · **上限 12 行**：选了超过 12 条时，相同快递公司（含驿站）聚合成一行，
//     取件码只显示该组第一条，公司名后标「×N」（地址取组首的）；
//     聚合后仍超过 12 组的极端情况，多余的在卡尾用一行「另有 N 件未列出」交代；
//   · 单条版式与多码版式是**同一 struct 的两个分支** —— 渲染管线、
//     固定浅色、署名行完全共用，只有中段不同。
//
// 渲染细节：
//   · 卡内**不用语义色**（.primary / .secondary）—— ImageRenderer 的环境
//     不可控，语义色会随渲染环境漂移；全部显式定色；
//   · CourierLogo 的官方图标来自 Assets，ImageRenderer 可正常画出。
// ============================================================================

/// 多码分享卡上的一行：组首记录 + 该快递公司的件数（单条组 count = 1）。
struct PickupShareLine: Identifiable {
    let record: PickupRecord
    let count: Int
    var id: UUID { record.id }
}

/// 分享卡版式（固定浅色，脱离环境）。
struct PickupShareCard: View {
    let records: [PickupRecord]

    /// 单条分享（详情页 / 长按菜单的原入口）
    init(record: PickupRecord) { self.records = [record] }
    /// 多条分享（多选模式）
    init(records: [PickupRecord]) { self.records = records }

    /// 多码卡的行数上限：超过即触发同司聚合（2026-09-23 主人定：6 → 12）
    static let maxLines = 12

    /// 卡片主色 = **图标主题色**（2026-10-25 主人：卡片色调要和图标主色一致）。
    /// 与图标同口径取源：快递公司 > 驿站 > 短信平台。
    /// 以前用 `brandColor`（= 短信平台色），拼多多发的圆通件会出现"紫图标 + 粉卡面"。
    private var tint: Color {
        guard let first = records.first else { return Color(hex: 0x0B63F3) }
        return CourierBrand.color(for: first.namingResolved.iconSource)
    }
    private var isSingle: Bool { records.count <= 1 }

    /// 措辞跟随记录自身状态（2026-11-16）。
    ///
    /// 🔴 起因：已取页现在也能多选分享，原来卡头硬写「待取 N 件」——
    ///    从已取页分享出去的一律被标成「待取」，图直接是错的。
    private var pickedCount: Int { records.filter(\.isPickedUp).count }

    private var countTitle: String {
        if pickedCount == records.count { return "已取 \(records.count) 件" }
        if pickedCount == 0 { return "待取 \(records.count) 件" }
        // 两页各自只含一种状态，混合只可能来自以后的新入口，给个中性说法
        return "取件 \(records.count) 件"
    }

    private var footerTitle: String {
        !records.isEmpty && pickedCount == records.count ? "Codelumi · 已取件" : "Codelumi · 待取件"
    }

    var body: some View {
        if isSingle {
            singleCard
        } else {
            multiCard
        }
    }

    // MARK: 单条版式（390×500，保持不变）

    private var singleRecord: PickupRecord { records[0] }

    @ViewBuilder
    private var singleCard: some View {
        // 🔴 `if let` 而不是直接 `records[0]`（2026-10-25 审查修）：
        // `isSingle` 的判定是 `records.count <= 1`，空数组也会落进这个分支，
        // 于是 `records[0]` 会越界崩溃。当前调用侧（`SharePresenter.present`）有
        // `guard !records.isEmpty` 挡着，属于"上游保护、下游裸奔"——
        // 一旦以后从别处直接构造分享卡（预览、导出、测试）就会崩。
        if let record = records.first {
        // 图标/主名口径统一走 `PickupNaming`（2026-10-28 主人：整个Codelumi一套逻辑）。
        // 之前这里是第三套写法（`courier > 驿站 > 平台`），分享出去的名字
        // 与列表卡自相矛盾（拼多多发的圆通件在列表是「圆通快递｜拼多多」）。
        let naming = record.namingResolved
        let titlePrimary = naming.primary
        let titleSecondary: String? = naming.secondaryLabel

        VStack(alignment: .leading, spacing: 0) {
            // 顶部：品牌身份行
            HStack(spacing: 12) {
                // 图标 = 主名第一段，画法与列表卡同源（`PickupIcon`）
                PickupIcon(naming: naming, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(titlePrimary.L)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x1C1C1E))
                            .lineLimit(1)

                        if let titleSecondary {
                            Text("|")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(hex: 0x8E8E93))
                            Text(titleSecondary.L)
                                .font(.system(size: 15))
                                .foregroundStyle(Color(hex: 0x6E6E73))
                                .lineLimit(1)
                        }

                        // 快递柜标签（2026-10-28，与列表卡 / 详情页同一位置同一口径）
                        if let locker = record.locker, !locker.isEmpty {
                            Text(locker.L)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tint)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.14), in: .capsule)
                        }
                    }

                }

                Spacer(minLength: 0)
            }
            .padding(.top, 30)

            // 中部：取件码是唯一主角
            VStack(alignment: .leading, spacing: 10) {
                record.emphasizedCodeText(tint: tint)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospaced()
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)

                if !record.address.isEmpty {
                    Text(record.address.L)
                        .font(.system(size: 15))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            shareFooter
        }
        .padding(.horizontal, 28)
        .frame(width: 390, height: 500, alignment: .top)
        .background { shareBackground }
        }
    }

    // MARK: 多码版式（宽 390，高度随行数）

    /// 2–12 条：逐条一行；>12 条：同快递公司聚合，组首码 + ×N。
    private var lines: [PickupShareLine] {
        if records.count <= Self.maxLines {
            return records.map { PickupShareLine(record: $0, count: 1) }
        }
        // 按**主名**聚合（与卡片首行第一段同源），保持首次出现顺序，组首 = 第一条的取件码。
        // 🔴 旧实现按 `record.company`（短信平台）聚合，于是拼多多发的圆通件会被
        // 归到「拼多多」组里，与卡面写的「圆通快递」对不上 —— 统一走 PickupNaming。
        func groupKey(_ record: PickupRecord) -> String {
            record.namingResolved.primary
        }
        var order: [String] = []
        var firsts: [String: PickupRecord] = [:]
        var counts: [String: Int] = [:]
        for record in records {
            let key = groupKey(record)
            if firsts[key] == nil {
                order.append(key)
                firsts[key] = record
            }
            counts[key, default: 0] += 1
        }
        return order.prefix(Self.maxLines).compactMap { key in
            firsts[key].map { PickupShareLine(record: $0, count: counts[key] ?? 1) }
        }
    }

    /// 聚合截断后没能上卡的件数（仅 >12 条且分组数 >12 时 >0）
    private var omittedCount: Int {
        guard records.count > Self.maxLines else { return 0 }
        let shown = lines.reduce(0) { $0 + $1.count }
        return records.count - shown
    }

    @ViewBuilder
    private var multiCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            multiHead
            multiLines
            shareFooter
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .frame(width: 390, height: multiCardHeight, alignment: .top)
        .background { shareBackground }
    }

    /// 多码卡总高：头部 28+44 + 间距 12 + 行区（码行 50 / 带地址行 69）
    /// + 省略行 26 + 页脚 56。地址行按**实际有地址的条数**累加。
    private var multiCardHeight: CGFloat {
        let lineList = lines
        let addressRows = lineList.filter { !$0.record.address.isEmpty }.count
        let rowsHeight = lineList.count * 50 + addressRows * 19
        let omittedRow: Int = omittedCount > 0 ? 26 : 0
        return CGFloat(28 + 44 + 12 + rowsHeight + omittedRow + 12 + 18 + 26)
    }

    /// 卡头：件数。地址不在这里 —— 多条不一定同地，地址跟各自的行走（主人指认）。
    /// 图标用**软件图标**（`AppMarkIcon` → 当前选中的 `AppIconNN`），不是第一家快递 —— 多条来自不同快递时，
    /// 抬头摆任何一家的图标都误导（2026-09-23 主人指认）。
    private var multiHead: some View {
        HStack(spacing: 12) {
            AppMarkIcon(size: 40)

            Text(countTitle)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Spacer(minLength: 0)
        }
        .padding(.top, 28)
    }

    /// 行区：每行 = 图标 + 公司 +（×N）+ 码；聚合截断后补省略行
    private var multiLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Rectangle()
                        .fill(Color(hex: 0x1C1C1E).opacity(0.08))
                        .frame(height: 0.5)
                }
                lineRow(line)
            }

            if omittedCount > 0 {
                Text("另有 \(omittedCount) 件未列出")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x8E8E93))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 14)
    }

    /// 多码卡上的一行：码行 + 该条**自己的地址**（空则不画）。
    /// 取件码用**该行自己**的品牌色 —— 行与行颜色不同，扫一眼就能对上「哪行是哪家」。
    /// 聚合行（×N）地址取组首的：同公司大概率同驿站，属于聚合本来就接受的取舍。
    private func lineRow(_ line: PickupShareLine) -> some View {
        // 行主名 / 图标 / 取色全部走 PickupNaming（与列表卡同一真源）：
        // 以前这行写的是 `record.company` + 平台图标，圆通件会被画成「拼多多」。
        let naming = line.record.namingResolved
        let tint = CourierBrand.color(for: naming.iconSource)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                // 图标 = 主名第一段，与列表卡 / 详情页同一实现（`PickupIcon`）
                PickupIcon(naming: naming, size: 22)

                Text(naming.primary.L)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color(hex: 0x1C1C1E))

                // 快递柜标签（2026-10-28 与卡片同款）
                if let locker = line.record.locker, !locker.isEmpty {
                    Text(locker.L)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(tint.opacity(0.14), in: .capsule)
                }

                if line.count > 1 {
                    Text("×\(line.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(tint, in: .capsule)
                }

                Spacer(minLength: 8)

                line.record.emphasizedCodeText(tint: tint)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            let address = line.record.address.trimmingCharacters(in: .whitespaces)
            if !address.isEmpty {
                Text(address.L)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(hex: 0x8E8E93))
                    .padding(.leading, 32)   // 与公司名对齐（图标 22 + 间距 10）
            }
        }
        .padding(.vertical, 10.5)
    }

    // MARK: 共用部件

    /// 底部：来源署名 + 时间（单条显示记录时间，多条显示渲染时刻）
    private var shareFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(footerTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x8E8E93))

            Spacer(minLength: 0)

            Text((records.first?.receivedAt ?? Date())
                .formatted(.dateTime.month().day().hour().minute()))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0xAEAEB2))
        }
        .padding(.bottom, 26)
    }

    /// 白底 + 顶部品牌色氛围渐变（与 App / 小组件同一口径）
    private var shareBackground: some View {
        ZStack(alignment: .top) {
            Color.white
            LinearGradient(colors: [tint.opacity(0.12), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
        }
    }
}

// MARK: - 分享预览面板（单条 / 多条共用）

/// 分享图渲染：**弹出面板那一刻才渲染**（选中集随时在变，预渲染没有意义）。
@MainActor
private final class SharePreviewModel: ObservableObject {
    let image: UIImage?
    /// 非 nil 时在预览页之上再弹系统分享面板（App 列表由系统给出）
    @Published var showActivity = false
    /// 保存 / 拷贝完成后的短暂勾选反馈
    @Published var saved = false
    @Published var copied = false
    private var resetTask: Task<Void, Never>?

    init(records: [PickupRecord]) {
        let renderer = ImageRenderer(content: PickupShareCard(records: records))
        renderer.scale = 3
        self.image = renderer.uiImage
    }

    /// 勾选态 1.4s 后回弹
    func resetFlagsLater() {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.saved = false
            self?.copied = false
        }
    }
}

/// 分享预览面板（2026-09-24 主人定）：**先看图，再分享** ——
/// 上半是渲染好的分享卡大图预览，底部一行快捷操作：
/// 保存图片 / 拷贝图片 / 更多分享。
/// 微信、QQ 等第三方 App 的图标行在「更多分享」的系统面板里 ——
/// iOS 不允许自绘直跳其它 App 带图分享，应用列表只能由系统给出。
///
/// **单条与多条共用**：单条传 `[record]`（走单条版式），多条传选中集（走多码版式），
/// 两个入口的分享体验因此完全一致。
///
/// ⚠️ 它必须挂在**页面**上，不能挂进长按浮层：面板的呈现者要比菜单活得久 ——
/// 长按菜单收起时会连同浮层一起被摘掉，挂在其内的呈现者（曾经的 `ShareLink`）
/// 会因锚点消失而根本弹不出来（踩坑记录见 `CardMenu.swift`）。
// MARK: - 分享面板的全局呈现器

/// 分享预览面板的呈现状态（2026-10-25 结构性改造）。
///
/// 🔴 为什么不再用页面级 `.sheet` / `.fullScreenCover`：
/// Duo 外屏右侧有 84pt 竖排标签栏、底部有 34pt Home 指示条。页面级 cover 会
/// **重新引入**这两块安全区 —— 实测内容容器只剩 ~300pt（真实可用 435pt），
/// 于是按钮永远贴不到右缘、底部多出一圈灰条，且 `ignoresSafeArea` 加在外层
/// 也穿不透 `NavigationStack`。
///
/// 把面板提到 `RootView` 顶层 ZStack 后（不是 cover，不重开容器），
/// `.ignoresSafeArea()` 才真正生效，宽度与四周留白完全可控。
final class SharePresenter: ObservableObject {
    static let shared = SharePresenter()

    /// 非 nil 即呈现；空数组会被忽略（没有可分享的记录）
    @Published var records: [PickupRecord]?

    /// 面板关闭后的收尾动作（可选）。
    ///
    /// 目前只有一处用它：已取页的「选择 → 分享」—— 分享完还停在勾选态没有意义
    /// （2026-11-16 主人：「分享面片中点击完成后，选择的状态就可以取消掉了」）。
    /// 🔴 必须在这里清理干净：`SharePresenter` 是单例，残留的回调会在下一次
    /// 面板关闭时误触发（比如从详情页分享一条，却把已取页的选择态也收掉）。
    private var onFinish: (() -> Void)?

    func present(_ records: [PickupRecord], onFinish: (() -> Void)? = nil) {
        guard !records.isEmpty else { return }
        self.onFinish = onFinish
        self.records = records
    }

    /// 关闭面板。点「完成」与点遮罩走同一条路，收尾动作都执行。
    func dismiss() {
        let finish = onFinish
        onFinish = nil
        records = nil
        finish?()
    }
}

struct SharePreviewSheet: View {
    @StateObject private var model: SharePreviewModel
    @Environment(\.dismiss) private var dismiss
    /// 深色模式下要把面板底色提亮一档，否则和遮罩糊成一片（见下方 `panelBackground`）
    @Environment(\.colorScheme) private var colorScheme
    /// `.regular` = iPhone Duo 内屏（宽屏），走 Duo 定制布局；其余走常规居中布局
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(records: [PickupRecord]) {
        _model = StateObject(wrappedValue: SharePreviewModel(records: records))
    }

    var body: some View {
        // 矮屏（Duo 折叠态 678pt）：直板机 ≥ 850pt，永远走不到这个分支
        // 🔴 iPad 不算紧凑屏（2026-11-12 主人：iPad 不要和 Duo 混）：只对 iPhone 生效
        let compact = UIDevice.current.userInterfaceIdiom == .phone && Self.windowSize.height < 720

        return ZStack {
            // 遮罩：点击关闭（RootView 级 overlay，没有下滑手势，补一个退出路径）
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { SharePresenter.shared.dismiss() }

            // 🔴 按尺寸类分流（2026-10-27 重构）。
            // 此前这里**只有一套为 Duo 定制的布局**：D 型屏的 UnevenRoundedRectangle 圆角、
            // 操作按钮竖排在右侧、卡片左距用一套「反推状态栏中心线」的公式。
            // 这些在普通 iPhone 上全不成立 —— 表现为面板左方右圆、按钮悬在屏幕右缘外侧、
            // 卡片明显偏左（主人截图指的就是这个）。现在常规屏走标准居中布局，
            // Duo（regular）保留原定制，两边互不污染。
            if horizontalSizeClass == .regular {
                duoLayout
            } else {
                // 🔴 尺寸**不能**用 GeometryReader 读：它在被 ignore 安全区的层级里
                //    仍然报"安全区内"的尺寸，Duo 外屏会少掉上下两条边，面板变得不满屏。
                phoneLayout(in: Self.windowSize)
            }
        }
        // 🔴 Duo 外屏的状态栏时间画在面板内部右上角，正压在「完成」胶囊上。
        //    分享面板是模态的，紧凑态下直接隐藏状态栏（2026-11-01 主人截图）。
        .statusBarHidden(compact)
        .sheet(isPresented: $model.showActivity) {
            if let image = model.image {
                ActivityShareSheet(activityItems: [image])
            }
        }
    }

    // MARK: - 常规 iPhone

    /// 标准「预览 + 底部操作条」布局：卡片水平居中、操作按钮在底部横排。
    /// 面板四角同半径（26pt）、四周留 8pt 浮在遮罩上，与系统 sheet 观感一致。
    /// 摄像头属于**保留区域**（reserved region），由系统告知，不该写死像素。
    /// iOS 27.1 起可查；查不到（老系统/没有遮挡）时退回安全区，调用方取两者较大值。
    private static var occlusionInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? scenes.first?.windows.first else { return .zero }
        guard #available(iOS 27.1, *) else { return .zero }

        let bounds = window.bounds
        var insets = UIEdgeInsets.zero
        let tol: CGFloat = 1
        for region in window.reservedRegions(kind: .occlusion) where region.isActive {
            let f = region.frame
            if f.maxX >= bounds.maxX - tol { insets.right = max(insets.right, bounds.maxX - f.minX) }
            if f.minX <= bounds.minX + tol { insets.left = max(insets.left, f.maxX - bounds.minX) }
            if f.maxY >= bounds.maxY - tol { insets.bottom = max(insets.bottom, bounds.maxY - f.minY) }
            if f.minY <= bounds.minY + tol { insets.top = max(insets.top, f.maxY - bounds.minY) }
        }
        return insets
    }

    /// 安全区里除遮挡之外的部分（Home 条等）；与 `occlusionInsets` 分边取大
    private static var effectiveInsets: UIEdgeInsets {
        let occ = occlusionInsets
        let safe = windowSafeInsets
        return UIEdgeInsets(top: max(occ.top, safe.top),
                            left: max(occ.left, safe.left),
                            bottom: max(occ.bottom, safe.bottom),
                            right: max(occ.right, safe.right))
    }

    /// 当前窗口尺寸（面板挂在 RootView 顶层 overlay，窗口即全屏）
    private static var windowSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        if let size = window?.bounds.size { return size }
        // 兜底：窗口还没连上时用场景里的屏幕（不要用 UIScreen.main，iOS 26 已弃用）
        return scenes.first?.screen.bounds.size ?? CGSize(width: 402, height: 874)
    }

    private func phoneLayout(in size: CGSize) -> some View {
        // 🔴 面板圆角 = **系统真实屏幕圆角 − 内缩量**，这样两者的弧线才同心平行
        // （2026-10-27 主人两次指出「四个圆角跟手机屏幕圆角不一致」）。
        // 之前先写 26、再凭经验写 46，都是硬编码猜测 —— 机型一对就露馅。
        // 现在直接读 UIScreen 的 displayCornerRadius；读不到才回落到 55。
        let inset: CGFloat = 8
        let corner = max(0, Self.displayCornerRadius - inset)
        // 🔴 矮屏（Duo 折叠态 678pt）走紧凑版式：直板机 ≥ 850pt，永远进不来。
        let compact = UIDevice.current.userInterfaceIdiom == .phone && size.height < 720

        return VStack(spacing: 0) {
            phoneHeader(compact: compact, corner: corner)
            phoneCard(compact: compact)
            phoneActions(compact: compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark
                    ? AppTheme.cardSurface
                    : AppTheme.pageBackground)
        // 🔴 Duo 外屏是**D 型屏**（2026-10-25 主人指出，2026-11-01 再次强调）：
        //    铰链侧（左）是小圆角、机身外缘（右）是大圆角，四角同半径必然错位。
        //    直板机仍用统一圆角。
        // 🔴 官方推荐是 `ConcentricRectangle`，但它靠**容器**的 cornerConfiguration 推导半径；
        //    本面板挂在 RootView 顶层 overlay（没有圆角配置），实测会裁成直角。
        //    所以在自绘 overlay 里只能按屏幕半径显式算：
        //    机身外缘（右）= 屏幕圆角 − 内缩；铰链侧（左）是机身直边，用小圆角。
        .clipShape(compact
                   ? AnyShape(UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: corner,
                        topTrailingRadius: corner,
                        style: .continuous))
                   : AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous)))
        // 🔴 面板挂在 RootView 顶层并 `.ignoresSafeArea()`（为了盖住标签栏），
        //    所以这里必须**自己**把安全区补回来。Duo 外屏实测：
        //    `window=466x678 inset t=0 l=0 r=84 b=34` —— 右侧 84pt 是摄像头 / dock，
        //    底部 34pt 是 Home 条。不补，卡片和「完成」就被压在摄像头下面
        //    （2026-11-01 主人截图）。直板机不走这个分支。
        .padding(.trailing, compact ? Self.effectiveInsets.right : 0)
        .padding(.leading, compact ? Self.effectiveInsets.left : 0)
        // 🔴 底部**不再**额外让出 34pt（2026-11-01 主人：底部间距太大，
        //    要和顶部一致）。顶部也只有 inset 8，所以底部同样只留 8；
        //    Home 指示条由面板内按钮条的 padding 让开。
        .padding(inset)
    }

    private func phoneHeader(compact: Bool, corner: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text("分享取件码")
                .font(.system(size: 17, weight: .semibold))

            Spacer(minLength: 8)

            // 与 Duo 分支同一个「完成」胶囊：Text + 手势（裸 Button 在 iOS 26 会被
            // 套一层玻璃底、字看不见，`.buttonStyle(.plain)` 也去不掉）。
            // 常规屏不需要那套「对齐挖孔 / 右距 61」的补偿，标准 20pt 边距即可。
            Text("完成")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .appGlass(.capsule, interactive: true)
                .contentShape(.capsule)
                .onTapGesture { SharePresenter.shared.dismiss() }
                .accessibilityAddTraits(.isButton)
        }
        // 🔴 面板挂着 `.ignoresSafeArea()`（RootView 那个 overlay 加的），所以这里
        // **拿不到安全区自动避让** —— 不手动补，标题会压在状态栏时间上、胶囊会被灵动岛吞掉。
        // 用 UIKit 直接取窗口 inset（比 GeometryReader 在被忽略安全区的层级里读可靠）。
        //
        // 🔴 紧凑屏（Duo 折叠态）额外把左右让到圆角之内：面板圆角 = 屏幕圆角 − 8，
        //    466pt 宽的屏上那个弧很大，20pt 边距会把「完成」胶囊压进弧里被切掉
        //    （2026-11-01 主人截图）。
        .padding(.horizontal, 20)
        // 紧凑屏顶部要同时躲开**系统状态栏**（Duo 上时间压在面板右上角）与**面板大圆角**
        .padding(.top, (compact ? max(Self.windowSafeInsets.top, 16) : Self.windowSafeInsets.top) + (compact ? 10 : 0))
        .padding(.bottom, 4)
    }

    /// 预览卡片：按「可用宽 / 可用高」双约束等比铺满，再水平居中。
    private func phoneCard(compact: Bool) -> some View {
        GeometryReader { proxy in
            // 紧凑态底部不再有一条横栏，左右留白可以收窄，卡片随之变宽（方案 B）
            let hPad: CGFloat = compact ? 24 : 28
            let availW = max(0, proxy.size.width - hPad * 2)
            // 紧凑屏留一点上下呼吸；卡片不再顶满整个剩余高度
            let availH = max(0, proxy.size.height - (compact ? 14 : 8))
            let ratio = imageRatio
            let fitW = ratio > 0 ? min(availW, availH * ratio) : availW
            let cardW = fitW
            let cardH = ratio > 0 ? cardW / ratio : availH

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
                }
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // 🔴 Duo 外屏的状态栏时间画在面板**内部**（顶部约 72pt 处），
        //    卡片不往下让就会被时钟压住（2026-11-01 主人截图）。
        .padding(.top, compact ? 12 : 0)
    }

    /// 底部操作条：复用 `QuickShareAction`（竖排图标 + 文字、横向均分），
    /// 这也是它原本的形态（Duo 那次改版把取件码分享挪到右侧竖排，车票分享还在用它）。
    private func phoneActions(compact: Bool) -> some View {
        Group {
            if compact {
                // 🔴 紧凑态（Duo 外屏）：三个**独立胶囊**，不再占满整条底栏。
                //    省下来的高度全给卡片（2026-11-01 主人选方案 B）。
                HStack(spacing: 26) {
                    ForEach(Array(compactActionItems.enumerated()), id: \.offset) { _, item in
                        // 三个**圆形悬浮按钮**（2026-11-01 主人）：只有图标，没有文字，
                        // 悬浮在面板上，比整条横栏轻得多。
                        Button { item.action() } label: {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(item.highlight ? Color.white : Color.primary)
                                .frame(width: 48, height: 48)
                                .background {
                                    Circle()
                                        .fill(item.highlight
                                              ? AnyShapeStyle(AppTheme.accent)
                                              : AnyShapeStyle(.regularMaterial))
                                }
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                // 🔴 2026-11-08：直板机底部原先留 72pt（那是为 Duo 外屏的 Home 条留的），
                //    直板机看起来「按钮悬在半空」。直板机按系统安全区走，只留 24。
                .padding(.bottom, 24)
            } else {
                HStack(spacing: 0) {
                    if let image = model.image {
                        QuickShareAction(icon: model.saved ? "checkmark" : "square.and.arrow.down",
                                         title: model.saved ? "已保存" : "保存图片",
                                         highlight: model.saved) {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            model.saved = true
                            model.resetFlagsLater()
                        }

                        QuickShareAction(icon: model.copied ? "checkmark" : "doc.on.doc",
                                         title: model.copied ? "已拷贝" : "拷贝图片",
                                         highlight: model.copied) {
                            UIPasteboard.general.image = image
                            model.copied = true
                            model.resetFlagsLater()
                        }
                    }

                    QuickShareAction(icon: "square.and.arrow.up",
                                     title: "更多分享",
                                     highlight: false) {
                        model.showActivity = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                // 原来只留 safeBottom+8（≈42），按钮文字离 Home 指示条太近，
                // 整组像贴在面板底边（2026-10-27 主人：「底部的三个按钮太靠下了」）。
                // 现在给到 safeBottom+20（≈54），留出呼吸。
                .padding(.bottom, max(28, Self.windowSafeInsets.bottom + 20))
            }
        }
    }

    /// 紧凑态的胶囊按钮内容（图标 + 短标题 + 动作）
    private struct CompactAction {
        let icon: String
        let title: String
        let highlight: Bool
        let action: () -> Void
    }

    private var compactActionItems: [CompactAction] {
        var items: [CompactAction] = []
        if let image = model.image {
            items.append(CompactAction(icon: model.saved ? "checkmark" : "square.and.arrow.down",
                                       title: model.saved ? "已保存" : "保存",
                                       highlight: model.saved) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                model.saved = true
                model.resetFlagsLater()
            })
            items.append(CompactAction(icon: model.copied ? "checkmark" : "doc.on.doc",
                                       title: model.copied ? "已拷贝" : "拷贝",
                                       highlight: model.copied) {
                UIPasteboard.general.image = image
                model.copied = true
                model.resetFlagsLater()
            })
        }
        items.append(CompactAction(icon: "square.and.arrow.up",
                                   title: "分享",
                                   highlight: false) {
            model.showActivity = true
        })
        return items
    }

    // MARK: - iPhone Duo（宽屏，保留原定制，2026-10-25 版）

    private var duoLayout: some View {
        VStack(spacing: 0) {
            // ── 顶栏（自绘）：标题左、完成右 ──
            HStack(spacing: 12) {
                Text("分享取件码")
                    .font(.system(size: 17, weight: .semibold))

                Spacer(minLength: 8)

                // 用 Text + 手势，而不是 Button（2026-10-25）：
                // 裸 Button 在 iOS 26 会被套一层玻璃底，在浅色面板上表现为
                // 一块淡蓝模糊、看不见字；`.buttonStyle(.plain)` 也去不掉。
                //
                // 🔴 样式与位置都对齐首页顶栏那个胶囊组（2026-10-25 主人：
                // 「完成按钮使用和首页选择按钮一样的液态玻璃组件，同样的位置」）：
                // 首页 + / 选择 是 iOS 26 自动合并的液态玻璃胶囊，右缘距屏幕右 83pt。
                Text("完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.0, green: 0.42, blue: 0.9))
                    .padding(.horizontal, 16)
                    // 🔴 高度 34pt = 右上角**前置摄像头挖孔直径**（2026-10-25 主人：
                    // 「完成按钮的高度和摄像头区域的高度一致」）。实测设备图：屏幕 466pt 宽
                    // 对应 915px，挖孔 66.8px ⇒ 34.0pt。原来靠 padding(.vertical, 7) 得到
                    // 27pt，比挖孔矮 7pt，视觉上不齐。
                    .frame(height: 34)
                    // 液态玻璃（替代原「白色实底 + 阴影」）：与工具栏胶囊同一材质，
                    // `.interactive()` 提供按下时的形变反馈
                    .appGlass(.capsule, interactive: true)
                    .contentShape(.capsule)
                    .onTapGesture { SharePresenter.shared.dismiss() }
                    .accessibilityAddTraits(.isButton)
                    // 🔴 右距 61 ⇒ 胶囊右缘距屏幕右 61+14+6 = 81pt，与首页顶栏胶囊组的
                    // 83pt 基本重合；同时让开右上角**前置摄像头挖孔**（占距屏右 35…64pt）。
                    // 模拟器不画开孔，所以截图看不出冲突，只有真机/设备图才暴露。
                    .padding(.trailing, 61)
            }
            // 🔴 距顶/左右必须 > 圆角 26，否则「完成」正好落在弧线上被切掉
            .padding(.horizontal, 14)
            // 圆角 46 时，y≈30 处的安全水平界限约 3pt，x=14 起是安全的
            .padding(.top, 30)
            .padding(.bottom, 8)

            // ── 内容：预览卡片 + 右侧竖排操作条 ──
            // 🔴 必须用 GeometryReader 显式算尺寸（2026-10-25 主人第二次要求「卡片大一些」）：
            // 交给 `HStack { Image.scaledToFit(); Spacer(); actions }` 自动布局时，
            // Image 与 Spacer 同为 flexible，宽度被 Spacer 抢走 → 卡片只长到 ideal
            // 尺寸（390×500）的 87%（实测 340×436pt），且底部悬空 84pt。
            // 这里按「可用宽 / 可用高」双约束取满，卡片才能真正变到 392×502。
            GeometryReader { proxy in
                let hPad: CGFloat = 6
                let gap: CGFloat = 8
                let actionsWidth: CGFloat = 44
                // 主人 2026-10-25：卡片缩小 10%（385×494 → 347×445），整体不再贴底
                let cardScale: CGFloat = 0.9
                let ratio = imageRatio
                let availW = max(0, proxy.size.width - hPad * 2 - gap - actionsWidth)
                let availH = max(0, proxy.size.height)
                // 先按宽/高双约束算出「能占满的尺寸」，再整体缩 10%：
                // 外屏宽度是瓶颈、内屏高度是瓶颈，两种情形都等比缩小，不会变形。
                let fitW = min(availW, availH * ratio)
                let cardW = fitW * cardScale
                let cardH = ratio > 0 ? cardW / ratio : availH

                HStack(alignment: .bottom, spacing: gap) {
                    if let image = model.image {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: cardW, height: cardH)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
                    }

                    Spacer(minLength: 0)

                    // 三个按钮的下沿与卡片下沿齐平（主人 2026-10-25 要求）
                    verticalActions
                }
                // 🔴 水平方向不再整体居中（主人 2026-10-25：「三个按钮向右移，保持和顶部的
                // 居中对齐」）：顶部那条竖列是右侧 84pt 系统标签栏里的状态栏（时间 / Wi-Fi）。
                // ⚠️ 不能按「84pt 标签栏的几何中心（距屏右 42pt）」算 —— 系统实际把状态栏
                // 画得更靠内。实测截图（1398px 宽 = 466pt）：
                //   · 时间「12:17」x 1197...1309，中心 1252px；
                //   · Wi-Fi 图标    x 1193...1315，中心 1253px；
                //   → 状态栏中心距屏幕右缘 48.3pt，按钮中心必须落在这条线上。
                //     按钮半径 22pt + 中心距屏右 48.3pt ⇒ 右边缘距屏右 26.3pt；
                //     扣掉面板 padding(6) ⇒ `.padding(.trailing, 20)`。
                //   · 卡片左距 = 原来居中时的左距（公式还原，位置分毫不动）。
                .padding(.leading, max(6, (proxy.size.width - cardW - gap - actionsWidth) / 2))
                .padding(.trailing, 20)
                // 垂直方向仍然居中（主人 2026-10-25：「整体往上移动，太靠低了」）
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 🔴 深色模式必须换一档底色（2026-10-25 审查修）：
        // `systemGroupedBackground` 在深色下是**纯黑 #000000**，而面板后面正是
        // `Color.black.opacity(0.30)` 的遮罩 —— 两者叠在一起，面板圆角、边界、
        // 浮动层次全部消失，整屏看起来就是一块黑。改用 `secondarySystemGroupedBackground`
        // （深色下 #1C1C1E）后边界清晰；浅色下它偏白，会丢掉「浅灰面板 + 白卡」的层次，
        // 所以按 colorScheme 分别取值，浅色仍走 systemGroupedBackground。
        .background(colorScheme == .dark
                    ? AppTheme.cardSurface
                    : AppTheme.pageBackground)
        // 🔴 Duo 外屏是 **D 型屏**（2026-10-25 主人指出）：
        // 左边（铰链侧）两角几乎是方的，右边（机身外缘）两角才是大圆角。
        // 四角用同一个半径必然错位 —— 这里用 UnevenRoundedRectangle 分边设置。
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,      // 左上：铰链侧，小圆角
                bottomLeadingRadius: 16,   // 左下：铰链侧，小圆角
                bottomTrailingRadius: 55,  // 右下：机身外缘，大圆角（≈屏幕圆角）
                topTrailingRadius: 55,     // 右上：同上
                style: .continuous
            )
        )
        .padding(6)
        // Duo 面板是全屏浮动卡片，四周由 padding(6) 控制
        .ignoresSafeArea()
    }

    /// 屏幕物理圆角半径（pt）——**逐机型实时读取**，覆盖 iPhone 11 ~ 18 Pro Max 全部直板机。
    ///
    /// 为什么不能写死：各代圆角差得很远（X/XS 一带 ≈39、12~14 ≈47、14 Pro 起 ≈55，
    /// 到 iOS 26 这代实测 iPhone 16 Pro 已经是 **72**）。任何固定数字只对一台机器成立，
    /// 换机型立刻「四角和机身不平行」——这个坑已经踩过两次（先 26、再 46）。
    ///
    /// 取值顺序：
    ///  ① `UIScreen.displayCornerRadius`：系统真实值（私有键，**只读**），全系直板机都有效；
    ///  ② 取不到时按屏幕短边等比估算（圆角约占屏宽 15%），并夹在 [36, 80] 之间，
    ///     保证任何机型都不会算出离谱的角，最差也只是差几 pt，不会像写死后那样差 26pt。
    static var displayCornerRadius: CGFloat {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen

        if let radius = screen?.value(forKey: "_displayCornerRadius") as? CGFloat, radius > 0 {
            return radius
        }

        // 兜底：按短边比例估算。系数 0.155 由 iPhone 16 Pro（402pt 屏 / 72pt 角）反推，
        // 夹紧上下限避免极端值。
        // 不再用 UIScreen.main（iOS 26 已废弃）；拿不到屏幕就退回一个中性值
        guard let bounds = screen?.bounds else { return 55 }
        let shortSide = min(bounds.width, bounds.height)
        guard shortSide > 0 else { return 55 }
        return min(80, max(36, shortSide * 0.155))
    }

    /// 当前窗口的真实安全区（状态栏 / 灵动岛 / Home 指示条）。
    ///
    /// 为什么不用 `GeometryReader` 的 `safeAreaInsets`：本面板外层被 `.ignoresSafeArea()`
    /// 包裹，那层里的 inset 实测取到 0，避不开灵动岛。UIKit 的窗口 inset 不受此影响。
    static var windowSafeInsets: UIEdgeInsets {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first(where: { $0.isKeyWindow })?.safeAreaInsets
            ?? UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
    }

    /// 分享卡的宽高比（取渲染图自身尺寸：单条 390×500，多码 390×变高）。
    /// 未渲染出图时回落到单条版式的 0.78，保证布局不崩。
    private var imageRatio: CGFloat {
        guard let image = model.image, image.size.height > 0 else { return 390.0 / 500.0 }
        return image.size.width / image.size.height
    }

    /// 右侧竖排操作条：保存 / 拷贝 / 更多分享。
    /// 2026-10-25 主人：从底部横排移到屏幕右侧，并改成**液态玻璃**按钮。
    private var verticalActions: some View {
        VStack(spacing: 14) {
            if let image = model.image {
                ShareGlassAction(icon: model.saved ? "checkmark" : "square.and.arrow.down",
                                 label: model.saved ? "已保存" : "保存图片",
                                 highlight: model.saved) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    model.saved = true
                    model.resetFlagsLater()
                }

                ShareGlassAction(icon: model.copied ? "checkmark" : "doc.on.doc",
                                 label: model.copied ? "已拷贝" : "拷贝图片",
                                 highlight: model.copied) {
                    UIPasteboard.general.image = image
                    model.copied = true
                    model.resetFlagsLater()
                }
            }

            ShareGlassAction(icon: "square.and.arrow.up",
                             label: "更多分享",
                             highlight: false) {
                model.showActivity = true
            }
        }
        .padding(.trailing, 0)
    }
}

/// 分享预览右侧的单个操作钮：46pt 圆形液态玻璃 + 图标，完成态转绿。
///
/// 与底部横排的老 `QuickShareAction` 并存 —— 后者仍被车票分享复用，
/// 这里只服务「分享取件码」的右侧竖排形态。
private struct ShareGlassAction: View {
    let icon: String
    let label: String
    let highlight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(highlight ? Color.green : Color.primary)
                .frame(width: 44, height: 44)
                .appGlass(.circle,
                          tint: highlight ? Color.green.opacity(0.35) : .clear,
                          interactive: true)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 快捷分享按钮：竖排圆底图标 + 文字，横向均分。
/// 取件码分享与车票分享共用（internal，跨文件复用）。
struct QuickShareAction: View {
    let icon: String
    let title: String
    let highlight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(highlight ? Color.green.opacity(0.15)
                                          : AppTheme.cardSurface,
                                in: Circle())
                    .foregroundStyle(highlight ? Color.green : Color.primary)
                Text(title.L)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// 系统分享面板的 SwiftUI 包装（分享预览面板的「更多分享」用）。
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
