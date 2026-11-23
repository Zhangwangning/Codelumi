import SwiftUI
import UIKit

// MARK: ============================================================================
// 卡片长按菜单（自绘，替代系统 `.contextMenu`）
//
// 为什么自绘：
//   系统 `.contextMenu` 会给预览快照套一层**浅色圆角背景板**（`UIPreviewParameters`
//   的默认 material），SwiftUI 没有公开 API 能去掉它 —— 表现出来就是「长按卡片后，
//   卡片外面又多出一个白框」。主人明确不要这个框，要的是「原卡片自己高亮」。
//
// 自绘把四件事拆开做，全部可控：
//   1. **按压反馈**：按住回弹 0.975 → 触发后放大浮起（高亮**不加描边、不变色**）；
//   2. **景深**：底层列表整体缩小 0.965 + 整屏毛玻璃，被按的卡片以「替身」浮在
//      毛玻璃**之上** ⇒ 背景糊、主角清晰（主人指定的 iOS 文件夹长按观感）；
//   3. **菜单位置**：按卡片上报的真实 frame 贴它的下沿弹出，下方放不下则翻到上沿，
//      并避开浮动的 Tab 栏；
//   4. **零多余图层**：卡片本体不动形状、不加背景板 —— 那正是系统白框的来源。
//   5. **菜单项不自己弹面板**：面板一律由页面承载。浮层是条件渲染
//      （`if let openID`），点菜单项就收起 ⇒ 浮层连同其中的呈现者一起被摘掉，
//      挂在里面的 `ShareLink` / `.sheet` 都来不及弹。详见 `CardMenuItem` 注释。
// ============================================================================

// MARK: - 景深参数

/// 长按时的景深参数。
///
/// ⚠️ 页面（缩放底层列表）与浮层（换算卡片位置、放大替身）**必须共用同一份**：
/// 拆成两处字面量写死，早晚出现「菜单贴着缩放前的旧位置」这类错位。
enum CardMenuMetrics {
    /// 底层列表整体缩小的比例 —— 制造「卡片被抽出来、背景退后」的纵深。
    static let backgroundScale: CGFloat = 0.965
    /// 底层列表的模糊半径（pt）。
    ///
    /// 刻意**不用 `.ultraThinMaterial`**：材质除了模糊还会整体提亮/洗色，
    /// 背景会被糊成一片灰白（实测卡片轮廓几乎消失），主人的要求是「模糊一点点」。
    /// 直接对底层视图做 `blur` —— 半径可控、不改颜色，背景依然认得出是什么。
    ///
    /// 🔴 2026-11-17 流畅度：5 → 3。
    ///    这个 blur 是 `.scaleEffect` 一起被隐式动画驱动的，意味着**弹簧的每一帧
    ///    都要对整屏做一次高斯模糊**（离屏渲染整棵子树）。实测打开菜单那一下
    ///    主线程冻结 100ms、之后持续掉帧。半径 3 的采样面积约为 5 的一半，
    ///    视觉上仍是「模糊一点点」，轮廓与颜色都不受影响。
    static let backgroundBlur: CGFloat = 3
    /// 被拾起的卡片（替身）放大比例。
    static let cardScale: CGFloat = 1.035
    /// 浮层底部需要避开的区域：浮动 Tab 栏 + 主屏指示条。
    /// 本 App 的列表都在 `TabView` 里，且 Tab 栏是**浮在内容之上**的 ——
    /// 不算进可用高度，菜单会有一截被压在 Tab 栏底下（实测「删除记录」会被压掉）。
    /// 90pt 比实测的 84pt 多留一点余量：宁可整体上移，也不要被遮。
    static let bottomInset: CGFloat = 90
}

// MARK: - 菜单项

