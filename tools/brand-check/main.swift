// 品牌表自检（独立运行，不进 App target）
//
// 用法：
//   swiftc -O -o /tmp/brand-check \
//     "/Volumes/ZWN/Downloads/Project/Codelumi/Codelumi/CodelumiShared/CourierBrand.swift" \
//     /Volumes/ZWN/Downloads/Project/Codelumi/tools/brand-check/main.swift
//   /tmp/brand-check
//
// 目的：关键词匹配优先级、官方图资源挂载、key 唯一性 —— 这三项是「图标挂错」
// 的高发区，且 UI 上不报错、只表现为「图标不对」，所以用脚本兜住。

import SwiftUI

// CourierBrand 唯一的跨文件依赖是 AppTheme 里的 Color(hex:)。
// 这里给一份等价实现，好让自检脚本不必拉进 AppTheme（那会牵出 UIKit）。
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - 1. 匹配优先级

let cases: [(input: String, expect: String)] = [
    ("顺丰速运", "顺丰速运"),
    ("【京东快递】您的包裹", "京东快递"),      // 长关键词必须赢过「京东」
    ("京东物流已揽收", "京东物流"),
    ("【京东】订单", "京东物流"),
    ("【京东秒送】", "京东秒送"),
    ("菜鸟驿站", "菜鸟驿站"),
    ("【菜鸟裹裹】", "菜鸟驿站"),
    ("妈妈驿站", "妈妈驿站"),
    ("拼多多驿站", "拼多多驿站"),
    ("【淘宝闪购】", "淘宝闪购"),            // 必须赢过「淘宝」
    ("【淘宝】", "淘宝"),
    ("【天猫超市】", "天猫"),
    ("【美团】取餐码", "美团"),
    ("星巴克臻选", "星巴克"),
    ("瑞幸咖啡", "瑞幸咖啡"),
    ("【抖音】", "抖音"),
    ("邮政 EMS", "邮政 EMS"),
    ("EMS 快递", "邮政 EMS"),               // 别名命中
    ("【丰巢】", "丰巢"),
    ("近邻宝", "近邻宝"),
    ("韵达快递", "韵达快递"),
    ("德邦快递", "德邦快递"),
    ("申通快递", "申通快递"),
    ("圆通速递", "圆通速递"),
    ("中通快递", "中通快递"),
    ("小红书", "小红书"),
    ("得物", "得物"),
    ("闲鱼", "闲鱼"),
    ("转转", "转转"),
    ("货拉拉", "货拉拉"),
    // ── 2026-09-21 第二批官方图标对应的品牌 ──
    ("【安能物流】您的货物", "安能物流"),
    ("百世快运", "百世快递"),
    ("【百世】", "百世快递"),
    ("优速快递派件中", "优速快递"),
    ("宅急送已揽收", "宅急送"),
    ("中铁快运", "中铁快运"),
    ("【铁路12306】", "铁路12306"),
    ("中国铁路", "铁路12306"),          // 别名命中
    ("【蜜雪冰城】取餐码", "蜜雪冰城"),
    ("【蜜雪】您的饮品", "蜜雪冰城"),     // 别名命中
    ("放哈", "放哈"),
    ("驿收发", "驿收发"),
    ("邻里驿站", "邻里驿站"),
    ("快宝驿站", "快宝驿站"),
    ("熊猫快收", "熊猫快收"),
    ("小兵驿站", "小兵驿站"),
    ("心甜智能柜", "心甜智能柜"),
    ("鸟箱", "鸟箱"),
    ("亚马逊", "亚马逊"),
    ("DHL", "DHL"),
    ("国际转运", "国际转运"),
    // 未收录的「XX驿站」落到通用驿站条目 —— 这是刻意设计：
    // 短信里出现陌生长名时，一个中性的驿站图标比「首字色块」更有信息量。
    ("某某冷门驿站", "快递驿站"),
]

