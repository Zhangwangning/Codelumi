import Foundation

// MARK: ============================================================================
// 本机安装的「iOS 签名」还剩多久（2026-11-05）
//
// 为什么要它：免费 Apple ID 的描述文件只有 7 天，到期 App 直接打不开（不是崩，
// 是系统拒绝启动）。用户看不出还剩几天，只能凭感觉"好像昨天还能用"。
//
// 做法：读主 bundle 里的 `embedded.mobileprovision`（一个 CMS 签名包，
// 里面原样嵌着 XML plist），把 `<?xml … </plist>` 那段切出来解析，
// 拿 `ExpirationDate`。**不需要 Security.framework，也不需要联网。**
//
// ⚠️ App Store 分发的版本**没有** embedded.mobileprovision → 返回 nil，
// 界面上就不显示这一行（正式版不该有"签名倒计时"这种概念）。
// ============================================================================

enum SigningProfile {

    /// 描述文件到期时间；读不到（App Store 版 / 文件缺失）返回 nil
    static let expirationDate: Date? = {
        // 截图脚手架：模拟器上没有描述文件，用 FAKE_SIGNING_DAYS 造一个（仅 Debug）
        if BuildFlags.scaffoldsEnabled,
           let raw = ProcessInfo.processInfo.environment["FAKE_SIGNING_DAYS"],
           let days = Int(raw) {
            return Calendar.current.date(byAdding: .day, value: days, to: Date())
        }
        let url = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url) else { return nil }

        // 在 CMS 里定位内嵌的 XML plist
        guard let startRange = data.range(of: Data("<?xml".utf8)),
              let endRange = data.range(of: Data("</plist>".utf8)),
              startRange.lowerBound < endRange.upperBound else { return nil }

        let plistData = data[startRange.lowerBound..<endRange.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(
            from: Data(plistData), options: [], format: nil) as? [String: Any],
              let expiry = plist["ExpirationDate"] as? Date else { return nil }
        return expiry
    }()

    /// 距到期还有几天（向下取整）。已过期返回负数；读不到返回 nil。
    static var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }

    /// 界面一句话：还剩 N 天 / 今天到期 / 已过期
    static var statusText: String? {
        guard let days = daysRemaining else { return nil }
        if days < 0 { return "已过期，需重新安装" }
        if days == 0 { return "今天到期" }
        return "还剩 \(days) 天"
    }
}
