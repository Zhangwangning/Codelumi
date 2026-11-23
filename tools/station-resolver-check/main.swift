// 驿站解析 / 归组 / 组间排序回归自检 —— 独立运行，不进 App target
//
// 用法（2026-11-21 新建，随「组是地点 / 手工指定 / 组名不参与识别」的定案而来）：
//   swiftc -O -o /tmp/station-resolver-check \
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
//     "$PWD/tools/station-resolver-check/main.swift" && /tmp/station-resolver-check
//
// 断言口径（2026-11-21 主人定）：
//   ① 一个驿站**只属于一个组** —— 勾选会把它从原组移过来（移组时已有记录钉在原组）；
//   ② 记录可以**手工指定**驿站 / 组，优先级压过自动识别；
//   ③ 组名 / 别名**不参与**识别（识别只用内置词表 `name`/`aliases` 与自定义驿站名）；
//   ④ 组间排序：件数多在前 → 同数按名字 → 「未标注驿站」置底；组内按「驿站内排序」。
//
// 🔴 退出码 0 = 全过；1 = 有失败项（逐条打印）。
//    改规则时**不要**改这里让它是绿的 —— 先确认每处变化都符合上述口径。

import Foundation


func rec(_ code: String, _ raw: String, station: String? = nil, group: String? = nil) -> PickupRecord {
    var r = PickupRecord(company: "拼多多", code: code, kind: .code, address: "", rawMessage: raw, receivedAt: Date())
    r.stationOverride = station
    r.stationGroupOverride = group
    return r
}

/// CLI 里没有 StationDirectory（App target），这里直接取品牌表
func StationDirectory_builtinNames() -> [String] {
    var seen = Set<String>()
    return CourierBrand.table
        .filter { $0.category == .station || $0.category == .locker }
        .compactMap { seen.insert($0.name).inserted ? $0.name : nil }
}

var fails = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { print("  ✅ \(name)：\(got)") }
    else { fails += 1; print("  ❌ \(name)：got \(got) / want \(want)") }
}

// 0. 每次都从干净状态起跑：先清掉上一次留在磁盘上的组（跑第二遍时同名建组会失败）
for group in StationGroupStore.all() { StationGroupStore.delete(id: group.id) }
// CLI 环境先把内置清单灌进登记表（App 里由启动流程做）
StationIdentity.sync(builtins: StationDirectory_builtinNames(), customs: [])
print("  登记数：\(StationIdentity.allNames().count)")
if let tid = StationIdentity.id(for: "菜鸟驿站") { print("  菜鸟驿站 ID=\(tid)") } else { print("  ❌ 菜鸟驿站 没 ID") }

// 1. 唯一归属 → 组名
let gA = StationGroupStore.create(name: "恒大御府", memberIDs: [StationIdentity.id(for: "菜鸟驿站") ?? ""]) ?? {
    print("  ❌ 建组失败（恒大御府）"); exit(1)
}()
print("  建组结果：members=\(gA.memberIDs.count) id=\(gA.id) name=\(gA.name) 现有组=\(StationGroupStore.all().count) 索引=\(StationGroupStore.groupsByMember().count)")
let r1 = rec("C-1", "菜鸟驿站取件码 C-1")
check("唯一归属", r1.stationResolution.displayName, "恒大御府")

// 2. 同一驿站再进另一个组 → 移过来（一个驿站只属于一个组）
let displaced = StationGroupStore.displacedMembers([StationIdentity.id(for: "菜鸟驿站") ?? ""],
                                                   excluding: nil)
check("移组前能算出原组", displaced.values.first ?? "nil", gA.id)
let gB = StationGroupStore.create(name: "蓝山公馆", memberIDs: [StationIdentity.id(for: "菜鸟驿站") ?? ""]) ?? {
    print("  ❌ 建组失败（蓝山公馆）"); exit(1)
}()
let r2 = rec("C-2", "菜鸟驿站取件码 C-2")
let res2 = r2.stationResolution
check("移组后归属新组", res2.displayName, "蓝山公馆")
check("移组后不再有候选", "\(res2.candidateGroups.count)", "0")
check("移组后不歧义", "\(res2.isAmbiguous)", "false")
check("原组成员被摘掉",
      "\(StationGroupStore.group(id: gA.id)?.memberIDs.count ?? -1)", "0")

// 3. 「编辑驿站 › 驿站组」的快速分组：加入新组时返回原组、并从原组摘掉
let movedBack = StationGroupStore.addMember(stationName: "菜鸟驿站", toGroup: gA.id)
check("快速分组返回原组", movedBack ?? "nil", gB.id)
check("快速分组后归新组", rec("C-2b", "菜鸟驿站取件码").stationResolution.displayName, "恒大御府")
StationGroupStore.removeMember(stationName: "菜鸟驿站")
check("不归组后回落原名", rec("C-2c", "菜鸟驿站取件码").stationResolution.displayName, "菜鸟驿站")
StationGroupStore.addMember(stationName: "菜鸟驿站", toGroup: gB.id)

// 4. 记录级指定组 → 压过一切
let r3 = rec("C-3", "菜鸟驿站取件码 C-3", group: gB.id)
check("记录指定组（压过自动识别）", r3.stationResolution.displayName, "蓝山公馆")
check("记录指定组来源", r3.stationResolution.source.rawValue, "groupOverride")

// 5. 记录级指定驿站名（自定义）→ 用这个名字
let r4 = rec("C-4", "随便一条短信", station: "惠鲜果蔬店")
check("记录指定驿站", r4.stationResolution.stationName, "惠鲜果蔬店")
check("记录指定驿站来源", r4.stationResolution.source.rawValue, "stationOverride")

// 6. 组间排序：件数多在前；未标注置底
var list: [PickupRecord] = []
for i in 0..<3 { list.append(rec("A-\(i)", "菜鸟驿站取件码 A-\(i)")) }          // 菜鸟 → 蓝山公馆 3 件
for i in 0..<1 { list.append(rec("B-\(i)", "妈妈驿站取件码 B-\(i)", group: gA.id)) } // 恒大一
for i in 0..<2 { list.append(rec("Z-\(i)", "没有任何驿站名的短信 \(i)")) }              // 未标注 x2
let sorted = PickupSortLogic.sort(list, mode: .station)
let order = sorted.map { PickupSortLogic.stationName(of: $0) }
print("  排序结果：\(order)")
if order.last!.hasPrefix("未标") == false { fails += 1; print("  ❌ 未标注应在最后") }
// 「蓝山公馆」3 件 > 「恒大御府」1 件 → 蓝山在前
if let firstStation = order.first, let lastStation = order.dropLast().last {
    if firstStation == "恒大御府" && lastStation == "蓝山公馆" { fails += 1; print("  ❌ 件数多的应在前面") }
}

print("\n=== 汇总：失败 \(fails) 项 ===")
exit(fails == 0 ? 0 : 1)
