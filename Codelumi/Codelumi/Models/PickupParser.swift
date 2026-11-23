import Foundation
import NaturalLanguage

// MARK: ============================================================================
// 解析引擎：把 iOS 快捷指令「快递取件码」V7.3.0 的六套正则与优先级链移植进 App。
//
// 关键前提：App 与快捷指令的「匹配文本」动作同用 ICU（NSRegularExpression），
// 因此公式可逐字移植，行为一致——包括 lookbehind 必须定长、`\w`/`\d`/`\s`
// 的字符类语义（ICU 下 `\w` 含 CJK）。
//
// 本文件只依赖 Foundation，可独立编译做 51 条语料回归（见 tools/parser-regression）。
// ============================================================================

/// 一次解析的结果
///
/// 🔴 **字段口径（2026-09-23 主人定）**：`company` = **平台**（【】里的品牌），
/// `courier` = **快递公司**（承运方，正文里找）——「【拼多多】您的圆通快递…」
/// 平台是拼多多、快递公司是圆通快递，两者必须分开，不能混成一个字段。
/// `waybill` / `tail` 是**次要凭证**：主凭证（`kind` + `value`）按优先级链只取一个，
/// 短信里同时出现的运单号 / 尾号落在其次要字段里，**没有就留空串**。
struct PickupParseResult: Equatable {
    var kind: PickupKind
    var value: String
    var company: String
    var address: String
    var rawText: String
    /// 快递公司（承运方）。判别不出时为空串。
    var courier: String = ""
    /// 运单号（主凭证是运单号时与 `value` 相同，否则为短信里另带的运单号）。
    var waybill: String = ""
    /// 尾号（主凭证是尾号时与 `value` 相同，否则为短信里另带的尾号）。
    var tail: String = ""
    /// 货架号（2026-10-14 参照「码上取」补的字段：菜鸟驿站等场景下，
    /// 货架号比取件码更能直接定位包裹 —— 「3号货架」「货架号：3-12」）。
    var shelf: String = ""
    /// 快递柜格口（2026-10-27 从快捷指令 V8.0.2 的「快递柜」公式移植）。
    ///
    /// 与 `shelf` 是**两种不同的东西**，不能合并：
    ///   · `shelf` = 驿站里的货架（「货架3-12」「3号货架」），人进去自己找；
    ///   · `locker` = 智能柜的格口（「2号柜」「12-34格口」「柜A12」），机器弹门。
    /// 到柜前必须先知道是几号柜，这条信息在小组件里紧跟取件码显示。
    var locker: String = ""
}

// MARK: ============================================================================
// （行程字段 TravelFields 已随出行功能下线一并移除 —— Codelumi回归快递单一主业。）
// ============================================================================


// MARK: - 地址兜底（NaturalLanguage）

/// 公式没抓到地址时，用**系统分词 + 地名标注**补一段。
///
/// 取舍：
///   · 只在 `address.isEmpty` 时调用，不动已命中的结果 —— 保证语料回归不回退；
///   · 取「第一个地名锚点」向右扩展到句读 / 取件码关键字之前，长度 ≥4 才采用；
///   · 纯本地运算（NaturalLanguage 不上传、不联网）。
func naturalLanguageAddress(from text: String) -> String? {
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = text
    tagger.setLanguage(.simplifiedChinese, range: text.startIndex..<text.endIndex)

    var anchor: Range<String.Index>?
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                         scheme: .nameType,
                         options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
        if tag == .placeName, anchor == nil {
            anchor = range
            return false
        }
        return true
    }
    guard let start = anchor?.lowerBound else { return nil }

    let stops = CharacterSet(charactersIn: "，。；！,;\n")
    var end = anchor!.upperBound
    while end < text.endIndex {
        let rest = text[end...]
        if text[end].unicodeScalars.contains(where: { stops.contains($0) }) { break }
        if rest.hasPrefix("取件码") || rest.hasPrefix("取货码") || rest.hasPrefix("请") { break }
        end = text.index(after: end)
    }
    let candidate = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
    guard candidate.count >= 4, candidate.count <= 40 else { return nil }
    return candidate
}

enum PickupParser {

    // MARK: - 正则真值（V7.3.0 本体实测，逐字移植）

    /// 关键词：V7.3.0 中作为**闸门**使用（凭证全空或关键词为空即拒绝写入）
    ///
    /// 🔴 2026-11-17：`京东` 补 `(?!卡)` —— 「京东卡」是营销奖品，不是承运方。
    ///    华为云那条推广短信就是靠「京东卡」混过这道闸门的。`京东快递` 不受影响。
    static let keywordPattern =
        #"快递|快件|速递|取件|取货|提货|包裹|近邻宝|兔喜生活|丰巢|顺丰|圆通|申通|中通|韵达|邮政|百世|德邦|京东(?!卡)|优速|速运|极兔|菜鸟|鸟箱|驿站"#

    /// 取件码（V7.3.0 本体值；`[:："\s]*` 在 lookbehind 之后属匹配内容，
    /// 故结果可能带前导 `"` / `：` —— App 侧统一 trimLeadingSeparators 清理）
    static let codePattern =
        #"(?<=盒|用|暂存码?|凭「?|"|“|”|快递码|“|”|快递码|(提|取)货?件?(验证)?码?「?为?|(提|取)货?件?(验证)?码?"|(提|取)货?件?(验证)?码?:|(提|取)货?件?(验证)?码?：|(提|取)货?件?(验证)?码?为"?|(提|取)货?件?(验证)?码?为:|(提|取)货?件?(验证)?码?为：|(提|取)货?件?(验证)?码?(为|是)?[:：]?[「"“]|、|，|,[A-Z]?)\s*(?!(\+?86)?1[3-9]\d{9})((\[A-Z]\d{6,})|((\d+(-|—))+\d+)|(\d?\+?[A-Za-z]+?(-?\d+)+)|(\d+[A-Za-z]\d+)|\d{5,})|(?<=包裹)(\d{4,8})(?!\d)|(?<=(提|取)货?件?(验证)?码?(为|是)?[:：]?)\s*(\d{4})(?!\d)|(?<=凭)\s*(\d{3,8})(?=\s*取件)|(?<=编号)\s*(\d{3,8})(?=\s*(?:[\u4E00-\u9FA5]{0,6}快递|到|请))"#

    /// 运单号（V7.3.0 已补「快件」分支）
    static let waybillPattern =
        #"((?<=(包裹|(快|速)(递|件)】?|邮件))[A-Z]{0,3}\d{11,})|(?<=(快递|件|运单)尾号为?)\s*[:：”"\s]*\s*(?!(\+?86)?1[3-9]\d{9})(((\d+-)+\d+)|(\d?\+?[A-Za-z]+?(-?\d+)+)|(\d+[A-Za-z]\d+)|\d{4,})"#

