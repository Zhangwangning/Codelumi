import SwiftUI

// MARK: ============================================================================
// 自绘侧滑行（2026-10-25）
//
// 为什么不用系统的 `.swipeActions`：
//   · 「卡片右缘 ↔ 按钮」的间距由系统写死，实测约 **29pt**，SwiftUI 没有任何参数可调；
//   · iOS 26 的侧滑按钮改成了「圆形图标 + 下方文字」，圆形落在矩形槽位里居中，
//     左右各留白，视觉上把这段空隙放得更明显（主人：「滑开后间距也太大了」）；
//   · 系统的卡片位移 = 按钮总宽 + 该间距，按钮一多卡片就被推得很远，整行发空。
//
// 这里自己接管横向拖拽：间距（`cardGap`）、按钮宽度（`buttonWidth`）、
// 圆角与配色全部可控，且**只响应以水平为主的拖拽**，垂直滚动仍交给 List。
//
// 手势用 `simultaneousGesture` 而不是 `gesture`：前者不会抢走 List 的滚动识别，
// 后者会让整行变成「拖不动列表」。垂直滚动时 `dx≈0`，被方向判断挡掉，offset 不动。
// ============================================================================

/// 一个侧滑按钮的定义
struct SwipeActionItem: Identifiable {
    /// 🔴 用 `title` 而不是 `UUID()`：`UUID()` 每次构造都是新值，
    /// 而这两组数组是在 `body` 里现构造的 —— id 一变，`ForEach` 就认为
    /// 所有按钮都是全新的，每帧都销毁重建（动画、点击态都会抖）。
    var id: String { title }
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void
}

/// 侧滑的两侧
enum SwipeSide {
    case leading   // 向右滑（卡片右移，露出左侧按钮）
    case trailing  // 向左滑（卡片左移，露出右侧按钮）
}

struct SwipeActionRow<Content: View>: View {

    let rowID: UUID
    /// 当前打开侧滑的行（全局只允许一行处于打开态）
    @Binding var openRowID: UUID?

    var leading: [SwipeActionItem] = []
    var trailing: [SwipeActionItem] = []
    /// 多选态等场景下整体禁用（与系统 swipeActions 一致：那时不该有破坏性操作）
    var enabled: Bool = true
    /// 哪一侧「滑过阈值松手就**直接执行**第一个动作」，不停在展开态。
    /// 2026-10-25 主人：**向右滑 = 直接复制**（高频、可重复、不破坏数据，一步到位）；
    /// 另一侧放「已取 / 恢复」这类会改变记录状态的，展开后需再点一下确认。
    var autoPerformSide: SwipeSide? = nil
    /// 调试用：允许 `openRowID` 变化时把本行摆成打开态（截图脚手架需要）。
    /// 正式交互下**不允许**它主动展开 —— 那是「滑一下自己弹到另一边」的元凶。
    var debugAllowsForcedOpen: Bool = false
    /// 调试用：首帧就把卡片拉到「超出按钮宽度 N pt」的形变态，用于截图取证
    /// full-swipe 的拉伸效果（命令行拖不了手势）。正式交互恒为 0。
    var debugStretch: CGFloat = 0

    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    // ⚠️ 这里**不再有** `isDragging` / `lockedAxis` 这类"跨帧方向状态"。
    //    原因：`List` 的滚动手势赢下竞争时，我们的 DragGesture 会直接**失败**，
    //    SwiftUI **不会**回调 `onEnded` —— 状态就永远留在上一次的值上，
    //    下一次横滑会被旧锁挡住（或反过来），表现出来就是"一阵一阵"。
    //    现在方向判定一律用 `value.translation`（每次手势自动从 0 开始），
    //    不依赖任何需要清理的状态。

    /// 第一段滑到展开位后，手指**停在原地**的起始时刻（2026-10-28 两段式左滑）。
    ///
    /// 用途：不抬手也能进入第二段 —— 必须在展开位**停顿 ≥ `stretchHoldDelay`**，
    /// 之后继续左滑才会把按钮拉长。快速一滑到底时这里只会计时、不给拉长，
    /// 松手就停在展开态。
    @State private var openHoldStart: Date?

    /// 按钮槽宽：46pt 圆 + 文字自适应，取 54 —— 与系统 `.swipeActions` 的单按钮宽度接近，
    /// 卡片被推开的距离因此不比系统大，但「卡片 ↔ 按钮」间距从 29pt 收到 8pt。
    private let buttonWidth: CGFloat = 54

    /// 第一段停在展开位后，需要停顿多久才允许进入第二段（拉长）。
    /// 0.3s ≈「手指明显停了一下」，比系统长按短得多，不会让"再滑一次"变慢。
    // 泛型类型不支持 static stored property，所以用实例常量。
    private let stretchHoldDelay: TimeInterval = 0.3
    private let buttonSpacing: CGFloat = 8
    /// 🔴 卡片与按钮之间的**唯一**间距控制点（系统是 29pt，这里压到 8pt）
    private let cardGap: CGFloat = 8

