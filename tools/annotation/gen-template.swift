import Foundation

// 生成人工标注模板（TSV）：每条短信一行，先用现有解析器预填，
// 人工只需改错的行。列顺序可在 Numbers / Excel 里直接看。
//
// 用法：
//   swiftc -O -o /tmp/gen-template Codelumi/Codelumi/Models/PickupParser.swift \
//     /tmp/stub.swift tools/annotation/gen-template.swift
//   /tmp/gen-template 短信语料库_v1.md > 标注模板.tsv

@main
struct Gen {
    static func main() {
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "短信语料库_v1.md"
    guard let corpus = try? String(contentsOfFile: path, encoding: .utf8) else { exit(1) }
    
    func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ")
         .replacingOccurrences(of: "\n", with: " ")
    }
    
    print(["序号", "预填", "取件码", "运单号", "尾号", "快递公司", "地址", "货架", "柜位",
           "原文", "人工判定(pickup/other)", "人工取件码", "人工地址", "人工备注"]
            .joined(separator: "\t"))
    
    // 🔴 语料里有大量重复段（同一模板反复出现），不去重会让标注量翻倍，
    //    还会让训练集被少数模板主导。去重口径：**去掉所有空白后完全一致**才算重复；
    //    只差数字的样本保留（那是有价值的不同样本）。
    func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{3000}", with: " ")
         .components(separatedBy: .whitespacesAndNewlines)
         .joined()
    }
    var seen = Set<String>()
    var seq = 0
    for line in corpus.split(separator: "\n", omittingEmptySubsequences: false) {
        var t = String(line).trimmingCharacters(in: .whitespaces)
        if t.isEmpty { continue }
        if t.hasPrefix("#") || t.hasPrefix("-") || t.hasPrefix("*") || t.hasPrefix("|")
            || t.hasPrefix(">") || t.hasPrefix("```") { continue }
        if let r = t.range(of: #"^\d+\.\s*"#, options: .regularExpression) { t.removeSubrange(r) }
        if t.count < 8 { continue }
    
        let key = collapse(t)
        guard !seen.contains(key) else { continue }
        seen.insert(key)

        seq += 1
        let r = PickupParser.parse(t)
        let row = [
            "\(seq)",
            r == nil ? "other" : "pickup",
            r?.value ?? "",
            r?.waybill ?? "",
            r?.tail ?? "",
            r?.courier ?? "",
            r?.address ?? "",
            r?.shelf ?? "",
            r?.locker ?? "",
            t,
            "", "", "", ""
        ].map(clean)
        print(row.joined(separator: "\t"))
    }
    }
}
