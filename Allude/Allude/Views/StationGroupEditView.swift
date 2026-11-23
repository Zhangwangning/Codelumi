import SwiftUI
import PhotosUI
import WidgetKit

// MARK: - 驿站组编辑页（2026-11-17 主人）
//
// 一个「驿站组」就是一个**全新的驿站**：有自己的名称、图标、位置。
// 三项各自独立，可以自定义，也可以「只从某一个成员继承」——
// 继承是**动态引用**（成员换图 / 换位置，组立刻跟着变），不是复制一份快照。
//
// 成员关系挂的是成员**驿站 ID**（`NZYZ…` / `DZYYZ…`），所以成员改名不会断链。
// 2026-11-21 主人定：**一个驿站只属于一个组**（取件地点固定，多个组都收同一个品牌
// 会让短信没法定组）。勾选已在别组的成员会把它移过来，行里先标一句「在「X」里」；
// 移组时已有记录会被钉在原组（`PickupStore.pinRecords`），历史归属不会跟着变。

struct StationGroupEditView: View {

    enum Mode: Equatable {
        case create
        /// 编辑已有组：传组 ID（`FZYD…`），不传名字 —— 名字可以改，ID 不会变
        case edit(String)
    }

    /// 图标来源三档
    enum IconMode: String, CaseIterable, Identifiable {
        case fallback
        case custom
        case inherit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fallback: "名称首字"
            case .custom:   "自定义图片"
            case .inherit:  "继承成员"
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var station = StationDirectory.shared
    @ObservedObject private var locationStore = StationLocationStore.shared

    @State private var name: String
    @State private var selectedMemberIDs: Set<String>
    @State private var iconMode: IconMode
    @State private var iconData: Data?
    @State private var iconInheritMemberID: String?
    @State private var locationInheritMemberID: String?
    @State private var pickerSelection: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    /// 新建组时的位置草稿（老大：创建时就能加定位，默认当前位置）
    @State private var draftCoordinate: CLLocationCoordinate2D?
    @State private var showLocationPicker = false
    /// 成员搜索（2026-11-21）
    @State private var memberQuery: String = ""

    /// `preselectedMemberIDs`：从「编辑驿站 › 驿站组 › 新建驿站组…」进来时，
    /// 把这个驿站预先勾上（2026-11-21 主人要的快速分组）。
    init(mode: Mode, preselectedMemberIDs: [String] = []) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _selectedMemberIDs = State(initialValue: Set(preselectedMemberIDs))
            _iconMode = State(initialValue: .fallback)
            _iconInheritMemberID = State(initialValue: nil)
            _locationInheritMemberID = State(initialValue: nil)

        case .edit(let id):
            let group = StationGroupStore.group(id: id)
            _name = State(initialValue: group?.name ?? "")
            _selectedMemberIDs = State(initialValue: Set(group?.memberIDs ?? []))
            _iconInheritMemberID = State(initialValue: group?.iconInheritMemberID)
            _locationInheritMemberID = State(initialValue: group?.locationInheritMemberID)

