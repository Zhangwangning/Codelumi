import SwiftUI

// MARK: ============================================================================
// 版本历史（「我的 › 关于 › 版本」点开的二级页）
//
// 2026-09-24 主人要求：把从 0 到现在的开发历程按版本总结，点版本号进来能看
// 每个版本的成果。
//
// 版式 = 时间线：左侧一条竖线串起各版本节点，当前版本（列表首项）用主题色
// 圆点 + 「当前版本」徽章高亮，历史版本灰点。每个版本一张卡：
//   版本号（大字等宽）· 日期 · 主题一句话 · 成果条目列表。
//
// 2026-11-15 主人：「内测版本你可以写更新内容，但是后面的内测号 309、312 等也要
// 跟上，你把 1.0.0 的内测版本各版本内容也添加到版本历史页面中」。
//   → 1.0.0 卡片底部挂一个**可折叠的内测记录区**（默认收起，全铺开会把整页
//     拉到几万点高）。数据在 `BetaBuildLog.swift`，本页只负责画。
//   → 有折叠态就必须有 @State 了（`expandedBeta`），不再是纯静态页。
//
// 🔴 本页文案是**工作产出**，口径与对外承诺一致：
//   · 不出现「主人」等对话称呼；
//   · 不写内测阶段的功能许诺，只写已经落地的成果。
//
// 🔴 2026-11-21 整页文案精简（用户原话，这是本页最重要的写作原则）：
//   「我是开发者，App 中的更新内容不是给我看的，是给用户看的，所以要精简，要有重点，
//     而不是长篇大论，告诉用户哪里有优化就行了」。
//   → 每个版本 2–7 条，**一条一句话**，只说「你现在能干什么 / 哪里变好了」；
//   → 不写实现：不出现 pt 数值、线程、字段名、「作用于当前可见集合（搜索、排序之后）」
//     这类只有写代码的人关心的定语；
//   → 已被移除的功能（纪念票、第三方模型通道、iPad 分栏）只留一句史实，不展开。
//   → 1.0.0 由 34 条降到 7 条，全页约 200 条降到 74 条。
// ============================================================================

struct VersionHistoryView: View {
    private struct Entry: Identifiable {
        let version: String
        let date: String
        let theme: String
        let highlights: [String]
        /// 这一版的内测构建记录（默认空 = 没有内测区）。目前只有 1.0.0 有。
        var beta: [BetaBuild] = []

        /// 🔴 身份必须用**版本号**，不能用 `UUID()`：
        /// `entries` 是 struct 的存储属性，视图结构体每被重建一次就重新生成一批 UUID，
        /// 而 `@State` 里的 UUID 是上一批的 —— 一改状态、外层 body 重算，
        /// `expandedBeta.contains(entry.id)` 就永远为假，表现为「点了展开又弹回去」。
        /// 版本号本来就是唯一的（1.0.0 那条重复的已合并），天然适合当身份。
        var id: String { version }
    }

    /// 展开了内测区的版本（按版本号记）。默认空 = 全部收起。
    @State private var expandedBeta: Set<String> = []

    /// 🔴 谁在最上面谁就是当前版本：不再手写 isCurrent，避免每发一版都要记得改上一个，
    ///    漏改就会出现两个"当前版本"（2026-11-05 主人发现 0.3.1 还挂着标记）。
    private func isCurrent(_ entry: Entry) -> Bool {
        entries.first?.id == entry.id
    }

