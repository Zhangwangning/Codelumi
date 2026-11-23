import Foundation

// MARK: ============================================================================
// App 图标切换（2026-11-01 主人）
//
// 十五套内置图标，**第 6 套（黑盒立体）为默认主图标**。
//
// 🔴 编号演进（每次改动都要同步 `legacyMap` 与 `currentScheme`，否则老用户选错图）：
//    · 方案 1：早期编号，带空洞（2,3,5,7,9,12,14…22）。
//    · 方案 2（2026-11-15）：重排为连续 01–15，当晚补「蓝线稿白盒」成 16，
//      次日再加「皮革卡包」成 17。默认从那时的第 4 套「C 标」换成第 7 套「黑盒立体」。
//    · 方案 3（2026-11-21）：删掉 6 套（包裹 / 蓝牌 / 黑牌 / 暗牌 / 光泽黑标 / 白盒平涂），
//      其中 5 套图面上印着「ALLUDE」，品牌改名 Codelumi 后不能再用。
//      剩 11 套按原相对顺序重排为 01–11，默认那套「黑盒立体」由 07 变成 **06**。
//    · 方案 4（2026-11-21 晚）：在 11 套后面**追加** 12–15（用户给的「优化App图标」四张）。
//      纯追加、不动 01–11 的编号 → `legacyMap` 无需再扩，老用户选择不受影响。
//
// 🔴 图标的 imageset 统一放 `CodelumiShared/Assets.xcassets`（2026-11-15 从 App 的
//    catalog 迁过来）：App 与小组件两个 target **都**编译这份共享 catalog，
//    灵动岛/锁屏才取得到图。之前只放在 App 的 catalog 里，小组件进程找不到
//    `AppIconNN` 这名字，`Image(…)` 直接渲染成灰块 —— 那是 1.0.0(312) 灵动岛
//    不显示 App 图标的根因。
// 图都是 512 / 1536 满幅方图，不再裁切；主图标 art 与 alternate 的对应关系见下。
//
// 主图标放 `AppIcon.appiconset`；其余是 **alternate icon** —— 由 Info.plist 的
// `CFBundleAlternateIcons` 声明，图是包根目录的 `IconNN@2x/@3x`（iPad 另加
// `IconNN~ipad` / `IconNN@2x~ipad`），**不能只放资产目录**：App Store 校验
// ITMS-90032 会认不出资产目录里的备用图标，直接用错误退包（2026-11-12 踩过）。
// 每套都带 Any / Dark / Tinted 三张 1024（iOS 18 起系统按外观自动选）。
// 需要 `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`，否则 actool 会跳过这些图标集。
//
// 🔴 选择状态存 **App Group**：灵动岛/锁屏由小组件进程渲染，它读不到 App 的偏好，
//    只有共享容器里的这份能两边都看到。
// 🔴 给灵动岛用的图必须带 `template-rendering-intent: original` 与 1x/2x/3x 三档，
//    否则 WidgetKit 会把它当模板涂成单色 —— 详见 AGENTS.md。
// ============================================================================

enum AppIconChoice: String, CaseIterable, Identifiable {
    /// 编号与界面网格**严格一致**：从上到下、从左到右 = 01…15。
    case icon01, icon02, icon03, icon04, icon05, icon06
    case icon07, icon08, icon09, icon10, icon11
    /// 2026-11-21 新增四套（用户给的「优化App图标」四张）。只追加，不动前面编号。
    case icon12, icon13, icon14, icon15

    /// 默认图标 = 第 6 套（黑盒立体）。
    ///
    /// 🔴 它同时是**主图标**（`AppIcon.appiconset` 的三张 1024），所以
    ///    `alternateName` 对它返回 nil（= 用回主图标），`Info.plist` 的
    ///    `CFBundleAlternateIcons` **不能**登记 `Icon06`，否则两处打架。
    ///    其余 14 套都走 alternate，文件是 `Codelumi/AppIcons/IconNN@2x|@3x.png`。
    static let fallback: AppIconChoice = .icon06

    var id: String { rawValue }

    /// 序号（1–15），与网格顺序一致。用于文案与文件名。
    var number: Int {
        switch self {
        case .icon01: 1
        case .icon02: 2
        case .icon03: 3
        case .icon04: 4
        case .icon05: 5
        case .icon06: 6
        case .icon07: 7
        case .icon08: 8
        case .icon09: 9
        case .icon10: 10
        case .icon11: 11
        case .icon12: 12
        case .icon13: 13
        case .icon14: 14
        case .icon15: 15
        }
    }

