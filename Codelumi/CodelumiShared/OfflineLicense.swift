import Foundation
import CryptoKit

// MARK: ============================================================================
// 离线凭证（2026-09-23 定型）
//
// 商业形态：Codelumi**纯离线**运行 —— App 内不含任何价格、购买按钮、外链或
// 订阅引导。用户在外部平台下单后拿到一串凭证，在「解锁」页粘贴导入即可。
//
// **为什么用非对称签名，而不是校验一个固定字符串**
//   固定字符串（以及任何本地可推导的规则）反编译一次即全网泄露：一个买家
//   把它发到群里，等于所有人免费。签名方案里 App 只带**公钥**，而公钥推不出
//   私钥，所以反编译 App 拿不到任何能用来伪造凭证的东西。
//
// 🔴 私钥永不进仓库、永不进 App 包，只在发码时使用（tools/license-gen/）。
// 🔴 换公钥 = 已发出的全部凭证当场作废。要轮换必须让 App **同时接受新旧**
//    两把公钥（`publicKeysBase64` 做成数组就是为了这个），不能直接替换。
//
// 凭证格式（三段，`.` 分隔，Base64URL 无填充）：
//
//     CLIP1.<payload>.<signature>
//
// payload 是 JSON：`{"s":"lifetime","e":null,"i":"…","n":"订单号","d":"设备码"}`
//   s = 档位   e = 到期时间（永久档为 null）   i = 签发时间   n = 备注
//   d = 绑定设备码（32 位大写 HEX，**必填**，见 `LicenseDevice`）
//
// 🔴 一张凭证只在签发时指定的那台设备上生效：买家把码转发给别人也解锁不了。
//    这是纯离线体系里唯一能挡「一码多卖」的机制，不能省。
//
// **签名对象是 `CLIP1.<payload>` 整段**，不是只有 payload —— 否则把前缀
// 从 CLIP1 改成 CLIP2 就能骗过任何"只签 payload"的实现。
//
// ⚠️ 本地授权的天花板：能防伪造，防不住越狱后直接改文件。但因为我们**每次
//    读取都重新验签**（见 `EntitlementSnapshot.load()`），篡改 entitlement.json
//    里的档位字段是无效的 —— 签名对不上，当场降级。
// ============================================================================

// MARK: - 档位

/// 凭证里卖的档位。
///
/// 🔴 2026-10-30 改为**买断制**（主人定）：
///    · `lifetime` = 买断，凭证**不带到期字段**；
///    · `trial`    = 临时凭证，到期时间 = 签发时间 + 7 天。
///    原来那套 `monthly` / `yearly` 订阅档已删除 —— 不是年费制，
///    所以凭证层也不再出现订阅语义。
enum LicenseService: String, Codable, CaseIterable {
    case trial
    case lifetime
    /// 🔴 历史订阅档（2026-09 那批发出的年费/月付凭证）。
    ///
    /// **只用于解码，不再签发** —— 留着是因为真机上确实还有生效中的旧凭证
    /// （已售出的一张 `yearly` 有效期到 2027-10）。删掉这两个 case 的话，
    /// 那些凭证会在 `JSONDecoder` 这一步解不出枚举，被判 `malformed`，
    /// 用户当场掉回免费档 —— 那是"改版把人家买过的东西弄没了"，绝不能发生。
    ///
    /// 它们统一映射到 `.trial`：语义正好对（都是「带到期时间的凭证」），
    /// 到期由 `verify` 里的 `expiresAt <= now` 自然降级，不需要额外逻辑。
    case monthly
    case yearly

    var plan: MembershipPlan {
        switch self {
        case .trial, .monthly, .yearly: return .trial
        case .lifetime: return .lifetime
        }
    }

    var title: String { plan.title }
}

// MARK: - 载荷

/// 凭证里签名的内容。字段名取短（s/e/i/n/d）是为了让凭证字符串短到能贴进
/// 聊天框而不折行 —— 这是买家要手动复制的字符串，长度直接等于出错概率。
struct LicensePayload: Codable, Equatable {
    var service: LicenseService
    /// 到期时间。永久档为 nil（不设到期）。
    var expiresAt: Date?
    var issuedAt: Date?
    /// 自由备注，例如订单号后四位 —— 只作售后对账用，App 不解析。
    var note: String?
    /// 🔴 **绑定的设备码**（32 位大写十六进制，见 `LicenseDevice`）。
    ///
    /// 这是整套体系里唯一"防白嫖"的字段：一张凭证只有落在签发时指定的那台
    /// 设备上才生效，买家把凭证转发给别人、别人导进去也白搭。
    ///
    /// 签发侧**必填**（`issue.mjs --device`），App 侧**空值即拒绝** ——
    /// 不带设备码的凭证等于"全网通用券"，正是要挡的东西。
    var device: String?

    enum CodingKeys: String, CodingKey {
        case service = "s"
        case expiresAt = "e"
        case issuedAt = "i"
        case note = "n"
        case device = "d"
    }
}

// MARK: - 失败原因

