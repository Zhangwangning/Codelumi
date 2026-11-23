import Foundation
import Security

// MARK: ============================================================================
// 本机设备码（2026-09-23 主人定型：凭证绑定设备）
//
// 商业模式：用户在 App 里拿到**本机设备码** → 发给服务提供方 → 对方用私钥
// 把这个码签进凭证 → 用户把凭证导回 App。于是**一张凭证只能在一台设备上生效**，
// 挡住"一个买家把凭证发到群里，所有人白嫖"。
//
// ── 码怎么来的 ──────────────────────────────────────────────────────────────
//
// 首次调用时随机生成一个 UUID（16 字节），转成 **32 位大写十六进制**。
// 不直接用 UUID 字符串（36 位带连字符）有两个原因：
//   · 用户要把它发给卖家，短且无连字符的十六进制更不容易抄错；
//   · 凭证载荷是 Base64 的 JSON，短 4 个字符也是省。
//
// ── 为什么存 Keychain 而不是 UserDefaults ──────────────────────────────────
//
// UserDefaults（含 App Group）在**卸载时会被系统一并删除**。用户卸载重装后
// 设备码变了 → 手上那张凭证当场失效 → 得重新找卖家换码。这种售后是纯损耗，
// 而 Keychain 的条目在卸载后仍然保留，重装能读回同一个值。
//
// ── 为什么还要往 App Group 写一份缓存 ─────────────────────────────────────
//
// 小组件扩展**读不到 App 的私有 Keychain**（要共享 Keychain 得另配
// keychain-access-groups，为一个只读字符串不值得）。但扩展侧的
// `EntitlementSnapshot.load()` 也要校验设备 —— 否则越狱用户把别人的凭证
// 塞进 `entitlement.json` 就能解锁。所以主 App 把码同步一份到 App Group，
// 扩展读那份。
//
// 🔴 因此扩展**只读缓存、绝不生成**：`cached` 返回 nil 时不落任何东西。
// 🔴 冷启动顺序：`CodelumiApp.init()` 必须调一次 `LicenseDevice.current`
//    （或 `bootstrap()`），把缓存写好，否则扩展会读到 nil。
// ============================================================================

enum LicenseDevice {
    private static let keychainService = "com.jikezhang.codelumi.device"
    private static let keychainAccount = "device-code"
    private static let cacheKey = "codelumi.deviceCode"

    /// 本机设备码：32 位大写十六进制，无连字符。
    ///
    /// 首次调用会生成并写入 Keychain + App Group 缓存；之后稳定不变
    /// （重装 App 也不变）。**只有主 App 该调它** —— 扩展请用 `cached`。
    static var current: String {
        if let cached { return cached }
        if let stored = readKeychain() {
            cache(stored)
            return stored
        }
        let fresh = makeCode()
        writeKeychain(fresh)
        cache(fresh)
        return fresh
    }

    /// 只读 App Group 缓存，**读不到就返回 nil，不生成任何东西**。
    ///
    /// 扩展进程用它；主 App 在 `load()` 的校验路径上也用它 —— 两边读同一份，
    /// 不会出现"App 认为匹配、小组件认为不匹配"的撕裂。
    static var cached: String? {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        guard let value = defaults.string(forKey: cacheKey), !value.isEmpty else { return nil }
        return value
    }

    /// 分组显示（每 8 位一组，**单行**），**仅供人眼核对**。
    ///
    /// 🔴 复制出去的永远是未分组的原值 —— 分组里那些连字符一旦被带进凭证，
    ///    校验就会失败。
    /// 🔴 **不折行**（主人 2026-09-23 要求）：32 位十六进制 + 3 个连字符 = 35 字符。
    ///    调用方（`LicenseImportView`）用 **15pt 等宽 + `lineLimit(1)`** 承载 ——
    ///    35 × 约 9pt ≈ 315pt，在 342pt 的卡片内容宽里刚好一行；**字号不得再调大**，
    ///    调大就会折行，那串码断成两截用户极容易漏抄。
    static func display(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 8).map { offset -> String in
            let start = code.index(code.startIndex, offsetBy: offset)
            let end = code.index(start, offsetBy: min(8, code.count - offset))
            return String(code[start..<end])
        }
        .joined(separator: "-")
    }

    /// 全遮蔽展示：**一个字符都不露，也不带连字符**。
    ///
    /// 2026-10-31 主人：设备 UUID 在界面上全部加密显示，不给用户明文查看的权限；
    /// 并且**不要**显示 `-` 分隔符 —— 那串分隔符会让人以为界面里真有一个可读的码，
    /// 去掉之后就是纯粹的一整块遮蔽，没有任何可读信息。
    /// 需要用时点「复制」拿完整值（走剪贴板，不经过屏幕）。
    static func masked(_ code: String) -> String {
        String(repeating: "•", count: 32)
    }

    /// 把用户可能贴回来的各种写法（小写、带连字符、带空格）归一成标准形态。
    /// 发码工具与 App 两侧都必须走它，否则"大小写差一个字母导致验不过"
    /// 会变成最常见的售后。
    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter(\.isHexDigit)
    }

    /// 判断凭证里绑的设备码是否就是本机。
    /// 空值一律视为"不匹配" —— 调用方应先判 `payload.device` 是否为空。
    static func matches(_ bound: String) -> Bool {
        let target = normalize(bound)
        guard !target.isEmpty else { return false }
        // 主 App 里 `cached` 必定已写好（见 `current`），扩展里靠 App 写过
        guard let mine = cached else { return false }
        return normalize(mine) == target
    }

    // MARK: 生成

    private static func makeCode() -> String {
        var uuid = UUID().uuid
        let bytes = withUnsafeBytes(of: &uuid) { Data($0) }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: App Group 缓存

    private static func cache(_ value: String) {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        defaults.set(value, forKey: cacheKey)
    }

    // MARK: Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func readKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    private static func writeKeychain(_ value: String) {
        // 先删后写：SecItemAdd 遇到同 service/account 的旧条目会返回
        // errSecDuplicateItem，不删就是永远写不进新的
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(value.utf8)
        // `AfterFirstUnlock`：用户重启手机后、首次解锁前也可能被后台读到
        // （小组件取时间线），比 `WhenUnlocked` 更合适，也不像
        // `Always` 那样在设备未解锁时暴露。
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
