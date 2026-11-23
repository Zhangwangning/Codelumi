// 通知文案自检（独立运行，不进 App target）
//
// 用法：
//   swiftc -O -o /tmp/notify-check \
//     "/Volumes/ZWN/Downloads/Project/Codelumi/Codelumi/Codelumi/Models/PickupNotifier.swift" \
//     /Volumes/ZWN/Downloads/Project/Codelumi/tools/notify-check/main.swift
//   /tmp/notify-check
//
// 为什么需要这个脚本：通知是**唯一没法在模拟器里自动验证**的东西 ——
// 权限弹窗点不了、横幅要等真机或后台触发。而通知最容易错的地方又特别隐蔽：
// 「取件码有没有真的在标题里」「平台和地址有没有串位」「分隔符是不是英文管道符」。
// 这几件事在界面上完全看不出来，只有用户真收到通知才会发现。
// 所以把文案映射抽成纯函数后在这里断言。

import Foundation

// PickupNotifier.swift 依赖 App 侧的 PickupRecord / PickupKind。
// 这里给最小等价实现，好让脚本不必拉进 Models.swift（那会牵出 SwiftUI + WidgetKit）。
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

struct PickupRecord: Identifiable, Equatable {
    var id = UUID()
    var company: String
    var code: String
    var kind: PickupKind
    var address: String
    var isPickedUp = false
    var receivedAt = Date()
    // 2026-10-28：通知标题要接柜位/货架，桩里同步补上（真身是 Optional）
    var locker: String? = nil
    var shelf: String? = nil
}

/// `PickupNotifier` 的提醒重排会读全表；自检只测文案，给个空实现即可。
enum PickupStorage {
    static func load() -> [PickupRecord] { [] }
}

/// 提醒排期会读权益档位（超时提醒、重复提醒都是 Codelumi Pro）。
/// 自检只测文案映射，恒按 Pro 跑即可，不牵进真正的权益验签链路。
enum EntitlementSnapshot {
    static var licensedPro: Bool { true }
}

var failures = 0
func expect(_ condition: Bool, _ message: String) {
    print("\(condition ? "✓" : "✗") \(message)")
    if !condition { failures += 1 }
}

// MARK: - 1. 标题 = 取件码本身；正文 = 平台 | 地址

print("── 1. 标题=码本身（不带类型字样）/ 正文=「平台 | 地址」 ──")

let samples: [(PickupRecord, String)] = [
    (PickupRecord(company: "兔喜生活", code: "C-4082", kind: .code,
                  address: "舜耕中路恒大御府南门西侧3栋104号惠鲜果蔬店"), "兔喜生活"),
    (PickupRecord(company: "菜鸟驿站", code: "110-5-6178", kind: .code,
                  address: "临沂大学菜鸟驿站"), "菜鸟"),
    (PickupRecord(company: "顺丰速运", code: "8823", kind: .tail,
                  address: "顺丰驿站甘州店"), "顺丰尾号"),
    (PickupRecord(company: "申通快递", code: "770223805536683", kind: .waybill,
                  address: "临沂大学申通快递"), "申通运单号"),
    (PickupRecord(company: "丰巢", code: "8801", kind: .special,
                  address: "甘州院子南门丰巢智能柜"), "丰巢特殊码"),
]

for (record, tag) in samples {
    let copy = PickupNotifier.notificationCopy(for: record)
    let expectedBody = "\(record.company)\(PickupNotifier.fieldSeparator)\(record.address)"
    // 2026-10-28：标题 = 码（有柜位/货架就接在后面），不再拼任何类型前缀
    let suffix = [record.locker, record.shelf]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? ""
    let expectedTitle = suffix.isEmpty ? record.code : "\(record.code) \(suffix)"
    let ok = copy.title == expectedTitle && copy.body == expectedBody
    expect(ok, "[\(tag)] 标题「\(copy.title)」/ 正文「\(copy.body)」")
}

// 2026-10-28 主人：码后面有柜位就带上，没有就空着
print("\n── 1b. 码 + 柜位（有就带，没有不占位） ──")
var withLocker = PickupRecord(company: "丰巢", code: "8-2-4031", kind: .code,
                              address: "甘州院子南门")
withLocker.locker = "3号柜"
let lockerCopy = PickupNotifier.notificationCopy(for: withLocker)
expect(lockerCopy.title == "8-2-4031 3号柜", "带柜位：标题「\(lockerCopy.title)」")

var withShelf = PickupRecord(company: "菜鸟驿站", code: "110-5-6178", kind: .code,
                             address: "临沂大学")
withShelf.shelf = "3-12"
let shelfCopy = PickupNotifier.notificationCopy(for: withShelf)
expect(shelfCopy.title == "110-5-6178 3-12", "带货架：标题「\(shelfCopy.title)」")