var failures = 0
print("── 1. 关键词匹配 ──")
for (input, expect) in cases {
    let got = CourierBrand.info(for: input).name
    let ok = got == expect
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(input.padding(toLength: 22, withPad: " ", startingAt: 0)) → \(got)\(ok ? "" : "  （应为 \(expect)）")")
}

// MARK: - 2. 官方图资源挂载

// 这批资源已由 tools/import_brand_logos.py 写入 Asset Catalog
let expectedAssets: Set<String> = [
    "brand-shunfeng", "brand-jd", "brand-jd-express", "brand-zhongtong",
    "brand-yuantong", "brand-shentong", "brand-yunda", "brand-ems", "brand-deppon",
    "brand-cainiao", "brand-mama", "brand-tuxi", "brand-pinduoduo",
    "brand-fengchao", "brand-jinlinbao",
    "brand-jd-miaosong", "brand-tmall", "brand-taobao", "brand-taobao-shangou",
    "brand-xiaohongshu", "brand-dewu", "brand-douyin", "brand-meituan",
    "brand-starbucks", "brand-luckin", "brand-huolala", "brand-zhuanzhuan", "brand-xianyu",
    // 2026-09-21 第二批（主人提供的 18 张官方图标）
    "brand-anneng", "brand-baishi", "brand-yousu", "brand-zhaijisong",
    "brand-zhongtie", "brand-railway12306", "brand-fangha", "brand-mixue",
    "brand-yishoufa", "brand-linli", "brand-kuaibao", "brand-xiongmao",
    "brand-xiaobing", "brand-xintian", "brand-niaoxiang", "brand-amazon",
    "brand-dhl", "brand-guojizhuanyun",
    // 极兔：品牌表新增（资源在 CodelumiShared/Assets.xcassets/Brands/brand-jitu.imageset）
    "brand-jitu",
]

print("\n── 2. 官方图标挂载 ──")
let mounted = Set(CourierBrand.table.compactMap(\.asset))
let missing = expectedAssets.subtracting(mounted)
let extra = mounted.subtracting(expectedAssets)
print("表内挂载 \(mounted.count) 个 / 预期 \(expectedAssets.count) 个")
if !missing.isEmpty { failures += 1; print("✗ 表里没挂上：\(missing.sorted().joined(separator: ", "))") }
if !extra.isEmpty { failures += 1; print("✗ 表里多出未预期资源：\(extra.sorted().joined(separator: ", "))") }
if missing.isEmpty && extra.isEmpty { print("✓ 完全一致") }

// MARK: - 2b. 挂载的资源**真的躺在工程里**

