import Foundation
import FoundationModels

// MARK: ============================================================================
// 端侧 AI 辅助解析（2026-10-28 主人：「在解析短信时候就用这个 AI 来辅助提取信息」）
//
// 定位：**兜底，不是主力**
// ----------------------
// `PickupParser` 的四套正则负责主解析（毫秒级、结果稳定、可回归），
// 这里只在**正则没捞到某个字段**时补一刀。永远遵守两条红线：
//   1. **只填空，不覆盖** —— 正则已经解析出来的值（尤其取件码）一律不动；
//      取件码是全局唯一的凭证，模型改错一次就是「去驿站报了个别人的码」。
//   2. **不可用就当没有** —— 老设备 / 没开 Apple Intelligence / 模型还没下载完，
//      全部安静退回纯正则，用户无感。
//
// 为什么用系统模型而不是云端 API
// ----------------------------
// 短信原文里有姓名、门牌、电话号码。`SystemLanguageModel` 跑在设备上，
// 不联网、不花钱、没有配额，也省掉了「把用户短信发给第三方」的隐私声明。
// 系统工程 `IPHONEOS_DEPLOYMENT_TARGET = 27.0`，`FoundationModels`（iOS 26+）直接可用；
// 而且本 App **没有通知服务扩展**（只有 Codelumi + CodelumiWidget 两个 target），
// 解析跑在主 App 进程里，不受扩展那 24MB 内存上限的约束。
//
// 为什么不让模型替代正则
// --------------------
// 3B 端侧模型做「短文本字段抽取」够用，但它有两个正则没有的毛病：
// 慢（首次加载 + 每条几百毫秒到两秒）和不确定（同样输入可能有细微差别）。
// 所以：能秒出结果的场合绝不等模型；解析链路本身仍然同步完成入库，
// 模型结果是**后到后补**的（见 `PickupAIEnhancer`）。
// ============================================================================

/// 模型要吐出来的结构。
///
/// 用 `@Generable` 走结构化生成：模型只能按 schema 填字段，不会自由发挥成一段话。
/// 每个字段都用 `@Guide` 写死口径 —— 尤其是「没有就填空」「照抄不要改写」，
/// 这是压住模型幻觉最有效的一句话。
@available(iOS 26.0, *)
@Generable
@available(iOS 26.0, *)
struct AIPickupFields: Sendable {
    @Guide(description: "取件码：顾客要报给店员、或要在柜机上输入的那串字符，原样抄下，不要加空格")
    var code: String

    @Guide(description: "快递公司（承运方），如「圆通快递」「顺丰速运」「中通快递」；短信里没写就返回空字符串")
    var courier: String

    @Guide(description: "取件地点品牌，如「菜鸟驿站」「丰巢」「兔喜生活」「妈妈驿站」；没有就返回空字符串")
    var station: String

    @Guide(description: "快递柜格口，如「2号柜」「12-34格口」「柜A12」；没有就返回空字符串")
    var locker: String

    @Guide(description: "驿站里的货架号，如「3-12」「5号货架」；没有就返回空字符串")
    var shelf: String

    @Guide(description: "取件地址（到哪儿去取），照抄短信原话，不要改写、不要编造；没有就返回空字符串")
    var address: String
}

/// 「打开 Apple 智能」用户开关（2026-11-22 主人要求放进 Apple 智能页）。
///
/// 与 `PickupAI.isAvailable`（系统事实）分开：
///   · `isAvailable` —— 这台 iPhone 到底给不给用，App 改不了；
///   · `isEnabled`   —— 用户**愿不愿意**用。默认开（改造前就是这个行为），
///     关掉之后所有端侧调用直接跳过，只剩正则，功能不受影响。
///
/// 为什么存 App Group：解析跑在主 App，但同一份偏好以后可能被扩展读到
/// （例如小组件将来要展示"增强已关闭"），跨进程一致比省一个 domain 更重要。
///
/// ⚠️ 2026-11-22 语音录入整块删除（老大：「先直接关闭吧，目前基本上没有大模型无法使用的」）：
///    原 `VoiceEntryStyle` / `VoiceSettings` / `voiceKey` / `voiceEntryKey` /
///    `resetVoiceOffOnceIfNeeded` 全部移除，`AISettings` 只剩这一个总开关。
enum AISettings {
    static let enabledKey = "codelumi.ai.enabled"

