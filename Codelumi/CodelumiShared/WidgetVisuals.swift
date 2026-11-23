import SwiftUI
import UIKit
import AppIntents
import WidgetKit

// MARK: ============================================================================
// 小组件可视层（App 与小组件扩展共同编译）
//
// 为什么放在共享层而不是 Widget target：
//   桌面小组件在模拟器上无法脚本化添加，唯一的「真实渲染证据」是在 App 内用
//   **同一份视图代码**按小组件尺寸渲染一次。放在共享层后，设置页里的「小组件预览」
//   也不用手写副本 —— 之前 SettingsView 里那个 MediumWidgetPreview 就是手工复刻，
//   两份代码一旦漂移就会出现「设置页看着好好的、桌面却不一样」的假象。
//
// 版式口径（2026-09-21 定稿）：
//   · **不放快递平台图标** —— 行首图标占宽约 41pt，去掉后全部让给取件码与地址；
//   · **取件码是唯一主角** —— 每行只有两级信息：取件码（大字）→ 平台｜地址（小字）；
//   · **行首圆形勾选框** —— 与 App 内 CompleteButton 同源，可直接在桌面点掉。
//
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

// MARK: - 停用态（已删除 · 2026-09-23）
//
// 这里原有 `WidgetDisabledContent`：用户在「设置 › 桌面小组件」关掉总开关后
// 桌面显示的「小组件已关闭」占位版式。总开关已被主人判定为无意义并整体删除
// （理由见 `PickupStorage.swift` 顶部同名注释），没有"关闭"这个状态了，
// 因此这块版式也一并退场 —— 保留它就是留一段永远画不到的死代码。

// MARK: - 圆形勾选框（可点击）

/// 小组件里的「标记已取」按钮。
///
/// 与 App 内 CompleteButton 的差别：
///   · 尺寸压缩到 21~22pt（小组件行高只有约 40pt）；
///   · 点击后由 `TogglePickupIntent` 直接写 App Group，不打开 App。
///
/// 小组件只展示「待取件」，因此 isDone 目前恒为 false（空心圆环）；
/// 参数保留是为了付费版大尺寸展示已取记录时可以直接复用。
struct WidgetCheckCircle: View {
    let isDone: Bool
    let tint: Color
    let recordID: String
    var size: CGFloat = 21
    /// 点击热区边长。列表卡用 32pt；单码卡画布只有 126pt 宽，热区再给 32 会把名字挤没。
    var hitSize: CGFloat = 32

    var body: some View {
        Button(intent: TogglePickupIntent(recordID: recordID)) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? tint : Color.secondary.opacity(0.55),
                                  lineWidth: max(1.6, size * 0.085))
                    .frame(width: size, height: size)

                if isDone {
                    Circle()
                        .fill(tint)
                        .frame(width: size, height: size)

                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            // 点击热区：圈本身只有 21pt，可点面积太小；
            // 扩到 32pt 仍在本行高预算内，且不改变视觉尺寸。
            .frame(width: hitSize, height: hitSize)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "已取件，轻点可恢复为待取件" : "标记为已取件")
    }
}

// MARK: - 细分隔线

/// 不用系统 `Divider()`：它会随环境 tint 变色，在小组件里与 App 内的分隔线观感不一致。
struct WidgetHairline: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(height: 0.5)
    }
}

// MARK: - 翻页控件（上下翻动查看）
//
// 为什么不是「滑动」：小组件**不支持原生滚动** —— 已对 iOS 27 SDK 的 WidgetKit /
// SwiftUI 接口逐一核实（无任何滚动相关 API），Apple 在 Meet WidgetKit 里也明确说
// List / ScrollView 在小组件内不滚动。真机表现是内容被裁掉、手指划不动。
//
// 可行且真能用的机制只有 iOS 17+ 的可交互小组件：两个 `Button(intent:)` 改页码、
// 重画时间线。用户按住上/下箭头即可逐页翻看，效果等同「上下翻动」。
//
// 页码写进 App Group（见 `WidgetPaging`），因此翻页不唤醒主 App 也能持久。

struct WidgetPager: View {
    let page: Int
    let pageCount: Int
    let familyKey: String

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.up", delta: -1, label: "上一页")