/// 长按菜单里的一项。
///
/// ⚠️ 菜单项**只负责「收起菜单 + 回调」**，不自己弹任何面板。
///
/// 这里曾有一个 `kind: .share`：该行内部挂 `ShareLink`，点击后由系统接管面板。
/// 结果是**面板永远不出现** —— 点它的同时菜单收起了，`if let openID` 把整个浮层
/// 从视图树上摘掉，`ShareLink` 的呈现锚点随之消失，系统面板还没弹就被取消。
/// （多码分享不受影响，因为它的面板 `SharePreviewSheet` 挂在稳定的列表页上。）
///
/// 现在的口径：分享由页面级的 `.sheet` 承载（见 `SharePreviewSheet`），
/// 菜单只把「哪条记录要分享」这个意图交回页面 —— 浮层生灭与面板无关。
struct CardMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var tint: Color = .primary
    var role: ButtonRole?
    /// 在这一行之前补一条分隔线（系统菜单里「删除」那种收尾项）
    var showsSeparatorBefore = false
    var action: (() -> Void)?

    init(title: String,
         symbol: String,
         tint: Color = .primary,
         role: ButtonRole? = nil,
         showsSeparatorBefore: Bool = false,
         action: (() -> Void)? = nil) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.role = role
        self.showsSeparatorBefore = showsSeparatorBefore
        self.action = action
    }
}

// MARK: - 长按状态

/// 列表页共用的长按状态。
///
/// ⚠️ `frames` **故意不做 `@Published`**：滚动时每一行的位置都在变，
/// 若参与发布会让整个列表随之重渲染（实测会掉帧）。它只是菜单定位的原始数据，
/// 由 `onGeometryChange` 持续写入、在菜单打开的那一刻读取即可。
final class CardMenuState: ObservableObject {
    /// 菜单正开着的卡（放大浮起 + 描边）
    @Published private(set) var openID: UUID?

    private(set) var frames: [UUID: CGRect] = [:]

    func updateFrame(_ id: UUID, _ rect: CGRect) {
        frames[id] = rect
    }

    func frame(of id: UUID) -> CGRect? { frames[id] }

    func isOpen(_ id: UUID) -> Bool { openID == id }

    /// 触觉发生器。**常驻并预热**：临时 new 一个再 impact 会晚 20–40ms，
    /// 主人在真机上感觉就是"震动和菜单一起来"，不像原生那样先震一下。
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    init() {
        haptic.prepare()
    }

    /// 长按触发：**先震动、稍后再出东西**（2026-10-28 主人：
    /// 「iPhone 原生的长按再出现菜单时，先震动，然后才出现内容，你是同步的，不好」）。
    ///
    /// 90ms 是照着系统 contextMenu 的观感取的：触觉先落地，景深与菜单紧随其后，
    /// 两者不同时发生 —— 同步触发会让人分不清"是震动带着动画，还是动画带着震动"。
    func open(_ id: UUID) {
        haptic.impactOccurred()
        haptic.prepare()   // 立刻为下一次预热
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                self.openID = id
            }
        }
    }

    func close() {
        guard openID != nil else { return }
        withAnimation(AppMotion.quick) { openID = nil }
    }
}

// MARK: - 挂载修饰器

extension View {
    /// 给列表卡片挂上长按菜单：按住回弹 → 触发放大高亮。
    ///
    /// 卡片形状与背景完全不动 —— 高亮只由 `scaleEffect` + 描边 + 投影表达，
    /// 这也是「不再出现第二个矩形」的根本原因。
    ///
    /// - Parameter enabled: 传 `false` 时**完全不挂手势**（列表编辑模式下用），
    ///   而不是「挂上但空转」—— 空转的长按仍会吃掉一次按压识别。
    func cardLongPress(for id: UUID,
                       state: CardMenuState,
                       enabled: Bool = true) -> some View {
        modifier(CardLongPressModifier(recordID: id, menu: state, enabled: enabled))
    }
}