    /// 尾号（V7.3.0 本体排除词 + 完整版补的 `储蓄`）
    static let tailPattern =
        #"(?<=尾号为?)\s*[:：”"\s]*\s*(?!(\+?86)?1[3-9]\d{9})(((\d+-)+\d+)|(\d?\+?[A-Za-z]+?(-?\d+)+)|(\d+[A-Za-z]\d+)|\d{4,})(?!\d)(?!.*(?:支付|快捷|(信用|银行)卡|扣款|储蓄|消费|交易|转账|转入|转出|汇出|入账|人民币))"#

    /// 「按需派送运单9005」这类**没有取件码**的派送短信（2026-11-12 内测反馈）：
    /// 4–7 位当运单尾号处理，8 位以上当运单号处理，否则整条短信会被直接拒掉。
    static let deliveryNoPattern =
        #"(?<=运单)\s*[:：]?\s*([A-Za-z0-9]{4,})"#

    /// 特殊格式取件码（保持原样；匹配后把 `、`/`,` 归一为 `-`）
    static let specialPattern =
        #"(?<=快递码)(\d+?(,|、)){2}\d+?(?=，)"#

    /// 独立「地址:」字段（优先级高于主地址公式）
    static let standaloneAddressPattern =
        // 🔴 2026-11-05：原来把「兔喜生活/菜鸟驿站…」这些品牌名当成终点，
        //    导致「地址:甘州院子南门馨月湖南门兔喜生活」被截成「…馨月湖南门」。
        //    主人人工标注里 13 条都属于这种截断 —— 品牌名本身是地址的一部分，不该当边界。
        #"(?<=地址[:：])\s*([^。，,]+?)\s*(?=。|,|$)"#

    /// 匹配取件地址（V7.2.1 合并单条 v3 + 2026-09-19 宽容 lookahead）
    static let matchedAddressPattern =
        // 🔴 2026-11-11 内测反馈：申通「您…包裹已存放先锋翡翠湾44号楼一单元一楼商铺，
//    取件码1-4-9857」抓不到地址 —— 原来的引导词只有「在/放在/暂存」，没有「已存放」。
//    这一批补「已存放(于/在)、已投放到、已存至、投放到」等常见写法；只加引导词，
//    字符类与后瞻不动，避免影响已通过的语料回归。
#"(?<=暂存)\S+\s?\d+?(?=，暂存码)|他人签收|(?<=至|前往|由|已?放?(?<!正)在|已?存放(?:于|在)?|已?投放(?:于|到|至)?|已?存(?:至|到)|暂存到|到达「|到「|到达|到(?!达|店[扫自取领寄]))\s*([^\s到「，凭在码预]+?(?:站点)?)\s*(?=\s*(?:[（(]请前往|代签|滞留|请凭|免费|领?取件?|暂存码|取件码|取货码|码|签收|[，,。]|领取|自提|详询|有疑问|$))"#

    /// 快递公司名：优先 `【】` 内的品牌名
    static let companyBracketPattern = #"(?<=【)[^】]{1,20}(?=】)"#
    /// 兜底：正文里的「xx快递/速递/物流/驿站/速运/快运」
    static let companyFallbackPattern = #"[\u4E00-\u9FA5A-Za-z]{2,6}(?:快递|速递|物流|驿站|速运|快运)"#

    // MARK: 快递公司（承运方）识别

    /// 快递公司品牌词根。**只收快递公司**，不含驿站 / 代收点 / 商家 ——
    /// 「【拼多多】您的圆通快递…」要从正文里捞出「圆通」，而不能把平台自己算进去。
    /// （与 `CourierBrand` 表里 company 分类的词根保持同集；这里单独维护一份，
    ///  是为了保住本文件「只依赖 Foundation、可独立编译回归」的红线。）
    static let courierCompanyKeys = [
        "中国邮政", "邮政", "EMS", "顺丰", "圆通", "申通", "中通", "韵达",
        "百世", "德邦", "京东", "极兔", "天天", "优速", "宅急送", "跨越",
        "安能", "中铁", "速尔",
        // 🔴 2026-10-27 按快捷指令 V8.0.3 的名单补齐（原来少了这 7 家）。
        //    「菜鸟速递 / 苏宁物流 / 丰网」用**整词**而不是词根：
        //    「菜鸟」单独出现时多是「菜鸟驿站 / 菜鸟裹裹」（驿站与平台，不是承运方），
        //    只认「菜鸟速递」这条真承运业务。
        "菜鸟速递", "丰网", "壹米滴答", "日日顺", "苏宁物流", "丹鸟", "递四方",
    ]

    /// 平台名若长这样（圆通快递 / 顺丰速运 / 中国邮政…），它本身就是快递公司。
    /// 🔴 用**白名单**而不是「以快递结尾就算」：【微快递】是驿站品牌，
    ///     「以快递结尾」会把它误判成快递公司。
    private static let platformIsCourierPattern =
        #"^(?:中国)?(?:顺丰|圆通|申通|中通|韵达|百世|德邦|京东|极兔|天天|优速|宅急送|跨越|安能|中铁|速尔)(?:快递|速递|速运|物流|快运)?$|^(?:中国邮政|EMS)$"#

    /// 快递公司后缀词：品牌词根后面紧跟这些字时一并算进公司名（「圆通」→「圆通快递」）
    private static let courierSuffixes = ["快递", "速递", "速运", "物流", "快运"]

    /// 一码多件的链式取件码（「取货码0909-0022、0909-0014」「取件码为260108,260110」）。
    /// lookbehind 各分支**定长**（ICU 红线），`、`/`,`/`，` 分隔 ≥2 段才算链。
    static let codeChainPattern =
        #"(?<=取件码为|取件码[:：]|取件码|取货码为|取货码[:：]|取货码)\s*[「“"]?\s*[\dA-Za-z][\dA-Za-z\-—]*(?:\s*[、,，]\s*[\dA-Za-z][\dA-Za-z\-—]*)+"#

    // MARK: 货架号（2026-10-14）

    /// ① 显式「货架号：3-12」（lookbehind「货架号：」定长，ICU 合法）
    static let shelfExplicitPattern =
        #"(?<=货架号[:：])\s*[0-9A-Za-z]{1,4}(?:[-—][0-9A-Za-z]{1,4})?"#
    /// ② 「货架3-12」紧贴写法（lookbehind「货架」定长）
    static let shelfGluedPattern =
        #"(?<=货架)\s*[0-9]{1,3}[-—][0-9]{1,4}"#
    /// ③ 「3号货架」前置写法（捕获在货架词之前，无 lookbehind）
    static let shelfLeadingPattern =
        #"[0-9]{1,3}(?:[-—][0-9]{1,4})?\s*号货架"#