/// 每一种失败都给一句**能指导下一步动作**的话。用户拿到一串码被拒时，
/// 最需要知道的是"是复制少了、还是这码本身是假的、还是已经过期了"。
enum LicenseError: Error, Equatable {
    /// 段数不对 / Base64 解不开
    case malformed
    /// 前缀不是 CLIP1
    case wrongPrefix
    /// 签名校验不通过（伪造、或传输中缺字符）
    case badSignature
    /// 签名有效但已过有效期
    case expired(Date)
    /// 签名有效，但凭证里没绑设备码（签发侧漏传）
    case unbound
    /// 签名有效，但绑的不是本机
    case wrongDevice

    var title: String {
        switch self {
        case .malformed: return "凭证格式不对"
        case .wrongPrefix: return "这不是Codelumi的凭证"
        case .badSignature: return "凭证校验未通过"
        case .expired: return "凭证已过期"
        case .unbound: return "凭证没有绑定设备"
        case .wrongDevice: return "这张凭证不属于这台设备"
        }
    }

    var message: String {
        switch self {
        case .malformed:
            return "看起来少复制了一段。凭证是一整串没有空格的字符，从 CLIP1 开始、到末尾结束，请整段复制。"
        case .wrongPrefix:
            return "Codelumi的凭证以 CLIP1 开头。如果卖家给的是图片或链接，请让对方发原始的一串码。"
        case .badSignature:
            return "这串码校验不通过，可能是复制时漏了字符或多了空格。请整段重新复制一次；仍然不行请向签发方核对。"
        case .expired(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy 年 M 月 d 日"
            return "这张凭证的有效期到 \(formatter.string(from: date))，已经过期。需要继续使用请联系签发方。"
        case .unbound:
            return "这张凭证没有绑定任何设备，无法在本机启用。请把本机设备码提供给签发方，按这个码重新签发。"
        case .wrongDevice:
            return "每张凭证只在一台设备上生效，这张不是为当前设备签发的。请把本机设备码提供给签发方，按这个码重新签发。"
        }
    }
}

// MARK: - 验签

enum LicenseVerifier {
    /// 格式版本前缀。将来换算法（比如改 Ed25519）时升成 CLIP2，
    /// 老版本 App 会明确回「不支持」而不是解出一堆乱码。
    static let prefix = "CLIP1"

    /// 验签公钥（P-256 / prime256v1，SPKI-DER，Base64）。
    ///
    /// 🔴 公钥本身不是秘密，公开也无妨 —— 它只能验、不能签。
    /// 🔴 数组里保留多把是为了**平滑轮换**：新凭证用新私钥签，旧凭证靠旧公钥
    ///    继续有效；等所有存量凭证都过期了再把旧的那把删掉。
    /// 🔴 私钥在 `tools/license-gen/private-key.pem`，**永不入库**。
    private static let publicKeysBase64: [String] = [
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAErD8m/KY2RAZ0LOCUE+aJK2IiC8vuStczFvGcPkyud8TpQlHvNow7xfICx3ZZmnJLG6jP3UkokEuDSzl5SY30jg=="
    ]