private struct CardLongPressModifier: ViewModifier {
    let recordID: UUID
    @ObservedObject var menu: CardMenuState
    var enabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                // 高亮**不加描边**（主人明确不要彩色边框）：只靠「放大 + 投影加深」
                // 表达卡片被拾起。卡片本身的形状、背景、圆角一律不动。
                .scaleEffect(scale)
                .shadow(color: .black.opacity(isOpen ? 0.22 : 0),
                        radius: isOpen ? 18 : 0,
                        x: 0, y: isOpen ? 10 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: scale)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { rect in
                    menu.updateFrame(recordID, rect)
                }
                // 🔴 **长按用 `simultaneousGesture`**（2026-10-28 第三次定稿）。
                //
                // 演化史，三条路都试过，别再走回头路：
                //   1. `.onLongPressGesture { open }` —— 行内 `SwipeActionRow` 的 DragGesture
                //      让它**等 Drag 失败**才成立，Drag 的失败被推迟到抬手 ⇒ "松手才弹"；
                //   2. `.simultaneousGesture` + 一条 `minimumDuration: 0.05` 的手势上报 pressing
                //      —— 按住即弹了，但那条 0.05s 的手势会在触摸链最前面抢先"识别成功"，
                //      轻点进详情变得不稳；
                //   3. `.highPriorityGesture` —— 长按与 tap 都正常了，但它会把识别器提到
                //      列表滚动手势**之前**，并让触摸延迟交付给 UIScrollView：
                //      实测「手指落在卡片上就再也划不动列表」（主人 09:35 报的就是这个）。
                //  ⇒ 只能走 `simultaneousGesture`：它与滚动手势**并行**，不夺权、不延迟。
                //     配合 0.45s 时长与 18pt 容差，滑动列表时它会自然失败，不会打断滚动。
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45, maximumDistance: 18)
                        .onEnded { _ in
                            menu.open(recordID)
                        }
                )
        } else {
            content
        }
    }

    private var isOpen: Bool { menu.isOpen(recordID) }

    /// 只有"打开"这一档。按下回弹（0.975）随 0.05s 上报手势一起删掉了：
    /// 那条手势是"轻点进详情不稳"的来源，而回弹只是 0.45s 之内的过渡动画，
    /// 拿掉不影响任何信息传达。
    private var scale: CGFloat {
        isOpen ? 1.035 : 1
    }
}

// MARK: - 菜单浮层

/// 贴着卡片弹出的菜单浮层（含长按时的景深效果）。整层覆盖列表，点空白处收起。
///
/// 三层结构，自下而上：
///   1. **捕获层**：完全透明，只负责「点空白收起」；
///   2. **卡片替身**：与列表里那张卡同版式、同位、同尺寸 —— 它浮在底层之上，
///      而底层的模糊是加在页面的列表上（见 `CardMenuMetrics.backgroundBlur`），
///      所以只有它（和菜单）保持清晰，这就是 iOS 文件夹长按的观感；
///   3. **菜单**。
struct CardMenuLayer<Replica: View>: View {
    /// 卡片在 `.global` 坐标系里的位置（由 `CardLongPressModifier` 上报的**布局**坐标）。
    /// 传 `nil` 时（坐标尚未上报）回落到屏幕中上部 —— 宁可位置差一点，也不要整个菜单不出现。
    let anchor: CGRect?
    let items: [CardMenuItem]
    let onDismiss: () -> Void
    /// 卡片替身。由页面提供（浮层不该知道卡片有哪些种类），
    /// 回调一律给空实现 —— 替身只负责「被看见」，不参与交互。
    @ViewBuilder let cardReplica: () -> Replica

    /// 菜单固定宽：与系统 contextMenu 的观感接近（能放下「恢复为待取件」六个字）
    private let menuWidth: CGFloat = 228
    private let rowHeight: CGFloat = 44
    private let verticalPadding: CGFloat = 6
    private let gap: CGFloat = 8
    private let margin: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let size = geo.size
            let menuHeight = CGFloat(items.count) * rowHeight + verticalPadding * 2
            let card = cardRect(anchor: anchor, origin: origin, size: size)
            let point = menuOrigin(card: card, menuHeight: menuHeight, in: size)

