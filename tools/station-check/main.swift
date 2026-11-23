import Foundation
import SwiftUI

// MARK: ============================================================================
// 驿站匹配自检（2026-10-31）
//
// 为什么单独做一个：驿站是卡片上最显眼的一行，也是"拿去照着找店"的那一行，
// 但它此前**完全没有回归覆盖** —— 解析回归只比 code / address / company，
// 驿站错了不会红。这套检查把它固化下来。
//
// 用法：
// ```
// swiftc -O -o /tmp/station-check \
//   Codelumi/CodelumiShared/CourierBrand.swift \
//   Codelumi/CodelumiShared/BrandPalette.swift \
//   tools/station-check/main.swift && /tmp/station-check
// ```
// 退出码 0 = 全部符合基线；1 = 有差异（会逐条打印）。
//
// 🔴 改驿站匹配规则时**不要顺手改 expected.txt 让它变绿**。
//    先确认新判定是对的，再逐条确认每一处变化都符合预期，最后才更新基线。
//    cases.txt / expected.txt 一一对应，行数必须相等。
// ============================================================================

/// `CourierBrand` 依赖 AppTheme 的 `Color(hex:)`，而 AppTheme 用了 UIKit
/// （swiftc 直接编 macOS 时没有 UIColor）。这个最小替身只为让本工具能独立编译，
/// **不参与 App 构建**。
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    static func adaptive(light: UInt32, dark: UInt32) -> Color { Color(hex: light) }
}

// 工具目录由 #filePath 推出，换机器也能跑
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let casesURL = here.appendingPathComponent("cases.txt")
let expectedURL = here.appendingPathComponent("expected.txt")

func readLines(_ url: URL) -> [String] {
    guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
        print("读不到 \(url.lastPathComponent) —— 本工具必须与 cases.txt / expected.txt 放在同一目录")
        exit(2)
    }
    return raw.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// 跑一组「语料 ↔ 期望」对拍，返回不一致条目数。
func runSuite(name: String, cases: URL, expected: URL) -> Int {
    let cases = readLines(cases)
    let expectedNames = readLines(expected)
    guard cases.count == expectedNames.count else {
        print("❌ \(name)：语料 \(cases.count) 行 / 基线 \(expectedNames.count) 行，不一致")
        return -1
    }

    var mismatches: [(index: Int, text: String, want: String, got: String)] = []
    for (i, text) in cases.enumerated() {
        let got = CourierBrand.stationMatch(in: [text])?.name ?? "-"
        if got != expectedNames[i] {
            mismatches.append((i + 1, text, expectedNames[i], got))
        }
    }

    if mismatches.isEmpty {
        print("✅ \(name)：\(cases.count) 条全部符合基线")
        return 0
    }

    print("❌ \(name)：\(mismatches.count)/\(cases.count) 条不符")
    for m in mismatches {
        print("  #\(m.index)  期望 \(m.want)  实际 \(m.got)")
        print("        \(m.text.prefix(56))")
    }
    return mismatches.count
}

let normal = runSuite(name: "精选短信",
                      cases: here.appendingPathComponent("cases.txt"),
                      expected: here.appendingPathComponent("expected.txt"))

// 对抗样本：专门喂"含品牌字样但不是驿站"的短信，防止两字 key 之类的规则再次放水。
// 已知歧义一条：品牌名本身就是常用两字词（如「蓝店」），与「蓝店咖啡馆」无法区分，
// 该条按当前实现记入基线，不作修复。
let adversarial = runSuite(name: "对抗样本",
                           cases: here.appendingPathComponent("adversarial-cases.txt"),
                           expected: here.appendingPathComponent("adversarial-expected.txt"))

if normal == 0 && adversarial == 0 {
    print("✅ 驿站匹配自检通过")
    exit(0)
}
print("\n若改动是有意的：逐条确认后用新结果更新对应基线（别偷偷改基线）。")
exit(1)
