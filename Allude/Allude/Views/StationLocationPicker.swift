import SwiftUI
import MapKit
import CoreLocation

// MARK: - 位置选择（草稿态，2026-11-17 老大）
//
// 老大定的口径：
//   · 驿站**创建时**就能顺手把位置加上（可选），不再要求「先保存、再回来设位置」；
//   · 打开就是**当前位置**——不用先按「用当前位置」，想改就点地图换点（手动选）；
//   · 这是草稿：只把坐标传回上层，落盘由创建流程在拿到驿站名之后统一做，
//     避免出现「名字还没定就先写了一条位置」的孤儿记录。
//
// 与 `StationLocationEditor`（已保存驿站的定位页）的分工：那边读写
// `StationLocationStore`，这边只捎一个坐标回去。

struct StationLocationPicker: View {

    /// 选中的坐标。进来时若为 nil，会自动取一次当前位置填进来。
    @Binding var coordinate: CLLocationCoordinate2D?
    /// 只用于地图标记的标题文字，可空
    var stationName: String = ""

    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    @State private var hint: String?
    @State private var locating = false
    /// 自动取位置只跑一次：用户手动改过点之后，不该再被拉回当前位置
    @State private var didAutoLocate = false

    private var corner: CGFloat { AppTheme.innerRadius }

    private var markerTitle: String {
        stationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "驿站位置" : stationName
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapCard
                statusCard
                Text("位置只存在本机，用于判断你有没有到店，不上传、不记录轨迹。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("选择位置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
                    .fontWeight(.semibold)
                    .disabled(coordinate == nil)
            }
            ToolbarItem(placement: .topBarLeading) {
                if coordinate != nil {
                    Button("清除") {
                        coordinate = nil
                        hint = nil
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .task {
            guard !didAutoLocate else { return }
            didAutoLocate = true
            // 已有坐标（改完又进来）：直接把镜头对过去，不重新定位
            if let coordinate {
                camera = .region(MKCoordinateRegion(center: coordinate,
                                                    latitudinalMeters: 800,
                                                    longitudinalMeters: 800))
                return
            }
            locateCurrent()
        }
    }

    // MARK: 地图

    private var mapCard: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate {
                    Marker(markerTitle, coordinate: coordinate)
                        .tint(AppTheme.violet)
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.primary.opacity(0.10), lineWidth: 0.5)
            }
            .mapControls { MapCompass() }
            .onTapGesture { point in
                guard let hit = proxy.convert(point, from: .local) else { return }
                coordinate = hit
                hint = nil
            }
            .overlay(alignment: .topTrailing) {
                // 🔴 放右上角：右下角是「高德地图」法律信息水印，圆钮压上去会打架
                locateButton
                    .padding(10)
            }
            .overlay(alignment: .bottom) {
                if coordinate == nil {
                    Text("在地图上点一下，标记驿站位置")
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
    }

    private var locateButton: some View {
        Button(action: locateCurrent) {
            Image(systemName: locating ? "location.fill" : "location")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.violet)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: .circle)
                .overlay {
                    Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(locating)
        .accessibilityLabel("回到当前位置")
    }

    private func locateCurrent() {
        locating = true
        StationLocationService.shared.requestCurrentCoordinate { hit in
            locating = false
            guard let hit else {
                hint = "没取到当前位置。可以直接在地图上点一下选点，或到系统设置里检查定位权限。"
                return
            }
            coordinate = hit
            camera = .region(MKCoordinateRegion(center: hit,
                                                latitudinalMeters: 800,
                                                longitudinalMeters: 800))
            hint = nil
        }
    }

    // MARK: 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已选位置")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
            if let coordinate {
                Text(String(format: "%.5f, %.5f",
                            coordinate.latitude, coordinate.longitude))
                    .font(AppTheme.TypeScale.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("未选择")
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
}