    private static let keys: [P256.Signing.PublicKey] = publicKeysBase64.compactMap {
        guard let der = Data(base64Encoded: $0) else { return nil }
        return try? P256.Signing.PublicKey(derRepresentation: der)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// 校验一串凭证。
    ///
    /// - Parameter now: 判定"是否过期"所依据的时间。默认当前时间；调用方
    ///   （`EntitlementSnapshot.load()`）会传入**历史见过的最大时间**，
    ///   以封堵「把系统时间调回去继续用过期卡」这条路。
    /// - Parameter device: 用来和凭证里绑定的设备码比对的**本机码**。
    ///   默认取 `LicenseDevice.cached`（App Group 缓存）。
    ///
    /// 🔴 设备校验放在这里而不是各调用点，是因为"每处都记得校验"迟早会漏一处；
    ///    收进唯一的验签入口，任何拿到 payload 的路径都已经过设备比对。
    /// 🔴 缓存读不到时（App 从未启动过的扩展进程）判定为不匹配 —— 那种状态下
    ///    本机不可能存有凭证（凭证必须经 App 导入），拒绝是安全的默认值。
    static func verify(_ raw: String,
                       now: Date = Date(),
                       device: String? = LicenseDevice.cached) -> Result<LicensePayload, LicenseError> {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = code.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        guard parts.count == 3 else { return .failure(.malformed) }
        guard parts[0] == prefix else { return .failure(.wrongPrefix) }

        guard let payloadData = Data(base64URL: parts[1]),
              let signatureData = Data(base64URL: parts[2]) else {
            return .failure(.malformed)
        }

        // 签名对象是整段「前缀.payload」——见文件头说明
        let signed = Data("\(parts[0]).\(parts[1])".utf8)

        guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        else { return .failure(.badSignature) }

        // 🔴 这里**不能**写 `try?`：iOS 27 SDK 起 CryptoKit 把
        //    `isValidSignature(_:for:)` 从 `throws` 改成了直接返回 `Bool`
        //    （签名无效即 `false`，不再抛 `CryptoKitError`）。多包一层 `try?`
        //    只会得到「No calls to throwing functions occur within 'try'
        //    expression」警告；判断结果完全一样，去掉即可。
        //    旧写法遗留自 iOS 26 及更早的 SDK，那些版本才需要 `try?`。
        let verified = keys.contains { key in
            key.isValidSignature(signature, for: signed)
        }
        guard verified else { return .failure(.badSignature) }

        guard let payload = try? decoder.decode(LicensePayload.self, from: payloadData)
        else { return .failure(.malformed) }

        // 设备绑定 —— 先于过期判定，因为"不是你的卡"比"卡过期了"更该先说
        guard let bound = payload.device, !LicenseDevice.normalize(bound).isEmpty else {
            return .failure(.unbound)
        }
        guard let mine = device,
              !LicenseDevice.normalize(mine).isEmpty,
              LicenseDevice.normalize(mine) == LicenseDevice.normalize(bound) else {
            return .failure(.wrongDevice)
        }

        if let expiry = payload.expiresAt, expiry <= now {
            return .failure(.expired(expiry))
        }

        return .success(payload)
    }
}

// MARK: - 激活

enum LicenseActivation {
    /// 校验并写入权益。
    ///
    /// 🔴 **只升不降**：已经解锁永久版的用户又导入一张月卡（比如买多了、
    ///    或把旧卡翻出来再导一次），不该被打回月付。低档凭证在更高档位
    ///    生效期间视为"已生效"，直接返回成功而不改动现状 —— 报错只会让人
    ///    以为卡是假的。
    static func activate(_ raw: String) -> Result<LicensePayload, LicenseError> {
        // 🔴 这里显式传 `LicenseDevice.current` 而不是走默认的 `cached`：
        //    `current` 会"读不到就生成并写缓存"，保证这次导入之后，
        //    App Group 里必定有一份与本机一致的设备码 —— 否则扩展侧
        //    下次校验时读到 nil，会把这刚导入的凭证当成不是本机的。
        // 🔴 2026-10-31：**激活也必须按水位判定**，否则"到期后把系统时间调回去、
        //    再把同一张凭证粘一次"就能续命 —— 因为 `verify` 默认用 `Date()`，
        //    而 `load()` 用的是 `max(Date(), 水位)`。两条路径口径不一致就是漏洞。
        //
        // 水位（`lastSeenAt`）只增不减：它是"这台设备曾经见过的最晚时间"，
        // 已经用过的到期凭证，无论怎么调时间都过不去。
        let current = EntitlementSnapshot.load()
        let reference = max(Date(), current.lastSeenAt ?? .distantPast)

        switch LicenseVerifier.verify(raw, now: reference, device: LicenseDevice.current) {
        case .failure(let error):
            return .failure(error)

        case .success(let payload):
            let incoming = payload.service.plan

            // 🔴 「只升不降」只在当前权益**有有效凭证背书**时才成立（2026-09-24 修订）。
            //
            // 原实现只判 `current.plan.isActive`，于是任何「无凭证的会员快照」都会
            // 永久压住后续导入 —— 这类快照有两个来源：
            //   · 截图 / 调试脚手架 `PLAN=` / `PRO=1`：`PickupStore.setPlan` 走的是
            //     正式链路、真写 App Group，但**不带 license 字段**；
            //   · 老版本升级上来的已购用户（当年还没有凭证体系）。
            //
            // 症状：导入一张月付凭证 → 导入页提示「已解锁 · 月付会员」（那里的档位
            // 取自凭证载荷）→ 回到 VIP 页仍是「永久会员」，且**再导入任何凭证都无法
            // 纠正**。两个页面自相矛盾，用户无从自解。
            //
            // 无凭证的状态没有签名背书，本就不该压过一张验签通过的正式凭证，
            // 因此必须以「当前权益是否由凭证支撑」作为前置条件。
            let backedByLicense = !(current.license ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

            if backedByLicense, current.plan.isActive, incoming.rank < current.plan.rank {
                return .success(payload)
            }

            EntitlementSnapshot.activate(plan: incoming,
                                         expiresAt: payload.expiresAt,
                                         license: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            return .success(payload)
        }
    }
}

// MARK: - 档位高低

extension MembershipPlan {
    /// 档位高低，**只用于「只升不降」的比较**，不参与任何价格或展示逻辑。
    var rank: Int {
        switch self {
        case .none: return 0
        case .trial: return 1
        case .lifetime: return 3
        }
    }
}

// MARK: - Base64URL

// 凭证走 URL 安全的 Base64（`-` `_`、无 `=` 填充）：它要在聊天软件、
// 短信、表单里传来传去，标准 Base64 的 `+` `/` `=` 会在这些环节被转义或
// 截断，是最常见的"明明复制对了却校验失败"来源。

extension Data {
    init?(base64URL string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 { normalized += "=" }
        self.init(base64Encoded: normalized)
    }

    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
