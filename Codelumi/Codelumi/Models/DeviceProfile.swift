import UIKit

// MARK: ============================================================================
// 设备能力档案
//
// 灵动岛没有公开的「支持与否」查询 API —— ActivityKit 在任何设备上都可用，
// 系统会自动把灵动岛形态降级成锁屏卡片。但产品口径需要区分（#主人 2026-09-21）：
// **没有灵动岛的机型（iPhone 13 Pro Max 及更早 / 全系非 Pro 刘海屏），
// 不该在 UI 里展示「灵动岛」这个功能** —— 说了用户也用不上，只会困惑。
// 锁屏实时活动在这些设备上照常有效（系统自动降级），所以功能本身不关，
// 只是把「灵动岛」字样与岛形态的展示收起来。
//
// 机型判定：utsname 读 machine；**模拟器不返回机型名**（返回 arm64/x86_64），
// 用 `SIMULATOR_MODEL_IDENTIFIER` 环境变量拿真实机型 —— 模拟器选「iPhone 16 Pro」
// 就该按有岛处理、选「iPhone 13 Pro Max」就按无岛处理。
// ============================================================================

enum DeviceProfile {

    private static let machine: String = {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        #endif
    }()

    /// 机型标识（`iPhone17,1` 这类）。给自检/诊断用，别拿它做功能分支。
    static var machineID: String { machine }

    /// iPhone 14 Pro 起才有灵动岛；白名单 + 「iPhone17/18/19 及以后全系」规则。
    /// iPhone 15 全系、16 全系（含 16e）、17 全系都有岛；14 / 13 及更早全系没有。
    static var hasDynamicIsland: Bool {
        switch machine {
        case "iPhone15,2", "iPhone15,3":          // 14 Pro / 14 Pro Max
            return true
        case "iPhone15,4", "iPhone15,5",          // 15 / 15 Plus
             "iPhone16,1", "iPhone16,2":          // 15 Pro / 15 Pro Max
            return true
        default:
            // iPhone 16 / 17 及以后全系标配灵动岛（identifier 前缀 iPhone17+）
            return machine.hasPrefix("iPhone17")
                || machine.hasPrefix("iPhone18")
                || machine.hasPrefix("iPhone19")
        }
    }

    /// 当前窗口的逻辑宽度（pt）。
    ///
    /// 灵动岛展开态的宽度**不是固定值**，而是跟着机型走的：
    /// 官方尺寸表 `393 屏 → 371` / `430 屏 → 408`，两档的差值恰好都是 **22pt**
    /// （岛两侧各留 11pt 不画）。所以公式 = 屏宽 − 22，iPhone 16 Pro（402）→ **380**。
    ///
    /// 预览以前写死 371（393 档），在 402 的机器上比真机窄 9pt；
    /// 高度上又缺了挖孔那一行，于是整体比真机小一大截 —— 主人 2026-10-28 指认。
    /// `UIScreen.main` 在 iOS 26 已废弃，改从 windowScene 取。
    static var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.width ?? 393
    }

    /// 灵动岛展开态的整岛宽度（含黑壳）。
    ///
    /// 🔴 2026-10-28 最终值 = **屏宽 − 28**（402 → 374）。
    /// 依据：真机完整截图 1206×2622（3x，即 402pt 屏）上，岛体横向占
    /// x 42…1163 = 1121px = **374pt**，两侧各留 14pt。
    ///
    /// 前面几版都偏窄，因为标定用的图有缩放、拿不到准确 px/pt：
    /// HIG 推的「屏宽 − 22」= 380（略宽）、按手机边框推的 348 / 362（偏窄）。
    /// 只有「3x 原始截图 + 直接数像素」这条路是准的。
    static var islandExpandedWidth: CGFloat { screenWidth - 28 }
}