    /// 格子里的无障碍名。主人没点名，按图形起的描述名，随时可改。
    var title: String {
        switch self {
        case .icon01: "信封"
        case .icon02: "取件袋"
        case .icon03: "文件夹"
        case .icon04: "C 标"
        case .icon05: "霓虹 A"
        case .icon06: "黑盒立体"
        case .icon07: "蓝盒立体"
        case .icon08: "黑盒平涂"
        case .icon09: "蓝盒平涂"
        case .icon10: "线框白盒"
        case .icon11: "皮革卡包"
        case .icon12: "黑牌微笑"
        case .icon13: "蓝牌微笑"
        case .icon14: "玻璃立方"
        case .icon15: "四格蓝柱"
        }
    }

    /// 资源目录里的图（App 内预览、灵动岛、关于页都用这个名字）
    var assetName: String { String(format: "AppIcon%02d", number) }

    /// 🔴 **图标目录编号**（2026-11-21 主人）：`DZYTB` = 自定义图标，后 4 位补零，
    /// 按网格**从上到下、从左到右**发号，`DZYTB0001` … `DZYTB0015`。
    ///
    /// 为什么要有它：口头说「第 12 套」时，"第几个"随增删会漂，而图又不是靠序号
    /// 就能认出来的（12 和 13 都是深色底）。有了这个号，界面底部直接显示
    /// 「当前选中 DZYTB0006」，对不上时一眼就能确认到底选的是哪一张。
    /// 口径与驿站 ID（`NZYZ00001` / `DZYYZ00001` / `FZYD00001`）一致，方便互相对照。
    var catalogID: String { String(format: "DZYTB%04d", number) }

    /// `UIApplication.setAlternateIconName` 用的名字；默认图标返回 nil
    ///
    /// 注意：`Icon02`（原主图标「取件袋」）现在是 alternate，必须由
    /// `Codelumi/Info.plist` 的 `CFBundleAlternateIcons` 声明 + bundle 根目录的
    /// `Icon02@2x.png`(120) / `Icon02@3x.png`(180) 两份文件，缺一不可。
    var alternateName: String? {
        self == Self.fallback ? nil : String(format: "Icon%02d", number)
    }
}

enum AppIconStore {
    private static let key = "codelumi.appIcon"
    /// 编号方案版本。`"3"` = 2026-11-21 删 6 套、重排为连续 01…11。
    /// ⚠️ 12–15 是**追加**，不改变已有序号，所以方案号仍留在 `"3"`。
    ///    只有「已有图标的序号被改动」时才需要升版本并扩 `legacyMap`。
    private static let schemeKey = "codelumi.appIcon.scheme"
    private static let currentScheme = "3"

    /// 方案 1 的老 `rawValue` → **方案 2 的序号**。
    ///
    /// ⚠️ 这里存的是序号不是 case：case 名会随方案变（`icon09` 在方案 1 是「霓虹 A」，
    ///    在方案 2 是「蓝牌」，在方案 3 是「蓝盒平涂」），只有序号能跨版本对齐。
    /// 已被删掉的那几套（1 号码牌 / 4 扫码件 / 6 手提袋 / 8 卡包 / 11 牛皮纸 / 13 快递箱 /
    /// 23 玻璃白盒）不在表里 → 落到 `fallback`。
    private static let legacyV1Numbers: [String: Int] = [
        "icon02": 1,    // 信封
        "icon03": 2,    // 取件袋
        "icon05": 3,    // 文件夹
        "icon07": 4,    // C 标
        "icon09": 5,    // 霓虹 A
        "icon12": 6,    // 包裹
        "icon14": 7,    // 黑盒立体
        "icon15": 8,    // 蓝盒立体
        "icon16": 9,    // 蓝牌
        "icon17": 10,   // 黑盒平涂
        "icon18": 11,   // 蓝盒平涂
        "icon19": 12,   // 黑牌
        "icon20": 13,   // 暗牌
        "icon21": 14,   // 光泽黑标
        "icon22": 15,   // 白盒平涂
    ]

    /// **方案 2 的序号 → 方案 3 的序号**。
    ///
    /// 被删的 6 套（2 号方案里的 6 包裹 / 9 蓝牌 / 12 黑牌 / 13 暗牌 / 14 光泽黑标 /
    /// 15 白盒平涂）故意不在表里 → 那些用户落到默认图标。
    private static let v2ToV3Numbers: [Int: Int] = [
        1: 1, 2: 2, 3: 3, 4: 4, 5: 5,
        7: 6,          // 黑盒立体（原名默认，现仍是默认）
        8: 7,          // 蓝盒立体
        10: 8,         // 黑盒平涂
        11: 9,         // 蓝盒平涂
        16: 10,        // 线框白盒
        17: 11,        // 皮革卡包
    ]

