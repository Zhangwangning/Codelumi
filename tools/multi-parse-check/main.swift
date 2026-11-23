// 多段解析自检（独立运行，不进 App target）
//
// 用法：
//   swiftc -O -o /tmp/multi-parse \
//     "…/Codelumi/Models/PickupParser.swift" \
//     tools/multi-parse-check/main.swift
//   /tmp/multi-parse
//
// 🔴 2026-11-16 修正用法：原先还要编 `CourierBrand.swift`，但 PickupParser
//    从不引用它；而 CourierBrand 现在又依赖 BrandPalette / BrandDebug / UIImage，
//    拉进独立编译只会报一堆找不到符号。去掉它，回归才能真正跑起来。
//
// 盯的是两件事：
//   ① 一次粘贴多条短信时，**每一条都要被解析出来**（不能只出第一条）；
//   ② OCR 的视觉折行**不能被当成两条**（否则一条短信会被切成两个半截，全废）。

import Foundation
import SwiftUI

// CourierBrand 依赖 AppTheme 的 Color(hex:)，这里补最小等价实现
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// 解析引擎只需要 PickupKind 的类型名与 case
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

/// `PickupParser` 里会调用这个判断（把「3号货架」这种只描述货位的地址清空）。
/// 真身在 `PickupRecord.addressIsShelfOnly`，但完整的 PickupRecord 依赖
/// SwiftUI/WidgetKit 一大串，无法与 PickupParser 单独编译 —— 回归只需**同义**实现。
/// ⚠️ 与 `tools/parser-regression/main.swift` 保持同一份；改真身必须两处同步。
/// 2026-11-16 补：此前缺这个桩，脚本独立编译直接报
/// `cannot find 'PickupRecord' in scope`，等于这条回归一直没跑起来。
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

var failures = 0
func expect(_ condition: Bool, _ message: String) {
    print("\(condition ? "✓" : "✗") \(message)")
    if !condition { failures += 1 }
}

// MARK: - ① 主人给的 5 条短信（从短信 App 多选复制）

let fiveMessages = """
【菜鸟驿站】您有1个包裹已到临沂大学菜鸟驿站，请凭110-5-6178取件。如需查询更多信息，点击u.cainiao.com/51hSXinGLPm
【妈妈驿站】取货码47-6-0637，您有圆通快递包裹，已到临沂大学体育场圆通速递，询18053994327
【兔喜生活】您的中国邮政包裹已到甘州院子南门馨月湖南门兔喜生活，凭080400来取，有问题联系19193601936
【兔喜生活】您有快递已暂存院子馨月湖南门店，暂存码110226，更多服务请点击s.tuxi.com/w/JYOGpXH3
【申通快递】您的包裹770223805536683已在临沂大学申通快递滞留1天未取，请尽快取件16-4-6683，详询17762053653
"""

print("── ① 一次粘贴 5 条 ──")
let segments = PickupParser.segments(fiveMessages)
expect(segments.count == 5, "切段数 = \(segments.count)（应为 5）")

let parsed = PickupParser.parseAll(fiveMessages, ocrSource: true)
expect(parsed.count == 5, "解析出 \(parsed.count) 条（应为 5）")

for (i, item) in parsed.enumerated() {
    print("""
      [\(i + 1)] \(item.kind.label)  code=\(item.value)
           平台=\(item.company)
           地址=\(item.address)
    """)
}

// MARK: - ② OCR 视觉折行不能被切成两条

print("\n── ② OCR 折行不误切 ──")
let wrapped = """
【兔喜生活】您有快递已暂存院子馨月湖南门店，暂存
码110226，更多服务请点击s.tuxi.com/w/JYOGpXH3
"""
let wrappedSegments = PickupParser.segments(wrapped)
expect(wrappedSegments.count == 1, "折行文本切段数 = \(wrappedSegments.count)（应为 1）")
let wrappedParsed = PickupParser.parseAll(wrapped, ocrSource: true)
expect(wrappedParsed.count == 1, "折行文本解析出 \(wrappedParsed.count) 条（应为 1）")
if let first = wrappedParsed.first {
    expect(first.value == "110226", "折行后取件码 = \(first.value)（应为 110226）")
}

// 折行 + 多条的混合：第 1 条折行，后面还跟着第 2 条
print("\n── ②b 折行 + 多条混合 ──")
let mixed = """
【兔喜生活】您有快递已暂存院子馨月湖南门店，暂存
码110226，更多服务请点击s.tuxi.com/w/JYOGpXH3
【菜鸟驿站】您有1个包裹已到临沂大学菜鸟驿站，请凭110-5-6178取件。
"""
let mixedSegments = PickupParser.segments(mixed)
expect(mixedSegments.count == 2, "混合文本切段数 = \(mixedSegments.count)（应为 2）")
let mixedParsed = PickupParser.parseAll(mixed, ocrSource: true)
expect(mixedParsed.count == 2, "混合文本解析出 \(mixedParsed.count) 条（应为 2）")

// MARK: - ③ 无「【」的输入仍按单条处理

print("\n── ③ 无品牌括号 ──")
expect(PickupParser.segments("C-4082").count == 1, "裸码切段数 = 1")
expect(PickupParser.segments("取件码为C-4082，请到东门驿站取").count == 1, "无括号单条切段数 = 1")
expect(PickupParser.parseAll("C-4082", ocrSource: true).isEmpty,
       "裸码不该被解析成取件信息（应由调用方走裸码兜底）")

// MARK: - ④ 混入非快递短信时只取有信息的

print("\n── ④ 干扰项 ──")
let noisy = """
【招商银行】您账户1234于9月21日支出人民币58.00元，余额12345.67元。
【菜鸟驿站】您有1个包裹已到临沂大学菜鸟驿站，请凭110-5-6178取件。
【中国移动】您本月流量已使用80%，剩余2GB。
"""
let noisyParsed = PickupParser.parseAll(noisy, ocrSource: true)
expect(noisyParsed.count == 1, "干扰文本解析出 \(noisyParsed.count) 条（应为 1）")
if let only = noisyParsed.first {
    expect(only.company.contains("菜鸟"), "干扰中取到的是 \(only.company)")
}

print("\n" + (failures == 0 ? "全部通过" : "❌ \(failures) 项未通过"))
exit(failures == 0 ? 0 : 1)
