import SwiftUI
import MapKit
import CoreLocation

// MARK: - 驿站定位编辑页（2026-11-16 主人：到达提醒 / 实验室）
//
// 内置驿站与自定义驿站**共用这一页**：内置的只读项是名称 / 图标 / 能否删除，
// 位置同样可以自己设。交互按老大定的口径：
//   · 地图上点一下落点（可反复改）；
//   · 或「用当前位置」一键记点（只申请「使用期间」，不碰「始终」）；
//   · 再选提醒半径，决定这个驿站是否纳入到达提醒。
//
// ⚠️ 地图底图依赖系统地图服务，离线时可能空白 —— 但取坐标不依赖底图，
//    仍可点选 / 用当前位置，这也是把到达提醒标成实验功能的原因之一。

struct StationLocationEditor: View {

    let stationName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var locationStore = StationLocationStore.shared

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var radius: CLLocationDistance
    @State private var enabled: Bool
    @State private var camera: MapCameraPosition
    @State private var hint: String?
    @State private var askingLocation = false
    @State private var showRadiusMenu = false
    /// 没存过位置时，进页面自动取一次当前位置当默认点（只跑一次）
    @State private var didAutoLocate = false

    init(stationName: String) {
        self.stationName = stationName
        let saved = StationLocationStore.shared.location(for: stationName)
        _coordinate = State(initialValue: saved?.coordinate)
        _radius = State(initialValue: saved?.radius ?? StationLocation.defaultRadius)
        _enabled = State(initialValue: saved?.enabled ?? false)
        if let saved {
            let span = max(saved.radius * 4, 1_000)
            _camera = State(initialValue: .region(MKCoordinateRegion(
                center: saved.coordinate,
                latitudinalMeters: span,
                longitudinalMeters: span)))
        } else {
            _camera = State(initialValue: .automatic)
        }
    }

    private var corner: CGFloat { AppTheme.innerRadius }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapCard
                coordinateCard
                settingsCard
                // 2026-11-21 主人：内置驿站点进来也要能直接分组，不用再绕到组里去勾
                StationGroupMembershipRow(stationName: stationName)
                disclaimer
                if locationStore.location(for: stationName) != nil {
                    deleteButton
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("驿站位置")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(coordinate == nil)
            }
        }
        .task {
            // 老大 2026-11-17：定位直接手动选，打开就该有个可用的默认点 ——
            // 没存过位置时自动取当前位置落到地图上，想换就点地图别处。
            guard !didAutoLocate else { return }
            didAutoLocate = true
            guard coordinate == nil else { return }
            useCurrentLocation()
        }
    }

    // MARK: 地图

    private var mapCard: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate {
                    Marker(stationName, coordinate: coordinate)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.primary.opacity(0.10), lineWidth: 0.5)
            }
            .mapControls {
                MapCompass()
            }
            // 点一下即落点。Map 自身的拖拽/缩放手势与 tap 不冲突。
            .onTapGesture { point in
                if let hit = proxy.convert(point, from: .local) {
                    coordinate = hit
                    hint = nil
                }
            }
            .overlay(alignment: .topTrailing) {
                // 🔴 放右上角：右下角是「高德地图」法律信息水印，圆钮压上去会打架
                locateButton
                    .padding(10)
            }
        }
        .overlay(alignment: .bottom) {
            if coordinate == nil {
                Text("在地图上点按，标记驿站所在位置")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.bottom, 10)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 地图右下角的「定位到当前位置」圆钮。
    /// 🔴 2026-11-17：原来是整条白卡按钮，占地又显眼；定位改成默认自动取一次，
    ///    这里只留一个返场用的圆钮（失败了也能重试）。
    private var locateButton: some View {
        Button(action: useCurrentLocation) {
            Image(systemName: askingLocation ? "location.fill" : "location")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.violet)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: .circle)
                .overlay {
                    Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(askingLocation)
        .accessibilityLabel("定位到当前位置")
    }

    private func useCurrentLocation() {
        askingLocation = true
        StationLocationService.shared.requestCurrentCoordinate { hit in
            askingLocation = false
            guard let hit else {
                hint = "没取到当前位置。可以在地图上点一下，或到系统设置里检查定位权限。"
                return
            }
            coordinate = hit
            camera = .region(MKCoordinateRegion(center: hit,
                                                latitudinalMeters: 1_000,
                                                longitudinalMeters: 1_000))
            hint = nil
        }
    }

    // MARK: 设置

    private var settingsCard: some View {
        VStack(spacing: 0) {
            SettingsPlainRow(title: "提醒半径") {
                // 🔴 不用系统 Menu：它会把 label 强制染成蓝色，
                //    与通知页「值 = 灰字 + chevron」的既定口径不一致。
                //    这里沿用同一套自绘 popover（勾号 Apple 蓝、贴最右端）。
                Button {
                    showRadiusMenu = true
                } label: {
                    SettingsValueLabel(text: Self.radiusLabel(radius))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showRadiusMenu, arrowEdge: .top) {
                    radiusMenu
                        .presentationCompactAdaptation(.popover)
                }
            }

            SettingsDivider(style: .plain)

            // 2026-11-22 主人：实验标记要挂在**这一行**的标题上，
            // 不是孤零零摆在页面底部的说明旁边。
            SettingsPlainRow(title: "到达提醒", isLab: true) {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(AppTheme.accent)
            }
        }
        .settingsCard()
    }

    /// 半径选单（自绘）：勾号贴最右端、用系统蓝；未选中行不留占位图形。
    private var radiusMenu: some View {
        VStack(spacing: 0) {
            ForEach(StationLocation.radiusOptions, id: \.self) { option in
                Button {
                    radius = option
                    showRadiusMenu = false
                } label: {
                    HStack(spacing: 12) {
                        Text(Self.radiusLabel(option))
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 20)
                        if option == radius {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(.systemBlue))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 168, height: 42)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private static func radiusLabel(_ value: CLLocationDistance) -> String {
        value >= 1_000 ? "1 公里" : "\(Int(value)) 米"
    }

    private var coordinateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前坐标")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
            if let coordinate {
                Text(String(format: "%.5f, %.5f",
                            coordinate.latitude, coordinate.longitude))
                    .font(AppTheme.TypeScale.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("未设置")
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.tertiary)
            }
            if let hint {
                Text(hint.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(AppTheme.pendingTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface()
    }

    private var disclaimer: some View {
        // 2026-11-22 主人：「实验标记要挂在到达提醒的标题里」——
        // 徽章已挪到上面那一行，这里只留代价与承诺，不再重复标记。
        Text("系统围栏可能有几分钟延迟，低电量、离线或定位精度差时可能不触发。位置只存本机，用于判断你是否到达，不上传、不记录轨迹。")
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var deleteButton: some View {
        Button {
            locationStore.set(nil, for: stationName)
            dismiss()
        } label: {
            Text("删除这个位置")
                .font(AppTheme.TypeScale.bodyMedium)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.10),
                            in: .rect(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let coordinate else {
            hint = "先在地图上点一下，或按「用当前位置」。"
            return
        }
        locationStore.set(StationLocation(latitude: coordinate.latitude,
                                          longitude: coordinate.longitude,
                                          radius: radius,
                                          enabled: enabled),
                          for: stationName)
        dismiss()
    }
}
