// 合并策略（同码再进）回归自检 —— 独立运行，不进 App target
//
// 用法（2026-11-20 更新：依赖链已随共享层增长，编译列表变长）：
//   swiftc -O -o /tmp/dedupe-check \
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
//     "$PWD/tools/dedupe-check/main.swift"
//   /tmp/dedupe-check
//
// 断言口径（🔴 2026-10-30 主人改过，别再按旧口径判）：
//   旧（2026-09-21）：「同码再进 → 旧条自动转已取 + 新条入列」。
//   现（2026-10-30 起）：**同码再进 = 同一件还在待取、又被提醒了一次** →
//     不新建、不改已取状态，只把这次时间记进旧条的 `history`（`Result.updated`）；
//     `Result.completed` 恒为空（旧口径残留字段）。
//   这条改动修掉了「用户没取件却被统计成已取、停留时长被算成 0」的假数据。
//
// 2026-11-20 接手时本工具：① `swiftc` 编不过（依赖链漂移）；② 断言仍是旧口径，
// 跑到用例 1 就因 `r.records[1]` 越界崩掉。现在两处都已按当前语义重写。

import Foundation
import SwiftUI

// `Color(hex:)` 由 `CodelumiShared/AppTheme.swift` 提供（本工具连带编译 AppTheme，
// 早先那份本地补丁会和它撞成「ambiguous use of init(hex:)」）。
// 颜色不参与合并策略的任何断言。

var failures = 0
var checks = 0

func expect(_ condition: Bool, _ label: String, detail: String = "") {
    checks += 1
    if condition {
        print("  ✅ \(label)")
    } else {
        failures += 1
        print("  ❌ \(label)\(detail.isEmpty ? "" : "  →  \(detail)")")
    }
}

func make(_ company: String, _ code: String, _ address: String,
          kind: PickupKind = .code, picked: Bool = false) -> PickupRecord {
    PickupRecord(company: company, code: code, kind: kind, address: address,
                 rawMessage: "【\(company)】取件码 \(code)", receivedAt: Date(),
                 isPickedUp: picked)
}

func marks(_ list: [PickupRecord]) -> String {
    list.map { "\($0.code)\($0.isPickedUp ? "(已取)" : "(待取)")" }.joined(separator: " → ")
}

print("=== 合并策略（同码再进）回归自检 ===\n")

// ── 用例 1：核心语义 —— 同码再进，旧条不翻状态，只追加时间线
do {
    print("① 同码再进 → 不新建、不标已取，只记一次提醒时间")
    let old = make("兔喜生活", "C-4082", "舜耕中路104号惠鲜果蔬店")
    let new = make("兔喜生活", "C-4082", "舜耕中路104号惠鲜果蔬店")
    let r = PickupMerge.merge([old], with: [new])
    expect(r.added.isEmpty, "不新增记录", detail: "实际 \(r.added.count)")
    expect(r.completed.isEmpty, "不产生「自动完成」（旧口径已废）", detail: "\(r.completed)")
    expect(r.records.count == 1, "列表仍是 1 条", detail: "实际 \(r.records.count)")
    expect(r.records.first?.isPickedUp == false, "旧条保持待取（用户没取，不能替他判取）",
           detail: marks(r.records))
    expect(r.updated.count == 1, "记进 `updated`（这条被提醒了一次）", detail: "实际 \(r.updated.count)")
    expect((r.records.first?.history?.count ?? 0) == 2,
           "`history` 累积 2 个时间点", detail: "实际 \(r.records.first?.history?.count ?? -1)")
    print("     最终：\(marks(r.records))")
}

// ── 用例 2：已经取过件的同码 → 是一件新包裹，必须新增
do {
    print("\n② 同码但旧条已取件 → 新增一条待取")
    let old = make("菜鸟驿站", "8-2-109", "馨月湖小区南门菜鸟驿站", picked: true)
    let new = make("菜鸟驿站", "8-2-109", "馨月湖小区南门菜鸟驿站")
    let r = PickupMerge.merge([old], with: [new])
    expect(r.added.count == 1, "新增 1 条", detail: "实际 \(r.added.count)")
    expect(r.records.count == 2, "列表 2 条（历史 1 + 新 1）", detail: "实际 \(r.records.count)")
    expect(r.records.first?.isPickedUp == true, "历史条保持已取件")
    expect(r.records.last?.isPickedUp == false, "新条为待取件", detail: marks(r.records))
}

// ── 用例 3：不同取件码互不干扰
do {
    print("\n③ 不同取件码各自独立")
    let a = make("申通快递", "16-4-6683", "临沂大学申通快递")
    let b = make("申通快递", "9-15-34", "惠旺家便利店")
    let r = PickupMerge.merge([a], with: [b])
    expect(r.added.count == 1 && r.updated.isEmpty, "只有新码写入，无「重复提醒」")
    expect(r.records.count == 2 && r.records.allSatisfy { !$0.isPickedUp },
           "两条均为待取件", detail: marks(r.records))
}