// MARK: - 2. 分隔符必须是英文管道符

print("\n── 2. 分隔符 = 英文管道符 ──")
expect(PickupNotifier.fieldSeparator == " | ",
       "fieldSeparator = 「\(PickupNotifier.fieldSeparator)」")
for (record, tag) in samples {
    let body = PickupNotifier.notificationCopy(for: record).body
    expect(body.contains(" | "), "[\(tag)] 正文含「 | 」")
    // 全角/其他管道符都不算
    expect(!body.contains("｜"), "[\(tag)] 正文没用全角「｜」")
}
// 平台与地址必须**同一行**：正文里不能出现换行
for (record, tag) in samples {
    let body = PickupNotifier.notificationCopy(for: record).body
    expect(!body.contains("\n"), "[\(tag)] 正文无换行（平台与地址在同一行）")
}

// MARK: - 3. 硬要求：取件码必须独占标题

print("\n── 3. 「以取件码为重点」= 码必须落在标题 ──")
for (record, tag) in samples {
    let copy = PickupNotifier.notificationCopy(for: record)
    expect(copy.title.contains(record.code), "[\(tag)] 标题含码 \(record.code)")
    // 反向：码不能掉到正文里（那样就变成次要信息了）
    expect(!copy.body.contains(record.code), "[\(tag)] 正文不含码（码不该降级）")
}

// MARK: - 4. 长地址必须完整保留（不能截断）

print("\n── 4. 长地址完整保留 ──")
let longest = samples[0].0
let longBody = PickupNotifier.notificationCopy(for: longest).body
expect(longBody.hasSuffix(longest.address), "25 字长地址完整出现在正文末尾")
expect(longBody.contains(longest.address), "长地址未被截断")

// MARK: - 5. 空地址：不显示地址（不留占位文案）

print("\n── 5. 没识别到地址 → 正文只留平台 ──")
let noAddress = PickupRecord(company: "手动添加", code: "6602", kind: .code, address: "")
let noAddressCopy = PickupNotifier.notificationCopy(for: noAddress)
expect(noAddressCopy.body == "手动添加", "空地址时正文 = 「\(noAddressCopy.body)」（不带分隔符、不带占位词）")
expect(!noAddressCopy.body.contains("未识别"), "正文不含「未识别」这类占位文案")
expect(noAddressCopy.title.contains("6602"), "空地址时标题仍以码为准「\(noAddressCopy.title)」")

// 平台与地址都空 → 正文留空（只显示标题），不能崩也不能冒出分隔符
let blank = PickupRecord(company: "", code: "6603", kind: .code, address: "")
let blankCopy = PickupNotifier.notificationCopy(for: blank)
expect(blankCopy.body.isEmpty, "平台与地址全空时正文为空「\(blankCopy.body)」")

// 只有地址、没有平台 → 正文就是地址本身（前面不能挂分隔符）
let addressOnly = PickupRecord(company: "", code: "6604", kind: .code, address: "甘州院子南门丰巢")
let addressOnlyCopy = PickupNotifier.notificationCopy(for: addressOnly)
expect(addressOnlyCopy.body == "甘州院子南门丰巢", "只有地址时正文 = 「\(addressOnlyCopy.body)」")

// MARK: - 6. 一次多条时每条的码都是各自标题的主角

print("\n── 6. 一次来 5 条：每条各自成篇 ──")
let batch = [
    PickupRecord(company: "菜鸟驿站", code: "110-5-6178", kind: .code, address: "临沂大学菜鸟驿站"),
    PickupRecord(company: "妈妈驿站", code: "47-6-0637", kind: .code, address: "临沂大学体育场圆通速递"),
    PickupRecord(company: "兔喜生活", code: "080400", kind: .code, address: "甘州院子南门馨月湖南门兔喜生活"),
    PickupRecord(company: "兔喜生活", code: "110226", kind: .code, address: "院子馨月湖南门店"),
    PickupRecord(company: "申通快递", code: "16-4-6683", kind: .code, address: "临沂大学申通快递"),
]
let titles = batch.map { PickupNotifier.notificationCopy(for: $0).title }
expect(titles.count == 5, "5 条 → 5 条通知（不做摘要合并）")
expect(Set(titles).count == 5, "5 个标题互不相同（各是各的码）")
expect(titles.allSatisfy { t in batch.contains { t.contains($0.code) } }, "每个标题都能对上一条码")
for title in titles { print("     · \(title)") }

// MARK: - 7. 归组标识

print("\n── 7. 归组 ──")
expect(PickupNotifier.threadID == "com.jikezhang.codelumi.pickup",
       "threadIdentifier 固定为 \(PickupNotifier.threadID)（同批折叠成一组）")

print(failures == 0 ? "\n全部通过" : "\n✗ 有 \(failures) 项未通过")
exit(failures == 0 ? 0 : 1)