    private let entries: [Entry] = [
        Entry(version: "1.0.0", date: "2026-11-14", theme: "首个正式版 · 定名 Codelumi（珞米）", highlights: [
            "支持 iOS 17 及以上的 iPhone，老系统也能装。",
            "新增 iCloud 同步（默认关闭）：记录存进你自己的 iCloud，多台设备自动合并，不经过开发者服务器。",
            "驿站按「一个取件地点」归组，待取页、已取页与桌面小组件共用同一套排序。",
            "待取页可以按快递驿站分组，到店一次取完；分组方式会记住。",
            "桌面小组件有 16 款：一张清单（小中大可就地换尺寸），加上取件进度、最近一件、驿站分布、最久未取、单个取件码各按尺寸分开；背景可以选真透明或液态玻璃。",
            "通知不再一直堆在通知中心：取件或删除后自动撤掉对应的那条。",
            "默认图标换成「黑盒立体」，十五套图标都能在设置里换。",
        ], beta: BetaBuildLog.all),
        Entry(version: "0.3.7", date: "2026-11-08", theme: "整套设置换成液态玻璃", highlights: [
            "设置整体换成液态玻璃；iOS 18 及以下自动用系统原生卡片，功能一致。",
            "语言直接在 App 内选：跟随系统 / 简体中文 / 繁體中文。",
            "「添加驿站」改成弹窗，不再为填一个名字跳一层页面。",
            "锁屏卡改成一页三条取件码，右侧翻页看更多。",
        ]),
        Entry(version: "0.3.6", date: "2026-11-05", theme: "解析更准 · 记住你写的地址", highlights: [
            "「正在派送」的短信不再当成已到达；「凭 848 取件」「编号 304」这类写法也能认出来。",
            "改过一次地址之后，同一驿站的后续短信自动用你写的那个，不用每次重改。",
            "390 条真实短信实测：快递短信一条不漏，非快递一条不收。",
            "新增「帮助改进」：可以添加样本帮我把识别做得更准，数据只在你点导出时才离开手机。",
        ]),
        Entry(version: "0.3.5", date: "2026-11-05", theme: "短信自动收录 · 关键词自动化", highlights: [
            "一键把「收到短信 → 添加到 App」导进系统快捷指令自动化，导入后打开开关即可。",
            "预设四个关键词，默认只推【，避免通知太吵。",
            "修好点通知打不开 App 的问题。",
        ]),
        Entry(version: "0.3.4", date: "2026-11-04", theme: "外观与字号可调 · 繁体中文", highlights: [
            "外观可固定浅色 / 深色，也能跟随系统。",
            "字体大小七档可调，列表、卡片、设置一起变。",
            "新增繁体中文界面，简体环境不受影响。",
        ]),
        Entry(version: "0.3.3", date: "2026-11-01", theme: "首次引导与数据安全", highlights: [
            "首次打开先读条款再进教程，之后不再出现。",
            "「清空已取件记录」要输入随机四位数字才执行，输错会换一个新数字。",
            "图标可换，默认「取件袋」；关于页顶部与灵动岛同步当前图标。",
            "新增「声明与免责」：来源、技术栈与联系方式写在一页里。",
        ]),
        Entry(version: "0.3.2", date: "2026-11-01", theme: "设置页重排 · 图标可换", highlights: [
            "设置页重排：根页面只留高频入口，「帮助与反馈」与「关于」各自独立成页。",
            "App 图标可换，桌面、多任务、通知与灵动岛一起跟随。",
            "实时活动里能直接预览灵动岛的展开与折叠，看到的就是真机渲染的样子。",
            "修好灵动岛折叠态的图标显示成灰色方块的问题。",
        ]),
        Entry(version: "0.2.8", date: "2026-10-30", theme: "实时活动预览改为真实渲染", highlights: [
            "设置里的实时活动预览改成 App 内真实渲染：换一条记录、条数变化都跟着变。",
            "预览配了浅色 / 深色两套真机机模，深色下不再拿浅色壁纸凑数。",
            "灵动岛描边与取件码同色，强度随壁纸亮度自动调整，深色壁纸上也清楚。",
        ]),
        Entry(version: "0.2.7", date: "2026-10-30", theme: "品牌定名 · 重复短信只更新时间", highlights: [
            // 史实：0.x 内测期英文名是 Codelumi，1.0.0 定名 Codelumi。
            // 这条**保留原名**，好让用户看懂更名链路（别顺手改成 Codelumi）。
            "品牌定名：中文名「拾码」、英文名 Codelumi。",
            "重复短信不再新增卡片：同一个码再收到时只刷新时间。",
            "快递公司名称归一到标准名（「申通」存为「申通快递」），列表、详情、小组件全链路一致。",
            "存量数据自动回填，重复记录与无效取件码一并清理。",
        ]),
        Entry(version: "0.2.6", date: "2026-10-28", theme: "只认取件码 · 锁屏换原生液态玻璃", highlights: [
            "取件码、运单号、尾号统一按取件码呈现，界面不再出现类别标签。",
            "锁屏实时活动改用系统原生液态玻璃，任何壁纸上都读得清。",
            "解析增强：精确格口、第 N 箱、地址重复词都能处理。",
        ]),
        Entry(version: "0.2.5", date: "2026-10-27", theme: "小组件改版与解析同步", highlights: [
            "小尺寸小组件一屏显示 4 条纯取件码，字号统一。",
            "小组件的显示内容可以逐项开关（地址 / 快递公司 / 驿站 / 快递柜）。",
            "新增快递柜格口识别（2号柜 / 12-34格口），与货架号分开显示。",
            "「乐苑圆通超市」这类店名不再被当成快递公司。",
        ]),
        Entry(version: "0.2.4", date: "2026-10-25", theme: "全量缺陷修复", highlights: [
            "详情页编辑后保存不生效，已修好。",
            "「货架号：5-12」「3号货架」等写法现在能正确解析。",
            "全新安装时锁屏与灵动岛不出卡，已修好。",
            "地图导航改用地点搜索定位，不再一律显示「无法解析该地址」。",
        ]),
        Entry(version: "0.2.3", date: "2026-10-20", theme: "详情页重构与卡片一致性", highlights: [
            "详情页顶部卡与首页卡口径统一：快递公司优先于短信平台。",
            "取件码颜色跟随快递公司，一页不再出现两种颜色。",
            "「取件平台」改名「短信平台」，一眼分清发信平台与承运快递。",
        ]),
        Entry(version: "0.2.2", date: "2026-10-19", theme: "待取卡布局 v2", highlights: [
            "待取卡重排：图标缩小进取件码行，文字左缘与图标齐平。",
            "勾选「已取」回到取件码行右端，点一下直接切换状态。",
            "长码整卡宽度显示，不再被截断。",
        ]),
        Entry(version: "0.2.1", date: "2026-10-14", theme: "四标签信息架构", highlights: [
            "信息架构改为 待取 / 已取 / 统计 / 设置 四个标签，各司其职。",
            "首次安装引导：三页上手教程，设置页可以重看。",
            "新增反馈入口，邮件自动附带版本号。",
        ]),
        Entry(version: "0.2.0", date: "2026-10-13", theme: "设计语言 v2", highlights: [
            "卡片圆角与投影升级，整体更有质感。",
            "待取页统计卡改成仪表盘大卡，数字一眼可见。",
            "分组标题加上彩色数量徽标。",
        ]),
        Entry(version: "0.1.9", date: "2026-10-13", theme: "末四位高亮", highlights: [
            "取件码末四位放大并用品牌色强调，报码时一眼锁定。",
            "货架号进小组件二级行，排在地址之前。",
        ]),
        Entry(version: "0.1.8", date: "2026-10-12", theme: "驿站归类与货架号", highlights: [
            "按驿站归类：待取件按取件地点聚拢，到店一次取完。",
            "新增货架号，从解析到卡片、详情、小组件全线支持。",
            "批量标记已取，误触 5 秒内可撤销。",
        ]),
        Entry(version: "0.1.7", date: "2026-10-11", theme: "左滑右滑统一", highlights: [
            "全 App 的左滑 / 右滑统一为系统原生操作，手感更稳、不再误触。",
            "分组标题保留状态区分，一眼看出哪些还没取。",
        ]),
        Entry(version: "0.1.6", date: "2026-10-10", theme: "长按景深菜单", highlights: [
            "长按卡片：界面后退虚化，卡片浮起并贴着卡弹出菜单。",
            "菜单动作齐备：复制 / 分享 / 编辑 / 删除。",
        ]),
        Entry(version: "0.1.5", date: "2026-10-08", theme: "统计并入浏览页", highlights: [
            "统计与浏览合并成一页：总览 + 取件频率 / 时段 / 各快递 / 取件效率，一屏看完。",
        ]),
        Entry(version: "0.1.4", date: "2026-09-28", theme: "电子纪念票", highlights: [
            "纪念票上线：火车 / 高铁 / 飞机 / 汽车 / 轮船五类票面，分享可出真实票面长图。",
            "（该功能已于 0.2.1 移除，产品聚焦取件码）",
        ]),
        Entry(version: "0.1.3", date: "2026-09-24", theme: "多选分享与暗黑适配", highlights: [
            "多选分享：勾选多条出一张分享图，图上最多 12 个取件码。",
            "分享改成「先看图再分享」：大图预览 + 保存 / 拷贝 / 更多。",
            "暗黑模式全面修复，锁屏卡在深色背景下也能读清。",
        ]),
        Entry(version: "0.1.2", date: "2026-09-23", theme: "解析引擎扩展", highlights: [
            "解析扩展到快递公司 / 运单号 / 尾号，识别不出就留空，不摆占位。",
            "一条短信含多个取件码时自动拆成多条记录。",
            "扫码确认卡可编辑，支持一次识别多张图。",
        ]),
        Entry(version: "0.1.1", date: "2026-09-22", theme: "实时活动与真机交付", highlights: [
            "实时活动总开关：关掉后灵动岛与锁屏卡立刻收起。",
            "修好真机灵动岛图标发灰的问题。",
        ]),
        Entry(version: "0.1.0", date: "2026-09-22", theme: "初版 Demo", highlights: [
            "核心框架：待取 / 已取 / 统计三页 + 详情页。",
            "粘贴短信或扫面单就能添加，自动识别取件码与快递公司。",
            "桌面小组件 + 灵动岛 / 锁屏实时卡片。",
        ]),
    ]

