import SwiftUI
import PhotosUI
import WidgetKit

// MARK: - 自定义驿站编辑页（2026-10-15 主人定稿）
//
// 添加与编辑合并为同一页面：
//   · 名称必填，图标**可选** —— 不换图标则按名称首字自动生成（CourierLogo 兜底）；
//   · 图标来源不限（系统相册任意图片），保存后统一按圆角矩形呈现；
//   · 编辑模式可改名、可换图、可删除；内置驿站没有这个入口（只读）。

struct StationEditView: View {

    enum Mode: Equatable {
        case add
        case edit(String)   // 原名称
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var station = StationDirectory.shared
    /// 位置摘要要跟着设置页的改动即时刷新（2026-11-16 到达提醒）
    @ObservedObject private var locationStore = StationLocationStore.shared

    @State private var name: String
    /// 图标原始数据：编辑态预填当前图标；添加态为 nil（未选）
    @State private var iconData: Data?
    /// 本次是否真的换过图（决定保存时是否写盘，避免无变化也重存）
    @State private var iconChanged = false
    @State private var pickerSelection: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirm = false
    /// 添加态的位置草稿：进页面即当前位置，保存时随新驿站名一起落盘
    @State private var draftCoordinate: CLLocationCoordinate2D?
    @State private var showLocationPicker = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _iconData = State(initialValue: nil)
        case .edit(let original):
            _name = State(initialValue: original)
            _iconData = State(initialValue: StationDirectory.shared.iconData(for: original))
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var originalName: String? {
        if case .edit(let name) = mode { return name }
        return nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty }

