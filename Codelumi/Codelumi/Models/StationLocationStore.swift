import Foundation
import CoreLocation
import SwiftUI

// MARK: - 驿站位置库（2026-11-16 主人：到达提醒 / 实验室）
//
// 内置驿站与自定义驿站**共用同一张表**：内置的只读项是名称 / 图标 / 能否删除，
// 位置是可以自己设的 —— 老大明确要求「我们内置的也要支持这个功能」。
// key 用驿站名，跟 StationDirectory 的自定义名、CourierBrand 的规范名同一口径。

/// 一个驿站的位置设置。
struct StationLocation: Codable, Hashable {
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    /// 围栏半径（米）
    var radius: CLLocationDistance
    /// 是否纳入到达提醒监控。设了位置但不启用 = 只存不监控。
    var enabled: Bool
    /// 最后一次改动这个位置的时间（2026-11-21）。
    ///
    /// 用途只有一个：围栏超过 iOS 的 20 个上限时，**优先监控最近用过的**地点 ——
    /// 用户刚设好位置的驿站才是他这几天要去的地方。
    /// 🔴 Optional：旧数据没有这个键，`decodeIfPresent` 会给 nil，排序时置底即可。
    var updatedAt: Date? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let defaultRadius: CLLocationDistance = 200
    /// 半径档位：驿站一般就在小区门口/沿街店铺，1 公里以上没意义
    static let radiusOptions: [CLLocationDistance] = [100, 200, 500, 1000]
}

final class StationLocationStore: ObservableObject {

    static let shared = StationLocationStore()

    private static let storeKey = "station.locations.v1"
    private let defaults: UserDefaults

    @Published private(set) var locations: [String: StationLocation]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storeKey),
           let decoded = try? JSONDecoder().decode([String: StationLocation].self, from: data) {
            self.locations = decoded
        } else {
            self.locations = [:]
        }
    }

    func location(for name: String) -> StationLocation? { locations[name] }

    /// 写入 / 更新位置。传 nil = 删除这个驿站的位置。
    func set(_ location: StationLocation?, for name: String) {
        if var location {
            location.updatedAt = Date()
            locations[name] = location
        } else {
            locations.removeValue(forKey: name)
        }
        persist()
        StationLocationService.shared.syncRegions()
    }

    func setEnabled(_ enabled: Bool, for name: String) {
        guard var value = locations[name] else { return }
        value.enabled = enabled
        value.updatedAt = Date()
        locations[name] = value
        persist()
        StationLocationService.shared.syncRegions()
    }

    /// 已启用围栏的驿站名（排序保证列表稳定，也让 20 个上限的裁剪可预期）
    var enabledNames: [String] {
        locations.filter { $0.value.enabled }.keys.sorted()
    }

    /// 已启用的名字，**按最近改动倒序**（围栏 20 上限按这个顺序裁）
    var enabledNamesByRecency: [String] {
        locations
            .filter { $0.value.enabled }
            .sorted { a, b in
                let ta = a.value.updatedAt ?? .distantPast
                let tb = b.value.updatedAt ?? .distantPast
                if ta != tb { return ta > tb }
                return a.key < b.key
            }
            .map(\.key)
    }

    /// 已设过位置的全部驿站名
    var configuredNames: [String] { locations.keys.sorted() }

    /// 自定义驿站改名：位置跟着名字走（key 是名字）
    func rename(from: String, to: String) {
        guard let value = locations.removeValue(forKey: from) else { return }
        locations[to] = value
        persist()
        StationLocationService.shared.syncRegions()
    }

    /// 自定义驿站删除：位置一起清掉，别留孤儿围栏
    func remove(named: String) {
        guard locations.removeValue(forKey: named) != nil else { return }
        persist()
        StationLocationService.shared.syncRegions()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        defaults.set(data, forKey: Self.storeKey)
    }
}
