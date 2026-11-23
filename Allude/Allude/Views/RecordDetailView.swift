import SwiftUI
import UIKit
import WidgetKit

// MARK: ============================================================================
// 取件详情
//
// 版式口径（2026-09-21 重排）
// --------------------------
// · **主操作全部收进顶部一张卡**：品牌图标 + 主名（快递公司 > 驿站 > 短信平台）
//   在左上、取件码居中、底部内嵌「标记为已取」。
//   复制操作（次要动作）不放按钮，改由**长按取件码**唤起菜单完成，
//   码区因此占满整卡宽度（2026-10-20 主人要求：卡片上不要显示复制按钮）。
//   原先落在页面底部的那颗独立大按钮已取消 —— 从列表点进来后，
//   拇指不必再跨半屏去够，取件时的动作全部在首屏完成。
//
// · **卡片底 = 品牌色磨砂玻璃**：颜色取自该品牌**官方图标**的调色板
//   （tools/extract_brand_palette.py 提取，见 BrandPalette.swift），
//   再叠一层超薄材质做磨砂。于是淘宝是橙玻璃、星巴克是绿玻璃、抖音是黑玻璃 ——
//   每家的详情页颜色都不同，扫一眼就知道自己在看哪一家。
//
// · **主操作 = 液态玻璃按钮**：`标记为已取` / `恢复为待取件` 走 `glassEffect`。
//   待取件态用 `.regular.tint(doneTint)` 染色（本页唯一主动作），
//   已取件态退成 `.regular` 中性玻璃 + `.primary` 文字（回退操作，不该抢注意力）。
//   两者都带 `.interactive()` —— 少了它按下时没有形变与高光，就只是块半透明板子。
//   详见 `actionGlass`。
//
//   ⚠️ 这与 DesignSystem.swift 顶部「内容层不用玻璃」的既有口径是有出入的：
//   那条规则针对的是「导航层与内容层争夺层级」，而此处玻璃只出现在详情页的
//   唯一一张主卡上、且被品牌色染透，属于「以材质表达品牌身份」的用法。
//   系统「降低透明度 / 增强对比度」辅助功能下，`.ultraThinMaterial` 会自动
//   退化为不透明底，可读性由系统兜底。
//
// · **信息区改「标签一行、值一行」**：值不折行（长地址靠缩字自适应）。
//   原来的左右对齐在长地址上会被挤成三四行，扫读时视线要来回横跳。
// ============================================================================

struct RecordDetailView: View {
    /// iPad 分栏用：详情列**不要再自带一条导航栏** —— 否则顶部会出现两行
    /// （标签栏一行、详情标题一行），左列标题却和标签栏同一行，看起来"错位"。
    /// 传 true 时隐藏系统导航栏，分享 / 编辑 改用页内右上角的小胶囊。
    var hidesNavigationBar: Bool = false
    /// 进门时的快照。**只做两个用途**：① 仓库里暂时找不到该记录时的兜底渲染；
    /// ② 提供稳定的 `id` 供实时查询。**永远不直接参与渲染** ——
    /// 否则就是 2026-09-23 主人抓到的那个 bug：点「标记为已取」后仓库已经翻状态，
    /// 详情页却拿着值拷贝纹丝不动，像点了没反应一样。
    private let snapshot: PickupRecord

    init(record: PickupRecord, hidesNavigationBar: Bool = false) {
        self.hidesNavigationBar = hidesNavigationBar
        self.snapshot = record
        // 草稿用进门快照打底，进编辑态时会按仓库最新值重载（见 enterEdit）
        _draft = StateObject(wrappedValue: EditRecordModel(record: record))
    }

    @EnvironmentObject private var store: PickupStore
    /// 驿站名称库（2026-10-15）：详情页「快递驿站」行实时匹配用；
    /// 订阅它，自定义驿站改名/删图后本行同帧刷新（与列表卡片同款）。
    @ObservedObject private var stationDirectory = StationDirectory.shared
    @StateObject private var feedback = CopyFeedbackModel()
    /// 原始短信的复制反馈（与取件码那条分开，避免两个按钮互相闪）
    @StateObject private var rawFeedback = CopyFeedbackModel()
    /// 分享预览面板的开关。工程约定：CLI 链路下 `@State` 宏编不过，
    /// 局部状态一律 ObservableObject 承载（见 DesignSystem.swift 顶部）。
    @StateObject private var share = DetailShareModel()
    /// 详情页**原地编辑态**开关（2026-10-14 主人定稿：不弹二级页，就在本页编辑）。
    @StateObject private var edit = DetailEditModel()
    /// 编辑态草稿（字段全部存 String，空 = 可选字段不显示）。
    /// 宏规避口径（见 DesignSystem.swift 顶部）：ObservableObject 承载。
    @StateObject private var draft: EditRecordModel