    private var corner: CGFloat { 96 * 0.29 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 2026-11-21：图标与名称合并成一张卡（原来两张卡各占半屏，
                // 中间还夹一句说明）。现在「点头像＝换图、点名字＝改名」一眼就懂。
                headerCard
                // 2026-11-17 老大：创建时就能加位置（可选），不再要求「先建好再回来设」。
                locationCard
                if isEdit {
                    groupCard
                    deleteButton
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(isEdit ? "编辑驿站" : "添加驿站")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerSelection,
                      matching: .images, photoLibrary: .shared())
        .task(id: pickerSelection) {
            guard let item = pickerSelection else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                iconData = data
                iconChanged = true
            }
            pickerSelection = nil
        }
        .sheet(isPresented: $showLocationPicker) {
            NavigationStack {
                StationLocationPicker(coordinate: $draftCoordinate,
                                      stationName: trimmedName)
            }
        }
        .alert("无法保存", isPresented: $showError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorMessage.L)
        }
        .alert(isEdit ? "删除这个驿站？" : "放弃添加？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let original = originalName { station.remove(named: original) }
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(isEdit
                 ? "删除后，卡片将不再自动标注「\(originalName ?? "")」。"
                 : "当前编辑的内容不会被保存。")
        }
    }

    // MARK: 头部卡（图标 + 名称，2026-11-21 合并）

    private var headerCard: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                preview
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(AppTheme.accent, in: .circle)
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更换驿站图标")

            VStack(alignment: .leading, spacing: 6) {
                TextField(isEdit ? "驿站名称" : "如「XX 便利店代收」", text: $name)
                    .font(.system(size: 17, weight: .medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if iconData != nil {
                    Button {
                        iconData = nil
                        iconChanged = true
                    } label: {
                        Text("用名称首字")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// 预览优先级：已选新图 > 当前名称兜底首字（首字实时跟着输入变）
    @ViewBuilder
    private var preview: some View {
        if let data = iconData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 64 * 0.29, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 64 * 0.29, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 0.5)
                }
        } else if !trimmedName.isEmpty {
            CourierLogo(company: trimmedName, size: 64)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 64 * 0.29, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 64, height: 64)
        }
    }

    // MARK: 驿站组（2026-11-21 主人：点驿站就能快速分组）

    private var groupCard: some View {
        // 与内置驿站定位页共用同一份 Menu（2026-11-21 抽出组件）
        StationGroupMembershipRow(stationName: originalName ?? trimmedName)
    }

    // MARK: 位置（创建态与编辑态都显示，2026-11-17 老大）

    @ViewBuilder
    private var locationCard: some View {
        if isEdit {
            // 已保存的驿站：进定位设置页（读写位置表，还能调半径 / 启停提醒）
            NavigationLink {
                StationLocationEditor(stationName: originalName ?? "")
            } label: {
                locationRowLabel(title: "位置",
                                 summary: locationSummary,
                                 showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            // 还没保存：先在草稿里选，保存时随驿站名一起落盘
            Button {
                showLocationPicker = true
            } label: {
                locationRowLabel(title: "位置（可选）",
                                 summary: draftLocationSummary,
                                 showsChevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var draftLocationSummary: String {
        guard let c = draftCoordinate else { return "未设置，默认不填也可以" }
        return String(format: "已选 %.4f, %.4f", c.latitude, c.longitude)
    }

    private func locationRowLabel(title: String,
                                  summary: String,
                                  showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.violet)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.L)
                    .font(AppTheme.TypeScale.bodyMedium)
                    .foregroundStyle(.primary)
                Text(summary.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var locationSummary: String {
        guard let original = originalName,
              let loc = locationStore.location(for: original) else {
            return "未设置"
        }
        return String(format: "%.5f, %.5f", loc.latitude, loc.longitude)
    }

    // MARK: 删除（仅编辑态）

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Text("删除驿站")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.10),
                            in: .rect(cornerRadius: AppTheme.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 保存

    private func save() {
        guard !trimmedName.isEmpty else {
            errorMessage = "名称不能为空"
            showError = true
            return
        }

        if let original = originalName {
            // 编辑：先改名（重名会失败并提示），再按新名存图
            if trimmedName != original {
                guard station.rename(original, to: trimmedName) else {
                    errorMessage = "名称与内置或已有驿站重复"
                    showError = true
                    return
                }
            }
            if iconChanged, let data = iconData {
                station.setIcon(data, for: trimmedName)
            }
        } else {
            // 添加：先建名，再存图
            guard station.add(trimmedName) else {
                errorMessage = "名称与内置或已有驿站重复"
                showError = true
                return
            }
            if let data = iconData {
                station.setIcon(data, for: trimmedName)
            }
            // 位置草稿：创建时选过就一起落盘
            if let c = draftCoordinate {
                StationLocationStore.shared.set(
                    StationLocation(latitude: c.latitude,
                                    longitude: c.longitude,
                                    radius: StationLocation.defaultRadius,
                                    enabled: true),
                    for: trimmedName)
            }
        }
        dismiss()
    }
}

// MARK: - 添加驿站 · 居中弹窗（2026-11-08 主人定）

/// 参考系统 alert 版式：半透明蒙层 + 居中玻璃卡，两个胶囊按钮（取消 / 保存）。
/// 原来「添加驿站」是推入的独立页面，主人要求改成弹窗，不再切换页面。
struct StationAddDialog: View {
    var onDismiss: () -> Void

    @ObservedObject private var station = StationDirectory.shared

    @State private var name = ""
    @State private var iconData: Data?
    @State private var pickerSelection: PhotosPickerItem?
    @State private var errorMessage: String?
    /// 创建时顺手选的位置（草稿）：保存时才随驿站名一起落盘
    @State private var draftCoordinate: CLLocationCoordinate2D?
    @State private var showLocationPicker = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("添加驿站")
                .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
                .padding(.top, 4)

            // 图标（可选）：点一下从相册挑，没选就按名称首字自动生成
            PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                iconPreview
            }
            .buttonStyle(.plain)

            TextField("驿站名称，如「XX 便利店代收」", text: $name)
                .font(AppTheme.TypeScale.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // 位置（可选，2026-11-17 老大）：创建时就能加，进页面即当前位置，想改就点地图
            locationRow

            if let errorMessage {
                Text(errorMessage.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(AppTheme.pendingTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                dialogButton("取消", filled: false) { onDismiss() }
                dialogButton("保存", filled: true) { save() }
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.5 : 1)
            }
        }
        .padding(20)
        .frame(maxWidth: 320)
        // 🔴 弹窗要**读得清**：玻璃太透会透出后面的品牌图标。
        //    用系统厚材质打底 + 细描边 + 阴影，观感与系统 alert 一致。
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppTheme.cardSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, 28)
        .task(id: pickerSelection) {
            guard let item = pickerSelection else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                iconData = data
            }
            pickerSelection = nil
        }
        .sheet(isPresented: $showLocationPicker) {
            NavigationStack {
                StationLocationPicker(coordinate: $draftCoordinate,
                                      stationName: trimmedName)
            }
        }
    }

    /// 位置一行：进页面即当前位置，可清空（不设位置）。
    private var locationRow: some View {
        Button {
            showLocationPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: draftCoordinate == nil
                      ? "mappin.slash" : "mappin.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(draftCoordinate == nil
                                     ? Color.secondary : AppTheme.violet)

                Text(draftLocationSummary)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(draftCoordinate == nil ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(AppTheme.TypeScale.note.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var draftLocationSummary: String {
        guard let c = draftCoordinate else { return "位置（可选）" }
        return String(format: "位置 %.4f, %.4f", c.latitude, c.longitude)
    }

    @ViewBuilder
    private var iconPreview: some View {
        ZStack {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if !trimmedName.isEmpty {
                CourierLogo(company: trimmedName, size: 84)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 84, height: 84)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(5)
                .background(AppTheme.accent, in: .circle)
                .offset(x: 6, y: 6)
        }
        .accessibilityLabel("选择图标")
    }

    private func dialogButton(_ title: String,
                              filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.TypeScale.body.weight(.semibold))
                .foregroundStyle(filled ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .appGlass(.capsule,
                          tint: filled ? AppTheme.accent : nil,
                          interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        guard station.add(trimmedName) else {
            errorMessage = "名称与内置或已有驿站重复"
            return
        }
        if let iconData { station.setIcon(iconData, for: trimmedName) }
        writeDraftLocation()
        onDismiss()
    }

    /// 创建时选过位置就一起落盘（2026-11-17 老大）。
    /// 点了「位置」就是要提醒，所以直接 `enabled: true`；全局开关 / 权益 /
    /// 权限任一不满足时 `syncRegions()` 自己会跳过，不会偷偷起围栏。
    private func writeDraftLocation() {
        guard let c = draftCoordinate else { return }
        StationLocationStore.shared.set(
            StationLocation(latitude: c.latitude,
                            longitude: c.longitude,
                            radius: StationLocation.defaultRadius,
                            enabled: true),
            for: trimmedName)
    }
}
