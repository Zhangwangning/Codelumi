import Foundation

// 解析回归脚手架：逐行读语料，打印解析结果（供人工核对）。
// 用法：parse-check corpus.txt

let path = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "corpus.txt"

guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
    print("读不到语料: \(path)")
    exit(1)
}

var index = 0
for line in raw.components(separatedBy: .newlines) {
    let text = line.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { continue }
    index += 1

    let results = PickupParser.parseAll(text, ocrSource: false)
    if results.isEmpty {
        print(String(format: "%03d REJECT  %@", index, String(text.prefix(24))))
    } else {
        for r in results {
            let fields = "kind=\(r.kind.rawValue) value=\(r.value) company=\(r.company) courier=\(r.courier) waybill=\(r.waybill) tail=\(r.tail) address=\(r.address)"
            print(String(format: "%03d OK      %@", index, fields))
        }
    }
}
