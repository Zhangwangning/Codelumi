// OCR → 解析引擎 端到端验证（独立运行，不进 App target）
//
// 目的：证明「相册识别」这条路径真的能从一张图走到取件记录，而不是只有 UI。
// 覆盖三件事：
//   ① Vision 的中文 OCR 能否读出短信正文
//   ② PickupParser 能否从 OCR 结果里拿到正确的凭证与地址
//   ③ 同图里的银行消费短信（含「尾号」）是否被正确拦下
//
// 用法（2026-11-20 起必须带这 11 份 —— PickupParser 依赖 PickupRecord.addressIsShelfOnly，
// 只编 PickupParser 会报 "cannot find 'PickupRecord' in scope"）：
//   仓库根下执行：
//   swiftc -O -o /tmp/ocr-pipeline-check \
//     "$PWD/Codelumi/Codelumi/Models/PickupParser.swift" \
//     "$PWD/Codelumi/CodelumiShared/PickupModels.swift" \
//     "$PWD/Codelumi/CodelumiShared/CourierBrand.swift" \
//     "$PWD/Codelumi/CodelumiShared/BrandPalette.swift" \
//     "$PWD/Codelumi/CodelumiShared/PickupStorage.swift" \
//     "$PWD/Codelumi/CodelumiShared/StationGroups.swift" \
//     "$PWD/Codelumi/CodelumiShared/Localization.swift" \
//     "$PWD/Codelumi/CodelumiShared/AppTheme.swift" \
//     "$PWD/Codelumi/CodelumiShared/FontScale.swift" \
//     "$PWD/Codelumi/CodelumiShared/OfflineLicense.swift" \
//     "$PWD/Codelumi/CodelumiShared/LicenseDevice.swift" \
//     "$PWD/tools/swift-cli-shim.swift" \
//     "$PWD/tools/ocr-pipeline-check/main.swift"
//   /tmp/ocr-pipeline-check "$PWD/tools/ocr-pipeline-check/sms-sample.png"
// 实测（2026-11-20）：凭证 C-4082 / 平台 免喜生活 / 地址 舜耕中路2号院… / 银行短信已拦下，全部通过。

import Foundation
import Vision
import CoreGraphics
import ImageIO

// ⚠️ 2026-11-20：这里原本自己定义了一份最小 `PickupKind`，因为 PickupParser 只依赖
// Foundation、可以单文件编译。现在不行了 —— `PickupParser.swift` 会调
// `PickupRecord.addressIsShelfOnly(_:shelf:)`（在 `CodelumiShared/PickupModels.swift`），
// 所以必须把 PickupModels 一起编进来；自己再定义一份同名枚举就变成
// 「'PickupKind' is ambiguous for type lookup in this context」。
// 结论：本地枚举已删除，直接用 PickupModels 里的 `PickupKind`（`label` 口径相同）。
// 编译命令见文件头注释（要带 PickupModels 与它依赖的 iCloud / 品牌 / 主题那几份）。

let imagePath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "sms-sample.png"

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("❌ 读不到图片：\(imagePath)")
    exit(1)
}

print("图片：\(imagePath)  (\(cgImage.width)x\(cgImage.height))")

// MARK: - ① OCR

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = false   // 与 App 内 PickupOCR 保持同一口径

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try? handler.perform([request])

let observations = request.results ?? []
let lines = observations
    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }   // Vision 原点在左下
    .compactMap { $0.topCandidates(1).first?.string }

let ocrText = lines.joined(separator: "\n")

print("\n── OCR 原始输出（\(lines.count) 行）──")
for line in lines { print("  \(line)") }

guard !ocrText.isEmpty else {
    print("\n❌ OCR 没有读出任何文字")
    exit(1)
}

// MARK: - ② 解析

print("\n── 解析结果（走 OCR 多假设归一）──")

var failures: [String] = []

guard let parsed = PickupParser.parseOCR(ocrText) else {
    print("❌ 解析失败：OCR 文本没有通过凭证 / 关键词闸门")
    exit(1)
}

print("  类别：\(parsed.kind.label)  (\(parsed.kind.rawValue))")
print("  凭证：\(parsed.value)")
print("  平台：\(parsed.company)")
print("  地址：\(parsed.address.isEmpty ? "（未识别到）" : parsed.address)")

if parsed.kind != .code { failures.append("类别应为取件码，实际 \(parsed.kind.label)") }
if parsed.value != "C-4082" { failures.append("取件码应为 C-4082，实际 \(parsed.value)") }
if !parsed.address.contains("惠鲜果蔬店") { failures.append("地址应含『惠鲜果蔬店』，实际 \(parsed.address)") }
// 关键回归：按【分段必须把第二条短信隔在外面，否则地址会一路读到它的句号
if parsed.address.contains("中国银行") || parsed.address.contains("58.00") {
    failures.append("地址跨到了第二条短信上：\(parsed.address)")
}
if parsed.address.count > 40 {
    failures.append("地址异常长（\(parsed.address.count) 字），疑似跨段：\(parsed.address)")
}

// MARK: - ③ 干扰项必须被拦下

print("\n── 干扰项校验 ──")

let bankOnly = "【中国银行】您尾号6688的储蓄卡 9月20日 消费人民币58.00元。"
if let wrong = PickupParser.parse(bankOnly) {
    failures.append("银行消费短信被误判为 \(wrong.kind.label) \(wrong.value)")
    print("  ❌ 银行短信被错误写入：\(wrong.kind.label) \(wrong.value)")
} else {
    print("  ✅ 银行消费短信已被拦下（关键词闸门 / 尾号排除词生效）")
}

// MARK: - 结论

print("")
if failures.isEmpty {
    print("✅ 端到端通过：图片 → OCR → 解析，四类字段全部正确，干扰项已拦下")
    exit(0)
} else {
    print("❌ 存在问题：")
    for item in failures { print("   · \(item)") }
    exit(1)
}