    private static var store: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    /// 「打开 Apple 智能」总开关。默认 **true** —— 升级用户不该因为新增开关而静默降级。
    static var isEnabled: Bool {
        store.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ value: Bool) {
        store.set(value, forKey: enabledKey)
    }
}

@available(iOS 26.0, *)
enum PickupAI {

    /// 设备可用性的一句话描述（设置页 / 自检用）
    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可用"
        case .unavailable(let reason):
            switch reason {
            // 🔴 2026-11-05 主人指正：原来写「本机不支持（需 iPhone 15 Pro 及以上）」，
            //    括号里那句是"最低要求"，摆在 16 Pro 用户面前读起来像"你的手机不够格"。
            //    现在只陈述系统给的事实，最低要求另起一行说明（见 Apple 智能页的说明卡）。
            case .deviceNotEligible: return "系统未向本机开放端侧模型"
            case .appleIntelligenceNotEnabled: return "未开启 Apple 智能"
            case .modelNotReady: return "模型未就绪（系统在后台下载）"
            @unknown default: return "不可用"
            }
        }
    }

    /// 能不能用。**任何地方调用前都必须先过这一关** —— 不可用时一律退回纯正则。
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// 实际会不会真的去调模型 = 系统给用 **且** 用户没关开关。
    ///
    /// 2026-11-22：Apple 智能页加了「打开 Apple 智能」总开关，
    /// 判断「要不要发起端侧调用」的地方一律改用它 —— `isAvailable` 只表示硬件/系统的态度，
    /// 拿它当"要不要跑"会让关掉开关的用户继续被调用。
    static var isActive: Bool { isAvailable && AISettings.isEnabled }

    /// 从一条短信里抽字段。返回 nil = 不可用 / 超时 / 模型拒绝，调用方直接放弃。
    ///
    /// - Parameter timeout: 端侧模型首次调用要加载权重，默认给 8 秒；
    ///   超时宁可不要结果，也不能让解析任务一直挂着。
    static func extract(from text: String,
                        timeout: Duration = .seconds(8)) async -> AIPickupFields? {
        guard isActive else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return await withTaskGroup(of: AIPickupFields?.self) { group in
            group.addTask {
                do {
                    return try await PickupAISession.shared.parse(trimmed)
                } catch {
                    print("[codelumi-ai] 抽取失败：\(error)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// 会话复用。
///
/// `LanguageModelSession` 每次新建都要重新装载上下文；抓取一条短信只问一次，
/// 但连续入几条时会连问几次 —— 复用同一个会话能省掉重复的装载开销。
/// 用 actor 隔离：会话本身不是线程安全的，串行化访问最省心。
@available(iOS 26.0, *)
actor PickupAISession {
    static let shared = PickupAISession()

    private var session: LanguageModelSession?

    /// 系统提示词：把角色、边界、输出口径一次讲清。
    /// 语气上刻意写成「只抄不猜」—— 端侧小模型很容易顺着「常识」补出不存在的地址。
    private static let instructions = """
    你是快递取件短信的字段抽取器。输入是一条中文快递短信，输出是结构化字段。
    规则：
    1. 只抄短信里**明确出现**的信息，绝对不要推测、不要补全、不要改写。
    2. 某个字段短信里没有，就返回空字符串，不要用「未知」「无」之类的词填空。
    3. 取件码通常是 4-20 位的数字或字母组合，常跟在「取件码」「提货码」「凭」后面；
       不要把柜号（2号柜）、货架号（3-12）、手机尾号当成取件码。
    4. address 保留短信里的原始表述（可以去掉「请前往」「请您」这类动词），不要编造门牌。
    5. station 只填品牌名（菜鸟驿站、丰巢、兔喜生活…），门店名、小区名不算。
    """

    func parse(_ text: String) async throws -> AIPickupFields? {
        if session == nil {
            session = LanguageModelSession(instructions: Self.instructions)
        }
        guard let session else { return nil }
        let response = try await session.respond(to: text,
                                                 generating: AIPickupFields.self)
        return response.content
    }
}

// MARK: - 把模型结果并回记录

/// AI 结果的后置合并器（2026-10-28）。
///
/// 时序：`ingest` **同步**用正则解析入库并返回（列表立刻有条目），
/// 本类随后在后台补字段，补到东西再更新记录。
/// 这样用户永远不用等模型 —— 慢的是补全，不是入库。
///
/// ⚠️ 本类型**不能整体标 @MainActor**：`PickupStore.commitAll` 是同步非隔离方法，
/// 在里头调用主线程隔离的 `schedule` 会直接编译不过（Swift 6 严格并发）。
/// 只有真正改数据的那一小段（`apply`）需要主线程。
@available(iOS 26.0, *)
enum PickupAIEnhancer {

    /// 一条记录要不要请模型帮忙。
    ///
    /// 只在「正则明显缺东西」时触发，避免每条短信都跑模型（耗电、也没必要）：
    ///   · 取件地址空 —— 卡片和地图导航都要用，最值得补；
    ///   · 柜位与货架都空、但原文里有「柜 / 架」字 —— 说明这条是到柜/到架件，位置信息漏了。
    static func needsHelp(_ record: PickupRecord) -> Bool {
        if record.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let locker = record.locker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shelf = record.shelf?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if locker.isEmpty && shelf.isEmpty,
           record.rawMessage.contains("柜") || record.rawMessage.contains("架") {
            return true
        }
        return false
    }

    /// 新入库的记录排一轮后台补全（由 `commitAll` 调用）
    static func schedule(_ records: [PickupRecord]) {
        guard PickupAI.isActive else { return }
        let targets = records.filter(needsHelp)
        guard !targets.isEmpty else { return }

        for record in targets {
            let id = record.id
            let text = record.rawMessage
            Task.detached(priority: .utility) {
                guard let fields = await PickupAI.extract(from: text) else { return }
                await MainActor.run {
                    apply(fields, to: id)
                }
            }
        }
    }

    /// 合并字段：**只填空，不覆盖**。
    ///
    /// 🔴 取件码（`code`）**永不**采用模型结果：正则的码已经过 shape 校验
    /// （见 `PickupParser.codeChainParts`），模型改码一次就是报错别人的件。
    /// 模型给出不同码时只打日志，供后续人工比对。
    @MainActor
    static func apply(_ fields: AIPickupFields, to id: UUID) {
        let store = PickupStore.shared
        guard let index = store.records.firstIndex(where: { $0.id == id }) else { return }
        var record = store.records[index]
        var changed = false

        func clean(_ raw: String) -> String {
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let aiAddress = clean(fields.address)
        if record.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !aiAddress.isEmpty {
            record.address = aiAddress
            changed = true
        }

        let aiCourier = clean(fields.courier)
        if (record.courier ?? "").isEmpty, !aiCourier.isEmpty {
            record.courier = aiCourier
            changed = true
        }

        let aiLocker = clean(fields.locker)
        if (record.locker ?? "").isEmpty, !aiLocker.isEmpty {
            record.locker = aiLocker
            changed = true
        }

        let aiShelf = clean(fields.shelf)
        if (record.shelf ?? "").isEmpty, !aiShelf.isEmpty {
            record.shelf = aiShelf
            changed = true
        }

        // 仅供比对：模型与正则对取件码的判断不一致时留痕，不改数据
        let aiCode = clean(fields.code)
        if !aiCode.isEmpty, aiCode != record.code {
            print("[codelumi-ai] 取件码分歧 正则=\(record.code) 模型=\(aiCode)（保留正则值）")
        }

        guard changed else { return }
        print("[codelumi-ai] 补全 \(record.code)：地址/公司/柜位 = \(record.address) | \(record.courier ?? "") | \(record.locker ?? "")")
        store.update(record)
    }
}