    /// 快递柜格口（逐字移植自快捷指令 V8.0.2 的「快递柜」公式）。
    /// 三条分支：① 「2号」+ 前瞻柜/格口/箱（允许中间夹品牌词「2号 丰巢柜」）；
    /// ② 「12-34」+ 前瞻格口；③ 「柜A12」里的编号。
    static let lockerPattern =
        #"(?:(?:\d{1,3}|[一二三四五六七八九十]{1,3})\s*号(?=\s*(?:[兔喜菜鸟丰巢袋鼠格格心甜智能近邻宝]|快递)*(?:柜|格口|箱))|(?:\d{2}-\d{2})(?=\s*格口)|(?<=柜)[A-Z]\d{1,3}(?!\d))"#

    /// 精确格口「12-34格口」（2026-10-28 回归补：`#45` 微快递那条同时有
    /// 「快递驿站2号柜」和「快递柜02-23格口」，前者只是**柜体编号**，
    /// 后者才是要按的箱格 —— 原公式按出现顺序取到「2号柜」就停了。）
    static let lockerCellPattern = #"(?:\d{2}-\d{2})(?=\s*格口)"#

    /// 「第15箱」写法（2026-10-28 真机语料补：「秦皇帝锦钰翠轩一号柜第15箱」——
    /// 一号柜是柜体、第15箱才是箱格）。要求数字紧跟「箱」，避免误吃「鸟箱」这种品牌名。
    static let lockerBoxPattern = #"\d{1,3}(?=\s*箱)"#

    /// 快递柜格口提取。
    ///
    /// V8.0.2 的第一条分支只匹配到「2号」两个字符（柜字在前瞻里），
    /// 直接显示会变成孤零零的「2号」—— 所以这里把紧随的单位补回来：
    /// 「2号」+「柜」=「2号柜」、「12-34」+「格口」=「12-34格口」。
    ///
    /// 🔴 2026-10-30 主人：「短信写 快递柜A3，你就写 A3 就行，什么叫柜A3」——
    ///    「柜」字是**短信里的柜体名词**，不是格口编号的一部分；卡片上已经
    ///    有图标和地址说明这是快递柜，再顶一个「柜」字纯属重复。
    ///    所以字母开头的格口编号**原样输出**，不再补前缀。
    static func locker(from text: String) -> String {
        // ① 「12-34格口」是最精确的箱格编号，优先于任何「N号柜」
        if let cell = firstMatch(lockerCellPattern, in: text) {
            return cell.trimmingCharacters(in: .whitespaces) + "格口"
        }
        // ② 「第15箱」：同样是箱格级信息，优先于柜体编号
        if let box = firstMatch(lockerBoxPattern, in: text) {
            return box.trimmingCharacters(in: .whitespaces) + "箱"
        }

        guard let raw = firstMatch(lockerPattern, in: text) else { return "" }
        let hit = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hit.isEmpty else { return "" }

        if hit.hasSuffix("号") {
            return hit + (unitAfter(hit, in: text) ?? "柜")
        }
        // 「12-34」这类纯数字区间，单位一定是格口
        if hit.contains("-"), hit.allSatisfy({ $0.isNumber || $0 == "-" }) {
            return hit + "格口"
        }
        // 「A12」这种是「快递柜A12」的编号 —— 原样返回，不补「柜」前缀
        return hit
    }

    /// 找「N号」后面紧跟的容器单位（可能隔着品牌词，只往后看 10 个字）。
    private static func unitAfter(_ hit: String, in text: String) -> String? {
        guard let range = text.range(of: hit) else { return nil }
        let tail = String(text[range.upperBound...].prefix(10))
        for unit in ["格口", "柜", "箱"] where tail.contains(unit) { return unit }
        return nil
    }