    var body: some View {
        // 🔴 2026-10-25：底色改用 ZStack 独立铺一层 ——
        // 原先 `.background(...)` 挂在 ScrollView 上，在分栏 detail 列里撑不满，
        // 露出 NavigationStack 的默认白底，表现为「右栏整片白、左栏浅灰」。
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        timeline
                    }
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                // 截图脚手架：`-e '{"SCROLL_BOTTOM":"1"}'` 直接把初始位置锚到底部，
                // 用来拍 1.0.0 卡片末尾的内测区（simctl 没法滚动）。正式运行恒 .top。
                .defaultScrollAnchor(ProcessInfo.processInfo.environment["SCROLL_BOTTOM"] == "1" ? .bottom : .top)
                // 截图脚手架：`-e '{"SCROLL_TO":"beta"}'` 精确滚到内测区开头。
                .onAppear {
                    guard ProcessInfo.processInfo.environment["SCROLL_TO"] == "beta" else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        proxy.scrollTo("beta", anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("版本历史")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 截图脚手架：`-e '{"BETA_EXPAND":"1"}'` 直接展开内测区，省得手点。
            // 全展开要滚很久，截图用 `BETA_EXPAND=1` + 顶部可见区域即可。
            if ProcessInfo.processInfo.environment["BETA_EXPAND"] == "1" {
                expandedBeta = Set(entries.filter { !$0.beta.isEmpty }.map(\.id))
            }
        }
        .cloaksTabBar()
        // 隐藏入口：命中后推凭证页，返回即回到版本历史，不留任何标记

    }

