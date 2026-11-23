// 解析引擎回归脚本（独立运行，不进 App target）
//
// 用法：
//   swiftc -O -o /tmp/parser-regression \
//     "/Volumes/ZWN/Downloads/Project/Codelumi/Codelumi/Codelumi/Models/PickupParser.swift" \
//     /Volumes/ZWN/Downloads/Project/Codelumi/tools/parser-regression.swift
//   /tmp/parser-regression "/Volumes/ZWN/Downloads/Project/shortcuts-toolkit-master/快递取件码短信库.md"
//
// 说明：PickupParser 只依赖 Foundation，因此可与本文件单独编译，
// 不必构建整个 App —— 公式改动后可秒级回归。

import Foundation

// 解析引擎只需要 PickupKind 的类型名与 case，这里提供最小等价定义
enum PickupKind: String {
    case code, waybill, tail, special

    var label: String {
        switch self {
        case .code: "取件码"
        case .waybill: "运单号"
        case .tail: "尾号"
        case .special: "特殊取件码"
        }
    }
}

// MARK: - 回归桩

/// `PickupParser` 里会调用这个判断（把「3号货架」这种只描述货位的地址清空）。
/// 真身在 `PickupRecord.addressIsShelfOnly`，但 PickupRecord 依赖 SwiftUI/Color，
/// 无法与 PickupParser 单独编译 —— 回归只需**同义**实现，故在此复刻一份。
/// ⚠️ 改了真身必须同步这里，否则回归会与线上口径漂移。
enum PickupRecord {
    static func addressIsShelfOnly(_ address: String, shelf: String?) -> Bool {
        guard let shelf, !shelf.isEmpty else { return false }
        let compact = address.replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return false }
        let forms = ["\(shelf)号货架", "货架\(shelf)", "货架号\(shelf)",
                     "货架号：\(shelf)", "货架号:\(shelf)"]
        return forms.contains(compact)
    }
}

// MARK: - 读语料

let corpusPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "快递取件码短信库.md"

guard let corpus = try? String(contentsOfFile: corpusPath, encoding: .utf8) else {
    print("❌ 读不到语料文件：\(corpusPath)")
    exit(1)
}

