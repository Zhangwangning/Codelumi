import Foundation
import FoundationModels

// MARK: ============================================================================
// AI 辅助解析 · 真机自检（2026-10-28）
//
// 为什么要在真机上跑：`SystemLanguageModel` 在 iOS 模拟器里基本不可用，
// 「能不能用、准不准、要多久」只有在真机上才有真答案。
//
// 用法（真机，控制台直接看结果）：
// ```
// xcrun devicectl device process launch --console-pty --terminate-running-process \
//   --device <UDID> com.jikezhang.codelumi
// ```
// 环境变量 `SCREEN=aiCheck` 触发。输出形如：
// ```
// [ai-check] 可用性 = 可用
// [ai-check] #1 正则 code=2176—0166 addr=… locker=2号柜
// [ai-check] #1 模型 code=… addr=… locker=… (1.4s)
// ```
// 这份输出就是「AI 到底帮上忙没有」的证据：逐字段比对，
// 模型补正的 sample 再决定要不要固化成正则。
// ============================================================================

@available(iOS 26.0, *)
enum PickupAICheck {

    /// 自检语料：专挑「正则容易漏 / 容易被柜号货架号带偏」的样本。
    static let samples: [String] = [
        "【递管家】您的快递已到当代国际花园七号楼菜鸟驿站，请用提货码2176—0166到2号快递柜取包裹，询驿站工作人员",
        "【微快递】凭取件码199480，前往东冠·逸品龙湾3号楼底商快递驿站2号柜（请前往自提）超72小时收费快递柜02-23格口取您的包裹",
        "【丰巢】您的包裹已存入丰巢智能柜，取件码 5-5-6208，3 号柜，请及时取件",
        "【拼多多】您的快递已到兴裕隆超市，取件码3-1-7788，营业时间8:00-22:00，请及时领取",
        "【兔喜生活】凭431646到北苑家园东门南兔喜一号柜取您中通快递1528的包裹，如有问题请联系17606037630",
        "您的圆通快递已到馨月湖小区南门菜鸟驿站，取件码8-2-331，货架号3-12，请及时领取",
    ]

    /// 跑一遍并打印（真机 console 直接可读）
    static func run() async {
        print("[ai-check] ===== 开始 =====")
        print("[ai-check] 可用性 = \(PickupAI.statusText)")
        // 原始枚举：statusText 只有三档，排查时要看系统到底返回哪个 reason
        let raw = String(describing: SystemLanguageModel.default.availability)
        print("[ai-check] 原始 = \(raw)")
        print("[ai-check] 机型 = \(DeviceProfile.machineID) 系统 = "
              + "\(ProcessInfo.processInfo.operatingSystemVersionString) "
              + "地区 = \(Locale.current.region?.identifier ?? "-") "
              + "语言 = \(Locale.preferredLanguages.prefix(2).joined(separator: ",")) "
              + "支持语言 = \(SystemLanguageModel.default.supportedLanguages.map(\.minimalIdentifier).prefix(3).joined(separator: ",")) "
              + "是否含中文 = \(SystemLanguageModel.default.supportsLocale(Locale(identifier: "zh_CN")))")

        guard PickupAI.isAvailable else {
            print("[ai-check] 模型不可用，跳过（纯正则链路不受影响）")
            return
        }

        for (index, text) in samples.enumerated() {
            let tag = "#\(index + 1)"

            // ── 正则（现有主力） ──
            let parsed = PickupParser.parseAll(text, ocrSource: false)
            if let first = parsed.first {
                print("[ai-check] \(tag) 正则 code=\(first.value) courier=\(first.courier.isEmpty ? "-" : first.courier) addr=\(first.address.isEmpty ? "-" : first.address) locker=\(first.locker.isEmpty ? "-" : first.locker) shelf=\(first.shelf.isEmpty ? "-" : first.shelf) 条数=\(parsed.count)")
            } else {
                print("[ai-check] \(tag) 正则 未解析出任何结果")
            }

            // ── 端侧模型 ──
            let started = Date()
            let fields = await PickupAI.extract(from: text)
            let cost = String(format: "%.1fs", Date().timeIntervalSince(started))
            if let fields {
                print("[ai-check] \(tag) 模型 code=\(fields.code.isEmpty ? "-" : fields.code) courier=\(fields.courier.isEmpty ? "-" : fields.courier) station=\(fields.station.isEmpty ? "-" : fields.station) addr=\(fields.address.isEmpty ? "-" : fields.address) locker=\(fields.locker.isEmpty ? "-" : fields.locker) shelf=\(fields.shelf.isEmpty ? "-" : fields.shelf) (\(cost))")
            } else {
                print("[ai-check] \(tag) 模型 无结果 (\(cost))")
            }
        }

        print("[ai-check] ===== 结束 =====")
    }
}
