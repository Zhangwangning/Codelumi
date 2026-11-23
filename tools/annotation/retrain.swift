import Foundation
import CreateML

// 用人工标注过的 TSV 重训分类器。
//
// 用法：
//   swiftc -O -parse-as-library -o /tmp/retrain tools/annotation/retrain.swift
//   /tmp/retrain 标注模板.tsv
//
// 读取规则：
//   · 「人工判定」列有值（pickup / other）就用它，否则用「预填」列；
//   · 空行、没有原文的行一律跳过；
//   · 输出模型到 Codelumi/Codelumi/Resources/CodelumiPickup.mlmodel。

@main
struct Retrain {
    static func main() throws {
        let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "标注模板.tsv"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("读不到标注文件：\(path)"); exit(1)
        }
        // 🔴 兼容 CRLF：Excel / csv 写出来的 TSV 常带 \r\n，
        //    只按 \n 切会得到一整行，然后被判成"没有数据"（2026-11-05 实测）。
        var lines = raw.split(whereSeparator: \.isNewline).map(String.init)
        lines = lines.map { $0.replacingOccurrences(of: "\r", with: "") }
        guard lines.count > 1 else { print("没有数据"); exit(1) }
        lines.removeFirst()   // 表头

        var rows: [(String, String)] = []
        var corrected = 0
        for line in lines {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 10 else { continue }
            let prefilled = cols[1].trimmingCharacters(in: .whitespaces)
            let human = cols.count > 10 ? cols[10].trimmingCharacters(in: .whitespaces) : ""
            let text = cols[9]
            guard !text.isEmpty else { continue }
            var label = human.isEmpty ? prefilled : human
            if !human.isEmpty, human != prefilled { corrected += 1 }
            if label != "pickup" && label != "other" { label = "other" }
            rows.append((text, label))
        }
        let pos = rows.filter { $0.1 == "pickup" }.count
        print("样本 \(rows.count)（pickup \(pos) / other \(rows.count - pos)），人工改判 \(corrected) 条")

        let table = try MLDataTable(dictionary: [
            "text": rows.map { $0.0 },
            "label": rows.map { $0.1 }
        ])
        let (train, test) = table.randomSplit(by: 0.8, seed: 42)
        let classifier = try MLTextClassifier(trainingData: train,
                                              textColumn: "text", labelColumn: "label")

        var tp = 0, fn = 0, fp = 0, tn = 0
        for row in test.rows {
            guard let text = row["text"]?.stringValue,
                  let truth = row["label"]?.stringValue else { continue }
            let pred = (try? classifier.prediction(from: text)) ?? "other"
            if truth == "pickup" && pred == "pickup" { tp += 1 }
            if truth == "pickup" && pred != "pickup" { fn += 1 }
            if truth != "pickup" && pred == "pickup" { fp += 1 }
            if truth != "pickup" && pred != "pickup" { tn += 1 }
        }
        print("测试集：真快递保留 \(tp)/\(tp+fn)（误杀 \(fn)），非快递挡掉 \(tn)/\(tn+fp)（误放 \(fp)）")

        let out = URL(fileURLWithPath: "Codelumi/Codelumi/Resources/CodelumiPickup.mlmodel")
        try classifier.write(to: out)
        print("模型已写入：\(out.path)")
    }
}