// 语料支持两种形态（2026-09-21 扩容后语料改为纯行）：
//   ① 编号行 `12. 【xx】...`（历史格式）
//   ② 纯文本行  `【xx】...`（现行格式）
//
// 🔴 2026-10-28 修：两种形态**可能同时命中**。全量语料库（`短信语料库_v1.md`）
// 的短信正文里本身就有「1.京东已安排服务工程师…」「2.关注"甘肃电信"公众号…」
// 这种编号行，旧逻辑一看"有编号行"就只走编号模式，449 段只解析出 8 条，
// 汇总全错。现在两种模式都收集，**取条数多的那一种**；纯行模式再把
// 不以「【」开头的行当作上一条的续行合并（长短信导出时会被折成多行）。
let numberedPattern = try! NSRegularExpression(pattern: #"^\s*\d+\.\s*(.+)$"#)
var numberedCases: [String] = []
var lineCases: [String] = []
for line in corpus.split(separator: "\n", omittingEmptySubsequences: false) {
    let text = String(line)
    let range = NSRange(text.startIndex..., in: text)
    if let m = numberedPattern.firstMatch(in: text, range: range),
       let r = Range(m.range(at: 1), in: text) {
        numberedCases.append(String(text[r]))
    }

    // 纯行模式：跳过空行、标题行（#）、列表项（- / * / |）、引用（>）与代码围栏
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    if trimmed.hasPrefix("#") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*")
        || trimmed.hasPrefix("|") || trimmed.hasPrefix(">") || trimmed.hasPrefix("```") {
        continue
    }
    // ⚠️ 不要做「续行合并」：试过按「不以【开头就并回上一条」，结果把
    // 「您有包裹已到达天誉店，取件码为T5-4-1368…」这种**没有【】发件人的独立短信**
    // 也并了进去，精选库从 64 条缩成 63 条、少测一条。一行一条最安全，
    // 极少数被折行的长短信最多让非快递段落多一条，不影响取件凭证命中数。
    lineCases.append(trimmed)
}

let cases = numberedCases.count >= lineCases.count ? numberedCases : lineCases
print("语料形态：编号 \(numberedCases.count) 条 / 纯行 \(lineCases.count) 条 → 采用"
      + (numberedCases.count >= lineCases.count ? "编号" : "纯行")
      + "（\(cases.count) 条）")

// MARK: - 校验正则全部可编译

print("=== 正则编译自检 ===")
let patterns: [(String, String)] = [
    ("关键词", PickupParser.keywordPattern),
    ("取件码", PickupParser.codePattern),
    ("运单号", PickupParser.waybillPattern),
    ("尾号", PickupParser.tailPattern),
    ("特殊格式取件码", PickupParser.specialPattern),
    ("独立地址", PickupParser.standaloneAddressPattern),
    ("匹配地址", PickupParser.matchedAddressPattern),
    ("公司【】", PickupParser.companyBracketPattern),
    ("公司兜底", PickupParser.companyFallbackPattern),
]
var compileFailures = 0
for (name, pattern) in patterns {
    do {
        _ = try NSRegularExpression(pattern: pattern)
    } catch {
        compileFailures += 1
        print("  ❌ \(name) 编译失败：\(error.localizedDescription)")
    }
}
print(compileFailures == 0 ? "  ✅ 9/9 公式均可被 ICU 编译" : "  ⚠️ \(compileFailures) 条公式编译失败")

// MARK: - 逐条解析

print("\n=== \(cases.count) 条语料解析结果 ===")
var kindCount: [String: Int] = [:]
var addressHit = 0
var standaloneAddressHit = 0
var courierHit = 0
var lockerHit = 0
var shelfHit = 0
var unrecognized: [Int] = []
var seenValues: [String: Int] = [:]
/// 可疑项：原文里明明有线索，字段却是空的（供人工逐条核对）
var suspects: [String] = []

for (index, sms) in cases.enumerated() {
    let serial = index + 1
    guard let result = PickupParser.parse(sms) else {
        unrecognized.append(serial)
        print(String(format: "%2d. ❌ 未识别", serial))
        continue
    }
    kindCount[result.kind.label, default: 0] += 1
    if !result.address.isEmpty { addressHit += 1 }
    if !result.courier.isEmpty { courierHit += 1 }
    if !result.locker.isEmpty { lockerHit += 1 }
    if !result.shelf.isEmpty { shelfHit += 1 }
    seenValues[result.value, default: 0] += 1

    var extra: [String] = []
    if result.value.isEmpty { extra.append("⚠️值为空") }
    if result.address.isEmpty { extra.append("⚠️无地址") }
    if result.courier.isEmpty { extra.append("· 无快递公司") }
    let flag = extra.isEmpty ? "" : "  " + extra.joined(separator: " ")

    // 2026-10-28：把 courier / 货架 / 柜位一起打出来 —— 这三个字段是后来加的，
    // 之前回归只看 kind/value/company/address，等于没测。
    print(String(format: "%2d. [%@] %@  | 平台: %@  | 公司: %@  | 地址: %@  | 柜: %@  | 架: %@%@",
                 serial, result.kind.label, result.value,
                 result.company.isEmpty ? "-" : result.company,
                 result.courier.isEmpty ? "-" : result.courier,
                 result.address.isEmpty ? "-" : result.address,
                 result.locker.isEmpty ? "-" : result.locker,
                 result.shelf.isEmpty ? "-" : result.shelf,
                 flag))

    // 线索在、字段空的组合 → 记进可疑清单
    if result.locker.isEmpty, sms.contains("柜") {
        suspects.append("#\(serial) 原文含「柜」但柜位为空")
    }
    if result.shelf.isEmpty, sms.contains("货架") {
        suspects.append("#\(serial) 原文含「货架」但货架号为空")
    }
    if result.company.isEmpty {
        suspects.append("#\(serial) 短信平台为空")
    }
}

if !suspects.isEmpty {
    print("\n=== 可疑项（原文有线索、字段为空）===")
    for line in suspects { print("  " + line) }
}

// 独立地址字段单独统计（parser 内部已优先使用，这里单独跑一遍看覆盖率）
let standaloneRegex = try! NSRegularExpression(pattern: PickupParser.standaloneAddressPattern)
for sms in cases {
    let range = NSRange(sms.startIndex..., in: sms)
    if standaloneRegex.firstMatch(in: sms, range: range) != nil { standaloneAddressHit += 1 }
}

// MARK: - 汇总

print("\n=== 汇总 ===")
print("语料条数：\(cases.count)")
print("识别成功：\(cases.count - unrecognized.count)/\(cases.count)")
if !unrecognized.isEmpty {
    print("未识别序号：\(unrecognized.map(String.init).joined(separator: ", "))")
}
print("类型分布：" + kindCount.sorted { $0.key < $1.key }
        .map { "\($0.key) \($0.value)" }.joined(separator: " / "))
print("地址提取：\(addressHit)/\(cases.count)（其中走独立「地址:」字段 \(standaloneAddressHit) 条）")
print("快递公司：\(courierHit)/\(cases.count)")
print("快递柜位：\(lockerHit)/\(cases.count)")
print("驿站货架：\(shelfHit)/\(cases.count)")
print("空值条数：\(seenValues[""] ?? 0)")

// 与 V7.3.0 基线对照（2026-10-28 更新）
//
// 三套语料各有基线，按规模自动识别；自定义语料（比如临时从「信息」App 导出的
// 一小批）不做回退判定，只打印数值 —— 否则会拿精选库的 64 去比 52 条，误报回退。
//   · 449+ 条「手机短信全量副本」：识别 **192** / 地址 **189**
//     （2026-10-28 把 macOS「信息」App 导出的 18 条增量并入后，从 175/173 升到 192/189）
//   · 60–80 条「快递短信精选库」：识别 64 / 地址 60
//   · 其他：只报数
//
// 地址数为什么是 60 而不是 61：`#57`「您的邮件 NH1575… 已他人签收」原先锚出
// 地址「他人签收」—— 那是签收状态，不是地址，2026-10-28 改成整段弃用。
// **掉 1 条是修对了**，基线同步下调。
let baseline: (recognized: Int, address: Int, label: String)? = {
    if cases.count >= 400 { return (192, 189, "全量库") }
    if (60...80).contains(cases.count) { return (64, 60, "精选库") }
    return nil
}()
let recognized = cases.count - unrecognized.count

guard let baseline else {
    print("\n=== 基线对照 ===")
    print("自定义语料（\(cases.count) 条）：识别 \(recognized)、地址 \(addressHit)"
          + "、公司 \(courierHit)、柜位 \(lockerHit)")
    print("不做回退判定 —— 只看逐条结果对不对。")
    exit(compileFailures == 0 ? 0 : 2)
}

print("\n=== 与 V7.3.0 基线对照（\(baseline.label)）===")
print("识别：\(recognized)/\(cases.count)（基线 \(baseline.recognized)/\(cases.count)）"
      + (recognized >= baseline.recognized ? "  ✅ 无回退" : "  ❌ 回退"))
print("地址：\(addressHit)/\(cases.count)（基线 \(baseline.address)/\(cases.count)）"
      + (addressHit >= baseline.address ? "  ✅ 无回退" : "  ⚠️ 需核对"))

exit(recognized >= baseline.recognized && compileFailures == 0 ? 0 : 2)