    /// 同一容器内的镜像文件。
    ///
    /// 🔴 为什么需要它（2026-11-15 实测）：App Group **不可用**时
    ///    （典型是命令行 `CODE_SIGNING_ALLOWED=NO` 构建的无签名调试包），
    ///    `UserDefaults(suiteName:)` 返回 nil，App 写进自己的 `.standard`、
    ///    扩展写进扩展自己的 `.standard` —— 两个进程互相看不见。
    ///    结果就是「桌面图标换了、灵动岛还是 C 标」，主人一眼看出对不上。
    ///    文件走 `PickupStorage.directory`：App Group 在就用共享目录，
    ///    不在就回落到 App 容器（扩展与 App 共用同一个容器），两边都能读。
    private static var mirrorURL: URL {
        PickupStorage.directory.appendingPathComponent("appicon.txt")
    }

    /// 当前选中的图标。未选过 → `fallback`。
    ///
    /// 读取顺序：App Group 偏好 → 同容器镜像文件 → 本进程 `.standard`。
    static var current: AppIconChoice {
        if let raw = UserDefaults(suiteName: PickupStorage.appGroupID)?.string(forKey: key),
           let choice = AppIconChoice(rawValue: raw) {
            return choice
        }
        if let raw = try? String(contentsOf: mirrorURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let choice = AppIconChoice(rawValue: raw) {
            return choice
        }
        if let raw = UserDefaults.standard.string(forKey: key),
           let choice = AppIconChoice(rawValue: raw) {
            return choice
        }
        return .fallback
    }

    /// 存下来的原始值，**不做合法性校验**；三处按与 `current` 相同的优先级，
    /// 取第一个非空。没存过 → nil。
    private static var storedRawValue: String? {
        if let raw = UserDefaults(suiteName: PickupStorage.appGroupID)?.string(forKey: key) {
            return raw
        }
        if let raw = try? String(contentsOf: mirrorURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            return raw
        }
        return UserDefaults.standard.string(forKey: key)
    }

    /// 已记录过的编号方案；没记过就当方案 1（最早那版）。
    private static var storedScheme: String {
        UserDefaults(suiteName: PickupStorage.appGroupID)?.string(forKey: schemeKey)
            ?? UserDefaults.standard.string(forKey: schemeKey)
            ?? "1"
    }

    /// 一次性迁移：把老方案下存的选择换算到当前方案。
    ///
    /// 只在 `storedScheme != currentScheme` 时执行，跑完打标记，之后永久 no-op。
    /// 升级路径是**链式**的：方案 1 → 方案 2 → 方案 3，中途不能跳步
    /// （`icon09` 三个方案里是三种不同的图，直接查一张表会对错人）。
    /// 返回**迁移后应当生效的图标**；调用方负责把它同步给系统
    /// （`UIApplication.shared.setAlternateIconName(choice.alternateName)`）。
    /// 没有迁移发生（已是当前方案）时返回 nil。
    @discardableResult
    static func migrateLegacyNumberingIfNeeded() -> AppIconChoice? {
        let scheme = storedScheme
        if scheme == currentScheme { return nil }

        var v2Number: Int?
        if let raw = storedRawValue {
            if scheme == "2" {
                // 方案 2 的 rawValue 就是 "iconNN"，直接取序号
                if raw.hasPrefix("icon"), let n = Int(raw.dropFirst(4)) {
                    v2Number = n
                }
            } else {
                v2Number = legacyV1Numbers[raw]
            }
        }

        // 已删掉的图、或从没存过 → 回落到当前默认图标
        let target: AppIconChoice
        if let n = v2Number, let new = v2ToV3Numbers[n],
           let match = AppIconChoice.allCases.first(where: { $0.number == new }) {
            target = match
        } else {
            target = .fallback
        }

        // `store` 会顺手把方案标记写成当前版本，这里再补一遍确保三处一致
        store(target)
        return target
    }

    /// 写选择：三处都写（App Group 偏好、镜像文件、本进程偏好），
    /// 保证「有 App Group」与「没有 App Group」两种情况下扩展都读得到。
    /// 真正切换系统图标由 App 侧调用 `UIApplication.setAlternateIconName` 完成。
    ///
    /// 🔴 顺手打上 `schemeKey` 标记：新版本写下的值一律是「当前编号方案」，
    ///    否则下次冷启动的一次性迁移会把它当成老编号再换一遍（会换错）。
    static func store(_ choice: AppIconChoice) {
        UserDefaults(suiteName: PickupStorage.appGroupID)?.set(choice.rawValue, forKey: key)
        UserDefaults(suiteName: PickupStorage.appGroupID)?.set(currentScheme, forKey: schemeKey)
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        UserDefaults.standard.set(currentScheme, forKey: schemeKey)
        try? FileManager.default.createDirectory(at: PickupStorage.directory,
                                                 withIntermediateDirectories: true)
        try? choice.rawValue.write(to: mirrorURL, atomically: true, encoding: .utf8)
    }
}