    /// 🔴 **单一事实源**：视图一律从仓库按 id **实时取**（提醒事项 / 邮件详情页的
    /// 同款做法 —— 详情页永远是数据的镜像，不持有自己的状态）。
    /// 标记已取 / 恢复待取后 `records` 发布变更，本页同帧重绘：
    /// 「已取」徽章出现、取件码划线变灰、按钮切成「恢复为待取件」。
    private var record: PickupRecord {
        store.records.first { $0.id == snapshot.id } ?? snapshot
    }

    /// 卡片强调色（卡面底色 / 描边 / 勾选钮 / 货架胶囊）。
    ///
    /// 🔴 2026-10-30 主人定的总规则（全 App 一套）：
    ///    **图标 = 第一行第一个字段**（快递公司 / 驿站 / 短信平台，谁排第一就用谁的图标）；
    ///    **卡面与取件码的颜色 = 那个图标的主题色**。
    ///    所以这里恒等于 `iconBrand`，不再有「平台优先」的例外 ——
    ///    「圆通速递 ｜ 韵达快递超市」这张卡必须是圆通紫，不能是驿站绿。
    private var brand: Color { iconBrand }

    /// 取件码颜色**恒跟图标主题色**（2026-10-20 主人定）：图标显示快递公司/驿站/平台
    /// 时，取件码强调色与之一致（如「拼多多发的、圆通承运」→ 圆通主题色）。
    private var iconBrand: Color { CourierBrand.color(for: titleIconSource) }

    /// 快递驿站名（2026-10-15）：固定驿站/商铺品牌词在短信原文里实时匹配，
    /// 实时匹配，多个命中取最长词条；匹配不到 = 这条没有驿站（如韵达加盟
    /// 门店「林成驾校店」这类地址，不是固定驿站品牌，不进词表）。
    private var stationName: String? {
        stationDirectory.matchedName(in: [record.rawMessage])
    }

    /// 详情页与列表、小组件同一份解析结论（2026-11-21）
    private var resolution: StationResolution { record.stationResolution }

    /// 只读态显示的驿站名：**组名优先**，没有组才显示成员名（与卡面副名同口径）
    private var stationDisplayName: String {
        if let group = resolution.groupName, !group.isEmpty { return group }
        return resolution.hasStation ? resolution.stationName : ""
    }