            Text("\(page + 1)/\(pageCount)")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 1)

            chevron("chevron.down", delta: 1, label: "下一页")
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.14), in: .capsule)
    }

    private func chevron(_ symbol: String, delta: Int, label: String) -> some View {
        Button(intent: WidgetPageIntent(familyKey: familyKey,
                                        delta: delta)) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.secondary)
                // 箭头本身只有 9pt，可点面积扩到 18×16 —— 小组件上的手指精度更差，
                // 视觉尺寸不变但命中率翻倍。
                .frame(width: 18, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 翻页意图（写页码 + 重画）

/// 小组件内的上/下翻页动作。
///
/// ⚠️ `familyKey` / `delta` 必须是 `@Parameter`：
/// `Button(intent:)` 会被系统**归档成一个实例标识**再在扩展进程里还原，
/// 只有 `@Parameter` 标注的属性会进归档。写成普通存储属性会在还原后变成默认值 ——
/// 表现就是「点了没反应」或「永远停在第一页」。
struct WidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource { "翻页" }

    /// 与 `TogglePickupIntent` 同一口径：小组件内部指令，不进快捷指令 / 聚焦列表
    static var isDiscoverable: Bool { false }

    /// 纯后台：翻页绝不把 App 拉到前台
    /// 🔴 部署目标降到 iOS 18：`IntentModes`（含 `.background`）是 iOS 26 新增。
    ///    改用等价的 `openAppWhenRun = false`（iOS 16 起可用）：后台执行、不拉起 App。
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "尺寸")
    var familyKey: String

    @Parameter(title: "方向")
    var delta: Int

    init() {}

    init(familyKey: String, delta: Int) {
        self.familyKey = familyKey
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        // 与 `WidgetSnapshot.load()` 同一口径：翻页可及的最大条数也要按档位裁，
        // 否则免费用户在免费档上能翻到第 4 条以后（列表里根本没有那些条目）。
        let isPro = EntitlementSnapshot.licensedPro
        let cap = isPro ? PickupLimits.widgetListCap : PickupLimits.freeVisible

        // 现数一遍页数，不复用可视层传进来的值：翻页意图可能在任何时刻被唤醒，
        // 期间用户可能已经取走几件，用旧页数会翻到空白页。
        let count = min(PickupStorage.load()
            .filter { !$0.isPickedUp }
            .count, cap)
        let size = WidgetPageSize.rowCount(family: familyKey)
        let pageCount = max(1, Int(ceil(Double(count) / Double(size))))

        let current = WidgetPaging.page(family: familyKey)
        // 首尾**环形**相接：翻到最后再往下回到第 1 页。
        // 比「禁用按钮」少两个状态要渲染，也避免用户以为小组件卡住了。
        let next = ((current + delta) % pageCount + pageCount) % pageCount
        WidgetPaging.setPage(next, family: familyKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - 分页列表内容（中 / 大 / 超大尺寸共用）
//
// 三个尺寸只有「一页几行」不同，版式完全一致 —— 所以是同一个视图 + 一个 pageSize，
// 不是三份会各自漂移的副本。

struct WidgetPagedContent: View {
    let snapshot: WidgetSnapshot
    let pageSize: Int
    let familyKey: String
    /// 二级信息行显示哪几项。由款式（`WidgetContent`）决定，用户不直接调。
    var options: WidgetDisplayOptions = .full

    private var pageCount: Int { snapshot.pageCount(pageSize: pageSize) }
    private var current: Int {
        snapshot.clampedPage(WidgetPaging.page(family: familyKey),
                             pageSize: pageSize)
    }
    private var rows: [PickupRecord] { snapshot.pageItems(current, pageSize: pageSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 7)

            WidgetHairline()

            // 🔴 2026-10-28 主人：「数据少的时候仍然不能改变字号、行间距」。
            //
            // 原先是 `.frame(maxHeight: .infinity)` —— 行高按**剩余高度均分**：
            // 满页 8 条时每行 36pt，只有 2 条时每行会被拉到 140pt，
            // 进来一看就像「字变大了、行距变松了」，与满页完全是两种观感。
            //
            // 现在改成**行高恒定 = 满页时的行高**（可用高度 ÷ 每页条数），
            // 数据不足一页时多出来的空间留在底部，任何行数下字号与行距都一致。
            GeometryReader { geo in
                // 🔴 2026-11-08 修「内容重叠」：
                //    行高来自「可用高度 ÷ 每页条数」，高度不够时它会小于一行的自然高度，
                //    而 `.frame(height:)` **不会裁剪**内容 —— 第一行的第二行文字就压到了
                //    第二行上，看起来像串行。三处一起兜住：
                //      · 行高设下限（够放码 + 一行副标题），
                //      · 每行 `.clipped()`，任何溢出都截在本行内，
                //      · 外层随后由卡片 clipShape 兜底。
                let rawRowHeight = geo.size.height / CGFloat(max(pageSize, 1))
                let rowHeight = max(rawRowHeight, 28)
                VStack(spacing: 0) {
                    ForEach(rows) { record in
                        WidgetPickupRow(record: record,
                                        options: options,
                                        extraCodes: snapshot.extraCodes[record.id.uuidString] ?? [])
                            .frame(height: rowHeight, alignment: .top)
                            .clipped()
                    }
                    // 🔴 2026-11-22：**空槽（灰色骨架行）整块退场** —— 连同设置页那个
                    //    「占位符」开关。
                    //    理由：① 每个款式都是固定版式，数据不足一页时**留白**比伪造
                    //    几行灰条诚实；② 它本来就是误解源（2026-11-14 有用户反馈
                    //    「以为还有快递没显示出来」，才加了个开关去关它）；
                    //    ③ 行高由「可用高度 ÷ 每页条数」恒定，删掉空槽不会让字数变大
                    //    或行距变松，这正是当初加空槽想解决的问题，现在由行高兜住了。
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 头部：分类标题 + 真实总数 +（Pro 截断提示 / 今日已取）+ 翻页控件。
    ///
    /// 「Pro」与「今日已取」互斥显示：被截断时说明「为什么只看到这几条」
    /// 远比今天的成绩重要，两者同排会把头部挤到换行。
    /// 🔴 文案不带「免费版」「付费版」—— 对外只有「Codelumi」与「Codelumi Pro」
    ///    （2026-11-01 主人）。组部件里空间紧，这里用最短的「Pro」。
    private var header: some View {
        HStack(spacing: 6) {
            Text("待取件")
                .font(.system(size: 13, weight: .semibold))

            Text("\(snapshot.pendingTotal)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.pendingTint)

            Spacer(minLength: 0)

            if snapshot.isTruncated {
                freeBadge
            } else if snapshot.pickedTodayCount > 0 {
                todayChip
            }

            if pageCount > 1 {
                WidgetPager(page: current,
                            pageCount: pageCount,
                            familyKey: familyKey)
            }
        }
    }

    private var freeBadge: some View {
        HStack(spacing: 2.5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8.5, weight: .bold))
            Text("Pro")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(AppTheme.todayTint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var todayChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
            Text("今日已取 \(snapshot.pickedTodayCount)")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(AppTheme.doneTint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - 小尺寸内容（3-4 条）

/// 小尺寸（158×158）专用版式，两种形态：
///
/// · **只有码**（`.codeOnly`）—— 4 条，每条一行取件码。2026-10-27 主人定稿的形态：
///   「小尺寸就显示重要信息，取件码就行」+「一次性显示三到四个取件码」。
/// · **带副标题**（`.station` / `.company`）—— 3 条，码下面跟一行驿站或快递公司。
///
/// 🔴 带副标题为什么降到 3 条：一行要塞下 15pt 的码 + 10pt 的副标题（约 31pt），
///    4 条就是 124pt，加头部直接顶穿 126pt 的可用高度 —— WidgetKit 不报错，
///    直接从底部把最后一行裁掉半截，看起来像组件坏了。
///
/// 高度预算（158 − 上下 16 padding = 126pt）：
///   只有码　—— 头部 19 + 分隔线 5.5 + 上间距 6 + 4 行(21+3) ≈ 126；
///   带副标题 —— 头部 19 + 分隔线 5.5 + 上间距 5 + 3 行(18+1+12) + 2×2 ≈ 125。
struct WidgetSmallContent: View {
    let snapshot: WidgetSnapshot
    /// 每条显示到哪一层。决定条数上限与第二行内容。
    ///
    /// 🔴 2026-11-22 晚：由 `WidgetContent` 枚举换成值对象 ——
    ///    小尺寸三个变体各自固定一份（`.codeAndLocker` / `.station` / `.company`），
    ///    与中 / 大「用户开关」共用同一套渲染口径。
    var options: WidgetDisplayOptions = .codeAndLocker
    /// 版式。默认列表 —— 非列表的七款走各自的分支（见 `WidgetLayout`）。
    var layout: WidgetLayout = .list

    /// 只有码 4 条、带副标题 3 条（理由见类型注释的高度预算）。
    private var maxRows: Int { options.isCodeOnly ? 4 : 3 }
    private var visible: [PickupRecord] { Array(snapshot.items.prefix(maxRows)) }

    var body: some View {
        switch layout {
        case .list:         listBody
        case .todayProgress: WidgetTodayProgressContent(snapshot: snapshot)
        case .focusCode:    WidgetFocusCodeContent(snapshot: snapshot)
        case .stationBars:  WidgetStationBarsContent(snapshot: snapshot)
        case .oldestPending: WidgetOldestPendingContent(snapshot: snapshot)
        case .codeCard:     WidgetCodeCardContent(snapshot: snapshot)
        }
    }

    /// 列表版式（原来唯一的一种）。
    private var listBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("待取件")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text("\(snapshot.pendingTotal)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.pendingTint)
            }

            WidgetHairline()
                .padding(.top, 5)

            if options.isCodeOnly {
                VStack(spacing: 3) {
                    ForEach(visible) { record in
                        codeRow(record, height: 21)
                    }
                }
                .padding(.top, 6)
            } else {
                VStack(spacing: 1) {
                    ForEach(visible) { record in
                        VStack(alignment: .leading, spacing: 1) {
                            codeRow(record, height: 18)

                            if let subtitle = subtitle(record) {
                                Text(subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    // 与取件码左缘对齐：勾选圈的热区 32 + HStack 间距 6 = 38
                                    .padding(.leading, 38)
                            }
                        }
                    }
                }
                .padding(.top, 5)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 一行取件码：勾选圈 + 码 + （一卡多码时）+N。
    private func codeRow(_ record: PickupRecord, height: CGFloat) -> some View {
        HStack(spacing: 6) {
            // 勾选圈缩到 16pt：4 行时行高只有 21pt，再大就溢出。
            // 仍可直接点（WidgetCheckCircle 自带 AppIntent 按钮），
            // 只是这里的热区偏小 —— 真要勾取建议点开 App，这一页主要是"看码"。
            WidgetCheckCircle(isDone: false,
                              tint: record.codeColor,
                              recordID: record.id.uuidString,
                              size: 16)

            record.emphasizedCodeText(tint: record.codeColor)
                // 🔴 各行**字号完全统一**（2026-10-27 主人：「字体大小都保持一致」）。
                //    不做按码长缩放、也不做 minimumScaleFactor：
                //    取件码是 AttributedString，缩放对富文本本来就不生效，
                //    而"短码 17pt / 长码 11pt"混排更难看 —— 一屏四种大小，
                //    像没做完的列表。统一 15pt，真放不下的长码走尾部省略号。
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospaced()
                .lineLimit(1)
                .truncationMode(.tail)

            // 🔴 2026-11-16「一张卡片多个取件码」：小尺寸仍只画一行一码
            //    （不塞第二个大字，行高塞不下），但不能把同伴码**静默吃掉** ——
            //    补一个「+N」角标提示。
            if let extra = snapshot.extraCodes[record.id.uuidString],
               !extra.isEmpty {
                Text("+\(extra.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(height: height)
    }

    /// 副标题内容。
    ///
    /// 驿站走 `PickupSortLogic.stationName`（含驿站组名 —— 组名是用户自己起的名字，
    /// 比成员驿站名更好认）；公司走 `companyName`，与卡面主名同一口径。
    /// 拿不到就给 nil —— **宁可不画这一行，也不要画「未标注驿站」这种系统话**。
    ///
    /// 🔴 小尺寸只有一行副标题的位置：**驿站优先，没有驿站才退到快递公司** ——
    ///    「谁保管 + 去哪取」比「哪家快递」更靠近用户要做的动作。
    ///    地址一律不画：一行放不下门牌号，硬塞只会变成「馨月湖小区南门…」这种半截字。
    private func subtitle(_ record: PickupRecord) -> String? {
        // 🔴 2026-11-23：小 / 中 / 大合并成一款之后，「取件地址」在小尺寸上也得有落点，
        //    否则那个开关在 158pt 画布上等于失效（用户会当成 bug）。
        //    规则：开了地址就**优先画地址**（一行、截断），否则驿站优先、公司兜底 ——
        //    仍然只有一行，不额外吃高度。
        if options.showsStation {
            let name = PickupSortLogic.stationName(of: record)
            if name != PickupSortLogic.noStation { return name }
        }
        // 驿站认不出来时才轮到地址（默认口径仍是「谁保管」优先，观感不变）；
        // 想要小尺寸只看地址：把驿站与公司关掉、只留地址即可。
        if options.showsAddress {
            let address = record.address.trimmingCharacters(in: .whitespacesAndNewlines)
            if !address.isEmpty { return address }
        }
        if options.showsCompany {
            let name = PickupSortLogic.companyName(of: record)
            if !name.isEmpty { return name }
        }
        return nil
    }
}

// MARK: - 小尺寸 · 非列表版式（2026-11-22）
//
// 主人原话：「你多几个小尺寸的小组件，不全是取件列表啊，还可以是今日待取数量
// 单独做一个，发散思维」。列表是「逐条读码」的形态，但桌面上很多时候只想知道
// 一个数、一个码、或者一件事 —— 用列表去表达这些，等于把答案埋在细节里。
//
// 五款的共同口径：
//   · 高度预算 126pt（158 画布 − 系统 16×2 内边距）；
//   · 一律 `maxHeight: .infinity, alignment: .topLeading`，四款顶部基线对齐；
//   · 数字全用 `.rounded` + `monospacedDigit()` —— 位宽固定，刷新时数字不跳。

/// 非清单版式的**尺寸口径**（2026-11-22 晚：同一套版式要能画在三块画布上）。
///
/// 主人要求「中尺寸的小组件你在按照小尺寸的小组件的内容做对应的中尺寸的小组件，
/// 然后大尺寸的小组件亦是如此」—— 版式只有一份，尺寸靠这里放大。
///
/// 🔴 为什么不用 `scaleEffect` 整体放大：那是位图变换，1.75 倍的大尺寸上字会发虚。
///    这里放大的是**字号与关键尺寸本身**，文字仍然按真实字号排版。
struct WidgetHeroMetrics {
    /// 相对小尺寸（158×158）的倍数。
    var scale: CGFloat

    /// 把设计稿上的数值换算成当前画布的数值。
    func sc(_ value: CGFloat) -> CGFloat { value * scale }

    static let small = WidgetHeroMetrics(scale: 1)

    /// 中 / 大按**可用高度**定倍数（不是宽度：这三款都是竖向堆叠，宽度用不满也不需要）。
    /// 小 126pt → 中 138pt → 大 322pt，取 1 / 1.2 / 1.75。
    static func forFamily(_ family: WidgetFamily) -> WidgetHeroMetrics {
        switch family {
        case .systemSmall:  return .small
        case .systemMedium: return WidgetHeroMetrics(scale: 1.2)
        default:            return WidgetHeroMetrics(scale: 1.75)
        }
    }
}

/// 「取件进度」：**今日到件 + 取件进度**合成一款（2026-11-22 老大：「这两款可以合并一下」）。
///
/// 原来两款各答半个问题：
///   · 「今日到件」给一个大数字（今天到了几件），看不出取走几成；
///   · 「取件进度」给一个环（取走几成），分母里已经含着待取与今日已取，却看不到到件量。
/// 合并后一块画布同时给：**进度是比例，旁边（或下面）是今日到件 + 待取 / 已取**。
///
/// 分母口径沿用原来那套（`待取 + 今日已取`）：只拿待取当分母永远是 0%，
/// 只拿总数当分母又会在跨天时把上周的件算进来，都不对。
///
/// 三套排布，不是简单放大（2026-11-22 晚老大逐条定）：
///   · 窄（小尺寸，内容宽 126pt）：标题行右挂「今日 N」→ 环居中 → 底部待取 / 已取两格；
///   · 宽（中尺寸）：**左**「今日到件」大数字 + 图例，**右**环；
///   · 大（大尺寸）：**横线进度条** → **本月日历圆点**（绿=当天取完 / 红越深未取越多 /
///     浅灰=当天没件）→ 底部今日到件 / 待取 / 已取三格。
struct WidgetTodayProgressContent: View {
    let snapshot: WidgetSnapshot
    /// 当前画布的尺寸口径（小 / 中 / 大）。
    var metrics: WidgetHeroMetrics = .small

    private var denominator: Int { snapshot.pendingTotal + snapshot.pickedTodayCount }
    private var ratio: Double {
        guard denominator > 0 else { return 0 }
        return Double(snapshot.pickedTodayCount) / Double(denominator)
    }
    /// 中 / 大走横排 —— 画布变宽了，还竖着排会把两侧空间全空出来。
    private var isWide: Bool { metrics.scale > 1.01 }
    /// 大画布单独一套排布：横排那套按 1.75 放大后，环与文字都挤在上半部，
    /// 下面空出一大片；图例还会被裁成「待 1」「已 2」（2026-11-22 截图实测）。
    private var isLarge: Bool { metrics.scale > 1.3 }

    var body: some View {
        Group {
            if isLarge {
                largeLayout
            } else if isWide {
                wideLayout
            } else {
                narrowLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: isWide ? .leading : .topLeading)
    }

    // MARK: 大画布（大尺寸）

    /// 横线进度条 → 本月折线图 → 今日到件 / 待取 / 已取。
    ///
    /// 🔴 2026-11-22 老大两句话定的口径：
    ///    「进度做成横线进度条，然后进度条下方**只做**一个本月的……视图，
    ///      然后最下面的就是今日到件、待取、已取数量」
    ///    → 当晚改：「算了吧，不要做成日期的这种，直接做成月头到月底的折线图吧」。
    ///    —— 日历格子回答的是"哪几天有件"，折线回答的是"这个月是涨还是落"，
    ///    大画布上趋势比格子更值得占地方。
    ///
    /// 高度预算：画布 358pt。进度区 ~46 + 折线 ~168 + 坐标 ~20 + 三格 ~62 + 间隔 ~30 = 326。
    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            largeProgressBar
                .padding(.bottom, metrics.sc(4))

            // 网格是 flexible 的（GeometryReader），由它吃掉中间全部高度 ——
            // 这里再放 Spacer 会和它抢空间，反而把点挤小
            yearHeatmap

            largeStats
                .padding(.top, metrics.sc(3))

            // 末尾也要留一口气：VStack 撑满时最后一个元素会贴到内容区下缘，
            // 数字看着像被裁掉半截（截图实测）。三处 Spacer 均分余量最稳。
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 横线进度条：左标题、右百分比，下面一条胶囊。
    private var largeProgressBar: some View {
        VStack(alignment: .leading, spacing: metrics.sc(5)) {
            HStack(spacing: 0) {
                Text("取件进度")
                    .font(.system(size: metrics.sc(11), weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(size: metrics.sc(15), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.doneTint)
            }

            // 条宽靠 GeometryReader 拿实际宽度 —— 大画布虽固定，但换了字体大小 / 圆角
            // 之后仍是这个宽度，不要写死 306 之类的魔数。
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.16))

                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [AppTheme.doneTint, AppTheme.doneTintLight],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        // 0% 时也留一点：空条 + 0% 会像"没加载出来"，
                        // 留一小段是"刚起步"（与环的 min 0.015 同一个理由）。
                        .frame(width: max(metrics.sc(7), geo.size.width * ratio))
                }
            }
            .frame(height: metrics.sc(8))
        }
    }

    /// 本年到件热力图：**从 1 月 1 日连续排到 12 月 31 日**，每行数量固定，排满换行。
    ///
    /// 🔴 2026-11-22 老大口径最终收敛：
    ///    「不要按照每行一月的做法，做成从第一天连续到最后一天的」
    ///    →「只要圆点，不要标月份等」
    ///    →「中间区域也大着呢啊，每行的个数要一致，超过的放在下一行，
    ///       行数可以多一点，意味着每行的数量稍微减少一下」。
    ///    所以这里**没有月份/星期/标题任何标注**，一天一个点、连续折行，
    ///    每行点数固定 `perRow`，行高与点径由可用空间反算，把中间那块铺满。
    ///
    /// 圆点规则仍是那三条：全取完绿 / 有未取陶土红（越深越多）/ 没件浅灰，今天套一圈强调色。
    private var yearHeatmap: some View {
        GeometryReader { geo in
            heatGrid(size: geo.size)
        }
    }

    private func heatGrid(size: CGSize) -> some View {
        // 25 个一行：365 / 25 = 14.6 → 15 行，最后一行还有 15 个，不会孤零零剩一颗。
        // 这个数是按大画布（348 宽 × ~226 可用高）反算的 —— 点径 ~10.8pt、行距 ~4.3pt，
        // 既比"一周一列"时的 5pt 大一倍多，又正好把中间区域填满。
        let perRow = 25
        let dayCount = max(snapshot.yearDayCount, 365)
        let rows = max(Int(ceil(Double(dayCount) / Double(perRow))), 1)

        let cellWidth = max(size.width / CGFloat(perRow), 1)
        let rowPitch = max(size.height / CGFloat(rows), 1)
        // 点径同时受两边约束：横向不超过格宽的 78%，纵向不超过行高的 72%
        let diameter = max(min(cellWidth * 0.78, rowPitch * 0.72), 2)
        let series = yearSeries
        let today = todayIndex

        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<perRow, id: \.self) { column in
                        let index = row * perRow + column
                        Group {
                            if index < dayCount {
                                heatDot(stat: index < series.count ? series[index] : nil,
                                        isToday: index == today,
                                        diameter: diameter)
                            } else {
                                // 最后一行不足 26 个：留空，保持每行等宽
                                Color.clear
                                    .frame(width: diameter, height: diameter)
                            }
                        }
                        .frame(width: cellWidth, height: rowPitch)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// 一颗圆点。三态与日期圆点版完全一致，今天多套一圈强调色。
    private func heatDot(stat: WidgetDayStat?, isToday: Bool, diameter: CGFloat) -> some View {
        let filled = (stat?.total ?? 0) > 0
        let pending = stat?.pending ?? 0

        let fill: Color = !filled
            ? AppTheme.emptyDayDot
            : (pending > 0 ? AppTheme.undoneHeat(pending) : AppTheme.doneTint)

        return Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .overlay {
                if isToday {
                    Circle()
                        .strokeBorder(AppTheme.accent, lineWidth: metrics.sc(0.8))
                        .frame(width: diameter + metrics.sc(1.6),
                               height: diameter + metrics.sc(1.6))
                }
            }
    }

    /// 按「年内第几天（0-based）」排好的统计序列。
    ///
    /// 用月长表累加而不是对 365 个格子逐个做 `Calendar.date(from:)` ——
    /// 后者在小组件渲染里是几百次日期运算，没必要。
    private var yearSeries: [WidgetDayStat?] {
        let dayCount = max(snapshot.yearDayCount, 365)
        var series = [WidgetDayStat?](repeating: nil, count: dayCount)

        var index = 0
        for month in 1...12 {
            let length = daysIn(month)
            for day in 1...length {
                if index < dayCount, let stat = statByDate[month * 100 + day] {
                    series[index] = stat
                }
                index += 1
            }
        }
        return series
    }

    /// 今天在年内的序号（0-based），网格上给这一格描蓝圈。
    private var todayIndex: Int {
        var index = 0
        for month in 1..<max(snapshot.todayMonth, 1) {
            index += daysIn(month)
        }
        return index + max(snapshot.todayDay - 1, 0)
    }

    /// 某月有几天（2 月按当年算，闰年 29）。
    private var monthLengths: [Int: Int] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        var lengths: [Int: Int] = [:]
        for month in 1...12 {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            if let date = calendar.date(from: components),
               let range = calendar.range(of: .day, in: .month, for: date) {
                lengths[month] = range.count
            }
        }
        return lengths
    }

    private func daysIn(_ month: Int) -> Int {
        monthLengths[month] ?? 31
    }

    /// 月日 → 统计。键是 `month * 100 + day`，比字符串拼接省一次分配。
    /// 手写循环而不是 `Dictionary(uniqueKeysWithValues:)`：后者遇到重复 key 直接崩。
    private var statByDate: [Int: WidgetDayStat] {
        var map: [Int: WidgetDayStat] = [:]
        for stat in snapshot.yearDays { map[stat.key] = stat }
        return map
    }

    private var largeStats: some View {
        HStack(spacing: 0) {
            statCell("今日到件", snapshot.pendingTodayCount, AppTheme.todayTint)
            statDivider
            statCell("待取", snapshot.pendingTotal, AppTheme.pendingTint)
            statDivider
            statCell("已取", snapshot.pickedTodayCount, AppTheme.doneTint)
        }
    }

    private func statCell(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: metrics.sc(3)) {
            Text(title)
                .font(.system(size: metrics.sc(11)))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(value)")
                .font(.system(size: metrics.sc(30), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 0.5, height: metrics.sc(28))
    }

    // MARK: 窄画布（小尺寸）

    private var narrowLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("取件进度")
                    .font(.system(size: metrics.sc(11), weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                // 今日到件塞进标题行右侧：底部只有 126pt，三个数字挤一行必然被截
                Text("今日 \(snapshot.pendingTodayCount)")
                    .font(.system(size: metrics.sc(11), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.todayTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 3)

            HStack {
                Spacer(minLength: 0)
                ring
                Spacer(minLength: 0)
            }

            Spacer(minLength: 3)

            HStack(spacing: 0) {
                legend("待取", snapshot.pendingTotal, AppTheme.pendingTint)
                Spacer(minLength: 6)
                legend("已取", snapshot.pickedTodayCount, AppTheme.doneTint)
            }
        }
    }

    // MARK: 宽画布（中尺寸）

    /// 🔴 2026-11-22 老大：「将今日到件改左边，取件进度放在右边」——
    ///    与原来的「环在左、数字在右」正好对调。改的是**阅读起点**：
    ///    先看今天到了几件（今天的量），再看取走几成（今天的进度），
    ///    和中文「先量后率」的习惯一致。
    private var wideLayout: some View {
        HStack(alignment: .center, spacing: metrics.sc(16)) {
            VStack(alignment: .leading, spacing: metrics.sc(3)) {
                Text("今日到件")
                    .font(.system(size: metrics.sc(11), weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: metrics.sc(3)) {
                    Text("\(snapshot.pendingTodayCount)")
                        .font(.system(size: metrics.sc(34), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        // 橙 = App 里的「今日新增」，与统计页同一个语义色
                        .foregroundStyle(AppTheme.todayTint)

                    Text("件")
                        .font(.system(size: metrics.sc(12), weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: metrics.sc(12)) {
                    legend("待取", snapshot.pendingTotal, AppTheme.pendingTint)
                    legend("已取", snapshot.pickedTodayCount, AppTheme.doneTint)
                }
                .padding(.top, metrics.sc(2))
            }

            Spacer(minLength: 0)

            ring
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: 零件

    private var ring: some View {
        let diameter = metrics.sc(isLarge ? 96 : (isWide ? 78 : 60))
        let lineWidth = metrics.sc(isLarge ? 10 : (isWide ? 9 : 7))

        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: lineWidth)

            Circle()
                // 0 时也留一丝：空环 + 一个点，看起来是「还没开始」，
                // 而不是「这个组件坏了」。
                .trim(from: 0, to: max(0.015, ratio))
                .stroke(AppTheme.doneTint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(size: metrics.sc(isLarge ? 21 : (isWide ? 19 : 15)),
                                  weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("已取")
                    .font(.system(size: metrics.sc(isLarge ? 10 : (isWide ? 9 : 8))))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func legend(_ title: String, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: metrics.sc(6), height: metrics.sc(6))
            Text(title)
                .font(.system(size: metrics.sc(11)))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: metrics.sc(13), weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        // 大画布上「待取 14」曾被压成「待 1」—— 这里必须允许缩得更狠
        .minimumScaleFactor(0.5)
    }
}


/// 「最近一件」：只放一件，取件码放到最大。
///
/// 用的还是列表第 1 条 —— 排序已经按「驿站 → 取件码」排过，
/// 第 1 条就是用户最可能去取的那件，不需要另算一套推荐逻辑。
struct WidgetFocusCodeContent: View {
    let snapshot: WidgetSnapshot
    /// 当前画布的尺寸口径（小 / 中 / 大共用一个版式）。
    var metrics: WidgetHeroMetrics = .small

    private var record: PickupRecord? { snapshot.items.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "qrcode")
                    .font(.system(size: metrics.sc(10), weight: .semibold))
                Text("最近一件")
                    .font(.system(size: metrics.sc(12), weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 2)

            if let record {
                record.emphasizedCodeText(tint: record.codeColor)
                    // 22pt 是「一个码占满一行」的字号：15 位运单号会缩到 ~13pt，
                    // 短码（C-4082）保持 22pt —— 单码款的价值就在这个「大」。
                    .font(.system(size: metrics.sc(22), weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)

                if let subtitle = subtitle(of: record) {
                    Text(subtitle)
                        .font(.system(size: metrics.sc(10)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 4)

            WidgetHairline()

            Text(remainingText)
                .font(.system(size: metrics.sc(11), weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 驿站优先（去哪个门），没有驿站退到快递公司；都没有就不画这一行。
    private func subtitle(of record: PickupRecord) -> String? {
        let station = PickupSortLogic.stationName(of: record)
        if station != PickupSortLogic.noStation { return station }
        let company = PickupSortLogic.companyName(of: record)
        return company.isEmpty ? nil : company
    }

    private var remainingText: String {
        let rest = snapshot.pendingTotal - 1
        return rest > 0 ? "还有 \(rest) 件待取" : "就这一件"
    }
}

/// 「驿站分布」：哪个驿站还压着几件。
///
/// 小尺寸只有 3 行位置：件数最多的 3 个驿站实名，尾巴并成「其他」
/// （`WidgetSnapshot.stationBreakdown` 已经把这一步算好了）。
struct WidgetStationBarsContent: View {
    let snapshot: WidgetSnapshot
    /// 当前画布的尺寸口径（小 / 中 / 大共用一个版式）。
    var metrics: WidgetHeroMetrics = .small

    private var rows: [StationCount] { Array(snapshot.stationCounts.prefix(3)) }
    private var peak: Int { max(1, rows.map(\.count).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("驿站分布")
                    .font(.system(size: metrics.sc(12), weight: .semibold))
                Spacer(minLength: 0)
                Text("\(snapshot.pendingTotal)")
                    .font(.system(size: metrics.sc(11), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.pendingTint)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: metrics.sc(7)) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(row.name)
                                .font(.system(size: metrics.sc(10), weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 2)

                            Text("\(row.count)")
                                .font(.system(size: metrics.sc(10), weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.accent)
                        }

                        // 条形：宽度按「相对最多的那个驿站」算，不是按总数 ——
                        // 按总数算的话 14 件里 5 件的条只有三分之一长，读不出差距。
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.14))
                                Capsule()
                                    .fill(AppTheme.accent.opacity(0.85))
                                    .frame(width: max(3, proxy.size.width
                                                      * CGFloat(row.count) / CGFloat(peak)))
                            }
                        }
                        .frame(height: metrics.sc(3))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「最久未取」：压了几天 + 那一件的取件码。
///
/// 为什么值得单独做一款：待取清单里所有件长得一样，只有这一款会告诉用户
/// 「有一件已经压了三天」—— 这是唯一会「过期」的信息，越晚看越没用。
struct WidgetOldestPendingContent: View {
    let snapshot: WidgetSnapshot
    /// 当前画布的尺寸口径（小 / 中 / 大共用一个版式）。
    var metrics: WidgetHeroMetrics = .small

    private var record: PickupRecord? { snapshot.oldestPending ?? snapshot.items.last }

    private var ageDays: Int {
        guard let record else { return 0 }
        return Calendar.current.dateComponents([.day], from: record.receivedAt, to: .now).day ?? 0
    }

    private var ageHours: Int {
        guard let record else { return 0 }
        return Calendar.current.dateComponents([.hour], from: record.receivedAt, to: .now).hour ?? 0
    }

    /// 不到一天用小时 —— 显示「0 天」等于说「刚到的」，那就不叫最久了。
    private var value: Int { ageDays >= 1 ? ageDays : max(1, ageHours) }
    private var unit: String { ageDays >= 1 ? "天" : "小时" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: metrics.sc(10), weight: .semibold))
                Text("最久未取")
                    .font(.system(size: metrics.sc(12), weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 2)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: metrics.sc(40), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(AppTheme.amber)
                Text(unit)
                    .font(.system(size: metrics.sc(12), weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let record {
                record.emphasizedCodeText(tint: record.codeColor)
                    .font(.system(size: metrics.sc(16), weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                if let station = stationName(of: record) {
                    Text(station)
                        .font(.system(size: metrics.sc(10)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stationName(of record: PickupRecord) -> String? {
        let name = PickupSortLogic.stationName(of: record)
        return name == PickupSortLogic.noStation ? nil : name
    }
}

// MARK: - 取件码卡片（2026-11-22 合并「单个取件码」+「一键拷贝」）

/// 一款卡片同时做两件事：**一件一件翻着看** + **右上角一键复制**。
///
/// 🔴 主人 2026-11-22 晚：「单个取件码的小组件可以和一键拷贝的小组件组合成一个，
///    然后把这个内容的不做大尺寸的，不然太浪费了」——
///    看码和拷贝本来是同一次动作的两半，拆成两条等于让用户在图库里二选一；
///    而大尺寸那块画布放一张卡片，四周全是空的，确实浪费。
///
/// 版式（主人逐行指定，2026-11-22 晚定稿）：
///   · 中画布：第一行 快递公司 ｜ 快递驿站；第二行 公司图标 + 大号取件码；第三行 取件地址；
///     **底部**横排「上一个 / 第几件 / 下一个」；**右上角**复制按钮，其**正下方**是勾选框。
///   · 小画布：图标退到**左上角**，复制与勾选**并排在右上**；下面是码、地址、底部切换。
///
/// ⚠️ 平台边界：WidgetKit 不支持文本选择，所谓"拷贝"只能做成「轻点复制」，
///    反馈靠 `WidgetActionBridge.justCopied` + 立刻重画（3 秒后恢复）。
struct WidgetCodeCardContent: View {
    let snapshot: WidgetSnapshot
    /// 当前画布的尺寸口径（小 / 中共用这一份版式）。
    var metrics: WidgetHeroMetrics = .small

    private var limit: Int { snapshot.items.count }
    private var index: Int { WidgetSingleCursor.index(limit: limit) }
    private var record: PickupRecord? {
        guard limit > 0 else { return nil }
        return snapshot.items[index]
    }
    private var canStepBack: Bool { index > 0 }
    private var canStepForward: Bool { index < limit - 1 }
    private var copied: Bool { record.map { WidgetActionBridge.justCopied($0.code) } ?? false }

    /// 小画布（158pt）：宽度只够一行字，第一行就只放「驿站，没有则公司」。
    ///
    /// 🔴 中尺寸按主人要求「驿站 ｜ 公司」并排；但 126pt 可用宽里并排放两个名字，
    ///    两边都会被截成「兔喜…」—— 那不是信息，是噪音。
    private var isCompact: Bool { metrics.scale <= 1.01 }

    var body: some View {
        Group {
            if let record {
                content(record)
            } else {
                emptyLabel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(_ record: PickupRecord) -> some View {
        if isCompact {
            compactContent(record)
        } else {
            regularContent(record)
        }
    }

    /// 没有待取件时的占位（不再给「语音添加」留入口，那一整块功能已按主人要求删除）。
    private var emptyLabel: some View {
        VStack(spacing: metrics.sc(6)) {
            Image(systemName: "shippingbox")
                .font(.system(size: metrics.sc(18), weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.5))

            Text("没有待取的件")
                .font(.system(size: metrics.sc(10.5)))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 小画布（126pt 可用宽）：**图标在左上角**，复制与勾选并排在右上角，切换按钮在底部。
    ///
    /// 🔴 宽度预算（126pt）：图标 17 + 名字 + 复制 22（热区 30）+ 勾选 20（热区 28）
    ///    = 固定部分 99pt，名字只剩 ~27pt —— 所以名字用 10.5pt + `minimumScaleFactor(0.7)`，
    ///    宁可整体缩一号，也不要出现「兔…」这种只剩一个字的名字。
    private func compactContent(_ record: PickupRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.sc(4)) {
                logo(record, size: metrics.sc(17))

                Text(nameText(record))
                    .font(.system(size: metrics.sc(10.5), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)

                Spacer(minLength: metrics.sc(2))

                copyButton(record, size: metrics.sc(22))
                checkCircle(record, size: metrics.sc(20), hit: metrics.sc(28))
            }

            Spacer(minLength: metrics.sc(4))

            codeText(record)

            if let address = addressText(record) {
                Text(address)
                    .font(.system(size: metrics.sc(9.5)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, metrics.sc(2))
            }

            Spacer(minLength: 0)

            pager
        }
    }

    /// 中画布（348×170）：公司｜驿站 → 图标 + 大码 → 地址 → 底部切换；
    /// 右上角是复制，复制**下方**是勾选（主人指定：中尺寸勾选框放在复制按钮下面）。
    private func regularContent(_ record: PickupRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(record)
                // 给右上角那两个按钮让位，长名字不要跑到按钮底下
                .padding(.trailing, metrics.sc(38))

            Spacer(minLength: metrics.sc(5))

            // 第二行：公司图标 + 大号取件码（中尺寸图标稍大，与 22pt 的码视觉同高）
            HStack(spacing: metrics.sc(8)) {
                logo(record, size: metrics.sc(26))

                codeText(record)
            }

            if let address = addressText(record) {
                Text(address)
                    .font(.system(size: metrics.sc(9.5)))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, metrics.sc(3))
            }

            Spacer(minLength: metrics.sc(4))

            pager
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: metrics.sc(6)) {
                copyButton(record, size: metrics.sc(26))
                checkCircle(record, size: metrics.sc(24))
            }
        }
    }

    // MARK: 零件

    /// 第一行（中画布）：**快递公司 ｜ 快递驿站**。
    ///
    /// · 缺一项就不画分隔线，两项都没有退到「取件码」；
    /// · 两者同名（很多驿站就叫「菜鸟驿站」、承运方也是它）只显示一次，
    ///   不要「兔喜生活 ｜ 兔喜生活」这种把同一句话说两遍的排版。
    private func header(_ record: PickupRecord) -> some View {
        let naming = record.naming(station: record.station)
        let primary = naming.primary
        let secondary = naming.secondary

        return HStack(spacing: metrics.sc(5)) {
            Text(primary.isEmpty ? "取件码" : primary)
                .font(.system(size: metrics.sc(11), weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let secondary, !secondary.isEmpty, secondary != primary {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1, height: metrics.sc(9))

                Text(secondary)
                    .font(.system(size: metrics.sc(11), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
    }

    /// 小画布第一行只放一个名字（126pt 并排放两个，两边都会被截成「兔喜…」）。
    private func nameText(_ record: PickupRecord) -> String {
        let naming = record.naming(station: record.station)
        for candidate in [naming.primary, naming.secondary ?? ""] where !candidate.isEmpty {
            return candidate
        }
        return "取件码"
    }

    /// 一条取件码的图标 —— **取自卡面第一段**（`PickupNaming.iconSource`，恒等于 `primary`）。
    ///
    /// 🔴 2026-11-22 主人定规：「图标就是当前显示在最前面的那一个（三个字段中谁在前面，
    ///    图标就显示谁的）」——App 内所有面统一走 `PickupIcon`（DesignSystem.swift）。
    ///    小组件是**独立进程**，读不到 `StationDirectory`（自定义驿站图 + `.standard` 偏好），
    ///    所以这里直接用 `CourierLogo` + `usesStaticAsset`；**取名口径完全一样**，
    ///    只是「用户自己上传的驿站图」这一路跨进程取不到，会退到品牌兜底（平台边界）。
    ///    ⚠️ 这里**不能**写 `record.company`：那是短信平台（拼多多），
    ///    「圆通发的、兔喜取的」会被画成拼多多 —— 2026-11-22 修过一次，别改回去。
    private func logo(_ record: PickupRecord, size: CGFloat) -> some View {
        CourierLogo(company: record.naming(station: record.station).iconSource,
                    size: size,
                    showsShadow: false,
                    usesStaticAsset: true)
    }

    /// 取件码本体（大号，长码靠 `minimumScaleFactor` 缩，不截断）。
    private func codeText(_ record: PickupRecord) -> some View {
        record.emphasizedCodeText(tint: record.codeColor)
            .font(.system(size: metrics.sc(24), weight: .bold, design: .rounded))
            .monospaced()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// 底部切换条：上一个 · 第几件 / 共几件 · 下一个。
    ///
    /// 🔴 2026-11-22 晚主人：「将切换按钮恢复为在底部的」——
    ///    之前挪到右侧竖排看着像"翻页器"，底部横排才与中尺寸列表的翻页控件同族。
    private var pager: some View {
        HStack(spacing: 0) {
            stepButton(.previous, enabled: canStepBack)

            Spacer(minLength: metrics.sc(4))

            Text("\(index + 1) / \(limit)")
                .font(.system(size: metrics.sc(9), weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: metrics.sc(4))

            stepButton(.next, enabled: canStepForward)
        }
    }

    /// 复制按钮（右上角）：只画图标 —— 角落位置给不了文字宽度，复制后变绿勾。
    private func copyButton(_ record: PickupRecord, size: CGFloat) -> some View {
        Button(intent: CopyPickupCodeIntent(code: record.code)) {
            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(copied ? AppTheme.doneTint : AppTheme.accent)
                .frame(width: size, height: size)
                .background((copied ? AppTheme.doneTint : AppTheme.accent).opacity(0.14),
                            in: .circle)
                // 视觉尺寸之外再放宽热区（小组件里的手指精度）
                .frame(width: size + 8, height: size + 8)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(copied ? "已复制取件码" : "复制取件码"))
    }

    /// 勾选框：轻点直接把这一件标记为已取（与桌面列表里的勾选动作同一个意图）。
    private func checkCircle(_ record: PickupRecord, size: CGFloat, hit: CGFloat = 32) -> some View {
        WidgetCheckCircle(isDone: false,
                          tint: record.codeColor,
                          recordID: record.id.uuidString,
                          size: size,
                          hitSize: hit)
    }

    /// 切换方向。按钮在底部横排 → 上一个朝左、下一个朝右。
    enum Step {
        case previous
        case next

        /// 游标位移。上一个 = 往回退一位（index - 1）。
        var delta: Int { self == .previous ? -1 : 1 }
        var symbol: String { self == .previous ? "chevron.left" : "chevron.right" }
        var actionTitle: String { self == .previous ? "上一个取件码" : "下一个取件码" }
        var edgeTitle: String { self == .previous ? "已经是第一个" : "已经是最后一个" }
    }

    /// 🔴 到头时**不画成 Button**，直接画一个置灰的图标：
    ///    `Button(intent:)` 没有可用的 `.disabled` 语义（意图是系统发起的），
    ///    画成按钮再加 `.disabled` 只是视觉置灰、系统照样执行，容易让人以为翻到循环了。
    @ViewBuilder
    private func stepButton(_ step: Step, enabled: Bool) -> some View {
        if enabled {
            Button(intent: WidgetSingleCodeStepIntent(delta: step.delta)) {
                Image(systemName: step.symbol)
                    .font(.system(size: metrics.sc(11), weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: metrics.sc(26), height: metrics.sc(20))
                    .background(AppTheme.accent.opacity(0.14), in: .capsule)
                    .frame(width: metrics.sc(34), height: metrics.sc(26))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.actionTitle)
        } else {
            Image(systemName: step.symbol)
                .font(.system(size: metrics.sc(11), weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.28))
                .frame(width: metrics.sc(26), height: metrics.sc(20))
                .background(Color.secondary.opacity(0.07), in: .capsule)
                .frame(width: metrics.sc(34), height: metrics.sc(26))
                .accessibilityLabel(step.edgeTitle)
        }
    }

    // MARK: 文案

    /// 驿站名。没有驿站返回 nil（这一行就不画它，也不画「未标注驿站」这种系统话）。
    private func stationText(_ record: PickupRecord) -> String? {
        let name = PickupSortLogic.stationName(of: record)
        return name == PickupSortLogic.noStation ? nil : name
    }

    private func companyText(_ record: PickupRecord) -> String? {
        let name = PickupSortLogic.companyName(of: record)
        return name.isEmpty ? nil : name
    }

    private func addressText(_ record: PickupRecord) -> String? {
        let address = record.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }
}

// MARK: - 动作型意图（拷贝）

/// 把取件码写进系统剪贴板。
///
/// ⚠️ `code` 必须是 `@Parameter`：`Button(intent:)` 会被系统归档成实例标识、
///    再在扩展进程里还原，只有 `@Parameter` 的属性会进归档（同一坑见 `WidgetPageIntent`）。
struct CopyPickupCodeIntent: AppIntent {
    static var title: LocalizedStringResource { "复制取件码" }

    /// 小组件内部指令，不进快捷指令 / 聚焦列表
    static var isDiscoverable: Bool { false }

    /// 纯后台：复制不该把 App 拉到前台（正好贴上「桌面顺手一拷」的用法）。
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "取件码")
    var code: String

    init() {}

    init(code: String) {
        self.code = code
    }

    func perform() async throws -> some IntentResult {
        UIPasteboard.general.string = code
        WidgetActionBridge.markCopied(code)
        // 重画一次，卡片立刻变成「已复制」——这是小组件能给的唯一反馈
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - 单码切换意图

/// 「单个取件码」的上一件 / 下一件。
///
/// 🔴 夹紧（clamp）而不是环形翻页：主人要「第一个时左键不可点、最后一个时右键不可点」，
///    环形的话按到头会突然跳回另一端，与置灰的按钮自相矛盾。
struct WidgetSingleCodeStepIntent: AppIntent {
    static var title: LocalizedStringResource { "切换取件码" }

    static var isDiscoverable: Bool { false }

    /// 纯后台：翻件不拉起 App
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "方向")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        // 条数**现数一遍**，不复用可视层传的值：期间用户可能已经取走几件，
        // 旧条数会让游标停在越界位置（画出来是空白）。
        // 用 `WidgetSnapshot.load().items` 而不是自己去 `PickupStorage` 过滤 ——
        // 那条链还含「一卡多码」的分组，与视图看到的行数才是同一个口径。
        let count = WidgetSnapshot.load().items.count
        guard count > 0 else { return .result() }

        let current = WidgetSingleCursor.index(limit: count)
        let next = min(max(0, current + delta), count - 1)
        WidgetSingleCursor.set(next)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - 单码游标（「单个取件码」那一款的翻页状态）

/// 「单个取件码」当前停在第几个。
///
/// 与 `WidgetPaging` 分开存：那是**列表类**款式按尺寸共享的页码，这一款是
/// 「一件一件看」的游标，两者混用的话，用户在中尺寸翻到第 2 页会把小尺寸的单码
/// 也带到第 2 件 —— 两个完全不相关的界面互相干扰。
enum WidgetSingleCursor {
    private static let key = "codelumi.widget.singleIndex"

    private static var store: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    /// 读当前位次，**按实际条数夹紧** —— 取走一件之后条数变少，
    /// 旧游标可能越界（画出来会是一片空白）。
    static func index(limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        return min(max(0, store.integer(forKey: key)), limit - 1)
    }

    static func set(_ value: Int) {
        store.set(value, forKey: key)
    }
}

// MARK: - 单行（中尺寸）

struct WidgetPickupRow: View {
    let record: PickupRecord
    /// 二级信息行的显示项。`.full` = 平台｜地址（改版前版式）。
    var options: WidgetDisplayOptions = .full
    /// 同一条短信里的其它取件码（2026-11-16）。空 = 一行一码，版式零变化。
    var extraCodes: [String] = []

    var body: some View {
        HStack(spacing: 8) {
            // 行首圆形勾选框：与 App 内 CompleteButton 同款视觉，可直接点
            WidgetCheckCircle(isDone: false,
                              tint: record.codeColor,
                              recordID: record.id.uuidString,
                              size: 21)

            VStack(alignment: .leading, spacing: 2) {
                // 第一行：取件码（主角）+ 柜位 + 必要的类别标签
                HStack(spacing: 5) {
                    record.emphasizedCodeText(tint: record.codeColor)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    // 柜位 / 货架（2026-10-27 主人）：有就显示，没有就空着。
                    // 它是到柜那一刻要用的信息，紧跟取件码最省眼动。
                    if let spot = record.widgetLockerLabel(options) {
                        Text(spot.L)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // 🔴 2026-11-16「一张卡片多个取件码」：中尺寸一行高度固定，
                    //    多出来的码用 12pt 跟在主码后面，不另起一行（会把行高撑破）。
                    //    仍走 `PickupCodeEmphasis.text`，颜色 / 透明度与 App 全端统一。
                    ForEach(extraCodes, id: \.self) { code in
                        PickupCodeEmphasis.text(code, tint: record.codeColor)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospaced()
                            .lineLimit(1)
                    }

                    // 🔴 类型标签全部去掉（2026-10-27 主人：「运单号、尾号、特殊码也不要了，
                    // 是哪个类型对用户没啥意义」）。小组件里这行的宽度要全留给
                    // 取件码和柜位，标签占位不划算；类型信息在详情页仍可查。
                }

                // 第二行：按显示设置拼（可能是「平台｜地址」「只有平台」「整行不画」）。
                // 取件码那行不动 —— 它不参与配置。
                if let subtitle = record.widgetSubtitle(options) {
                    Text(subtitle.L)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            Text(record.clockTime.L)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - 空槽（已删除 · 2026-11-22）
//
// 这里原有 `WidgetPlaceholderRow`：数据不足一页时补几行灰色骨架，
// 向用户传达「就这些了」。重构款式后整块退场，理由写在
// `WidgetPagedContent` 的 body 里（固定版式下留白比伪造行更诚实）。

// MARK: - 版式分发（桌面与 App 内预览共用同一份）

/// 按款式版式 + 尺寸把内容画出来。
///
/// 🔴 **桌面（`PickupWidgetEntryView`）与 App 内预览（`WidgetPresetContent`）都走这里** ——
///    两处各写一遍必然漂移，漂移出来就是「设置页看着好好的、桌面却不一样」。
///
/// 尺寸口径：
///   · 清单款 —— 小尺寸 `WidgetSmallContent`（4 条 / 3 条），中以上 `WidgetPagedContent`；
///   · 非清单版式 —— 同一份版式 + `WidgetHeroMetrics`（小 1 / 中 1.2 / 大 1.75）。
struct WidgetLayoutContent: View {
    let preset: WidgetPreset
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    /// 分页键与每页条数（中 / 大 / 超大不同，由调用方按真实画布算好传进来）。
    var pageKey: String = "medium"
    var pageSize: Int = WidgetPageSize.rowCount(family: "medium")
    /// 显示选项：清单款跟用户在详情页的开关，非清单版式不看这个值。
    var options: WidgetDisplayOptions? = nil

    private var resolvedOptions: WidgetDisplayOptions { options ?? preset.options }

    var body: some View {
        switch preset.layout {
        case .list:
            if family == .systemSmall {
                WidgetSmallContent(snapshot: snapshot, options: resolvedOptions)
            } else {
                WidgetPagedContent(snapshot: snapshot,
                                   pageSize: pageSize,
                                   familyKey: pageKey,
                                   options: resolvedOptions)
            }
        case .todayProgress: WidgetTodayProgressContent(snapshot: snapshot, metrics: metrics)
        case .focusCode:     WidgetFocusCodeContent(snapshot: snapshot, metrics: metrics)
        case .stationBars:   WidgetStationBarsContent(snapshot: snapshot, metrics: metrics)
        case .oldestPending: WidgetOldestPendingContent(snapshot: snapshot, metrics: metrics)
        case .codeCard:      WidgetCodeCardContent(snapshot: snapshot, metrics: metrics)
        }
    }

    private var metrics: WidgetHeroMetrics { .forFamily(family) }
}

// MARK: - 空态

struct WidgetEmptyContent: View {
    let pickedTodayCount: Int
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(AppTheme.doneTint.opacity(0.15))
                    .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: compact ? 18 : 22))
                    .foregroundStyle(AppTheme.doneTint)
            }

            Text("暂无待取件")
                .font(.system(size: compact ? 12.5 : 13.5, weight: .semibold))

            if !compact {
                // 有成绩先报成绩，没有才铺引导语 —— 空态里最想知道的是「之前那些怎么样了」。
                Text(pickedTodayCount > 0
                     ? "今天已取 \(pickedTodayCount) 件"
                     : "收到取件短信后会自动出现在这里")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 大尺寸未解锁占位（免费档）

/// 免费档用户添加了大尺寸小组件时的占位内容（2026-11-11 内测反馈修复）。
///
/// 背景：尺寸集自 2026-11-11 起固定为「全部」，不能按购买状态动态增减
/// （WidgetKit 注册时缓存，买完 Pro 也不会变大）。免费用户在大尺寸里看到
/// 这块占位；购买 Pro 后重新取时间线即渲染真实内容。
struct WidgetLockedContent: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text("Codelumi Pro")
                .font(.system(size: 14, weight: .semibold))
            Text("大尺寸以上需解锁 Codelumi Pro")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 勾选意图（桌面直接标记「已取」）
//
// 用途：小组件每行取件码前的圆形勾选框是一个可点击按钮，点击即把该条标记为已取，
// 不需要打开 App —— iOS 17+ 允许小组件内的 Button(intent:) 直接执行 AppIntent。
//
// 架构说明：本条是「小组件只读」原则的**唯一例外**。理由是该操作不产生新数据、
// 不跑正则、只翻转一个既有字段，并且用户预期桌面上的勾选框与 App 内行为一致
// （点不动会被当成故障）。写回的仍是 App Group 共享 JSON，与主 App 同一份。
//
// ⚠️ 主 App 侧配套：小组件改文件时主 App 可能正在后台持有内存副本，
//    因此 CodelumiApp 在回到前台（scenePhase == .active）时会重新读盘，
//    避免出现「桌面已勾、App 里还没勾」的两份状态。

struct TogglePickupIntent: AppIntent {
    static var title: LocalizedStringResource { "标记取件状态" }

    /// 不出现在「快捷指令 / 聚焦」的意图列表里：这是小组件内部指令，
    /// 用户手动编排快捷指令时看到「标记取件状态」只会造成困惑。
    static var isDiscoverable: Bool { false }

    /// 只支持后台执行：点勾选框只是翻一个字段，绝不把 App 拉到前台。
    /// 🔴 部署目标降到 iOS 18：`IntentModes`（含 `.background`）是 iOS 26 新增。
    ///    改用等价的 `openAppWhenRun = false`（iOS 16 起可用）：后台执行、不拉起 App。
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "记录 ID")
    var recordID: String

    init() {}

    init(recordID: String) {
        self.recordID = recordID
    }

    func perform() async throws -> some IntentResult {
        var all = PickupStorage.load()
        guard let index = all.firstIndex(where: { $0.id.uuidString == recordID }) else {
            return .result()
        }
        // 🔴 2026-11-16 状态回滚专项：**必须与 App 侧 `setPicked` 同一口径**，
        //    三个字段成对改。以前漏了 `updatedAt`，后果是 iCloud 合并 / 任何按
        //    时间戳的对齐都把这次改动判成「旧数据」，桌面刚点的完成被抹回去。
        let stamp = Date()
        let picked = !all[index].isPickedUp

        // 🔴 2026-11-16「一张卡片多个取件码」：桌面上勾一行 = 勾这一整张卡。
        //    App 里 `rowChrome` 也是整组动作，两边必须一致；否则小组件勾掉一个码，
        //    App 里那张卡还挂着两个码，其中一个已经「已取」，状态看着自相矛盾。
        var targets: [Int] = [index]
        if CodeAppearanceSettings.groupsMultipleCodes,
           let key = PickupRecordGrouping.key(all[index]) {
            targets = all.indices.filter { PickupRecordGrouping.key(all[$0]) == key }
        }
        var changedIDs: [UUID] = []
        for i in targets {
            all[i].isPickedUp = picked
            // 时间戳与状态成对改（口径同 App 侧 `PickupStore.setPicked`）：
            // 桌面上点的这一下同样是真实的取件时刻，统计页要认它。
            all[i].pickedUpAt = picked ? (all[i].pickedUpAt ?? stamp) : nil
            all[i].updatedAt = stamp
            changedIDs.append(all[i].id)
        }

        // ① 先把完整状态落进共享文件 —— 小组件 UI 的即时反馈靠的就是这份数据
        PickupStorage.save(all)
        // ② 再追加几十字节的增量标记作为护栏：主 App 后台若持有旧的内存副本，
        //    下一次 `load()` 仍会把这些状态重放回来，不会被整份覆盖掉。
        //    两步都是本机 atomic 文件写，无网络、无等待，点击响应不变慢。
        for id in changedIDs {
            WidgetToggleJournal.append(id: id, picked: picked, at: stamp)
        }
        // 立即重画，否则要等系统下一个刷新周期才看到勾选结果
        WidgetCenter.shared.reloadAllTimelines()
        // 锁屏实时活动必须同步跟上：这个意图跑的进程**不一定是 App**
        // （点小组件上的勾选框时是扩展进程），App 的 store 根本不会醒，
        // 所以这里直接推一次 —— 否则锁屏会一直挂着那条已经被取走的码。
        PickupActivityController.sync(pending: all.filter { !$0.isPickedUp })
        return .result()
    }
}

// MARK: - 预览 / 占位用示例数据
//
// 服务于四处：小组件坑位（placeholder）、小组件图库预览、App 内预览页的兜底、
// 以及三类新分类小组件的图库预览。放在共享层是因为 App target 也要用它。

extension WidgetSnapshot {
    /// 示例数据。**14 条**：既够「竖版超大」铺满一页（14 行/页），
    /// 又超过其它尺寸的一页（中 3 / 大 6），翻页控件也能被看到。
    /// 前两条压测两个极端 —— 最长凭证（15 位运单号）与最长标签（「特殊取件码」）
    /// 同时出现时仍要能单行排下。
    static var samples: [PickupRecord] {
        let now = Date()
        /// `locker` / `shelf` 是有意给值的（2026-10-27）：
        /// 设置页新增了「显示快递柜/货架」开关，示例数据若全是空的，
        /// 用户打开这个开关会看不出任何变化 —— 预览要能证明开关有用。
        /// 第 1 条演示柜口、第 5 条演示货架（驿站场景没有柜，走货架兜底）。
        func record(_ company: String, _ code: String, _ kind: PickupKind,
                    _ address: String, _ minutesAgo: Int,
                    message: String = "",
                    shelf: String? = nil, locker: String? = nil) -> PickupRecord {
            PickupRecord(company: company, code: code, kind: kind, address: address,
                         rawMessage: message.isEmpty ? "【\(company)】取件码 \(code)" : message,
                         receivedAt: now.addingTimeInterval(-Double(minutesAgo) * 60),
                         shelf: shelf, locker: locker)
        }

        return [
            record("兔喜生活", "C-4082", .code, "恒大御府南门西侧3栋104号", 26,
                   locker: "2号柜"),
            // 第 2 条刻意让「短信平台」与「驿站」不同（韵达发的件放在菜鸟驿站）：
            // 这样预览里能同时看到「韵达快递｜菜鸟驿站｜地址」三段，
            // 证明公司 / 驿站 / 地址是三个独立字段，不是同一个值换皮。
            record("韵达快递", "313105790279994", .waybill, "馨月湖小区南门兴裕隆超市", 95,
                   message: "【韵达快递】您的包裹已到菜鸟驿站，运单号313105790279994，请凭取件码领取"),
            record("申通快递", "3-7-12", .special, "馨月湖小区北门申通驿站", 130),
            record("菜鸟驿站", "6602", .tail, "恒大御府东门菜鸟驿站", 185),
            record("中通快递", "78-2-3051", .code, "馨月湖小区西门中通超市", 240,
                   shelf: "12-3"),
            record("顺丰速运", "SF1357902468", .waybill, "万寿街顺丰营业点", 310),
            record("圆通速递", "9-3-118", .code, "河西学院北门圆通妈妈驿站", 400),
            record("极兔速递", "JT9901", .code, "新墩镇便民超市", 520),
            // 下面 6 条是为「竖版超大 14 条/页」补的（2026-10-28）：
            // 一页 14 行才看得出这一档到底挤不挤，8 条永远只有半屏。
            // 公司、凭证形态（码/尾号/运单号）、柜口/货架都换着给，避免整页看起来一样。
            record("京东物流", "JD8812", .code, "恒大御府北门京东驿站", 640),
            record("中国邮政", "11185", .tail, "新墩镇邮政代办点", 760),
            record("德邦快递", "DB7745", .code, "万寿街德邦营业部", 880, shelf: "3-2"),
            record("丰巢智能柜", "HL-3021", .code, "恒大御府东门丰巢柜", 1000, locker: "8号柜"),
            record("天猫超市", "TM5540", .code, "馨月湖小区北门天猫驿站", 1180),
            record("极兔速递", "JT2088", .tail, "河西学院东门极兔驿站", 1360),
        ]
    }

    /// 顶部「效果预览」专用：只给 2 条 —— 中尺寸一页 3 行，
    /// 第 3 行正好是空位，用来演示「显示占位符」开关的效果（2026-11-14 主人）。
    static func previewTwoRows() -> WidgetSnapshot {
        let visible = Array(samples.prefix(2))
        return WidgetSnapshot(items: visible,
                              pendingTotal: 2,
                              pickedTodayCount: 0,
                              pendingTodayCount: 1,
                              stationCounts: WidgetSnapshot.stationBreakdown(of: visible),
                              oldestPending: visible.last)
    }

    /// 预览快照（App 内「桌面小组件」页与 `SCREEN=widgets`）。
    ///
    /// 🔴 2026-10-30：**按档位裁**。免费档桌面本来就只看得到 3 条，
    ///    预览却铺 10 条还带翻页控件，等于给人看一个自己用不上的形态。
    ///    `PRO` 环境变量（`0` / `1`）可强制档位 —— 命令行没法改真实权益文件，
    ///    要靠它一次拍出「免费 / 买断」两种观感（`tools/widget-shots.sh` 用它）。
    static func preview() -> WidgetSnapshot {
        let forced = ProcessInfo.processInfo.environment["PRO"]
        let isPro = forced == "1" ? true
            : forced == "0" ? false
            : EntitlementSnapshot.licensedPro
        let visible = isPro ? samples : Array(samples.prefix(PickupLimits.freeVisible))

        return WidgetSnapshot(items: visible,
                              // 头部数字用**真实总数**，与线上口径一致：
                              // 免费档也要显示「还有 7 件」，否则会被读成"一共就 3 件"。
                              pendingTotal: samples.count,
                              pickedTodayCount: 2,
                              // 非列表那几款（今日到件 / 驿站分布 / 最久未取）要的口径，
                              // 一律按**完整样本**算，不按裁过的 `visible` ——
                              // 否则免费档预览里「驿站分布」只有 4 件，看着像坏了。
                              pendingTodayCount: 3,
                              stationCounts: WidgetSnapshot.stationBreakdown(of: samples),
                              oldestPending: samples.last,
                              // 大画布「取件进度」的日历：不补这份示例，
                              // 图库里预览永远是一片浅灰点，看不出深浅规则
                              yearDays: previewYearDays(),
                              todayMonth: Calendar.current.component(.month, from: Date()),
                              todayDay: Calendar.current.component(.day, from: Date()))
    }

    /// 热力图示例：铺开过去半年，把几种状态都摆出来 —— 今天有未取、昨天全取完、
    /// 某天积压 4 件、大片没件的天（浅灰）。数值与上面 `pendingTodayCount: 3` /
    /// `pickedTodayCount: 2` 对得上（今天收到 4 件、取走 1 件、还剩 3 件待取）。
    private static func previewYearDays() -> [WidgetDayStat] {
        let calendar = Calendar.current
        let now = Date()
        // (几天前, 当天收到几件, 其中未取几件)
        let offsets: [(Int, Int, Int)] = [
            (0, 4, 3), (1, 2, 0), (2, 5, 3), (3, 1, 1), (5, 4, 0),
            (7, 2, 2), (9, 6, 4), (12, 1, 0), (15, 3, 1), (18, 2, 0),
            (21, 5, 2), (25, 3, 0), (30, 2, 1), (36, 4, 4), (44, 1, 0),
            (52, 6, 2), (61, 2, 0), (73, 3, 1), (86, 1, 0), (95, 5, 3),
            (110, 2, 0), (124, 4, 1), (140, 3, 0), (155, 2, 2),
        ]
        var stats: [WidgetDayStat] = []
        for (back, total, pending) in offsets {
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            let parts = calendar.dateComponents([.month, .day], from: date)
            guard let month = parts.month, let day = parts.day else { continue }
            stats.append(WidgetDayStat(month: month, day: day, total: total, pending: pending))
        }
        return stats
    }
}