    // MARK: 页首

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Codelumi")
                .font(.system(size: 17, weight: .semibold))
            Text("从第一行代码到现在的每一步。取件数据默认只在本机，开启 iCloud 同步后也只在你自己的 iCloud 里。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    // MARK: 时间线
    //
    // 结构 = 每个版本一行（左轨道 + 右卡片），行间不设间距 —— 卡片自身的
    // bottom padding 负责拉开卡片距离，这样轨道的竖线能**连续贯穿**：
    //   · 首行：13pt 空白（对齐卡内标题行）→ 圆点 → 竖线延伸到行底；
    //   · 中间行：竖线接上来 → 圆点 → 竖线继续；
    //   · 末行：竖线接上来 → 圆点收尾。
    private var timeline: some View {
        let shown = shownEntries
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: 14) {
                    track(for: entry, at: index, isLast: index == shown.count - 1)

                    entryCard(entry)
                        .padding(.bottom, index == shown.count - 1 ? 0 : 16)
                }
            }
        }
    }

    /// 正常情况就是全部版本；截图脚手架 `BETA_ONLY=1` 时只留首条（1.0.0），
    /// 这样 1.0.0 卡片末尾的内测区不用滚动就能拍全。正式运行恒定走全量分支。
    private var shownEntries: [Entry] {
        ProcessInfo.processInfo.environment["BETA_ONLY"] == "1" ? Array(entries.prefix(1)) : entries
    }

    /// 左轨道：宽 16pt，圆点落在卡内标题的视觉中心高度（顶 13pt + 圆点半径）。
    private func track(for entry: Entry, at index: Int, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            if index > 0 {
                Rectangle()
                    .fill(trackColor)
                    .frame(width: 1.5, height: 13)
            } else {
                Color.clear.frame(height: 13)
            }

            Circle()
                .fill(isCurrent(entry) ? AppTheme.accent : Color(.tertiaryLabel).opacity(0.6))
                .frame(width: isCurrent(entry) ? 12 : 8,
                       height: isCurrent(entry) ? 12 : 8)
                .overlay {
                    if isCurrent(entry) {
                        Circle()
                            .stroke(AppTheme.accent.opacity(0.25), lineWidth: 4)
                    }
                }

            if !isLast {
                Rectangle()
                    .fill(trackColor)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 16)
    }

    private var trackColor: Color { Color(.tertiaryLabel).opacity(0.25) }

    private func entryCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.version.L)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent(entry) ? AppTheme.accent : .primary)

                if isCurrent(entry) {
                    Text("当前版本")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.14), in: .capsule)
                        .foregroundStyle(AppTheme.accent)
                }

                Spacer(minLength: 8)

                Text("更新于 \(entry.date)")
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("更新于 \(entry.date)")
            }

            Text(entry.theme.L)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.highlights, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(isCurrent(entry) ? AppTheme.accent : Color(.tertiaryLabel))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)

                        Text(item.L)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.82))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !entry.beta.isEmpty {
                betaSection(entry)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    // MARK: 内测记录（折叠区）
    //
    // 只挂在 1.0.0 卡内。收起时是一行"本次正式版之前，1.0.0 一共推了 N 次构建"，
    // 展开后按构建号倒序逐条列出「构建 312 · 2026-11-15」+ 这一版改了什么。
    // 不用 DisclosureGroup：系统那套会自带一圈缩进和灰底，跟卡内的排版打架。

    private func betaSection(_ entry: Entry) -> some View {
        let expanded = expandedBeta.contains(entry.id)

        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(height: 0.5)
                .padding(.bottom, 12)

            Button {
                withAnimation(.snappy(duration: 0.26)) {
                    if expanded {
                        expandedBeta.remove(entry.id)
                    } else {
                        expandedBeta.insert(entry.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.version) 内测记录")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("\(entry.beta.count) 个构建 · 每个构建改了什么")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    // 2026-11-21 主人：这一类说明（iPad / 折叠屏 / 分栏）整段去掉，
                    // 内测记录只写「改了什么」。
                    Text("以下是 TestFlight 的逐次构建记录。")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ForEach(Array(entry.beta.enumerated()), id: \.element.id) { index, build in
                        betaRow(build,
                                isLatest: index == 0,
                                isLast: index == entry.beta.count - 1)
                    }
                }
                .padding(.top, 12)
            }
        }
        .id("beta")
    }

    private func betaRow(_ build: BetaBuild, isLatest: Bool, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                // 🔴 行内不再重复写 "1.0.0 (312)"：分区标题已经写明版本号，
                //    逐行都带一遍 1.0.0 反而像"版本号又重复了"（主人 2026-11-15 的要求）。
                Text("构建 \(build.build)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isLatest ? AppTheme.accent : .secondary)

                if isLatest {
                    Text("最新构建")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.accent.opacity(0.14), in: .capsule)
                        .foregroundStyle(AppTheme.accent)
                }

                Spacer(minLength: 8)

                Text(build.date)
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(build.points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(Color(.tertiaryLabel))
                            .frame(width: 3, height: 3)
                            .padding(.top, 6)

                        Text(point.L)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.72))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 2)
        }
        .padding(.bottom, isLast ? 0 : 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color(.separator).opacity(0.35))
                    .frame(height: 0.5)
                    .padding(.bottom, 6)
            }
        }
    }
}