    private func actionsWidth(_ items: [SwipeActionItem]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return CGFloat(items.count) * buttonWidth
            + CGFloat(items.count - 1) * buttonSpacing
            + cardGap
    }

    private var trailingWidth: CGFloat { actionsWidth(trailing) }
    private var leadingWidth: CGFloat { actionsWidth(leading) }

    /// 向左滑**超出按钮宽度**后的拉伸量（2026-10-25 主人：
    /// 「一直向左滑，取件按钮拉长形变，完成取件」）。
    /// 0 表示刚好停在按钮展开位，正值表示已经拉出去多远。
    private var trailingStretch: CGFloat {
        max(0, -offset - trailingWidth)
    }

    /// 拉伸到这么多就认为「要完成」，松手即执行（0.6 个按钮宽 ≈ 32pt）。
    private var stretchCommitThreshold: CGFloat { buttonWidth * 0.6 }

    var body: some View {
        ZStack {
            // 底层：按钮（贴各自一侧，卡片滑开多少就露多少）
            //
            // ⚠️ 这里**就是一个按钮就是一个按钮**，不要再包 `GlassEffectContainer`、
            //    也不要为了"粘连"把一个按钮拆成两个圆（2026-10-25 主人：
            //    「那一个按钮，硬生生让你做成了俩」）。容器融合只适合多个独立元素
            //    互相靠近的场景；单个操作按钮拆两半，静态下就是个怪花生，难看。
            HStack(spacing: 0) {
                if !leading.isEmpty {
                    HStack(spacing: buttonSpacing) {
                        ForEach(leading) { item in
                            button(item)
                        }
                    }
                    .padding(.trailing, cardGap)
                    .opacity(offset > 0 ? 1 : 0)
                }

                Spacer(minLength: 0)

                if !trailing.isEmpty {
                    HStack(spacing: buttonSpacing) {
                        // 第一个按钮承担拉伸：滑过头它就从圆变长条，
                        // 给出「再滑就完成」的明确预期。
                        ForEach(Array(trailing.enumerated()), id: \.element.id) { index, item in
                            button(item, stretch: index == 0 ? trailingStretch : 0)
                        }
                    }
                    .padding(.leading, cardGap)
                    .opacity(offset < 0 ? 1 : 0)
                }
            }

            // 上层：卡片本体
            content()
                .offset(x: offset)
                // 侧滑打开时点卡片 = 先收起（系统 swipeActions 同款行为），
                // 否则用户想关掉侧滑却一脚踏进了详情页。
                //
                // 🔴 拖拽手势必须挂在**这一层 overlay 的外面**（2026-10-25 修）：
                // 透明层的 `contentShape(.rect)` 会参与 hit-test，先挂手势的话
                // 一滑开就被它挡住 —— 表现为「右滑之后再也拖不回来」，只能点一下收起。
                .overlay {
                    if offset != 0 {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { close(animated: true) }
                    }
                }
                .simultaneousGesture(dragGesture)
        }
        .onChange(of: openRowID) { _, newValue in
            // 🔴 只在「别人打开了」时收起自己；**绝不**在 `newValue == rowID` 时
            // 主动把 offset 设成某个值（2026-10-25 修）。
            // 之前那段「等于自己就展开到 -trailingWidth」会和 `onEnded` 的定稿
            // 抢着改 offset —— 用户左滑松手后，`onChange` 又把它往另一侧拉一次，
            // 主观上就是「滑完它自己往反方向跑」。
            // 展开态一律由手势的 `onEnded` 决定。
            if newValue != rowID, offset != 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { offset = 0 }
            }
            // 截图脚手架：只有显式允许时才主动展开
            if newValue == rowID, debugAllowsForcedOpen, offset == 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    offset = leading.isEmpty ? -trailingWidth : leadingWidth
                }
            }
        }
        .onDisappear {
            if openRowID == rowID { openRowID = nil }
            offset = 0
        }
        // 只给截图脚手架用：直接落在「拉长形变」的位置上。
        // 用 `.task` 而不是 `.onAppear` —— List 行里 onAppear 的调用时机不稳定，
        // 实测有时根本不触发（2026-10-25 调试）。
        .task {
            guard debugStretch > 0, !trailing.isEmpty, offset == 0 else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            offset = -(trailingWidth + debugStretch)
        }
    }

    // MARK: 按钮

    /// 侧滑按钮（2026-10-25 定稿 · 第三版）。
    ///
    /// 走过两版弯路，记下来别再犯：
    ///   · 玻璃 tint（0.62）把品牌色洗成一层浅色膜，按钮**发灰发淡**，比实色难看；
    ///   · 两圆在 `GlassEffectContainer` 里融合出的花生形，静态就是个**怪形状**，
    ///     两端不饱满、中间塌陷，完全不像一个可以点的按钮。
    /// 结论：**按钮本身必须是饱满的实色**，液态感只放在「被拉动时的形变」上。
    /// 所以这里用实色胶囊 + 顶部一道高光（有体积感、不呆板），
    /// 拉长时纵向轻微收窄（最多 22%），保留一点被拉细的手感。
    private func button(_ item: SwipeActionItem, stretch: CGFloat = 0) -> some View {
        return Button {
            // 先收起再执行：删除会让整行消失，保持展开态会闪
            close(animated: true)
            item.action()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    // 实色胶囊：上浅下深的渐变给一点体积，避免纯色平板
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [item.tint.opacity(0.94), item.tint],
                                startPoint: .top,
                                endPoint: .bottom)
                        )
                        // 高度**恒定 46**，只横向拉长（2026-10-25 主人：
                        // 「高度不要变窄拉长的时候」）。之前做纵向收窄是为了
                        // 模拟"液体被拉细"，但按钮一瘦就更像异形、不像能点的钮。
                        .frame(width: 46 + stretch, height: 46)
                        // 内描边模拟玻璃边缘的一道亮线，比纯平涂更有质感
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                        }

                    // 图标保持原尺寸，不随横拉变形
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
                }
                .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.78),
                           value: stretch)

                Text(item.title.L)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.tint)
                    .lineLimit(1)
            }
            .frame(width: buttonWidth + stretch)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: 手势

    private var dragGesture: some Gesture {
        // 起步距离 22pt（2026-10-28 第二次调整）：
        // `List` 底层是 UICollectionView，它的滚动手势位移约 10pt 就激活，
        // 与我们这条 DragGesture 是**竞争关系**（不是并行）—— 谁先到阈值谁接管整次触摸。
        // 12pt 太接近滚动阈值，于是出现主人描述的「一阵一阵：有时能滑，有时划不动」。
        // 提到 22pt 让滚动几乎总是先赢；代价是侧滑起步稍晚，但对 54pt 的按钮位移无感。
        DragGesture(minimumDistance: 22)
            .onChanged { value in
                guard enabled else { return }
                let dx = value.translation.width
                let dy = value.translation.height

                // 手势的**起步阶段**（累计位移还很小）重新锚定起点。
                // 这一句同时兼做"上一次手势的残局清理"：滚动把手势顶掉时不会回调
                // `onEnded`，`dragStartOffset` / `openHoldStart` 可能停在上一次的值上；
                // 新手势一开始必然经过这里，于是自动归位。
                if abs(dx) < 24 && abs(dy) < 24 {
                    dragStartOffset = offset
                    openHoldStart = nil
                }

                // 方向判定用**本次手势的累计位移**，每帧都算，不需要锁。
                // 1.8 倍的门槛：斜着上滑（|dx| 只是略大于 |dy|）一律按垂直处理，
                // 交给列表滚动，绝不横向拖动卡片。
                guard abs(dx) > abs(dy) * 1.8 else { return }

                var next = dragStartOffset + dx

                // 🔴 **两段式左滑**（2026-10-28 主人）：
                //   · 第一段（从关闭态起手）：**最多只滑到按钮完全露出**，绝不提前拉长；
                //   · 第二段（手指不抬、从展开态继续左滑）：才允许继续拉开做形变。
                // 旧实现一次滑到底就能拉开 32pt 以上，松手立刻执行取件 ——
                // 主人反馈「一左滑或快速左滑就直接拉长并完成」，误取件的风险太高。
                // 判断依据是**这次手势从哪儿起手**（`dragStartOffset`），不是速度。
                let continuingFromOpen = !trailing.isEmpty
                    && dragStartOffset <= -(trailingWidth - 1)

                // 第二段的两个入口：①抬手后重新左滑（起手就在展开位）；
                // ②手不抬、在展开位**停顿够久**再继续滑。
                // 后者是主人描述的「出来之后延时 0.几秒，还在向左滑才拉长」。
                if !continuingFromOpen {
                    let wouldPassOpen = !trailing.isEmpty && -next >= trailingWidth - 1
                    if wouldPassOpen {
                        if openHoldStart == nil { openHoldStart = Date() }
                    } else if -next < trailingWidth - 8 {
                        // 退回第一段范围 → 重新计时
                        openHoldStart = nil
                    }
                }
                let heldEnough = openHoldStart
                    .map { Date().timeIntervalSince($0) >= stretchHoldDelay } ?? false
                let canStretch = continuingFromOpen || heldEnough

                let maxTrailing: CGFloat = canStretch
                    // 第二段：留出「整条按钮宽」的余量，能拉出完整形变
                    ? trailingWidth + buttonWidth + 24
                    // 第一段：只给 8pt 橡皮筋 —— 顶住的手感有了，
                    // 但 8 < 提交阈值（0.6×54 ≈ 32pt），不可能被误判成"要完成"
                    : trailingWidth + 8
                let maxLeading = leadingWidth + (leadingWidth > 0 ? 20 : 0)
                next = min(maxLeading, max(-maxTrailing, next))
                if trailing.isEmpty { next = max(0, next) }
                if leading.isEmpty { next = min(0, next) }

                offset = next
            }
            .onEnded { value in
                guard enabled else { return }
                // 🔴 垂直手势（含斜着上滑）**一律不当侧滑结算**（2026-10-28）：
                // 之前这里不看方向，垂直滚动结束时 `predictedEndTranslation.width`
                // 常常也有几十 pt，于是「上滑一下」被判成右滑过六成 → 直接复制。
                // 现在用与 `onChanged` 相同的 1.8 倍门槛校验整次手势。
                guard abs(value.translation.width) > abs(value.translation.height) * 1.8
                else {
                    if offset != 0 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { offset = 0 }
                        if openRowID == rowID { openRowID = nil }
                    }
                    return
                }

                let dx = value.translation.width
                let predicted = dragStartOffset
                    + value.predictedEndTranslation.width * 0.35
                    + dx * 0.65

                // 从「已打开」状态往回**轻扫 12pt** 就收起（2026-10-25 主人：
                // 「右滑一下但不想操作了，轻轻左滑就恢复」）。
                // 不学系统那样必须拖过一半宽度 —— 那时手感发黏，用户得用力甩回去。
                // 12pt 是「手指明显反向移动」的下限，再小会跟松手时的自然抖动打架。
                let shrinkThreshold: CGFloat = 12
                let shrinkingTrailing = dragStartOffset < 0 && dx > shrinkThreshold
                let shrinkingLeading = dragStartOffset > 0 && dx < -shrinkThreshold

                // 「拉长形变」达标 = 要完成（2026-10-25 主人：一直向左滑，
                // 取件按钮拉长，完成取件）。判定用**松手时的真实位置**而不是
                // predicted —— 形变是看得见的，按看得见的位置判定才符合直觉。
                // 只有**第二段**才允许拉长提交：要么起手就在展开位（抬手后再滑），
                // 要么在展开位停顿够久后继续滑。第一段就算被橡皮筋带到 8pt，
                // 也远达不到阈值（32pt），这是双重保险。
                let continuingFromOpen = !trailing.isEmpty
                    && dragStartOffset <= -(trailingWidth - 1)
                let heldEnough = openHoldStart
                    .map { Date().timeIntervalSince($0) >= stretchHoldDelay } ?? false
                let stretchCommitted = (continuingFromOpen || heldEnough)
                    && trailingStretch > stretchCommitThreshold
                openHoldStart = nil

                // 松手时的真实速度决定"冲"还是"收"：甩得快就快到位，
                // 慢慢拖就稳稳停 —— 这是 0.3s 固定贝塞尔做不到的部分。
                let releaseVelocity = value.predictedEndTranslation.width
                    - value.translation.width

                withAnimation(AppMotion.interactive(velocity: releaseVelocity)) {
                    if shrinkingTrailing || shrinkingLeading {
                        offset = 0
                        if openRowID == rowID { openRowID = nil }
                    } else if stretchCommitted {
                        // 左滑拉过阈值 → 直接完成取件，卡片回弹、不再停在展开态
                        offset = 0
                        if openRowID == rowID { openRowID = nil }
                        trailing[0].action()
                    } else if autoPerformSide == .trailing, continuingFromOpen,
                              !trailing.isEmpty, predicted < -trailingWidth * 0.62 {
                        // 向左滑过约六成 → 直接执行右侧按钮，不停在展开态
                        offset = 0
                        if openRowID == rowID { openRowID = nil }
                        trailing[0].action()
                    } else if autoPerformSide == .leading, !leading.isEmpty,
                              predicted > leadingWidth * 0.62 {
                        // 向右滑过约六成 → 直接执行左侧按钮（当前是「复制」）
                        offset = 0
                        if openRowID == rowID { openRowID = nil }
                        leading[0].action()
                    } else if !trailing.isEmpty, predicted < -trailingWidth / 2 {
                        offset = -trailingWidth
                        openRowID = rowID
                    } else if !leading.isEmpty, predicted > leadingWidth / 2 {
                        offset = leadingWidth
                        openRowID = rowID
                    } else {
                        offset = 0
                        if openRowID == rowID { openRowID = nil }
                    }
                }
            }
    }

    private func close(animated: Bool) {
        if animated {
            withAnimation(AppMotion.quick) { offset = 0 }
        } else {
            offset = 0
        }
        if openRowID == rowID { openRowID = nil }
    }
}