// 上面那条只比对「两个硬编码清单是否一致」，挡不住「资源名拼错」——
// 名字写错时表里照样有值、也照样通过，只有运行时才表现为一张空白方块，
// 而且不报任何错。所以这里直接查磁盘。
let projectRoot = URL(fileURLWithPath: #filePath)      // …/tools/brand-check/main.swift
    .deletingLastPathComponent()                        // …/tools/brand-check
    .deletingLastPathComponent()                        // …/tools
    .deletingLastPathComponent()                        // 工程根
// 🔴 projectRoot 是**仓库根**（main.swift 上溯三层：main.swift → brand-check → tools），
//    所以路径第一段是工程根 `Codelumi/`，第二段必须是共享层 `CodelumiShared/`
//    —— Brands 不在 App 自己的 Assets 里。2026-10-30 修（原写法指向 App 的 Assets，找不到目录）。
let brandsDir = projectRoot.appendingPathComponent("Codelumi/CodelumiShared/Assets.xcassets/Brands")

print("\n── 2b. 资源落盘校验 ──")
print("目录：\(brandsDir.path)")
if !FileManager.default.fileExists(atPath: brandsDir.path) {
    failures += 1
    print("✗ 找不到 Brands 目录（先跑 tools/import_brand_logos.py）")
} else {
    let notOnDisk = mounted.sorted().filter { asset in
        !FileManager.default.fileExists(
            atPath: brandsDir.appendingPathComponent("\(asset).imageset/Contents.json").path
        )
    }
    if notOnDisk.isEmpty {
        print("✓ \(mounted.count) 个资源全部存在于 Asset Catalog")
    } else {
        failures += 1
        print("✗ 表里挂了但磁盘上没有：\(notOnDisk.joined(separator: ", "))")
    }

    // 反向：磁盘上有、表里没挂 → 白导入了，图标永远不会出现
    let onDisk = Set(
        (try? FileManager.default.contentsOfDirectory(atPath: brandsDir.path))?
            .filter { $0.hasSuffix(".imageset") }
            .map { String($0.dropLast(".imageset".count)) } ?? []
    )
    let orphan = onDisk.subtracting(mounted)
    if orphan.isEmpty {
        print("✓ 磁盘上无孤儿资源")
    } else {
        failures += 1
        print("✗ 磁盘上有但表里没挂（等于白导入）：\(orphan.sorted().joined(separator: ", "))")
    }
}

// MARK: - 3. key 唯一性 + 分类计数

print("\n── 3. 表结构 ──")
var seenKeys = Set<String>()
var duplicated: [String] = []
for item in CourierBrand.table where !seenKeys.insert(item.key).inserted {
    duplicated.append(item.key)
}
if duplicated.isEmpty {
    print("✓ key 无重复（\(CourierBrand.table.count) 条）")
} else {
    failures += 1
    print("✗ key 重复：\(duplicated.joined(separator: ", "))")
}
for category in CourierBrand.Category.allCases {
    let n = CourierBrand.items(in: category).count
    print("  \(category.rawValue)：\(n) 个\(n == 0 ? "  ⚠ 空分类" : "")")
}

// MARK: - 4. 名称纠错不误伤

print("\n── 4. 名称纠错 ──")
let corrections: [(input: String, expect: String)] = [
    ("免喜生活", "兔喜生活"),   // OCR 形近字，应纠正
    // ⚠ 已知边界：「国通快递」按编辑距离判给「中通快递」（距离 1），
    //   而语义上更该是「圆通速递」（距离 2）。纯编辑距离无法区分
    //   「免喜→兔喜」（该纠）与「国通→中通」（不该纠）—— 两者形式完全相同。
    //   要根治需换成「OCR 形近字白名单」，属独立改动，此处只锁定现状防回归。
    ("国通快递", "中通快递"),
    // 2026-11-21 主人抓到的真 bug：原文含「圆通」，不许被纠成同距离的「中通快递」
    ("圆通快递", "圆通速递"),
    ("中通快递", "中通快递"),
    ("美团", "美团"),           // 已收录，不动
    ("EMS", "EMS"),            // 别名，不动
    ("菜鸟驿站", "菜鸟驿站"),    // 已收录，不动
    ("冷门小驿站", "冷门小驿站"), // 未知，不动
    // 新增品牌不得被纠错误伤；同时它们自身也要能纠 OCR 形近字
    ("蜜雪冰城", "蜜雪冰城"),
    ("蜜雪冰成", "蜜雪冰城"),    // OCR 形近字，应纠正
    ("中铁快远", "中铁快运"),    // OCR 形近字，应纠正
    ("鸟箱", "鸟箱"),           // 2 字名不参与近似匹配，原样返回
    ("放哈", "放哈"),
    ("驿收发", "驿收发"),
    ("宅急送", "宅急送"),
    // 3 字及以上别名是「正规写法」，必须原样保留（不能被纠短）
    ("百世快运", "百世快运"),
    ("中国铁路", "中国铁路"),
]
for (input, expect) in corrections {
    let got = CourierNameCorrector.correct(input)
    let ok = got == expect
    if !ok { failures += 1 }
    print("\(ok ? "✓" : "✗") \(input.padding(toLength: 14, withPad: " ", startingAt: 0)) → \(got)\(ok ? "" : "  （应为 \(expect)）")")
}

print("\n" + (failures == 0 ? "全部通过" : "❌ \(failures) 项未通过"))
exit(failures == 0 ? 0 : 1)