    /// 货架号提取：三种写法按「显式 > 紧贴 > 前置」顺序试。
    /// 「3号货架」命中后把后缀「号货架」裁掉，只留编号本身。
    static func shelf(from text: String) -> String {
        if let hit = firstMatch(shelfExplicitPattern, in: text) {
            return trimLeadingSeparators(hit)
        }
        if let hit = firstMatch(shelfGluedPattern, in: text) {
            return trimLeadingSeparators(hit)
        }
        if let hit = firstMatch(shelfLeadingPattern, in: text) {
            return hit
                .replacingOccurrences(of: "号货架", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    // MARK: - 编译缓存（正则只编译一次）

    private static let regexes: [String: NSRegularExpression] = {
        var map: [String: NSRegularExpression] = [:]
        // 🔴 三个 `shelf*Pattern` 必须在这里注册（2026-10-25 审查发现漏注册）：
        // `firstMatch` 只查这张表，没注册的 pattern 一律走 `guard let regex = regexes[pattern]
        // else { return nil }` 直接返回 nil。此前货架号三个正则全部缺席，
        // 导致 `shelf(from:)` 恒返回空串 —— 短信里的「3号货架」「货架号：3-12」从来没被识别过，
        // 用户只能手工去详情页补。
        for pattern in [keywordPattern, codePattern, waybillPattern, tailPattern, deliveryNoPattern,
                        specialPattern, standaloneAddressPattern, matchedAddressPattern,
                        companyBracketPattern, companyFallbackPattern,
                        platformIsCourierPattern, codeChainPattern,
                        shelfExplicitPattern, shelfGluedPattern, shelfLeadingPattern,
                        // 🔴 lockerPattern 也必须在这里注册（2026-10-27）：
                        // 与上面三个 shelf 正则同一个坑 —— 漏注册 → firstMatch 恒返回 nil
                        // → 快递柜永远抓不到，而且**不会报错**，只是安静地什么都不出。
                        lockerPattern,
                        // 2026-10-28 新增的精确格口公式，同样必须注册
                        lockerCellPattern, lockerBoxPattern] {
            map[pattern] = try? NSRegularExpression(pattern: pattern)
        }
        return map
    }()

    /// 正则是否全部编译通过（供自检 / 回归脚本使用）
    static var allPatternsValid: Bool {
        [keywordPattern, codePattern, waybillPattern, tailPattern,
         specialPattern, standaloneAddressPattern, matchedAddressPattern,
         companyFallbackPattern, companyBracketPattern,
         platformIsCourierPattern, codeChainPattern,
         shelfExplicitPattern, shelfGluedPattern, shelfLeadingPattern].allSatisfy { regexes[$0] != nil }
    }

    // MARK: - 匹配工具

    /// 取第一个匹配的**整段匹配文本**（等价于快捷指令的 Text Match `m[0]`，不要取分组）
    private static func firstMatch(_ pattern: String, in text: String,
                                   group: Int = 0) -> String? {
        guard let regex = regexes[pattern] else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard group < match.numberOfRanges,
              let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    /// 归一：全角/引号类前导分隔符与空白一律去掉
    private static func trimLeadingSeparators(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let junk: Set<Character> = [":", "：", "\"", "“", "”", "、", "，", ",", "；", ";"]
        while let first = result.first, junk.contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// `、` / `,` → `-`（特殊格式取件码归一，对应快捷指令里的「替换文本」动作）
    private static func normalizeSeparators(_ value: String) -> String {
        value.replacingOccurrences(of: #"[、,]"#, with: "-", options: .regularExpression)
    }

    // MARK: - 快递公司识别

    /// **短信平台** = `【】` 内的内容（发短信的平台）。2026-10-18 主人定：
    /// 平台严格等于【】内文本；短信不含【】时平台为空串，不再回落正文或「未知快递」哨兵。
    static func company(from text: String) -> String {
        guard let bracketed = firstMatch(companyBracketPattern, in: text) else { return "" }
        var name = bracketed.trimmingCharacters(in: .whitespaces)
        // 「【中国邮政】」这类前缀去掉更贴近用户叫法
        for prefix in ["中国", "国内"] where name.hasPrefix(prefix) && name.count > 4 {
            name.removeFirst(prefix.count)
        }
        return name
    }

    /// **快递公司（承运方）**：与平台（`company(from:)`）分开的两个概念。
    ///
    /// 规则：
    ///   1. 平台名本身就是快递公司（【圆通快递】【中国邮政】…命中白名单）→ 直接用它；
    ///   2. 否则在**正文**里找快递公司品牌词根的最早出现，后缀（快递/速递/…）一并带上
    ///      （「您的圆通快递YT886…」→「圆通快递」；「您的中国邮政包裹」→「中国邮政」）；
    ///   3. 找不到 → 空串（**留空**，不编造）。
    /// **快递公司（承运方）** —— 2026-10-18 主人定口径：
    ///   1. 先在 `【】` **以外**的正文里找快递公司品牌词根（最早出现、带后缀）；
    ///   2. 正文没有，则看 `【】` 内内容（platform）本身是不是快递公司（白名单）；
    ///   3. 都不是 → 空串（**留空**，不编造）。
    /// 与 `company(from:)`（平台=【】内）彻底分离，不再互为回填。
    static func courierCompany(from text: String, platform: String) -> String {
        // ① 正文（去掉【】内）优先
        let body = stripBracket(text)
        if let name = firstCourierKey(in: body) { return name }

        // ② 正文无 → 看【】内是否为快递公司
        if !platform.isEmpty,
           let regex = regexes[platformIsCourierPattern],
           regex.firstMatch(in: platform, options: [],
                            range: NSRange(platform.startIndex..., in: platform)) != nil {
            return platform
        }
        return ""
    }

    /// 去掉 `【…】` 片段，得到纯粹的「正文」用于快递公司匹配
    private static func stripBracket(_ text: String) -> String {
        text.replacingOccurrences(of: #"【[^】]*】"#, with: "", options: .regularExpression)
    }

    /// 品牌词后面紧跟这些词 ⇒ 它是**店铺名的一部分**，不是承运方。
    ///
    /// 实测反例（2026-10-27 主人）：「【中通快递】凭 9-1-1736 到 **乐苑圆通超市** 取 尾号…」
    /// —— 「乐苑圆通超市」是一个叫"圆通"的代收点，承运方其实是中通。
    /// 旧逻辑只在正文里找品牌词，「圆通」一出现就当成快递公司，
    /// 于是卡片主名、详情页「快递公司」全写成"圆通"，与短信里的中通自相矛盾。
    /// 超市 / 便利店 / 驿站代收的短信里这种写法极常见（XX 超市、XX 便利店、XX 驿站）。
    /// ⚠️ 这份词表等价于 V8.0.3 快递公司公式末尾的负向前瞻 `(?!超市|驿站|代收|快递柜)`，
    ///    并额外补了便利店 / 商店 / 小卖部 / 门市 / 店 —— 实际短信里"XX 便利店代收"很常见。
    private static let shopTailWords = ["超市", "便利店", "商店", "小卖部", "门市",
                                        "驿站", "代收", "快递柜", "店"]

    /// 候选词后面紧跟店名后缀？
    private static func isShopTail(_ tail: Substring) -> Bool {
        let probe = String(tail.prefix(8)).trimmingCharacters(in: .whitespaces)
        guard !probe.isEmpty else { return false }
        return shopTailWords.contains { probe.hasPrefix($0) }
    }

    /// 在给定文本里找最早的快递公司词根（带后缀），无则 nil
    private static func firstCourierKey(in text: String) -> String? {
        var best: (start: String.Index, name: String)?
        for key in courierCompanyKeys {
            guard let range = text.range(of: key) else { continue }

            var end = range.upperBound
            for suffix in courierSuffixes where text[end...].hasPrefix(suffix) {
                end = text.index(end, offsetBy: suffix.count)
                break
            }

            // 🔴 品牌词后面跟着「超市 / 便利店 / 驿站 / 店」⇒ 这是店名，跳过这个候选
            //    （2026-10-27）。注意判断位置在**吃完后缀之后**：
            //    「圆通快递超市」也要识别成店铺（后缀吃掉"快递"，剩下"超市"）。
            if isShopTail(text[end...]) { continue }

            if let found = best {
                if range.lowerBound > found.start { continue }
                if range.lowerBound == found.start && key.count <= found.name.count { continue }
            }
            best = (range.lowerBound, String(text[range.lowerBound..<end]))
        }
        return best?.name
    }

    /// 链式取件码（一码多件）：整段匹配文本按 `、`/`,`/`，` 切开。
    /// 返回 nil = 不是链式（单码）。调用方拿**首段**与主解析结果对齐。
    ///
    /// 🔴 2026-10-28 修：「，」既是链式分隔符，也是普通句读，会把柜位号误吞成第二件。
    /// 「【丰巢】…取件码8-2-4031，2号柜」切开得 `["8-2-4031", "2"]`，
    /// 于是多出一条码为「2」的垃圾记录（快捷指令 V8.0.3 只取第一段，
    /// 它没有「一码多件」这一步，所以天然不犯这个错；Codelumi要合并多件就必须自己判）。
    ///
    /// 判据 = **与首段同形 + 单段纯数字至少 4 位**：真实一码多件永远是同一种码型
    /// （`0909-0022、0909-0014`、`260108,260110`），而柜位/格口是「2」「12」这类短纯数字。
    static func codeChainParts(in text: String) -> [String]? {
        guard let matched = firstMatch(codeChainPattern, in: text) else { return nil }
        let parts = matched
            .components(separatedBy: CharacterSet(charactersIn: "、,，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains(where: \.isNumber) }
        guard let head = parts.first, parts.count >= 2 else { return nil }

        let shape = codeShape(head)
        let others = parts.dropFirst().filter { part in
            guard codeShape(part) == shape else { return false }
            // 单段纯数字：至少 4 位才算码，挡掉「2」「12」这种柜位 / 格口号
            let isPlainDigits = !part.contains("-") && !part.contains("—")
                && part.allSatisfy(\.isNumber)
            return isPlainDigits ? part.count >= 4 : true
        }

        return others.isEmpty ? nil : [head] + others
    }

    /// 码型指纹：数字段折叠成 `d`，字母段折叠成 `a`，用 `-` 连接。
    /// `0909-0022` → `d-d`；`260108` → `d`；`A-9182` → `a-d`。
    private static func codeShape(_ part: String) -> String {
        part.split(whereSeparator: { $0 == "-" || $0 == "—" })
            .map { $0.allSatisfy(\.isNumber) ? "d" : "a" }
            .joined(separator: "-")
    }

    // MARK: - 主流程

    /// 解析一条短信。返回 nil 表示「不是快递短信」（凭证与关键词双闸门均未通过）。
    static func parse(_ rawText: String) -> PickupParseResult? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // ① 四套凭证公式
        let code = firstMatch(codePattern, in: text).map(trimLeadingSeparators)
            .flatMap { $0.isEmpty || isVersionLikeCode($0) ? nil : $0 }
        let waybill = firstMatch(waybillPattern, in: text).map(trimLeadingSeparators).flatMap { $0.isEmpty ? nil : $0 }
        let tail = firstMatch(tailPattern, in: text).map(trimLeadingSeparators).flatMap { $0.isEmpty ? nil : $0 }
        let special = firstMatch(specialPattern, in: text).map(normalizeSeparators).flatMap { $0.isEmpty ? nil : $0 }
        // 「按需派送运单9005」：没有取件码，只有运单号/尾号（2026-11-12 内测反馈）
        let deliveryNo = firstMatch(deliveryNoPattern, in: text)
            .map(trimLeadingSeparators).flatMap { $0.isEmpty ? nil : $0 }

        // ② 全局闸门：四套全空 → 直接拒绝（V7.3.0 动作 51–62 的语义）
        guard code != nil || waybill != nil || tail != nil || special != nil || deliveryNo != nil else { return nil }

        // ②.5 「还没到」的派送通知不算取件（2026-11-05 主人标注发现）：        //    「您的快递正在派送，将投放代收点」「快递将投递」这类短信里有运单号、有品牌，
        //    会命中凭证公式被当成待取件，但包裹还没到驿站，收进去就是脏数据。
        //    只在**没有任何到达/取件线索**时才拒绝，避免误伤同时含两者的长短信。
        if PickupParser.isPendingDeliveryOnly(text) { return nil }

        // ②.6 推广 / 营销短信不算取件（2026-11-17 训练样本暴露）：
        //    华为云那条「限时活动赢华为运动手表、京东卡等大奖…拒收请回复R」
        //    ① 「京东卡」里的「京东」命中了关键词闸门；
        //    ② codePattern 的 `(?<=，)[A-Za-z]+-?\d+` 分支从 `glm-5.3-flash`
        //       里截出「glm-5」当取件码；
        //    ③ 品牌词表又从「天天送」里认出「天天」当快递公司。
        //    三层全错，最后入库成一条假取件码。
        if PickupParser.isPromotionalOnly(text) { return nil }

        // ③ 关键词闸门：为空 → 拒绝，防止非快递短信触发写入
        guard firstMatch(keywordPattern, in: text) != nil else { return nil }

        // ④ 优先级链：取件码 → 运单号 → 尾号 → 特殊格式（命中即止）
        let outcome: (PickupKind, String)
        if let code {
            outcome = (.code, code)
        } else if let waybill {
            outcome = (.waybill, waybill)
        } else if let tail {
            outcome = (.tail, tail)
        } else if let deliveryNo {
            // 「运单9005」是尾号、「运单123456789012」才是运单号
            outcome = deliveryNo.count >= 8 ? (.waybill, deliveryNo) : (.tail, deliveryNo)
        } else {
            outcome = (.special, special ?? "")
        }

        // ⑤ 地址两级口径：独立「地址:」字段优先，未命中回落主公式
        let address = firstMatch(standaloneAddressPattern, in: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? firstMatch(matchedAddressPattern, in: text)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        // ⑤.5 地址为空时的兜底：用系统分词 + 地名识别补一段（2026-11-05）
        //
        // 只在公式没抓到地址时启用，**绝不覆盖**已抓到的结果 —— 这条约束保证
        // 现有语料的地址命中数只可能持平或增加，不会因为兜底而变差。
        // 纯本地：NaturalLanguage 不联网、不上传，符合「数据不出手机」。
        var resolvedAddress = address
        if resolvedAddress.isEmpty, let guess = naturalLanguageAddress(from: text) {
            resolvedAddress = guess
        }

        // ⑥ 次要凭证与快递公司（2026-09-23 扩展：字段尽量全，没有就留空）：
        //    主凭证之外的运单号 / 尾号落进次要字段（「凭A-9182…取运单尾号7872包裹」
        //    主凭证是取件码，运单尾号 7872 也要带上）；快递公司按平台 / 正文两级判别。
        let platform = company(from: text)
        var result = PickupParseResult(kind: outcome.0,
                                       value: outcome.1,
                                       company: platform,
                                       address: resolvedAddress,
                                       rawText: rawText)
        result.waybill = outcome.0 == .waybill ? outcome.1 : (waybill ?? "")
        result.tail = outcome.0 == .tail ? outcome.1 : (tail ?? "")
        result.courier = courierCompany(from: text, platform: platform)
        result.shelf = shelf(from: text)
        result.locker = locker(from: text)

        // 货架描述被误当成地址（2026-10-25 审查修）：
        // 「您的包裹在3号货架，取件码8-8-8888」的地址公式会锚出「3号货架」，
        // 而它其实是货架号本身 —— 卡片上会变成「3号货架」+「货架3」重复显示，
        // 详情页地图还会拿它去做地理编码（必然失败、导航等于没用）。
        // 口径与存量清理共用 `PickupRecord.addressIsShelfOnly`；
        // 带门店名的（「甘州院子店3号货架」）不在此列，保留。
        if PickupRecord.addressIsShelfOnly(result.address, shelf: result.shelf) {
            result.address = ""
        }

        // 地址展示口径（2026-11-05 主人定 B 方案）：
        //   去行政前缀、括号别名前置、去掉「站点/店」冗余尾巴，与人工标注一致。
        result.address = normalizeAddressText(result.address)

        // 「已存放于X」的介词「于」会被吃进地址（2026-11-11 内测反馈修复）：
        // lookbehind 里的 `(?:于|在)?` 在「于」前也能匹配，结果变成「于家佳福…」。
        // 只在原文确实写了「存放于」时剥这一下，避免误伤「于家堡」这类真实地名。
        if result.address.hasPrefix("于"), text.contains("存放于") {
            result.address = String(result.address.dropFirst())
        }

        // 平台与快递公司彻底分离（2026-10-18 主人定）：平台=【】内（无则空），
        // 快递公司=正文优先→【】内兜底→空，两者各算各的，不再互为回填。

        // 运单号公式里带「(快递|件|运单)尾号」分支（V7.3.0 本体行为），
        // 「取运单尾号7872包裹」会同时命中运单号与尾号两套公式 —— 同一串数字
        // 在两个字段里出现两遍是错的：它是尾号，把运单号字段清掉。
        if outcome.0 != .waybill, !result.waybill.isEmpty, result.waybill == result.tail {
            result.waybill = ""
        }

        // 地址误锚兜底：公式的「已?放?在」分支让 bare-在 也是锚点，
        // 「正在派送」会锚出「派送」这类状态词 —— 不是地址，整段弃用。
        if AddressFalseAnchors.contains(address) {
            result.address = ""
        } else if let parenRange = result.address.range(of: "（请") {
            // 「…2号柜（请前往自提）超72小时收费…」：括注是取件说明不是地址，
            // 从「（请」起整段截掉。
            result.address = String(result.address[..<parenRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 快递员的「话术前缀」不是地址（2026-10-28 回归补，实测 #16）：
        // 「已由放指定地点-家门口」→ 剥掉「放指定地点-」，留「家门口」。
        if let range = result.address.range(of: "放指定地点") {
            let tail = String(result.address[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "-—－ ").union(.whitespaces))
            result.address = tail.isEmpty ? "" : tail
        }

        // 「他人签收 / 本人签收」是**签收状态**，不是地址（实测 #57：
        // 「您的邮件NH1575…已他人签收」被锚成地址「他人签收」，详情页还会拿它去地理编码）。
        if result.address.contains("签收") {
            result.address = ""
        }

        // 整段被全角/半角括号包住 → 去括号（实测 #50「(北门架子上)」）
        result.address = trimWrappingParens(result.address)

        // 地址里紧邻重复的词折叠一次（2026-10-28 真机语料实测：
        // 「恒隆广场办公楼B3兔喜快递柜兔喜快递柜取件」→ 品牌词被抄了两遍）。
        result.address = collapseRepeatedTail(result.address)

        return result
    }

    /// 折叠地址中**紧邻重复**的短语，如「…兔喜快递柜兔喜快递柜取件」→「…兔喜快递柜取件」。
    ///
    /// 只处理 3–8 字、至少包含一个汉字的重复片段，且最多折 3 次 ——
    /// 避免把「1111 号」这类数字或正常叠词也折掉。
    private static func collapseRepeatedTail(_ text: String) -> String {
        var value = text
        for _ in 0..<3 {
            var didCollapse = false
            let chars = Array(value)
            // 窗外长度从长到短试，优先折掉最长的重复块
            outer: for length in stride(from: min(8, chars.count / 2), through: 3, by: -1) {
                guard chars.count >= length * 2 else { continue }
                for start in 0...(chars.count - length * 2) {
                    let head = String(chars[start..<(start + length)])
                    let next = String(chars[(start + length)..<(start + length * 2)])
                    guard head == next, head.contains(where: { $0.isLetter }) else { continue }
                    let folded = String(chars[0..<(start + length)]) + String(chars[(start + length * 2)...])
                    value = folded
                    didCollapse = true
                    break outer
                }
            }
            if !didCollapse { break }
        }
        return value
    }

    /// 去掉包裹整段文本的括号：「(北门架子上)」→「北门架子上」。
    /// 只处理「首尾成对且内部不含另一半括号」的情况，避免削掉正常括注。
    private static func trimWrappingParens(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("（", "）"), ("(", ")"), ("【", "】")]
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = value.first, let last = value.last, first != last else { return value }
        for (open, close) in pairs where first == open && last == close {
            let inner = String(value.dropFirst().dropLast())
            guard !inner.isEmpty,
                  !inner.contains(open), !inner.contains(close) else { return value }
            value = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return value
    }

    /// 地址字段的整段弃用黑名单（精确匹配）
    private static let AddressFalseAnchors: Set<String> = [
        "派送", "派件", "投递", "送达", "上门", "代收点", "自提柜",
    ]

    // MARK: - OCR 来源的多假设解析

    /// 面向 OCR 文本的解析入口。
    ///
    /// **为什么需要单独一条入口**：公式的 lookbehind 是定长的（ICU 限制），
    /// 一旦锚点被切开就再也接不回来 —— 而 OCR 恰恰会在**视觉折行**处插入换行，
    /// 例如把「取件码为C-4082」读成两行「取件码」+「为C-4082」，
    /// 使 `取件码为` 这个锚点中间多出一个 `\n`，公式随即失配。
    /// 这个换行来自排版折行、并非语义分段，无法先验判断，只能生成若干候选逐个尝试。
    ///
    /// 候选顺序按「越保守越靠前」排列，命中即止。
    static func parseOCR(_ raw: String) -> PickupParseResult? {
        for candidate in OCRTextNormalizer.candidates(raw) {
            if let parsed = parse(candidate) { return parsed }
        }
        return nil
    }

    // MARK: - 一次多条

    /// 把一段文本切成若干「独立短信段」。
    ///
    /// **为什么需要**：一次粘贴常常就是好几条短信（从短信 App 多选复制），
    /// 一张截图里也常有 2–4 条。`parseOCR` 是「命中第一条就收工」，
    /// 拿它处理这种输入会把后面的全丢掉。
    ///
    /// **切法**：快递短信几乎都以「【品牌】」起头，所以
    /// - 以「【」开头的行 → 开启新的一段；
    /// - 不以「【」开头的行 → 视作**上一条的视觉折行**，直接接回去（不加空格）。
    ///
    /// 第二条规则是关键：OCR 在视觉折行处会插 `\n`，如果见换行就切，
    /// 一条短会被误切成两条半截的，反而全都解析不出来。
    static func segments(_ raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        // 没有任何一行以「【」起头 → 不是「多条」的形态，整体当一条处理
        // （可能是单行裸码，也可能是完全不带品牌括号的短信）。
        guard lines.contains(where: { $0.hasPrefix("【") }) else {
            return [normalized.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        var out: [String] = []
        var current = ""
        for line in lines {
            if line.hasPrefix("【") {
                if !current.isEmpty { out.append(current) }
                current = line
            } else {
                current = current.isEmpty ? line : current + line
            }
        }
        if !current.isEmpty { out.append(current) }

        return out
    }

    /// 解析整段文本，返回**全部**可识别的取件信息（顺序 = 出现顺序）。
    ///
    /// `ocrSource` 决定段内是否要走 OCR 的多假设归一：
    /// 短信原文的换行是语义换行，直接解析即可；截图 / 相册来的换行多是视觉折行，
    /// 必须先归一。两者在这一层分开，是因为**切段**规则对它们是一样的。
    ///
    /// `fallback` = **非快递场景的兜底解析器**（当前是出行）。
    ///
    /// 它只在**同一个候选文本的快递公式全部落空之后**才被调用，顺序严格是
    /// 「先快递、后兜底」，因此快递用户看到的结果与不传它时逐位一致 ——
    /// 这条不变量由 tools/parser-regression 守着。
    /// 传 `nil`（默认）时行为与改动前完全相同。
    static func parseAll(_ raw: String,
                         ocrSource: Bool,
                         fallback: ((String) -> PickupParseResult?)? = nil) -> [PickupParseResult] {
        var results: [PickupParseResult] = []
        for segment in segments(raw) {
            let candidates = ocrSource ? OCRTextNormalizer.candidates(segment) : [segment]
            for candidate in candidates {
                if let parsed = parse(candidate) {
                    results.append(parsed)

                    // 🔴 一码多件（「取货码0909-0022、0909-0014」）：
                    //    主公式只吃第一段，把链上其余的码逐个补成独立结果 ——
                    //    与首条同平台 / 同地址，落库后各自成行、各自去重。
                    //    仅当主凭证就是取件码时才展开，避免误伤运单号 / 尾号。
                    if parsed.kind == .code,
                       let parts = codeChainParts(in: candidate), parts.count >= 2,
                       parts[0] == parsed.value {
                        for extra in parts.dropFirst() where extra != parsed.value {
                            var copy = parsed
                            copy.value = extra
                            results.append(copy)
                        }
                    }
                    break
                }
                if let extra = fallback?(candidate) {
                    results.append(extra)
                    break
                }
            }
        }
        return results
    }
}

// MARK: - OCR 文本归一化

enum OCRTextNormalizer {

    /// 生成候选文本。顺序即优先级。
    static func candidates(_ raw: String) -> [String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let unwrapped = text.replacingOccurrences(of: "\n", with: "")
        let spaced = text.replacingOccurrences(of: "\n", with: " ")

        var out: [String] = [text]
        out.append(contentsOf: splitByBrandBracket(unwrapped))
        out.append(unwrapped)
        out.append(spaced)

        // 🔴 2026-11-16 主人转来的用户反馈：「有时候会帮别人取快递，会发一张截图」——
        //    朋友在聊天里手打的是口语标签「取件号：Y1234」「地点：妈妈驿站（建设路店）」，
        //    正则只认「取件码 / 取货码 / 地址:」，整段直接解析为空。
        //    这里把**标签同义词**换成正则认得的写法，作为**最后一个候选**：
        //      · 不动数字、不动地址内容，只换标签词；
        //      · 原有候选全部落空才轮到它 → OCR 既有语料结果逐字不变；
        //      · 短信原文（ocrSource: false）根本不经过 `candidates`，零回归风险。
        if let normalized = chatLabelNormalized(unwrapped),
           let spacedNormalized = chatLabelNormalized(spaced) {
            out.append(normalized)
            out.append(spacedNormalized)
        }

        // 保序去重
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 聊天 / 截图里的口语标签 → 短信公式认得的标签。
    ///
    /// 顺序有讲究：长词必须先替换，否则「取件地点」被「地点」先吃掉，
    /// 会留下半截「取件地址」没人管。
    private static func chatLabelNormalized(_ text: String) -> String? {
        let synonyms: [(String, String)] = [
            ("取件号", "取件码"), ("取货号", "取货码"), ("提货号", "提货码"),
            ("提件码", "取件码"), ("提件号", "取件码"),
            ("取件地址", "地址"), ("取货地址", "地址"),
            ("取件地点", "地址"), ("取货地点", "地址"),
            ("地点", "地址"), ("位置", "地址"),
        ]
        var out = text
        for (spoken, canonical) in synonyms {
            out = out.replacingOccurrences(of: spoken, with: canonical)
        }
        return out == text ? nil : out
    }

    /// 按「【」切段。
    ///
    /// 快递短信几乎都以【 开头，所以一张截图里若有两条以上短信，切完自然分段 ——
    /// 段内公式的「读到句号或结尾」就不会一路读到下一条短信上去。
    /// 段内同样要去折行，理由见 `parseOCR` 的说明。
    private static func splitByBrandBracket(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""

        for character in text {
            if character == "【", !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { pieces.append(current) }

        return pieces
    }

}

extension PickupParser {

    /// 版本号 / 型号不是取件码（2026-11-17）。
    ///
    /// `codePattern` 里有一条通用分支 `(\d?\+?[A-Za-z]+?(-?\d+)+)`，本意是接住
    /// `YT8861234`、`SF1234567890` 这类「字母前缀 + 长数字」的运单式取件码。
    /// 但它的字母段只要求 ≥1 个字符、数字段只要求 ≥1 位，于是
    /// **`glm-5.3-flash` 里的 `glm-5`**（前置逗号正好满足 lookbehind）也被当成了码。
    ///
    /// 判据刻意收得很窄：**纯字母 + 一个连字符 + 1~2 位数字**，整串就是版本号形态。
    /// · `glm-5` / `gpt-4` / `claude-3` → 是版本号；
    /// · `YT8861234`、`A-12`（柜位，且字母只有 1 位）、`8-4-3019` → 不受影响。
    /// 宁可漏掉极少数真长这样的码，也不能把推广短信里的模型名收成取件码。
    static func isVersionLikeCode(_ code: String) -> Bool {
        code.range(of: #"^[A-Za-z]{2,}-\d{1,2}$"#, options: .regularExpression) != nil
    }

    /// 仅"正在派送/将投递"、没有任何到达线索 → 不该收进待取件。
    static func isPendingDeliveryOnly(_ text: String) -> Bool {
        // 🔴 只挡「派送途中」，「将投递/即将送达」不挡：
        //    主人标注里「将投递（含运单尾号）」判 pickup、「正在派送（只有长运单号）」判 other；
        //    语料基线也把「将投递」那条算作有效短信 —— 挡了会掉基线（实测 64 → 63）。
        let pendingWords = ["正在派送", "派送中", "马上送达"]
        guard pendingWords.contains(where: { text.contains($0) }) else { return false }
        let arrivedWords = ["已到达", "已到", "已放", "已入柜", "请凭", "取件码", "取货码",
                            "暂存", "自提", "已暂存", "到柜"]
        return !arrivedWords.contains(where: { text.contains($0) })
    }

    /// 推广 / 营销短信：**有营销特征 + 零取件线索**两条同时成立才算。
    ///
    /// 🔴 为什么不能只凭「拒收请回复R」判死：**真实驿站短信也常带这句**
    ///    （「【菜鸟驿站】您的包裹已到…取件码 8-4-3019…拒收请回复R」）。
    ///    只按营销词拦，会把一整批正经取件通知杀掉。
    ///
    /// 反向也一样：只按「没有取件码」拦，等于把 ② 的全局闸门再写一遍，没有意义。
    /// 所以判据必须是**两个条件同时成立** —— 有营销话术、且通篇找不到任何取件语境。
    static func isPromotionalOnly(_ text: String) -> Bool {
        let promoWords = ["拒收请回复", "退订回", "回T退订", "回复T退", "限时活动",
                          "免费开通", "免费领取", "限时免费", "抽奖", "大奖",
                          "优惠券", "领取福利", "新用户专享", "首月0元", "限时优惠",
                          "立即下载", "点击下载", "活动详情"]
        guard promoWords.contains(where: { text.contains($0) }) else { return false }

        // 任一命中即视为「有取件语境」，放行给后面的公式去判断。
        // 注意不收「京东」这类品牌词：营销短信里也有「京东卡」。
        let pickupWords = ["取件码", "取货码", "取件", "提货", "驿站", "快递柜",
                           "丰巢", "自提柜", "代收点", "暂存", "凭取", "请凭",
                           "到货", "格口", "货架", "派送", "签收"]
        return !pickupWords.contains(where: { text.contains($0) })
    }
}


private let stationBrandWords = [
    "菜鸟驿站", "菜鸟", "兔喜生活", "兔喜快递", "兔喜", "妈妈驿站", "多多代收点",
    "快宝驿站", "驿收发", "中邮驿站", "邮政驿站", "蜂站", "递管家", "快递驿站",
    "快递超市", "韵达快递超市", "韵达超市", "圆通超市", "超市", "便利店", "驿站", "快递柜"
]

/// 地址展示规整：`张掖市甘州区馨月湖小区南门兴裕隆超市` → `馨月湖小区南门兴裕隆超市`
/// `菜鸟驿站甘州院子店（家佳福超市）店站点` → `菜鸟驿站甘州院子店（家佳福超市）`
func normalizeAddressText(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return s }

    // ① 去行政前缀：省 / 市 / 区县（「小区」「园区」「新区」「景区」「校区」不算）
    s = stripAdminPrefix(s)

    // ② 括号原样保留（2026-11-22 主人定，取代 2026-11-05 的「别名前置」）
    //
    // 老口径是「括号里的别名提到前面」：
    // `菜鸟驿站甘州院子店（家佳福超市）店` → `家佳福超市甘州院子店`。
    // 两个问题在真机上撞到一起：
    //   · 读起来语义是反的 —— 「家佳福超市甘州院子店」像是家佳福超市的分店，
    //     而原文说的是「菜鸟驿站甘州院子店，开在家佳福超市里」；
    //   · `超市` 本身是驿站品牌词（`stationBrandWords`），别名一被判成"驿站名"就
    //     整段丢弃，尾巴那个"店"再拼回去 —— 老大 2026-11-22 收到的
    //     `甘州院子店店` 就是这么来的。
    //
    // 现在的口径：**括号不动、品牌前缀不动**，只清句式尾巴。
    // `菜鸟驿站甘州院子店（家佳福超市）店站点` → `菜鸟驿站甘州院子店（家佳福超市）`
    if let open = s.firstIndex(where: { $0 == "（" || $0 == "(" }) {
        let closeChars: [Character] = ["）", ")"]
        if let close = s[open...].firstIndex(where: { closeChars.contains($0) }) {
            let alias = String(s[s.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            let head = String(s[..<open]).trimmingCharacters(in: .whitespaces)
            var tail = String(s[s.index(after: close)...])
                .replacingOccurrences(of: "站点", with: "")
                .replacingOccurrences(of: "店面", with: "")
                .trimmingCharacters(in: .whitespaces)

            // 「…到XX店站点」的句式尾巴只剩一个"店"：
            // 前半段已经以「店」或某个驿站品牌词（超市 / 便利店 / 驿站…）收尾时它是重复的，丢掉；
            // 否则（`XX（别名）店` 本身就是店名的写法）留着。
            let headLooksLikeStore = head.hasSuffix("店")
                || stationBrandWords.contains { head.hasSuffix($0) }
            if tail == "店", headLooksLikeStore {
                tail = ""
            }

            // 说明性括注（「（请前往自提）」「（超72小时收费）」）不是门店名，不进地址。
            // 正常路径上正则的 lookahead 已经把它截掉了，这里只是兜底。
            let noteWords = ["请", "超", "收取", "收费", "营业", "工作日", "自提",
                             "免费", "凭", "超时", "逾期"]
            let isNote = !alias.isEmpty && noteWords.contains { alias.hasPrefix($0) }

            // 括号里是**行政地址**（「（甘肃省张掖市甘州区馨月湖南门）」）时也不进卡面：
            // 卡上从来只显示"到哪取"的门店/小区，省市县对取件没有作用，留着只是把地址拖长。
            let aliasIsAdmin = !alias.isEmpty && stripAdminPrefix(alias) != alias

            if !alias.isEmpty, !isNote, !aliasIsAdmin {
                // 括号统一用全角，跨短信观感一致（原文半角也归成全角）
                s = head + "（" + alias + "）" + tail
            } else {
                s = head + tail
            }
        }
    }

    // ②.5 括号处理后再剥一次行政前缀（个别短信把省市写在括号前面）
    s = stripAdminPrefix(s)

    // ③ 句式尾巴：孤零零的「站点」、以及叠起来的「店店」
    s = s.replacingOccurrences(of: "店站点", with: "店")
    // 🔴 2026-11-22：`甘州院子店店` 这种重复"店"无论从哪条分支漏出来，最后都在这里折掉一次。
    //    只在结尾折（不动中间的「店」），最多两次，避免把「店店铺」这类正常店名越折越短。
    for _ in 0..<2 where s.hasSuffix("店店") { s.removeLast() }
    return s.trimmingCharacters(in: .whitespaces)
}

/// 反复剥离开头的省 / 市 / 区县，直到剥不动（最多 3 轮，避免死循环）
func stripAdminPrefix(_ input: String) -> String {
    var s = input
    let patterns = [
        #"^[\u4E00-\u9FA5]{2,4}(?:省|自治区|特别行政区)"#,
        #"^[\u4E00-\u9FA5]{2,4}(?:市|自治州|地区)"#,
        #"^[\u4E00-\u9FA5]{2,4}(?:区|县|旗)"#
    ]
    let notAdmin = ["小区", "园区", "新区", "景区", "校区", "社区",
                    "超市", "夜市", "城市", "都市", "市场", "门市", "集市"]
    for _ in 0..<3 {
        var changed = false
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(s.startIndex..., in: s)
            guard let m = re.firstMatch(in: s, range: range),
                  let r = Range(m.range, in: s) else { continue }
            let token = String(s[r])
            if notAdmin.contains(where: { token.contains($0) }) { continue }
            s.removeSubrange(r)
            changed = true
            break
        }
        if !changed { break }
    }
    return s
}