    /// 手工指定驿站 / 组的选择行（编辑态）。
    ///
    /// 优先级：这里选的 > 自动识别。选了组就只认组；选驿站会清掉组。
    /// 两个都选「自动识别」等于回到解析入口的默认结论。
    private var stationPickerRow: some View {
        let groups = StationGroupStore.all()
        let builtins = StationDirectory.builtinNames
        let customs = stationDirectory.customNames

        return VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 5) {
                Text("快递驿站")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Menu {
                    Button {
                        assignStation(station: nil, groupID: nil)
                    } label: {
                        Label("自动识别", systemImage: resolution.isManual ? "circle.dashed" : "checkmark")
                    }

                    if !groups.isEmpty {
                        Section("驿站组") {
                            ForEach(groups) { group in
                                Button {
                                    assignStation(station: nil, groupID: group.id)
                                } label: {
                                    Label(group.name,
                                          systemImage: resolution.groupID == group.id
                                          ? "checkmark" : "square.stack.3d.up")
                                }
                            }
                        }
                    }

                    Section("驿站") {
                        ForEach(builtins + customs, id: \.self) { name in
                            Button {
                                assignStation(station: name, groupID: nil)
                            } label: {
                                Label(name,
                                      systemImage: record.stationOverride == name
                                      ? "checkmark" : "mappin.and.ellipse")
                            }
                        }
                    }
                } label: {
                    // 与同卡其它字段一致：值靠右，chevron 跟在值后面
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text(stationDisplayName.isEmpty ? "未识别" : stationDisplayName)
                            .font(.system(size: 16))
                            .foregroundStyle(stationDisplayName.isEmpty
                                             ? Color(.tertiaryLabel) : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                // 同一驿站落在多个组时明确说一句，别让用户以为 App 猜错了
                if resolution.isAmbiguous {
                    Text("这个驿站在 \(resolution.candidateGroups.joined(separator: "、"))，请选一个")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    private func assignStation(station: String?, groupID: String?) {
        guard var copy = store.records.first(where: { $0.id == record.id }) else { return }
        copy.stationOverride = station
        copy.stationGroupOverride = groupID
        store.update(copy)
        // 让列表 / 小组件立刻按新归属重画
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 卡面命名 —— **统一走 `PickupNaming`**（2026-10-28 主人：
    /// 「整个Codelumi遵循一套逻辑」；之前详情页自己写了一套 `courier > 驿站 > company`，
    /// 于是同一笔记录在列表写「韵达快递 ｜ 兴裕隆超市」、在详情页写反）。
    private var naming: PickupNaming {
        record.namingResolved
    }
    private var titlePrimary: String { naming.primary }
    private var titleSecondary: String? { naming.secondaryLabel }
    /// 图标匹配串随主名走 —— 与「图标 = 第一行第一个字段」同源
    private var titleIconSource: String { naming.iconSource }

    /// 快递柜格口（与列表卡同口径）：有值就跟在第二段后面以胶囊标签显示
    private var lockerName: String? {
        let l = record.locker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return l.isEmpty ? nil : l
    }

    /// 卡面取色键 —— **恒等于图标取色键**（第一行第一个字段），
    /// 玻璃卡渐变（`palette`）也走它，保证「图标 / 卡面 / 取件码」三者同色。
    private var brandKey: String { titleIconSource }

    private var addressLine: String { record.address.trimmingCharacters(in: .whitespaces) }

    /// 品牌官方图标的调色板；未收录的品牌回落到「品牌主色 + 它的暗色档」。
    /// 🔴 取色键用 `brandKey`（与卡面强调色同源）—— 旧版恒用 `record.company`，
    /// 于是「无短信平台的裸取件码短信」详情页玻璃卡是**灰色兜底**，
    /// 而列表同一笔是快递公司本色，两处颜色对不上。
    private var palette: [Color] {
        let info = CourierBrand.info(for: brandKey)
        let hexes = BrandPalette.colors(forAsset: info.asset) ?? [info.from, info.to]
        return hexes.map { Color(hex: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                codeCard

                // 地图导航卡已下线（2026-10-31 主人：卡片里的地图没有意义）。
                // 取件地址本身仍在下方 `infoCard` 里，可长按选中、可点「导航」按钮走系统地图。

                infoCard
                rawMessageCard
            }
            .padding(.horizontal, AppTheme.hInset)
            // 📱 宽屏限宽居中（iPhone Duo 展开态 951pt）：详情是三张卡纵向成列，
            //    铺满 951pt 后每张卡都变成一条超宽横幅，地图卡尤其扁。
            //    窄屏（402/440pt）触不到 700 上限，视觉零变化。
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        // 🔴 状态翻转的过渡挂在**整页内容**上：标记已取 / 恢复待取的一瞬，
        //    徽章淡入、划线延伸、按钮换文案与玻璃染色同步弹簧过渡，
        //    而不是各元素各自硬跳。数据驱动（value:），不会误伤滚动等无关动画。
        .animation(.spring(response: 0.35, dampingFraction: 0.82),
                   value: record.isPickedUp)
        // 编辑态进出同样整页过渡：值行 ↔ 输入框整组换，逐元素硬跳会显得页面在抖。
        .animation(.spring(response: 0.30, dampingFraction: 0.85),
                   value: edit.isEditing)
        // 页面底 = 浅灰，卡片才是白（2026-09-23 修正）
        .background(AppTheme.pageBackground)
        // 标题恒为「详情」（2026-10-25 主人定）：此处曾用 `record.company`，
        // 结果是「拼多多发的、圆通承运」的件在标题上写「拼多多」，与卡片主名
        // （圆通快递）自相矛盾；短信平台名在卡内已单独标注，标题不再重复。
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            if hidesNavigationBar { inPageActions }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // #51 分享卡片：与列表长按菜单、多选分享**共用同一个面板**
                // （先看图，再分享）。🔴 不再走 `ShareLink` ——
                // 全 App 的「分享卡片」只保留一个口径，见 PickupShareCard.swift。
                Button {
                    SharePresenter.shared.present([record])
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享卡片")
            }

            // 编辑（2026-10-14 主人定稿）：**不弹二级页**，就在本页原地进入编辑态 ——
            // 信息区的值行换 TextField，「完成」统一提交（见 commitEdit）。
            ToolbarItem(placement: .topBarTrailing) {
                if edit.isEditing {
                    Button("完成") { commitEdit() }
                        .fontWeight(.semibold)
                } else {
                    Button("编辑") { enterEdit() }
                }
            }
        }
        // 截图脚手架：`SIMCTL_CHILD_EDIT=1` 启动即进编辑态（原地编辑没有
        // 菜单入口可脚本化，与列表页 SELECT_MODE 同一思路）。
        .onAppear {
            if ProcessInfo.processInfo.environment["EDIT"] == "1" {
                enterEdit()
            }
        }
    }

    /// 分栏详情列的页内动作（导航栏收起后仍要能分享 / 编辑）。
    private var inPageActions: some View {
        HStack(spacing: 8) {
            Button {
                SharePresenter.shared.present([record])
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("分享卡片")

            Button {
                edit.isEditing ? commitEdit() : enterEdit()
            } label: {
                Text(edit.isEditing ? "完成" : "编辑")
                    .font(.system(size: 15, weight: edit.isEditing ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .padding(.top, 6)
        .padding(.trailing, 16)
        .appGlass(.capsule)
        .padding(.trailing, 16)
    }

    // MARK: 原地编辑（2026-10-14 主人定稿）

    /// 进入编辑态：草稿按**仓库最新值**重载（不是进门快照 —— 进门后可能
    /// 已标记过已取，草稿要拿当前真值打底）。
    private func enterEdit() {
        draft.load(record)
        edit.isEditing = true
    }

    /// 「完成」：草稿归一后整条提交，退出编辑态。
    ///
    /// 归一口径与添加链路一致（Models.swift `commitAll`）：
    ///   · 空串 → nil（可选字段留空 = 不显示）；
    ///   · `id` / `receivedAt` / `isPickedUp` / `pickedUpAt` / `kind` 不参与编辑
    ///     —— kind 是解析期的后台分类，详情页不展示也不让改（主人 2026-10-14 定）；
    ///   · 取件码（主凭证）必填，为空则不提交（保持在编辑态）。
    private func commitEdit() {
        guard !draft.code.trimmed.isEmpty else { return }
        // 🔴 必须显式带上 `id: record.id`（2026-10-25 审查发现）。
        // `PickupRecord.id` 有默认值 `UUID()`，构造时漏掉它会**生成一个全新 id**；
        // 而 `PickupStore.update` 是按 id 查下标（`firstIndex(where: { $0.id == edited.id })`），
        // 查不到就直接 return —— 结果是「退出编辑态但一个字都没保存」，
        // 编辑功能整体失效，且没有任何报错提示。
        let edited = PickupRecord(
            id: record.id,
            company: draft.company.trimmed,
            code: draft.code.trimmed,
            kind: record.kind,
            address: draft.address.trimmed,
            rawMessage: record.rawMessage,
            receivedAt: record.receivedAt,
            isPickedUp: record.isPickedUp,
            // 提交时再归一一次：用户手敲「申通」「中通」也存成标准名
            courier: draft.courier.trimmed.isEmpty ? nil
                : CourierBrand.canonicalName(for: draft.courier.trimmed),
            waybill: draft.waybill.trimmed.isEmpty ? nil : draft.waybill.trimmed,
            tail: draft.tail.trimmed.isEmpty ? nil : draft.tail.trimmed,
            shelf: draft.shelf.trimmed.isEmpty ? nil : draft.shelf.trimmed,
            // 🔴 快递柜不可手改（解析自短信），但**必须原样带回** ——
            // 构造 `PickupRecord` 时漏传就等于把它清成 nil，
            // 保存任意一个字段后卡面的快递柜标签会凭空消失。
            locker: record.locker,
            // 🔴 通知历史是**证据**：只读、可累积、任何编辑都不能改也不能清空。
            //    构造 PickupRecord 时漏传就等于 nil ——「保存一下地址，通知记录全没了」。
            // 🔴 驿站 / 组的手工指定同样是**用户的选择**（2026-11-21）：
            //    漏传就等于「改一下地址，刚指定好的驿站被清掉」。
            stationOverride: record.stationOverride,
            history: record.history,
            stationGroupOverride: record.stationGroupOverride,
            pickedUpAt: record.pickedUpAt
        )
        store.update(edited)

        // 记住这次纠正（同一驿站下次直接套用）。只在地址**真的改了**时才记，
        // 并且必须有驿站名可作 key —— 没有驿站的短信（纯快递公司）不记，避免串味。
        if edited.address != record.address {
            if let station = StationDirectory.shared.matchedName(in: [record.rawMessage]),
               !station.isEmpty {
                PickupAddressMemory.remember(station: station, address: edited.address)
            }
        }

        edit.isEditing = false
    }

    // MARK: 顶部主卡（品牌色磨砂玻璃）

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 行 1：平台图标 + 平台名（左上角一组） ──
            // 注：不展示任何类别标签（2026-10-14 定，2026-10-28 全面执行）——
            // kind 只是解析期的后台分类，用户不需要知道「这条是按取件码还是运单号命中的」。
            // Codelumi内已不再区分凭证类型，`KindTag` 组件也已整体删除。
            HStack(spacing: 8) {
                // 图标 = 主名第一段（快递公司 > 短信平台 > 驿站），
                // 画法与列表卡同源 —— 统一在 `PickupIcon` 里，别再各写一遍分支。
                PickupIcon(naming: naming, size: 26)

                Text(titlePrimary.L)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    // 取色与列表卡主名同口径：主名一律 .primary（强调色只给图标与取件码）
                    .foregroundStyle(record.isPickedUp ? Color.secondary : Color.primary)

                // 第二段：驿站优先、其次短信平台（「圆通快递 | 菜鸟驿站」）
                if let secondary = titleSecondary {
                    Text("|")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(secondary.L)
                        .font(.system(size: 13))
                        .foregroundStyle(record.isPickedUp ? .tertiary : .secondary)
                        .lineLimit(1)
                }

                // 快递柜标签（2026-10-28 与列表卡同款）：紧跟第二段，胶囊样式，
                // 规格与行 1.5 的货架胶囊一致（10.5pt semibold / 999 圆角）。
                if let lockerName {
                    Text(lockerName.L)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(brand)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(brand.opacity(0.14), in: .capsule)
                }

                Spacer(minLength: 6)

                // 右上角：待取显示「入库日期时间」、已取显示「已取」徽章 —— 互斥，
                // 已取件不再显示（2026-10-20 主人定：入库信息移到卡片右上角，
                // 与主页卡同口径；已取后无意义故隐藏）。
                // 2026-10-20 主人再定：右上角不用相对时长（「已入库5天1小时…」），
                // 改回**日期与时间**（`shortTime` = 「M月d日 HH:mm」），与 App 内
                // 其他时间显示同一口径，方便对照短信到达时刻。
                if record.isPickedUp {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("已取")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.doneTint, in: .capsule)
                } else {
                    Text(record.shortTime.L)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // ── 行 1.5：取件地址 · 货架（与主页卡同口径，补足卡片信息） ──
            // 入库日期时间已上移到卡片右上角（见行 1），已取件不再显示，故此处不含。
            // 地址与货架都为空时整行隐藏，避免留下空间距。
            if !addressLine.isEmpty || (record.shelf.map { !$0.isEmpty } ?? false) {
                HStack(spacing: 6) {
                    if !addressLine.isEmpty {
                        Text(addressLine.L)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let shelf = record.shelf, !shelf.isEmpty {
                        Text("货架\(shelf)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(brand)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(brand.opacity(0.16), in: .capsule)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.top, 6)
            }

            // ── 行 2：取件码（居中） ──
            // 2026-10-20：卡片上不再放复制按钮（主人要求），复制收进长按菜单
            // （长按取件码 → 复制取件码）；码区因此恢复整卡宽度，长码不再需要
            // 为按钮让出右侧 34pt。
            record.emphasizedCodeText(isDone: record.isPickedUp, tint: iconBrand)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .strikethrough(record.isPickedUp, color: .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = record.code
                        feedback.flash()
                    } label: {
                        Label(feedback.copied ? "已复制取件码" : "复制取件码",
                              systemImage: feedback.copied ? "checkmark" : "doc.on.doc")
                    }
                }

            // 分割线已去掉（2026-09-23 主人要求）：取件码区与动作按钮之间
            // 只留间距，不做任何分界 —— 玻璃卡是一个整体，中间横一道虚线
            // 反而把它切成了上下两截。

            // ── 行 3：标记为已取（原先在页面底部，现收进卡内） ──
            actionButton
        }
        .padding(AppTheme.cardPadding + 3)
        .frame(maxWidth: .infinity)
        .background { glassBackground }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }

    private var actionButton: some View {
        Button {
            // 触感随语义走（工程先例：CameraScanner 成功用 notification、
            // CardMenu 用 impact）：「标记为已取」是完成态 → success 震动；
            // 「恢复为待取件」是回退 → medium 轻点即可。
            if record.isPickedUp {
                store.markPending(record)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                store.markPicked(record)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } label: {
            Label(record.isPickedUp ? "恢复为待取件" : "标记为已取",
                  systemImage: record.isPickedUp
                      ? "arrow.uturn.backward" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(record.isPickedUp ? Color.primary : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .appGlass(.rect(cornerRadius: AppTheme.innerRadius, style: .continuous),
                             tint: actionTint,
                             interactive: true)
                .contentShape(.rect(cornerRadius: AppTheme.innerRadius))
        }
        .buttonStyle(.plain)
    }

    /// 主操作按钮的液态玻璃。
    ///
    /// · **待取件 → 「标记为已取」**：`.regular.tint(doneTint.opacity(0.65))` 给玻璃**染一层薄色**。
    ///   染色后的玻璃仍是透光的（能看到底下品牌色卡背在流动），比原来的实心填充更有层次，
    ///   同时把「这是本页唯一主动作」讲清楚。
    ///   ⚠️ **tint 不能给满**：`.tint(doneTint)` 也就是 alpha=1 时，玻璃会被染成一块
    ///   不透明的墨绿，玻璃感全丢 —— 主人原话「不如已取件那个有质感」就是这个原因。
    ///   0.65 是在**真实卡背**上并排比对 0.50 / 0.65 / 0.80 三档选出来的：
    ///   0.50 绿色发灰；0.80 又回到实心感；0.65 既透出紫色卡背、上缘又有玻璃高光。
    /// · **已取件 → 「恢复为待取件」**：完全不加 tint，退成**中性玻璃**。它是个回退操作，
    ///   不该和主动作抢注意力；去掉染色后文字改 `.primary`，中性玻璃上用白字会糊。
    /// · `.interactive()` 两态都不能省 —— 少了它按下时没有形变与高光，
    ///   玻璃就只是块半透明板子，「液态」没了。
    /// 主动作的染色（`appGlass` 在 iOS 26 走液态玻璃、低版本走毛玻璃）
    private var actionTint: Color? {
        record.isPickedUp ? nil : AppTheme.doneTint.opacity(0.65)
    }

    /// 品牌色磨砂玻璃：品牌调色板渐变（底）+ 超薄材质（面）
    private var glassBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette[0].opacity(0.62),
                    palette[0].opacity(0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 第 2 / 3 色从另外两个角补进来，避免整卡只有一种色的单调渐变
            if palette.count > 1 {
                RadialGradient(colors: [palette[1].opacity(0.50), .clear],
                               center: .bottomTrailing,
                               startRadius: 0, endRadius: 210)
            }
            if palette.count > 2 {
                RadialGradient(colors: [palette[2].opacity(0.38), .clear],
                               center: .topTrailing,
                               startRadius: 0, endRadius: 165)
            }

            Rectangle().fill(.ultraThinMaterial)
        }
    }

    // MARK: 信息区（标签一行 / 值一行；编辑态值行换 TextField）

    /// 顺序按**取件动线**排（2026-10-14 主人定稿）：报什么码 → 去哪取 →
    /// 货架在哪 → 次要凭证 → 入库时间。「信息类别」不展示（后台分类，
    /// 见主卡行 1 注释）。
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider 与字段同生共死（放进 editableBlock 内）—— 否则可选字段
            // 空值隐藏时会留下两条紧邻的分隔线。
            // 🔴 2026-10-28 修：这里的取件码颜色必须与**顶部卡片**同一个来源。
            //    原来传的是 `brand`（按 `record.company` 取色），而卡片用的是
            //    `iconBrand`（按 courier ?? station ?? company 取色）——
            //    于是「拼多多/妈妈驿站发的、圆通承运」这条：
            //    卡片码是圆通紫，下面字段区却成了妈妈驿站的橙，一页两种颜色。
            editableBlock(label: "取件码", value: record.code, keyPath: \.code,
                          mono: true, tint: iconBrand, required: true)

            // 🔴 2026-10-28 主人：「三个值的优先级、显示、取色与卡片一致」——
            // 卡片首行是「快递公司｜快递驿站 / 短信平台」，信息区就按同一优先级排：
            // 快递公司 → 快递驿站 → 短信平台（旧顺序是 平台 → 公司 → 驿站，
            // 与卡面的读序正好相反）。
            // 值用 `record.courier` 原值：空则**整行不显示**（不再回落成平台名 ——
            // 否则「快递公司」与「短信平台」两行写成同一个值，正是卡片早已排除的重复）。
            editableBlock(label: "快递公司", value: record.courierDisplay ?? "", keyPath: \.courier,
                          placeholder: "默认与平台相同", divider: true)

            // 快递驿站（2026-10-15 主人定稿）：与「取件地址」是两个概念 ——
            // 驿站 = 固定驿站 / 商铺品牌名（菜鸟驿站、喵站、多多代收点…），由
            // StationDirectory 从短信原文 + 地址实时匹配，不落库、不可手改。
            // 匹配不到：只读态整行隐藏；编辑态显「未识别」占位
            //（主人 10-15 定：编辑时所有字段都要显示）。
            // 2026-11-21 主人定「加」：驿站 / 驿站组**可以在这一条上手工指定**。
            // 只读态仍是纯展示（组名优先）；编辑态换成菜单 ——
            // 同一个品牌在两个小区各有一个点时，自动识别必然分不清，得有地方说话。
            if edit.isEditing {
                stationPickerRow
            } else if !stationDisplayName.isEmpty {
                infoBlock(label: "快递驿站", value: stationDisplayName, divider: true)
            }

            editableBlock(label: "短信平台", value: record.company, keyPath: \.company,
                          divider: true)

            // 取件地址 = 解析器从短信「到 XX 取」提取的具体地址
            //（如「即墨区闫家岭小区西区林成驾校店」），可手改补填。
            editableBlock(label: "取件地址", value: record.address, keyPath: \.address,
                          placeholder: "如 XX小区XX号", divider: true, multiline: true)

            // 货架号紧跟驿站（取件时真正用来找包裹的那串），次要凭证退后
            editableBlock(label: "货架号", value: record.shelf ?? "", keyPath: \.shelf,
                          mono: true, tint: brand, placeholder: "如 3-12", divider: true)

            // 运单号 / 尾号：解析引擎从短信自动提取，**编辑态也不提供填写**
            // （2026-10-14 主人定：手改会与短信原文脱节，只做只读核对）。
            editableBlock(label: "运单号", value: record.waybill ?? "", keyPath: \.waybill,
                          mono: true, editable: false, divider: true)

            editableBlock(label: "尾号", value: record.tail ?? "", keyPath: \.tail,
                          mono: true, editable: false, divider: true)

            // 通知历史（2026-10-30）：同一个码被重复通知时，卡片只有一张、时间刷新，
            // 这里把每一次的通知时刻都列出来 —— 用户能看出「驿站到底催了几次」。
            // 添加时间（2026-10-30 主人）：与通知历史合并成一个模块，
            // **一行一个胶囊标签、倒序**（最新在上，最早在下 = 首次入库）。
            addTimeBlock
        }
        .padding(.vertical, 4)
        .cardSurface()
    }

    /// 一条信息 = 标签一行 + 值一行。
    ///
    /// 值**不折行**（`lineLimit(1)` + 缩字）：长地址折成三行会把「标签—值」的配对
    /// 关系打断，反而更难读。缩到 0.72 仍放不下的极端长地址才会截断。
    /// 「添加时间」块：**一行一个胶囊标签、最新在最上**。
    ///
    /// 第一行 = 最近一次被通知（品牌色高亮），最后一行 = 首次入库
    /// （= `receivedAt`，也等于 `history.first`）。旧数据没有 `history` → 只有一行。
    /// 之所以用胶囊而不是纯文本行：这个字段往往是三五条时间堆在一起，
    /// 纯文本连成一片看不出边界，胶囊一眼能数出「被催了几次」。
    private var addTimeBlock: some View {
        let times = (record.history ?? [record.receivedAt]).sorted(by: >)

        return VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("添加时间")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                        Text(Self.historyFormatter.string(from: time))
                            .font(.system(size: 13,
                                          weight: index == 0 ? .semibold : .regular,
                                          design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .foregroundStyle(index == 0 ? brand : .secondary)
                            .background(
                                (index == 0 ? brand.opacity(0.14) : Color.primary.opacity(0.06)),
                                in: .capsule
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    /// 「通知历史」用的时间格式：到秒 —— 两次提醒可能只差十几秒，
    /// 只到分钟会显示成一样的两行，看起来像重复 bug。
    static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm:ss"
        return formatter
    }()

    private func infoBlock(label: String,
                           value: String,
                           mono: Bool = false,
                           tint: Color = .primary,
                           divider: Bool = false) -> some View {
        // 值里带换行（如「通知历史」的多条时刻）时按多行排版，单行字段维持原样式
        VStack(alignment: .leading, spacing: 0) {
            if divider {
                Divider().padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(label.L)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Text(value.L)
                    .font(.system(size: 16,
                                  weight: mono ? .semibold : .regular,
                                  design: mono ? .rounded : .default))
                    .monospaced(mono)
                    .foregroundStyle(tint)
                    // 带换行的值（通知历史）按行渲染；单行字段仍是「一行 + 缩放」
                    .lineLimit(value.contains("\n") ? nil : 1)
                    .minimumScaleFactor(value.contains("\n") ? 1 : 0.72)
                    .allowsTightening(!value.contains("\n"))
                    .fixedSize(horizontal: false, vertical: value.contains("\n"))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    /// 可编辑字段行：编辑态换 TextField（绑草稿），只读态换 Text（**传仓库实时值**，
    /// 不用草稿 —— 草稿进门时加载，标记已取后会陈旧）。
    ///
    /// 🔴 空值行为分两态：**只读态留空即整行隐藏**（可选字段没有值就不占版面）；
    ///    **编辑态常驻**并显示 placeholder（不然用户看不到有这个字段可填）。
    ///    取件码（`required`）是主凭证，两态都常驻。
    /// 🔴 `editable: false` = 编辑态也只读（运单号 / 尾号这类解析提取字段，
    ///    见 infoCard 调用处注释）。
    private func editableBlock(label: String,
                               value: String,
                               keyPath: ReferenceWritableKeyPath<EditRecordModel, String>,
                               mono: Bool = false,
                               tint: Color = .primary,
                               placeholder: String = "",
                               required: Bool = false,
                               editable: Bool = true,
                               divider: Bool = false,
                               /// 多行显示（2026-10-28 主人：取件地址太长要换行，不要省略号）
                               multiline: Bool = false) -> some View {
        Group {
            // 显示条件：必填（主凭证）恒显 · 有值恒显 · **编辑态全部恒显**
            //（2026-10-15 主人定：编辑时所有字段都要显示，便于用户编辑 ——
            //  可选字段空值时编辑态也要占位，不能再整行隐藏）。
            if required || !value.trimmed.isEmpty || edit.isEditing {
                VStack(alignment: .leading, spacing: 0) {
                    if divider {
                        Divider().padding(.horizontal, 16)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(label.L)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)

                        if edit.isEditing && editable {
                            // multiline 时用竖向 TextField：地址在编辑态也能折行，
                            // 不至于一边显示完整、一边编辑时又被截断
                            TextField(placeholder,
                                      text: Binding(
                                        get: { draft[keyPath: keyPath] },
                                        set: { draft[keyPath: keyPath] = $0 }),
                                      axis: multiline ? .vertical : .horizontal)
                                .font(.system(size: 16,
                                              weight: mono ? .semibold : .regular,
                                              design: mono ? .rounded : .default))
                                .monospaced(mono)
                                .foregroundStyle(tint)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                        } else if value.trimmed.isEmpty {
                            // 编辑态不可编辑字段（运单号 / 尾号）的空值占位 ——
                            // 主人 2026-10-15 定：编辑时所有字段都要显示，
                            // 解析没提取到的字段显「未识别」，不留空白一行。
                            Text("未识别")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        } else {
                            Text(value.L)
                                .font(.system(size: 16,
                                              weight: mono ? .semibold : .regular,
                                              design: mono ? .rounded : .default))
                                .monospaced(mono)
                                .foregroundStyle(tint)
                                // 🔴 2026-10-28：multiline 走无限行 + 自然高度，
                                //    单行字段仍保持「一行 + 缩放」的老口径。
                                .lineLimit(multiline ? nil : 1)
                                .minimumScaleFactor(multiline ? 1 : 0.72)
                                .allowsTightening(!multiline)
                                .fixedSize(horizontal: false, vertical: multiline)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }
        }
    }

    // MARK: 原始短信

    private var rawMessageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(brand)
                Text("原始短信")
                    .font(.footnote.weight(.semibold))
                Spacer()

                // 复制整条原文（2026-10-31 主人）：售后排查、转发给快递公司都用得上。
                // 与取件码复制分开一个 feedback，否则点这里会把上面的码按钮也闪一下。
                Button {
                    UIPasteboard.general.string = record.rawMessage
                    rawFeedback.flash()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: rawFeedback.copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(rawFeedback.copied ? "已复制" : "复制")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(rawFeedback.copied ? AppTheme.doneTint : AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)

            Text(record.rawMessage.L)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - 局部状态

/// 详情页分享面板的开关。
///
/// 工程约定（见 DesignSystem.swift 顶部）：CLI 链路下 `@State` 等 SwiftUI 宏
/// 编不过，局部状态一律 ObservableObject + `@StateObject` 承载。
@MainActor
private final class DetailShareModel: ObservableObject {
    @Published var showing = false
}

/// 详情页原地编辑态开关（2026-10-14 主人定稿：编辑不弹二级页）。
@MainActor
final class DetailEditModel: ObservableObject {
    @Published var isEditing = false
}

// MARK: - 编辑草稿（详情页原地编辑专用）

/// 编辑态草稿：字段全部存 String（可选字段的空 = nil 在提交时归一）。
///
/// 原为二级编辑页（EditRecordView）的模型，2026-10-14 主人定稿「编辑就在
/// 详情页」后随原地编辑一并收编到这里。
final class EditRecordModel: ObservableObject {
    @Published var company = ""
    @Published var courier = ""
    @Published var address = ""
    @Published var code = ""
    @Published var waybill = ""
    @Published var tail = ""
    @Published var shelf = ""

    init(record: PickupRecord) {
        load(record)
    }

    /// 按记录装载草稿（进编辑态 / 外部刷新都走这里）。
    func load(_ record: PickupRecord) {
        company = record.company
        // 2026-10-28 主人：编辑态也要看到**标准名**（「申通」→「申通快递」）。
        // 草稿按 `courierDisplay` 载入，用户看到的就是存进去的那个名字；
        // 手改后提交仍会再归一一次（saveEdit 里）。
        courier = record.courierDisplay ?? ""
        address = record.address
        code = record.code
        waybill = record.waybill ?? ""
        tail = record.tail ?? ""
        shelf = record.shelf ?? ""
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