            let inherited = group?.iconInheritMemberID != nil
            let customData = group.flatMap { StationDirectory.shared.iconData(for: $0.id) }
            _iconData = State(initialValue: customData)
            _iconMode = State(initialValue: inherited ? .inherit : (customData != nil ? .custom : .fallback))
        }
    }

    // MARK: 基础

    private var groupID: String? {
        if case .edit(let id) = mode { return id }
        return nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// **已保存**的组名（位置表的 key 用它 —— 编辑页里改了名还没保存时，
    /// 不能拿新名字去写位置，否则会多出一条孤儿记录）
    private var savedGroup: StationGroup? {
        guard let groupID else { return nil }
        return StationGroupStore.group(id: groupID)
    }

    private var allCandidates: [(id: String, name: String)] {
        station.allNames.compactMap { name in
            guard let id = StationIdentity.id(for: name) else { return nil }
            return (id, name)
        }
    }

    /// 搜索过滤后的成员候选（空查询＝全部）
    private var filteredCandidates: [(id: String, name: String)] {
        let q = memberQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allCandidates }
        return allCandidates.filter { $0.name.localizedStandardContains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                locationCard
                memberCard

                if let errorMessage {
                    Text(errorMessage.L)
                        .font(.caption)
                        .foregroundStyle(AppTheme.pendingTint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                if groupID != nil {
                    deleteButton
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(groupID == nil ? "新建驿站组" : "编辑驿站组")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .photosPicker(isPresented: Binding(
            get: { pickerSelection != nil },
            set: { if !$0 { pickerSelection = nil } }
        ), selection: $pickerSelection, matching: .images, photoLibrary: .shared())
        .task(id: pickerSelection) {
            guard let item = pickerSelection else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                iconData = data
                iconMode = .custom
            }
            pickerSelection = nil
        }
        .sheet(isPresented: $showLocationPicker) {
            NavigationStack {
                StationLocationPicker(coordinate: $draftCoordinate,
                                      stationName: trimmedName)
            }
        }
        .alert("解散这个驿站组？", isPresented: $showDeleteConfirm) {
            Button("解散", role: .destructive) { deleteGroup() }
            Button("取消", role: .cancel) { }
        } message: {
            // 🔴 2026-11-22 主人：确认框只要说清「哪些会变、哪些不会」，不铺排。
            Text("成员恢复为独立驿站，记录与取件状态不受影响；组的图标与位置会清除。")
        }
    }

    // MARK: 名称

    // MARK: 头部卡（图标 + 组名 + 来源三选一，2026-11-21 合并）

    /// 原来「组名一张卡 + 图标一张卡 + 三格来源」占掉两屏，中间还夹着
    /// 「不能与内置驿站…」这类规则说明。现在合成一张：名字是主角，
    /// 图标摆在左边点一下就能换，来源退化成三枚小胶囊；规则说明删掉，
    /// 重名时保存会直接在页脚报错（`errorMessage`）。
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // 点图标 = 切到「相册」来源（下面立刻出现选图按钮），不另外弹窗
                Button {
                    iconMode = .custom
                } label: {
                    iconPreview
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更换组图标")

                VStack(alignment: .leading, spacing: 8) {
                    TextField("如「恒大御府驿站」", text: $name)
                        .font(.system(size: 17, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 8) {
                        ForEach(IconMode.allCases) { mode in
                            iconModePill(mode)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            switch iconMode {
            case .fallback:
                EmptyView()

            case .custom:
                PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                    Label(iconData == nil ? "从相册选择图片" : "换一张图片",
                          systemImage: "photo.badge.plus")
                        .font(AppTheme.TypeScale.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppTheme.violet.opacity(0.10),
                                    in: .rect(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

            case .inherit:
                memberStrip(selected: $iconInheritMemberID, noneTitle: nil, emptyHint: nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// 一枚来源胶囊：图标 + 两字，选中紫底。
    private func iconModePill(_ mode: IconMode) -> some View {
        let selected = iconMode == mode
        let symbol: String = {
            switch mode {
            case .fallback: "character.cursor.ibeam"
            case .custom:   "photo"
            case .inherit:  "person.2"
            }
        }()
        let title: String = {
            switch mode {
            case .fallback: "首字"
            case .custom:   "相册"
            case .inherit:  "继承"
            }
        }()
        return Button {
            iconMode = mode
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title.L).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? AppTheme.violet : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(selected ? AppTheme.violet.opacity(0.14) : Color(.tertiarySystemFill),
                        in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var iconPreview: some View {
        let corner: CGFloat = 64 * 0.29
        if iconMode == .custom, let iconData, let image = UIImage(data: iconData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 0.5)
                }
        } else if iconMode == .inherit,
                  let memberID = iconInheritMemberID,
                  let memberName = StationIdentity.name(for: memberID) {
            StationLogo(name: memberName, size: 64, showsShadow: false)
        } else if iconMode == .custom {
            // 选了「自定义图片」但还没挑图：竖图占位，别后退到首字，免得自相矛盾
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(AppTheme.violet.opacity(0.12))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppTheme.violet)
                }
        } else {
            // 与「名称首字」小格同一预览口径：空名时也用「驿」示意会出什么字
            CourierLogo(company: trimmedName.isEmpty ? "驿" : trimmedName,
                        size: 64, showsShadow: false)
        }
    }

    private var iconSummary: String {
        switch iconMode {
        case .fallback:
            return trimmedName.isEmpty ? "按组名首字生成" : "按「\(trimmedName)」首字生成"
        case .custom:
            return iconData == nil ? "还没选图片，保存后仍按首字兜底" : "使用你选的图片"
        case .inherit:
            guard let memberID = iconInheritMemberID,
                  let memberName = StationIdentity.name(for: memberID) else {
                return "还没选成员"
            }
            return "继承「\(memberName)」的图标"
        }
    }

    // MARK: 位置（2026-11-17 老大：这里只管定位，不提到达提醒）
    //
    // 两种来源，主操作永远是「在地图上选」——老大要「手动选择，直接点地图」：
    //   · 已保存的组 → 推入 `StationLocationEditor`（读写位置表，还能调半径）；
    //   · 还没保存（新建）→ 弹出草稿选择器，创建时一起落盘，不用先存再设。

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.violet)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("位置")
                        .font(AppTheme.TypeScale.bodyMedium)
                    Text(locationSummary)
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let savedName = savedGroup?.name {
                NavigationLink {
                    StationLocationEditor(stationName: savedName)
                } label: {
                    locationActionRow(hasLocation: locationStore.location(for: savedName) != nil)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    // 手动选点 = 改用自己的位置，继承自然失效
                    locationInheritMemberID = nil
                })
            } else {
                Button {
                    locationInheritMemberID = nil
                    showLocationPicker = true
                } label: {
                    locationActionRow(hasLocation: draftCoordinate != nil)
                }
                .buttonStyle(.plain)
            }

            // 位置来源（2026-11-21）：原来是一句「或直接沿用成员的位置」+ 一排成员图，
            // 把整张卡撑得很高。收成一行 Menu：用自己的位置 / 沿用某个成员。
            if !memberCandidates.isEmpty {
                Divider().opacity(0.6)
                HStack {
                    Text("位置来源")
                        .font(AppTheme.TypeScale.body)
                    Spacer(minLength: 8)
                    Menu {
                        Button("自己的位置") { locationInheritMemberID = nil }
                        Divider()
                        ForEach(memberCandidates, id: \.id) { member in
                            Button("沿用「\(member.name)」") {
                                locationInheritMemberID = member.id
                            }
                        }
                    } label: {
                        SettingsValueLabel(text: locationSourceTitle)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// 「位置来源」这一行右侧的值
    private var locationSourceTitle: String {
        if let memberID = locationInheritMemberID,
           let name = StationIdentity.name(for: memberID) {
            return "沿用「\(name)」"
        }
        return "自己的位置"
    }

    private func locationActionRow(hasLocation: Bool) -> some View {
        HStack {
            Text(hasLocation ? "在地图上重新选位置" : "在地图上选择位置")
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppTheme.violet.opacity(0.10),
                    in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
    }

    private var locationSummary: String {
        if let memberID = locationInheritMemberID,
           let memberName = StationIdentity.name(for: memberID) {
            return "沿用「\(memberName)」的位置"
        }
        if let savedName = savedGroup?.name,
           let loc = locationStore.location(for: savedName) {
            return String(format: "已设置 %.5f, %.5f", loc.latitude, loc.longitude)
        }
        if let c = draftCoordinate {
            return String(format: "已选 %.5f, %.5f", c.latitude, c.longitude)
        }
        return "未设置"
    }

    // MARK: 成员选择（图标继承 / 位置沿用 共用）

    /// 组里成员的图标横条：点一下 = 选中它当继承来源。
    ///
    /// 🔴 用横条代替下拉菜单的原因：下拉里只有文字，看不出图标/相对位置；
    ///    横条一眼能看到每个成员长什么样，点选也少一次弹出。
    @ViewBuilder
    private func memberStrip(selected: Binding<String?>,
                             noneTitle: String?,
                             emptyHint: String?) -> some View {
        if memberCandidates.isEmpty {
            if let emptyHint {
                Text(emptyHint.L)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let noneTitle {
                        chip(title: noneTitle,
                             systemImage: "slash.circle",
                             isSelected: selected.wrappedValue == nil, hasLogo: false) {
                            selected.wrappedValue = nil
                        }
                    }
                    ForEach(memberCandidates, id: \.id) { member in
                        chip(title: member.name,
                             systemImage: nil,
                             isSelected: selected.wrappedValue == member.id,
                             hasLogo: true) {
                            selected.wrappedValue = member.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(title: String,
                      systemImage: String?,
                      isSelected: Bool,
                      hasLogo: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if hasLogo {
                    StationLogo(name: title, size: 40, showsShadow: false)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: systemImage ?? "slash.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                }

                Text(title.L)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.violet : Color.secondary)
                    .lineLimit(1)
                    .frame(width: 52)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(isSelected ? AppTheme.violet.opacity(0.10) : .clear,
                        in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.violet.opacity(0.55) : .clear,
                                  lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    /// 组内成员（按名字排序，保证横条顺序稳定）
    private var memberCandidates: [(id: String, name: String)] {
        selectedMemberIDs.compactMap { id -> (id: String, name: String)? in
            guard let name = StationIdentity.name(for: id) else { return nil }
            return (id, name)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: 成员

    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("成员驿站")
                    .font(AppTheme.TypeScale.bodyMedium)
                Text("\(selectedMemberIDs.count)")
                    .font(AppTheme.TypeScale.note)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            // 搜索（2026-11-21）：34 个内置驿站 + 自定义，滑到一半就找不到要选的
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("搜索驿站", text: $memberQuery)
                    .font(AppTheme.TypeScale.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !memberQuery.isEmpty {
                    Button {
                        memberQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10, style: .continuous))

            LazyVStack(spacing: 0) {
                ForEach(filteredCandidates, id: \.id) { candidate in
                    Button {
                        toggle(candidate.id)
                    } label: {
                        memberRow(candidate)
                    }
                    .buttonStyle(.plain)

                    if candidate.id != filteredCandidates.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func memberRow(_ candidate: (id: String, name: String)) -> some View {
        HStack(spacing: 12) {
            StationLogo(name: candidate.name, size: 30, showsShadow: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name.L)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let other = occupiedGroupName(candidate.id) {
                    // 2026-11-21 主人选 A（组是地点）：同一个品牌可以在多个点各有组，
                    // 所以这里不再说「会移出」，改成如实说明「也在别处」。
                    Text("在「\(other)」里，勾选会移过来")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.violet)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: selectedMemberIDs.contains(candidate.id)
                  ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(selectedMemberIDs.contains(candidate.id)
                                 ? AppTheme.accent : Color.secondary.opacity(0.35))
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private func toggle(_ memberID: String) {
        if selectedMemberIDs.contains(memberID) {
            selectedMemberIDs.remove(memberID)
        } else {
            selectedMemberIDs.insert(memberID)
        }
    }

    /// 这个成员现在归在哪个别的组里
    private func occupiedGroupName(_ memberID: String) -> String? {
        for group in StationGroupStore.all() where group.id != groupID {
            if group.memberIDs.contains(memberID) { return group.name }
        }
        return nil
    }

    // MARK: 删除

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Text("解散驿站组")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.10),
                            in: .rect(cornerRadius: AppTheme.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func deleteGroup() {
        guard let groupID else { return }
        StationGroupStore.delete(id: groupID)
        dismiss()
    }

    // MARK: 保存

    private func save() {
        guard !trimmedName.isEmpty else {
            errorMessage = "组名不能为空"
            return
        }
        guard StationGroupStore.isValidGroupName(trimmedName,
                                                excluding: groupID,
                                                builtinAndCustom: station.allNames) else {
            errorMessage = "「\(trimmedName)」与内置驿站、自定义驿站或已有驿站组重复，换一个名字。"
            return
        }

        let members = Array(selectedMemberIDs)
        // 一个驿站只在一个组：这次保存会把它们从哪些旧组里拿走（用来钉住历史记录）
        let displaced = StationGroupStore.displacedMembers(members, excluding: groupID)
        let inheritIcon = iconMode == .inherit ? iconInheritMemberID : nil
        let inheritLocation = locationInheritMemberID

        if let groupID, var group = StationGroupStore.group(id: groupID) {
            let oldName = group.name
            group.name = trimmedName
            group.memberIDs = members
            group.iconInheritMemberID = inheritIcon
            group.locationInheritMemberID = inheritLocation
            StationGroupStore.update(group)

            // 位置表以名字为 key（与自定义驿站同一套迁移口径）。
            // 组名不进 `StationIdentity` 表 —— 组关系挂的是成员 ID，组本身不需要名字映射。
            if oldName != trimmedName {
                locationStore.rename(from: oldName, to: trimmedName)
            }

            switch iconMode {
            case .custom:
                if let iconData { station.setIcon(iconData, for: groupID) }
            case .fallback, .inherit:
                station.clearIcon(for: groupID)
            }
        } else {
            guard let created = StationGroupStore.create(name: trimmedName,
                                                         memberIDs: members,
                                                         iconInheritMemberID: inheritIcon,
                                                         locationInheritMemberID: inheritLocation) else {
                errorMessage = "创建失败，请换个名字再试。"
                return
            }
            if iconMode == .custom, let iconData {
                station.setIcon(iconData, for: created.id)
            }
            // 新建时顺手选的位置：挂到组名上（沿用成员位置时不需要，组自己不落点）
            if inheritLocation == nil, let c = draftCoordinate {
                locationStore.set(StationLocation(latitude: c.latitude,
                                                  longitude: c.longitude,
                                                  radius: StationLocation.defaultRadius,
                                                  enabled: true),
                                  for: created.name)
            }
        }

        // 换组后把**已有记录**钉回原组：那些件当初是在老地方取的，
        // 不钉的话一次移组会让历史记录集体改判到新组。
        if !displaced.isEmpty {
            let store = PickupStore.shared
            for (memberID, oldGroupID) in displaced {
                guard let name = StationIdentity.name(for: memberID) else { continue }
                store.pinRecords(station: name, toGroup: oldGroupID)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }

        StationGroupStore.invalidateCache()
        dismiss()
    }
}