// ── 用例 4：同一批里出现两次同码（一条输入含多条短信）
do {
    print("\n④ 同一批内同码两次 → 批内去重，只留一条")
    let b1 = make("兔喜生活", "260108", "甘州院子南门馨月湖南门兔喜生活")
    let b2 = make("兔喜生活", "260108", "甘州院子南门馨月湖南门兔喜生活")
    let r = PickupMerge.merge([], with: [b1, b2])
    expect(r.added.count == 1, "只写入 1 条（批内重复丢弃）", detail: "实际 \(r.added.count)")
    expect(r.records.count == 1, "列表 1 条", detail: "实际 \(r.records.count)")
    expect(r.records.first?.isPickedUp == false, "保持待取", detail: marks(r.records))
}

// ── 用例 5：地址不同 → 不算同一件
do {
    print("\n⑤ 取件码相同但地址不同 → 两条并存")
    let a = make("韵达快递", "0425-0007", "馨月湖小区南门兴裕隆超市")
    let b = make("韵达快递", "0425-0007", "甘州区滨河新区屋兰路82号")
    let r = PickupMerge.merge([a], with: [b])
    expect(r.updated.isEmpty, "不触发「重复提醒」（指纹含地址）")
    expect(r.added.count == 1, "新地址那条写入", detail: "实际 \(r.added.count)")
    expect(r.records.count == 2 && r.records.allSatisfy { !$0.isPickedUp },
           "两条均待取", detail: marks(r.records))
}

// ── 用例 6：类别不同 → 不算同一条
do {
    print("\n⑥ 凭证相同但类别不同 → 两条并存")
    let a = make("中国邮政", "0412", "投递中", kind: .tail)
    let b = make("中国邮政", "0412", "投递中", kind: .waybill)
    let r = PickupMerge.merge([a], with: [b])
    expect(r.updated.isEmpty, "不触发「重复提醒」（指纹含类别）")
    expect(r.added.count == 1 && r.records.count == 2, "两条并存", detail: marks(r.records))
}

// ── 用例 7：既有顺序保持，新增追加在末尾
do {
    print("\n⑦ 既有顺序不变，新条追加在末尾；同码那条只更新")
    let a = make("中通快递", "1-1-9069", "旭辉御府")
    let b = make("韵达快递", "7-3-1141", "旭辉御府13栋102")
    let c = make("圆通速递", "0629-8032", "门卫快递收发室")
    let r = PickupMerge.merge([a, b], with: [c])
    expect(r.records.map(\.code) == ["1-1-9069", "7-3-1141", "0629-8032"],
           "顺序 = 既有(2 条，原序) + 新增(1 条)",
           detail: r.records.map(\.code).joined(separator: " → "))
    expect(r.records[1].code == "7-3-1141" && !r.records[1].isPickedUp, "中间那条不受影响")

    // 同码再进：位置上不新增，原位置不变
    let c2 = make("圆通速递", "0629-8032", "门卫快递收发室")
    let r2 = PickupMerge.merge(r.records, with: [c2])
    expect(r2.records.map(\.code) == r.records.map(\.code), "同码再进不改变列表与顺序",
           detail: r2.records.map(\.code).joined(separator: " → "))
    expect(r2.updated.map(\.code) == ["0629-8032"], "记进 `updated` 的是那条同码",
           detail: "\(r2.updated.map(\.code))")
}

// ── 用例 8：多条混合（现实场景：一次粘贴 3 条短信，其中 1 条同码）
do {
    print("\n⑧ 混合场景：3 条新短信，其中 1 条与既有同码")
    let old = make("兔喜生活", "230376", "甘州院子南门馨月湖南门兔喜生活")
    let n1 = make("兔喜生活", "230376", "甘州院子南门馨月湖南门兔喜生活")
    let n2 = make("圆通速递", "0587", "北门架子上")
    let n3 = make("中通快递", "0629-8032", "门卫快递收发室")
    let r = PickupMerge.merge([old], with: [n1, n2, n3])
    expect(r.added.count == 2, "只有 2 条是新包裹", detail: "实际 \(r.added.count)")
    expect(r.updated.map(\.code) == ["230376"], "同码那条记为「重复提醒」", detail: "\(r.updated.map(\.code))")
    expect(r.records.count == 3, "列表共 3 条", detail: "实际 \(r.records.count)")
    let pending = r.records.filter { !$0.isPickedUp }.count
    expect(pending == 3, "待取 3 件（全是待取，没人被自动标已取）", detail: "实际 \(pending)")
}

print("\n=== 汇总 ===")
print("断言 \(checks) 项，失败 \(failures) 项")
if failures == 0 {
    print("✅ 合并策略符合「同码再进 → 视为同一件被重复提醒，只更新时间线」")
} else {
    print("❌ 有 \(failures) 项不符合预期")
}
exit(failures == 0 ? 0 : 1)