            ZStack(alignment: .topLeading) {
                // 1. 捕获层：本身必须完全透明（背景的模糊由页面的 `blur` 提供）。
                //    用 0.001 而不是 0 —— 完全透明的视图在部分系统版本上不参与命中测试。
                Color.black.opacity(0.001)
                    .contentShape(.rect)
                    .onTapGesture { onDismiss() }
                    .transition(.opacity)

                // 2. 卡片替身：保持清晰。投影比平时重 —— 景深效果靠它撑出「离屏幕更近」。
                cardReplica()
                    .frame(width: card.width, height: card.height)
                    .scaleEffect(CardMenuMetrics.cardScale)
                    .shadow(color: .black.opacity(0.24), radius: 26, x: 0, y: 13)
                    .offset(x: card.minX, y: card.minY)
                    // 出现时从「未放大」长到放大态，与底层卡片自身的按压放大接得上。
                    .transition(.scale(scale: 1 / CardMenuMetrics.cardScale)
                        .combined(with: .opacity))

                // 3. 菜单
                menuBody
                    .frame(width: menuWidth)
                    .offset(x: point.x, y: point.y)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    /// 卡片在本容器坐标系里的位置。
    ///
    /// 上报名的是**布局坐标**，而底层列表在长按时被缩放了 `backgroundScale` ——
    /// 缩放中心是列表中心（与本容器中心重合），据此把坐标换算到屏幕上真实的位置，
    /// 替身才不会与它盖住的那张卡错开。
    private func cardRect(anchor: CGRect?, origin: CGPoint, size: CGSize) -> CGRect {
        guard let anchor else {
            return CGRect(x: (size.width - 300) / 2, y: size.height * 0.3,
                          width: 300, height: 80)
        }

        let local = anchor.offsetBy(dx: -origin.x, dy: -origin.y)
        let scale = CardMenuMetrics.backgroundScale
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        return CGRect(x: center.x + (local.minX - center.x) * scale,
                      y: center.y + (local.minY - center.y) * scale,
                      width: local.width * scale,
                      height: local.height * scale)
    }

    /// 菜单左上角坐标：默认贴卡片下沿，下方放不下翻到上沿，都放不下就贴着可用区底边。
    private func menuOrigin(card: CGRect, menuHeight: CGFloat, in size: CGSize) -> CGPoint {
        let usableBottom = size.height - CardMenuMetrics.bottomInset
        let usableHeight = max(menuHeight + margin * 2, usableBottom)

        var y = card.maxY + gap

        if y + menuHeight > usableBottom - margin {
            let above = card.minY - gap - menuHeight
            y = above >= margin ? above : max(margin, usableHeight - menuHeight - margin)
        }

        let maxX = max(margin, size.width - menuWidth - margin)
        let x = min(max(margin, card.minX), maxX)

        return CGPoint(x: x, y: y)
    }

    private var menuBody: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if item.showsSeparatorBefore && index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.09))
                        .frame(height: 0.5)
                }

                row(item)
            }
        }
        .padding(.vertical, verticalPadding)
        .frame(width: menuWidth)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 10)
    }

    private func row(_ item: CardMenuItem) -> some View {
        Button(role: item.role) {
            onDismiss()
            item.action?()
        } label: {
            CardMenuRowContent(title: item.title, symbol: item.symbol, tint: item.tint)
        }
        .buttonStyle(.plain)
    }
}

/// 菜单行的统一版式（图标 + 文字，左对齐）。
struct CardMenuRowContent: View {
    let title: String
    let symbol: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 20)

            Text(title.L)
                .font(.system(size: 15))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .contentShape(.rect)
    }
}
