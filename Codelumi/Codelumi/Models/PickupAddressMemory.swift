import Foundation

// MARK: ============================================================================
// 地址记忆（2026-11-05 主人：「记住地址纠正」）
//
// 场景：同一个驿站，短信里写的地址五花八门
//   ① 甘州院子南门馨月湖南门兔喜生活
//   ② 院子馨月湖南门店
// 用户心里只有一个名字：馨月湖南门兔喜生活。
//
// 做法：用户**改过一次**地址，就把「驿站 → 用户写的地址」记进 App Group；
// 之后命中同一驿站的短信，解析完直接用记住的那份。
//
// 🔴 纯本地（App Group），不外传、不联网；规则推不出的规范名只能这样学。
// ============================================================================

enum PickupAddressMemory {
    private static let key = "codelumi.addressMemory"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    static func address(for station: String) -> String? {
        guard let map = defaults.dictionary(forKey: key) as? [String: String],
              let value = map[station], !value.isEmpty else { return nil }
        return value
    }

    static func remember(station: String, address: String) {
        guard !station.isEmpty, !address.isEmpty else { return }
        var map = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        map[station] = address
        defaults.set(map, forKey: key)
        DiagnosticsLog.record("addressMemory", "learned station=\(station.count)字 addr=\(address.count)字")
    }

    static func forget(station: String) {
        var map = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        map.removeValue(forKey: station)
        defaults.set(map, forKey: key)
    }

    static var count: Int {
        (defaults.dictionary(forKey: key) as? [String: String])?.count ?? 0
    }
}
