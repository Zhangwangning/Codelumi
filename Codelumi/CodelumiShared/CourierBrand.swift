import SwiftUI

// MARK: - 快递平台 / 驿站 / 商家 品牌图标体系
//
// ── 图标策略（2026-09-21 改为官方图标优先）────────────────────────────────
//  · **首选官方图标**：`asset` 指向 Asset Catalog 里的 `brand-*` 图片，
//    与各家 App 图标同形制（方形直角底，圆角由 CourierLogo 统一裁切）；
//  · **兜底自绘**：未收录的品牌退回「品牌色渐变方块 + 白色图形」——
//    图形优先选语义贴合的 SF Symbols，无贴切符号的用品牌字标；
//  · 颜色：无论走图片还是自绘，`from` / `to` 都是内容层配色的统一入口
//         （卡片上的品牌色文字、图标色晕都取它），因此必须填准；
//  · 兜底：未知快递取名称首字 + 稳定哈希配色，保证「任何新快递都有图标」；
//  · 所有 SF Symbols 名称均已对照 iOS 27 运行时的
//    CoreGlyphs/symbol_order.plist 逐个核验存在（避免出现空白图标）。
//
// ── 清单来源 ──────────────────────────────────────────────────────────
//  驿站/代收平台取自 CNPP《2026 快递驿站行业十大品牌》：菜鸟驿站、拼多多驿站、
//  兔喜、妈妈驿站、驿收发、中邮驿站、韵达快递超市、极兔邻里、喵站、快宝驿站，
//  并补入 蓝店、熊猫快收、小兵驿站、摩西管家、递管家、微快递 等 12 个品牌。
//  商家 / 电商为 2026-09-21 新增，覆盖「取餐码、到店码」这类非快递场景。

enum CourierBrand {

    enum Category: String, CaseIterable, Identifiable {
        case company = "快递公司"
        case station = "驿站 / 代收平台"
        case locker = "智能快递柜"
        case merchant = "商家 / 电商"
        case international = "国际快递"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .company: "shippingbox.fill"
            case .station: "storefront.fill"
            case .locker: "cabinet.fill"
            case .merchant: "cart.fill"
            case .international: "globe.asia.australia.fill"
            }
        }
    }

    enum Glyph {
        case symbol(String)
        case mark(String)
    }

    struct Info: Identifiable {
        let key: String          // 匹配关键词
        let name: String         // 规范名称
        let category: Category
        /// ⚠️ **只是手写兜底色**（2026-10-28 起）：没有官方图标的品牌才会用到。
        /// 有 `asset` 的品牌一律以图标提取色为准（见 `resolvedFrom`）——
        /// 以前 UI 直接吃这个值，于是丰巢图标是黄蜂巢、卡片却是手填的青绿。
        let from: UInt32
        let to: UInt32           // 渐变止色（仅自绘兜底时使用）
        let glyph: Glyph         // 自绘兜底图形
        var asset: String? = nil // 官方图标资源名；有则优先于自绘
        var aliases: [String] = []   // 额外匹配词（同一条目不必拆成多条）

        var id: String { key }

        /// **唯一正确的取色出口**（2026-10-28 主人：「模糊掉图标，那个颜色一般就是了」）：
        ///   ① 例外表 `CourierBrand.manualColors`（极少数图标读不准的品牌）
        ///   ② 有官方图标 → 取图标提取出的主色
        ///   ③ 都没有 → 手写 `from`
        /// UI 一律读这个值，不要再直接摸 `from`。
        var resolvedFrom: UInt32 {
            if let manual = CourierBrand.manualColors[name] { return manual }
            if let asset, let palette = BrandPalette.colors(forAsset: asset), let first = palette.first {
                return first
            }
            return from
        }

        /// UI 用色：随外观自适应 —— 浅色用墨色版本（亮品牌压暗），深色用提亮版本。
        /// 统一入口是 `CourierBrand.color(for:)`，这里保持一致，别各取一版。
        var color: Color { Color.adaptive(light: ink, dark: inkOnDark) }

        /// 浅色背景上的「品牌墨色」：主色过亮（黄、浅绿、浅粉）时自动压暗一档。
        ///
        /// 为什么需要：取色统一到图标之后，丰巢 / 韵达 / 美团 / DHL 这些**黄色品牌**
        /// 的取件码直接画 `#F3C50D` 会在浅黄卡面、浅黄玻璃底上糊成一片。
        /// 压暗后仍是同一色相（深黄），辨识度与可读性兼顾。
        /// ⚠️ 深色背景（锁屏卡、灵动岛）**不要**用这个 —— 那里亮色才看得清，用 `inkOnDark`。
        var ink: UInt32 { CourierBrand.inkColor(resolvedFrom) }

        /// 深色背景上的品牌文字色：**暗品牌提亮到可读**，亮品牌原样。
        ///
        /// 见 `CourierBrand.color(for:)` 的注释（2026-11-22 深色模式可读性修复）。
        var inkOnDark: UInt32 { CourierBrand.inkColorOnDark(resolvedFrom) }
    }

    /// 人工颜色覆盖表 —— **例外，不是常态**。
    ///
    /// 只收「图标里品牌彩块太小、提取必然读偏」的品牌：
    ///   · 顺丰速运：白底 + 黑环黑字 + 米粒大的红点，24 色量化也只能读到黑；
    ///     红才是它的识别色。
    ///   · 宅急送：白底 + 黑字 + 左下角绿猴圆标（绿只占 1.5%），提取会落到近黑。
    /// 其余品牌一律走图标提取，别往这张表里加"我觉得好看"的颜色。
    static let manualColors: [String: UInt32] = [
        "顺丰速运": 0xD6001C,
        "宅急送": 0x009B4E,
    ]

    /// 品牌清单。匹配规则见 `info(for:)` —— **最长关键词优先**，
    /// 所以这里不必为了「谁先谁后」而小心排序，按分类聚合、便于阅读即可。
    static let table: [Info] = [

        // ───────────────────────── 快递公司 ─────────────────────────
        Info(key: "顺丰", name: "顺丰速运", category: .company,
             from: 0xD6001C, to: 0x1F2126, glyph: .mark("顺"),
             asset: "brand-shunfeng"),
        // 「京东快递」「京东秒送」必须排在通用「京东」之前，否则会被它抢走匹配
        Info(key: "京东快递", name: "京东快递", category: .company,
             from: 0xE1251B, to: 0xA81A12, glyph: .mark("京"),
             asset: "brand-jd-express"),
        Info(key: "京东", name: "京东物流", category: .company,
             from: 0xE1251B, to: 0xA81A12, glyph: .mark("京"),
             asset: "brand-jd"),
        Info(key: "中通", name: "中通快递", category: .company,
             from: 0x1663C7, to: 0x0B4A96, glyph: .mark("中"),
             asset: "brand-zhongtong"),
        Info(key: "圆通", name: "圆通速递", category: .company,
             from: 0x7E57C2, to: 0x573B94, glyph: .mark("圆"),
             asset: "brand-yuantong"),
        Info(key: "申通", name: "申通快递", category: .company,
             from: 0xF58220, to: 0xC25F0C, glyph: .mark("申"),
             asset: "brand-shentong"),
        Info(key: "韵达", name: "韵达快递", category: .company,
             from: 0xF5B400, to: 0xBF8500, glyph: .mark("韵"),
             asset: "brand-yunda"),
        Info(key: "极兔", name: "极兔速递", category: .company,
             from: 0xD2103C, to: 0x9C0A2A, glyph: .symbol("hare.fill"),
             asset: "brand-jitu"),
        Info(key: "邮政", name: "邮政 EMS", category: .company,
             from: 0x007A33, to: 0x005324, glyph: .symbol("envelope.fill"),
             asset: "brand-ems", aliases: ["EMS"]),
        Info(key: "德邦", name: "德邦快递", category: .company,
             from: 0x35506E, to: 0x22364C, glyph: .mark("邦"),
             asset: "brand-deppon"),
        Info(key: "百世", name: "百世快递", category: .company,
             from: 0x1B3F7A, to: 0x112A55, glyph: .mark("百"),
             asset: "brand-baishi", aliases: ["百世快运"]),
        Info(key: "天天", name: "天天快递", category: .company,
             from: 0x29B6F6, to: 0x0277BD, glyph: .mark("天"),
             asset: "brand-tiantian"),
        Info(key: "优速", name: "优速快递", category: .company,
             from: 0x2A2E7E, to: 0x1B1E54, glyph: .symbol("bolt.fill"),
             asset: "brand-yousu"),
        Info(key: "安能", name: "安能物流", category: .company,
             from: 0xF97316, to: 0xC2570C, glyph: .symbol("truck.box.fill"),
             asset: "brand-anneng"),
        Info(key: "宅急送", name: "宅急送", category: .company,
             from: 0x009B4E, to: 0x006B36, glyph: .symbol("house.fill"),
             asset: "brand-zhaijisong"),
        Info(key: "跨越", name: "跨越速运", category: .company,
             from: 0x0B63C5, to: 0x08498F, glyph: .symbol("paperplane.fill")),
        Info(key: "速尔", name: "速尔快递", category: .company,
             from: 0x00897B, to: 0x00675C, glyph: .mark("速")),
        Info(key: "中铁", name: "中铁快运", category: .company,
             from: 0x1A4E8F, to: 0x113563, glyph: .symbol("tram.fill"),
             asset: "brand-zhongtie"),
        Info(key: "铁路12306", name: "铁路12306", category: .company,
             from: 0x1E6FD9, to: 0x14509E, glyph: .symbol("tram.fill"),
             asset: "brand-railway12306", aliases: ["中国铁路", "12306"]),

        // ───────────────────── 驿站 / 代收平台 ─────────────────────
        // 具体品牌必须排在通用「驿站」之前
        Info(key: "拼多多驿站", name: "拼多多驿站", category: .station,
             from: 0xE22E1F, to: 0xA81F13, glyph: .symbol("bag.fill"),
             asset: "brand-pinduoduo"),
        Info(key: "妈妈驿站", name: "妈妈驿站", category: .station,
             from: 0xF06292, to: 0xBE3A68, glyph: .symbol("heart.fill"),
             asset: "brand-mama"),
        Info(key: "中邮", name: "中邮驿站", category: .station,
             from: 0x007A33, to: 0x005324, glyph: .symbol("storefront.fill")),
        Info(key: "菜鸟", name: "菜鸟驿站", category: .station,
             from: 0x1E9EFF, to: 0x0A72C9, glyph: .symbol("bird.fill"),
             asset: "brand-cainiao", aliases: ["菜鸟裹裹"]),
        Info(key: "兔喜", name: "兔喜生活", category: .station,
             from: 0x363AFB, to: 0x2327B8, glyph: .mark("喜"),
             asset: "brand-tuxi", aliases: ["兔喜生活", "兔喜快递柜"]),
        Info(key: "驿收发", name: "驿收发", category: .station,
             from: 0x142F55, to: 0x0C1E38, glyph: .symbol("arrow.left.arrow.right"),
             asset: "brand-yishoufa"),
        Info(key: "邻里", name: "邻里驿站", category: .station,
             from: 0xE23A45, to: 0xB02430, glyph: .symbol("storefront.fill"),
             asset: "brand-linli"),
        Info(key: "喵站", name: "喵站", category: .station,
             from: 0xF58220, to: 0xC25F0C, glyph: .symbol("pawprint.fill"),
             asset: "brand-miaozhan", aliases: ["喵柜"]),
        Info(key: "快宝", name: "快宝驿站", category: .station,
             from: 0x22C55E, to: 0x168040, glyph: .symbol("storefront.fill"),
             asset: "brand-kuaibao"),
        Info(key: "蓝店", name: "蓝店", category: .station,
             from: 0x2E6BE6, to: 0x1F4CAD, glyph: .symbol("storefront.fill")),
        Info(key: "熊猫", name: "熊猫快收", category: .station,
             from: 0x3A3A3A, to: 0x1A1A1A, glyph: .symbol("pawprint.fill"),
             asset: "brand-xiongmao"),
        Info(key: "小兵", name: "小兵驿站", category: .station,
             from: 0x3FA845, to: 0x2A7431, glyph: .symbol("shield.lefthalf.filled"),
             asset: "brand-xiaobing"),
        Info(key: "摩西", name: "摩西管家", category: .station,
             from: 0x6D4C41, to: 0x4C342C, glyph: .symbol("person.crop.circle.fill")),
        Info(key: "递管家", name: "递管家", category: .station,
             from: 0x475569, to: 0x2C3746, glyph: .symbol("person.badge.shield.checkmark.fill")),
        Info(key: "微快递", name: "微快递", category: .station,
             from: 0x0EA5E9, to: 0x066FAF, glyph: .symbol("shippingbox.fill")),
        Info(key: "多多代收点", name: "多多代收点", category: .station,
             from: 0xE22E1F, to: 0xA81F13, glyph: .symbol("bag.fill"),
             asset: "brand-duoduodaishou"),
        Info(key: "绿驿", name: "绿驿生活", category: .station,
             from: 0x16A34A, to: 0x0E7433, glyph: .symbol("leaf.fill")),
        // 2026-10-31 主人报的一条：短信以【欢猫驿站】开头，但表里没有这个品牌，
        // 于是「驿站」只能靠地址里的另一家店命中。补进内置表后，
        // 它作为**已知驿站品牌**参与匹配（配色/图标也随之统一）。
        Info(key: "欢猫", name: "欢猫驿站", category: .station,
             from: 0xFF7A45, to: 0xD94F1E, glyph: .symbol("storefront.fill"),
             aliases: ["欢猫驿站"]),
        // 🔴 key 原来是「快递超市」这四个字 —— 太宽了：任何短信只要出现
        //    「某某快递超市」都会被认成韵达家的代收点（2026-10-31 主人报的
        //    「欢猫驿站」那条就是这么被误标的）。改成全名，只在真的写了
        //    「韵达快递超市」时才命中。
        Info(key: "韵达快递超市", name: "韵达快递超市", category: .station,
             from: 0xF5B400, to: 0xBF8500, glyph: .symbol("storefront.fill"),
             asset: "brand-yundakuaichaoshi"),
        // ⚠️ 2026-10-28 主人：删掉「快递代收点」与「快递驿站」两条。
        //    它们是「XX驿站 / 代收点」的通用兜底词（key 就是「驿站」「代收点」），
        //    不是真实品牌，摆进驿站管理的网格里只是凑数；
        //    杀掉后短信里只写「到XX驿站取」而没有具体品牌名的记录，
        //    第二段就老实留空，不再冒出一个没有身份的「快递驿站」图标。
        // 2026-10-18 互联网统计新增（CNPP《2026 快递驿站十大品牌》+ 报告大厅《2025 代收十大》补全覆盖）
        Info(key: "极兔邻里", name: "极兔邻里", category: .station,
             from: 0xD2103C, to: 0x9C0A2A, glyph: .symbol("storefront.fill")),
        Info(key: "百世邻里", name: "百世邻里", category: .station,
             from: 0x1B3F7A, to: 0x112A55, glyph: .symbol("storefront.fill")),
        Info(key: "中通快递超市", name: "中通快递超市", category: .station,
             from: 0x1663C7, to: 0x0B4A96, glyph: .symbol("storefront.fill")),
        Info(key: "申通快递超市", name: "申通快递超市", category: .station,
             from: 0xF58220, to: 0xC25F0C, glyph: .symbol("storefront.fill")),
        Info(key: "京东驿栈", name: "京东驿栈", category: .station,
             from: 0xE1251B, to: 0xA81A12, glyph: .symbol("storefront.fill"),
             aliases: ["京东快递站"]),

        // ─────────────────────── 智能快递柜 ───────────────────────
        Info(key: "丰巢", name: "丰巢", category: .locker,
             from: 0x00C2A8, to: 0x00897B, glyph: .symbol("hexagon.fill"),
             asset: "brand-fengchao"),
        Info(key: "近邻宝", name: "近邻宝", category: .locker,
             from: 0x5B5BD6, to: 0x3E3EA8, glyph: .symbol("cabinet.fill"),
             asset: "brand-jinlinbao"),
        // alias 里补「格格爽存」：那是格格家的柜，短信里写的是「【格格爽存】凭取件码…」。
        // 原来靠 key「格格」两字扫正文才命中的；key 退出自由文本匹配后，
        // 这类真实变体要**逐个**补成 alias，而不是把 key 放回去全局放水。
        Info(key: "格格", name: "格格货栈", category: .locker,
             from: 0x8B5CF6, to: 0x6234C4, glyph: .symbol("square.grid.3x3.fill"),
             aliases: ["格格爽存"]),
        // ⚠️ key 必须是**完整品牌名**：`info(for:)` 取「命中关键词最长」的那条，
        //    「心甜智能柜」同时含「心甜」(2) 与「智能柜」(3)。用短 key 时会被
        //    更长的通用词抢走、图标挂成通用柜子。加「心甜」作别名即可两全。
        //    （2026-10-28 通用「智能柜」「快递柜」两条已删，这条规则对
        //      「熊猫智能柜」等仍成立 —— 别处新增柜品牌时照此办理。）
        Info(key: "心甜智能柜", name: "心甜智能柜", category: .locker,
             from: 0xF58220, to: 0xC25F0C, glyph: .symbol("heart.circle.fill"),
             asset: "brand-xintian", aliases: ["心甜"]),
        Info(key: "鸟箱", name: "鸟箱", category: .locker,
             from: 0xF29B1D, to: 0xC17711, glyph: .symbol("square.grid.2x2.fill"),
             asset: "brand-niaoxiang"),
        Info(key: "收件宝", name: "收件宝", category: .locker,
             from: 0x009688, to: 0x00706A, glyph: .symbol("cabinet.fill"),
             asset: "brand-shoujianbao"),
        Info(key: "云柜", name: "云柜", category: .locker,
             from: 0x3F51B5, to: 0x2C3A82, glyph: .symbol("cabinet.fill")),
        // ⚠️ 2026-10-28 主人：删掉「智能快递柜」（key「智能柜」）与「快递柜」两条 ——
        //    同驿站侧一个道理，它们是通用词兜底，不是品牌；摆进柜子网格只是凑数，
        //    还会把「丰巢智能柜」这类具体品牌之外的短信兜成一个无名柜图标。
        // 2026-10-18 互联网统计新增（智能柜榜单补全覆盖）
        Info(key: "速递易", name: "速递易", category: .locker,
             from: 0x00C2A8, to: 0x00897B, glyph: .symbol("cabinet.fill")),
        Info(key: "递易", name: "递易", category: .locker,
             from: 0x5B5BD6, to: 0x3E3EA8, glyph: .symbol("cabinet.fill")),
        Info(key: "熊猫智能柜", name: "熊猫智能柜", category: .locker,
             from: 0x3A3A3A, to: 0x1A1A1A, glyph: .symbol("cabinet.fill")),
        // ⚠️ 2026-10-28 主人：删掉「日日顺乐家」。

        // ───────────────────── 商家 / 电商 ─────────────────────
        // 「取餐码、到店码」场景的主力：短信里出现的多是下单平台而非快递公司。
        // 顺序同样按「长关键词优先」——「淘宝闪购」必须在「淘宝」之前。
        Info(key: "拼多多", name: "拼多多", category: .merchant,
             from: 0xE22E1F, to: 0xA81F13, glyph: .symbol("bag.fill"),
             asset: "brand-pinduoduo"),
        Info(key: "京东秒送", name: "京东秒送", category: .merchant,
             from: 0xE1251B, to: 0xA81F12, glyph: .mark("秒"),
             asset: "brand-jd-miaosong"),
        Info(key: "淘宝闪购", name: "淘宝闪购", category: .merchant,
             from: 0xFF6100, to: 0xC44A00, glyph: .mark("闪"),
             asset: "brand-taobao-shangou"),
        Info(key: "淘宝", name: "淘宝", category: .merchant,
             from: 0xFF5000, to: 0xC43E00, glyph: .mark("淘"),
             asset: "brand-taobao"),
        Info(key: "天猫", name: "天猫", category: .merchant,
             from: 0xFF0036, to: 0xC40029, glyph: .mark("猫"),
             asset: "brand-tmall"),
        Info(key: "抖音", name: "抖音", category: .merchant,
             from: 0x1C1C1E, to: 0x000000, glyph: .mark("抖"),
             asset: "brand-douyin"),
        Info(key: "小红书", name: "小红书", category: .merchant,
             from: 0xFF2442, to: 0xC41B33, glyph: .mark("书"),
             asset: "brand-xiaohongshu"),
        Info(key: "得物", name: "得物", category: .merchant,
             from: 0x1C1C1E, to: 0x000000, glyph: .mark("得"),
             asset: "brand-dewu"),
        Info(key: "闲鱼", name: "闲鱼", category: .merchant,
             from: 0xFEE901, to: 0xC4B501, glyph: .mark("闲"),
             asset: "brand-xianyu"),
        Info(key: "转转", name: "转转", category: .merchant,
             from: 0xE6002D, to: 0xB30024, glyph: .mark("转"),
             asset: "brand-zhuanzhuan"),
        Info(key: "美团", name: "美团", category: .merchant,
             from: 0xFFD100, to: 0xC4A100, glyph: .mark("美"),
             asset: "brand-meituan"),
        Info(key: "星巴克", name: "星巴克", category: .merchant,
             from: 0x00704A, to: 0x005337, glyph: .symbol("cup.and.saucer.fill"),
             asset: "brand-starbucks"),
        Info(key: "瑞幸", name: "瑞幸咖啡", category: .merchant,
             from: 0x002D62, to: 0x001E42, glyph: .symbol("cup.and.saucer.fill"),
             asset: "brand-luckin"),
        Info(key: "货拉拉", name: "货拉拉", category: .merchant,
             from: 0xFF7100, to: 0xC45600, glyph: .symbol("truck.box.fill"),
             asset: "brand-huolala"),
        Info(key: "蜜雪冰城", name: "蜜雪冰城", category: .merchant,
             from: 0xE60012, to: 0xAE000E, glyph: .symbol("cup.and.saucer.fill"),
             asset: "brand-mixue", aliases: ["蜜雪"]),
        Info(key: "放哈", name: "放哈", category: .merchant,
             from: 0xF26522, to: 0xB84A17, glyph: .symbol("cup.and.saucer.fill"),
             asset: "brand-fangha", aliases: ["FUNDOSA"]),

        // ──────────────────────── 国际快递 ────────────────────────
        Info(key: "DHL", name: "DHL", category: .international,
             from: 0xFFCC00, to: 0xD9A800, glyph: .mark("DHL"),
             asset: "brand-dhl"),
        Info(key: "FEDEX", name: "FedEx", category: .international,
             from: 0x4D148C, to: 0x350D62, glyph: .mark("FedEx")),
        Info(key: "UPS", name: "UPS", category: .international,
             from: 0x5B4636, to: 0x351C15, glyph: .mark("UPS")),
        Info(key: "TNT", name: "TNT", category: .international,
             from: 0xFF6600, to: 0xC24E00, glyph: .mark("TNT")),
        Info(key: "亚马逊", name: "亚马逊", category: .international,
             from: 0xFF9900, to: 0xD17D00, glyph: .mark("亚"),
             asset: "brand-amazon"),
        Info(key: "国际", name: "国际转运", category: .international,
             from: 0xF5A623, to: 0xC07E12, glyph: .symbol("globe.asia.australia.fill"),
             asset: "brand-guojizhuanyun"),
    ]

    /// 未知快递的兜底色板（彼此可区分）
    private static let fallbackPalette: [UInt32] = [
        0x2E5BFF, 0xFF8A3D, 0x12C2A0, 0xEC4899,
        0xF5A623, 0x7C3AED, 0x0EA5E9, 0xE1251B,
    ]

    /// 稳定哈希：同一家公司永远同一个颜色
    private static func stableHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 5381
        for scalar in text.unicodeScalars {
            hash = (hash &* 33) &+ scalar.value
        }
        return hash
    }

    /// **最长关键词优先**：同一条文本可能命中多个 key（「京东秒送」同时含「京东」、
    /// 「淘宝闪购」同时含「淘宝」），取命中的**最长**那个，语义最具体。
    /// 长度相同时按表内顺序取先出现的（如「中邮驿站」对「中邮」+「驿站」）。
    ///
    /// 之所以不再依赖「表内顺序即优先级」：品牌一多，谁排前面就变得很脆弱 ——
    /// 「京东秒送」放在商家分类（表末尾）时曾被快递公司里的「京东」抢走。
    /// `info(for:)` 的结果缓存（2026-10-28）。
    ///
    /// 品牌匹配要遍历 80+ 条词表、每条再比对 3~4 个关键词（`contains`），
    /// 网格页几十个图标、列表每张卡都会调用；命中之后一律走字典。
    /// 用 NSLock 而不是 @MainActor：扩展侧（灵动岛 / 小组件）也会读。
    private nonisolated(unsafe) static var infoCache: [String: Info] = [:]
    private static let infoCacheLock = NSLock()

    static func info(for company: String) -> Info {
        infoCacheLock.lock()
        if let hit = infoCache[company] {
            infoCacheLock.unlock()
            return hit
        }
        infoCacheLock.unlock()

        let value = resolveInfo(for: company)

        infoCacheLock.lock()
        infoCache[company] = value
        infoCacheLock.unlock()
        return value
    }

    private static func resolveInfo(for company: String) -> Info {
        if let hit = matchedInfo(company) { return hit }

        let trimmed = company.trimmingCharacters(in: .whitespaces)
        let start = fallbackPalette[Int(stableHash(trimmed) % UInt32(fallbackPalette.count))]
        let mark = trimmed.isEmpty ? "包" : String(trimmed.prefix(1))
        return Info(key: trimmed, name: trimmed, category: .company,
                    from: start, to: shade(start, 0.72), glyph: .mark(mark))
    }

    /// 「最长关键词优先」的品牌匹配。
    ///
    /// 抽出来给 `info(for:)` 与 `scene(for:)` 共用 —— 两处若各写一套匹配规则，
    /// 迟早漂移成「图标按 A 品牌画、分类却按 B 品牌判」。
    private static func matchedInfo(_ company: String) -> Info? {
        let trimmed = company.trimmingCharacters(in: .whitespaces)

        var best: (item: Info, length: Int)?
        for item in table {
            for key in [item.key] + item.aliases
            where trimmed.localizedCaseInsensitiveContains(key) {
                if best == nil || key.count > best!.length {
                    best = (item, key.count)
                }
            }
        }
        return best?.item
    }

    /// **快递驿站 / 智能柜的实在品牌名匹配**（2026-10-18 主人定稿）。
    ///
    /// 数据源**仅短信原文**：在传入文本里做「包含匹配」，命中 station / locker
    /// 两类品牌的 name / key / alias，取**最长词条**（「菜鸟裹裹」同时含「菜鸟」
    /// 与「菜鸟裹裹」时取后者）。
    ///
    /// 与 `matchedInfo` 共用同一张 `table`，因此图标、分类、颜色永远一致 ——
    /// 不会出现「图标画 A、分类判 B」的漂移。返回 `(name, length)` 供上层
    /// （`StationDirectory.matchedName`）叠加自定义名时按最长优先比较。
    /// 位置是否落在开头那段【…】里（短信发送方签名）。
    private static func isInsideLeadingBracket(_ text: String, at position: Int) -> Bool {
        guard text.hasPrefix("【") else { return false }
        guard let close = text.firstIndex(of: "】") else { return false }
        let closeOffset = text.distance(from: text.startIndex, to: close)
        return position <= closeOffset
    }

    static func stationMatch(in texts: [String]) -> (name: String, length: Int)? {
        let haystacks = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !haystacks.isEmpty else { return nil }

        // 🔴 缓存（2026-10-28）：这是**每张卡片 body 都会走**的热路径 ——
        // 29 个驿站/柜 × haystack 全文 contains。列表滚动时同一批短信被反复匹配，
        // 缓存后热路径变成一次字典查。key 用原文拼接，空串代表"本条无驿站"。
        let cacheKey = haystacks.joined(separator: "\u{1}")
        stationCacheLock.lock()
        if let hit = stationCache[cacheKey] {
            stationCacheLock.unlock()
            guard !hit.isEmpty else { return nil }
            let parts = hit.split(separator: "|", maxSplits: 1)
            return (String(parts.count > 1 ? parts[1] : ""), Int(parts.first ?? "") ?? 0)
        }
        stationCacheLock.unlock()

        // 🔴 2026-10-31 判定顺序修正：**正文里的名字优先于开头【】里的发送方**。
        //
        // 起因：短信「【多多代收点】…在仙田百米驿站取…兔喜生活」被判成了「多多代收点」——
        // 那是发送方平台名，而取件点在正文里。原来的规则只比词长，谁长谁赢，
        // 于是平台名一长就盖掉真正的取件点。
        //
        // 现在的排序（依次比较）：
        //   ① 是否落在开头【…】之外 —— 正文里写的才是取件点；
        //   ② 词更长 —— 同是正文时，「兔喜生活」优先于「兔喜」；
        //   ③ 出现更早 —— 同一句里先说到的更可能是主取件点。
        var best: (name: String, length: Int, outside: Bool, position: Int)?
        for item in table where item.category == .station || item.category == .locker {
            // 🔴 2026-10-31：**不再用 key 扫正文**。key 是给"用户改名归一化"用的短名
            // （中邮 / 菜鸟 / 兔喜 / 熊猫…），拿去扫自由文本会把「中邮大厦」「熊猫便利超市」
            // 「邻里便利店」一律判成驿站。自由文本只认 name 与 aliases：
            // 短信里真正会写的是「中邮驿站」「菜鸟驿站」「兔喜生活」这些完整写法。
            // 若某条短信确实只写短名（例如只写「兔喜」），把它补成该条目的 alias，
            // 而不是把 key 放回这个循环 —— 补 alias 是一次有意决定，放回 key 是全局放水。
            for word in [item.name] + item.aliases {
                for haystack in haystacks {
                    guard let range = haystack.range(of: word, options: .caseInsensitive) else { continue }
                    let position = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
                    let outside = !Self.isInsideLeadingBracket(haystack, at: position)

                    guard let current = best else {
                        best = (item.name, word.count, outside, position)
                        continue
                    }
                    let better: Bool
                    if current.outside != outside {
                        better = outside                      // ① 正文优先
                    } else if word.count != current.length {
                        better = word.count > current.length  // ② 长词优先
                    } else {
                        better = position < current.position  // ③ 靠前优先
                    }
                    if better { best = (item.name, word.count, outside, position) }
                }
            }
        }

        let encoded = best.map { "\($0.length)|\($0.name)" } ?? ""
        stationCacheLock.lock()
        if stationCache.count > 512 { stationCache.removeAll(keepingCapacity: true) }
        stationCache[cacheKey] = encoded
        stationCacheLock.unlock()
        return best.map { (name: $0.name, length: $0.length) }
    }

    /// `stationMatch` 的结果缓存（空串 = 没有命中）
    private nonisolated(unsafe) static var stationCache: [String: String] = [:]
    private static let stationCacheLock = NSLock()

    /// 品牌主色 —— **全 App 统一的取色入口**（卡面淡染、取件码、图标晕、胶囊、详情字段）
    ///
    /// 🔴 2026-11-22 老大（深色模式截图）：「像圆通快递这样式的取件码信息基本上都看不见了」。
    ///    根因是这里一直只返回 `ink` —— 那是**为浅色底压暗**的颜色（亮品牌黄/浅绿压一档，
    ///    保证白底上不糊），圆通紫压完只剩 `#5B2C87` 这种亮度，放到深色卡面上就是
    ///    「深紫 on 深灰」，取件码、详情页字段、添加时间全看不清。
    ///
    /// 现在按外观二选一（`Color.adaptive`，随系统深色即时切换）：
    ///   · 浅色 → `ink`：压暗版，浅底可读（原有口径不变）；
    ///   · 深色 → `inkOnDark`：**原色亮度不够就向白色混合提亮**，直到 BT.601 亮度 ≥ 0.55，
    ///     色相不变（圆通仍是紫、丰巢仍是黄），只是从"墨紫"变成"亮紫"。
    ///
    /// ⚠️ 不要再在深色界面里写 `Color(hex: info.resolvedFrom)` 绕开这个入口 ——
    ///    那会得到与列表卡不同的色，又回到"同一个件两种颜色"。
    static func color(for company: String) -> Color {
        let brand = info(for: company)
        return Color.adaptive(light: brand.ink, dark: brand.inkOnDark)
    }

    /// 把「申通」这类**词根**归一成品牌表里的标准名（「申通快递」）。
    ///
    /// 2026-10-28 主人：「快递公司如果在短信内容中匹配到申通，那就是申通的标准名称，
    /// 而不只是匹配的两个字」—— 短信里常写「申通*57014」「中通 8888」，
    /// 正则只能截到词根，直接存会得到「申通」这种半截名字。
    ///
    /// 匹配不到的品牌**原样返回**（不编造），空串返回空串。
    static func canonicalName(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let hit = matchedInfo(trimmed) else { return trimmed }
        return hit.name
    }

    /// 把品牌主色压暗到「可当文字用」的程度；本来就不亮的品牌原样返回。
    ///
    /// 亮度口径用 ITU-R BT.601（0.299R + 0.587G + 0.114B），
    /// 阈值 0.66 ≈ #A8A8A8 的亮度 —— 比它更亮的色在浅底上做文字都偏虚。
    static func inkColor(_ hex: UInt32) -> UInt32 {
        luminance(hex) > 0.66 ? shade(hex, 0.62) : hex
    }

    /// 把品牌主色**提亮**到深色背景上可读；本来就够亮的品牌原样返回。
    ///
    /// 手法：向白色按 16% 逐档混合（色相不变，只抬明度），直到 BT.601 亮度 ≥ 0.55，
    /// 最多 6 档（= 96%，足够把任何深色抬成浅色）。举例：
    ///   · 圆通紫 `#5B2C87`（亮度 0.27）→ 混 3 档后约 `#A991C0`（0.62）—— 深灰卡面上清晰；
    ///   · 丰巢黄 `#F3C50D`（0.75）→ 本来就够亮，原样返回；
    ///   · 顺丰红 `#DC1E32`（0.36）→ 混 2 档后约 `#E96A77`，在深色卡上不再是"一团暗红"。
    ///
    /// 2026-11-22 加：老大深色模式截图里，圆通件的取件码、详情字段、添加时间几乎看不见。
    static func inkColorOnDark(_ hex: UInt32) -> UInt32 {
        if luminance(hex) >= 0.55 { return hex }
        var mixed = hex
        for step in 1...6 {
            mixed = blendWithWhite(hex, amount: Double(step) * 0.16)
            if luminance(mixed) >= 0.55 { return mixed }
        }
        return mixed
    }

    /// ITU-R BT.601 相对亮度（0…1）
    private static func luminance(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// 向白色混合 `amount`（0…1），只抬明度不改色相
    private static func blendWithWhite(_ hex: UInt32, amount: Double) -> UInt32 {
        func mix(_ channel: UInt32) -> UInt32 {
            let v = Double(channel) + (255 - Double(channel)) * amount
            return UInt32(min(255, v.rounded()))
        }
        return (mix((hex >> 16) & 0xFF) << 16) | (mix((hex >> 8) & 0xFF) << 8) | mix(hex & 0xFF)
    }

    /// 按分类取清单（供图标总览页使用）
    static func items(in category: Category) -> [Info] {
        table.filter { $0.category == category }
    }

    /// 把颜色调暗，用于渐变止色
    private static func shade(_ hex: UInt32, _ factor: Double) -> UInt32 {
        let r = UInt32(min(255, Double((hex >> 16) & 0xFF) * factor))
        let g = UInt32(min(255, Double((hex >> 8) & 0xFF) * factor))
        let b = UInt32(min(255, Double(hex & 0xFF) * factor))
        return (r << 16) | (g << 8) | b
    }
}

// MARK: ============================================================================
// 平台名纠错（面向 OCR / 相册识别）
//
// OCR 会把形近字读错：「兔喜生活」→「免喜生活」、「圆通」→「国通」。
// 这类错字不影响取件码与地址，但会明晃晃地写在卡片上，用户一眼觉得不对劲。
// 品牌表里已有规范写法，因此用**严格的单一条件**做纠正：名字与表内某项的编辑距离
// 恰好 ≤ 1。宁可漏纠，也绝不把用户真遇到的冷门驿站名改成另一个牌子。
// ============================================================================

enum CourierNameCorrector {

    /// 🔴 **关键词命中只有在长度 ≥ 3 时才豁免纠错**。
    ///
    /// 2 字关键词（「中铁」「蜜雪」「百世」）覆盖的文本太杂：短信里「中铁快远」
    /// 「蜜雪冰成」这类 OCR 形近字，一样含有「中铁」「蜜雪」，若按「含关键词 =
    /// 正常写法差异」豁免，错字就会一路显示到卡片上。
    /// 3 字及以上才足以说明「这确实是该品牌的另一种正规写法」（如「百世快运」
    /// 「中国铁路」），可以放心不纠。
    private static let safeKeyLength = 3

    static func correct(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }

        for item in CourierBrand.table {
            // 已经是规范写法
            if trimmed == item.name { return item.name }
            // 恰好等于关键词（【拼多多】→ 拼多多）：**原样保留**。
            // 🔴 不能在这里换成 item.name —— 「拼多多」是电商平台，
            //    硬写成「拼多多驿站」会把平台身份改错（2026-09-23 主人指正）。
            //    用户的原话是什么就显示什么，图标匹配走 CourierBrand 关键词，不受影响。
            if trimmed == item.key { return trimmed }
            // 表内关键词（含别名）被包含 —— 属于正常的长短写法差异，保持原样不动
            if item.key.count >= safeKeyLength,
               trimmed.localizedCaseInsensitiveContains(item.key) { return trimmed }
            for alias in item.aliases
            where alias.count >= safeKeyLength
                && trimmed.localizedCaseInsensitiveContains(alias) { return trimmed }
        }

        // 名称过短（2 字）时形近字误纠的概率明显上升，只对 3 字及以上做近似匹配
        guard trimmed.count >= 3 else { return trimmed }

        // 🔴 2026-11-21 主人抓到：「【圆通快递】…」的平台被纠成「中通快递」。
        //    原因是纯编辑距离打平 —— 「圆通快递」到「中通快递」（圆→中）与到
        //    「圆通速递」（快→速）都是 1，按表内顺序前者先命中就赢了。
        //    修法：同距离时**优先选「短信原文里已经含有它的关键词」的那个品牌**，
        //    其次比公共前缀长度，仍打平才按表内顺序。
        //    这样「圆通快递」→ 圆通速递（原文含「圆通」），而「国通快递」这种
        //    不含任何关键词的错字仍按距离走进「中通快递」（既有基线的行为不变）。
        struct Candidate {
            var name: String
            var distance: Int
            var keyContained: Bool
            var prefix: Int
        }
        var best: Candidate?
        for item in CourierBrand.table {
            let distance = min(editDistance(trimmed, item.name),
                               editDistance(trimmed, item.key))
            guard distance <= 1 else { continue }
            let keyContained = item.key.count >= 2
                && trimmed.localizedCaseInsensitiveContains(item.key)
            let candidate = Candidate(name: item.name,
                                      distance: distance,
                                      keyContained: keyContained,
                                      prefix: commonPrefixLength(trimmed, item.name))
            guard let current = best else { best = candidate; continue }
            if candidate.distance < current.distance
                || (candidate.distance == current.distance && candidate.keyContained && !current.keyContained)
                || (candidate.distance == current.distance && candidate.keyContained == current.keyContained
                    && candidate.prefix > current.prefix) {
                best = candidate
            }
        }

        return best?.name ?? trimmed
    }

    /// 公共前缀长度（同距离时的平局判据）。
    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var i = 0
        while i < a.count, i < b.count, a[i] == b[i] { i += 1 }
        return i
    }

    /// Levenshtein 距离。只用于很短的字符串（≤ 6 字 × 56 项），无需做算法优化。
    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : min(previous[j - 1], previous[j], current[j - 1]) + 1
            }
            previous = current
        }

        return previous[b.count]
    }
}

// MARK: - 品牌图标（App 图标观感的圆角方块）

struct CourierLogo: View {
    private let info: CourierBrand.Info
    private let size: CGFloat
    /// 是否画投影（2026-10-28 加）。**网格里必须关掉**：
    /// `CourierGalleryView` 一屏几十个图标，每个带一层带色投影 = 每帧几十次离屏渲染，
    /// 主人反馈「一点开快递公司 / 驿站管理就掉帧严重」就是这么来的。
    /// 单个展示场景（详情页、分享卡、编辑预览）保留投影，那里数量少、观感重要。
    private let showsShadow: Bool
    /// 是否用**静态资源名**取图（`Image("brand-xxx")`）。
    ///
    /// 🔴 2026-11-13 真机（iPad 锁屏实时活动）实测：动态 `UIImage(named:)` 取到的位图
    /// 在系统**跨进程渲染**的锁屏卡里会变成灰色占位方块；而 `Image(asset)` 由 SwiftUI
    /// 直接在渲染进程里按资源名解析，能正常出图。所以实时活动 / 小组件这些
    /// 「可能不在 App 进程里画」的地方传 `true`，App 内页面继续走动态路径。
    private let usesStaticAsset: Bool

    init(company: String, size: CGFloat = 46, showsShadow: Bool = true,
         usesStaticAsset: Bool = false) {
        self.info = CourierBrand.info(for: company)
        self.size = size
        self.showsShadow = showsShadow
        self.usesStaticAsset = usesStaticAsset
    }

    init(info: CourierBrand.Info, size: CGFloat = 46, showsShadow: Bool = true,
         usesStaticAsset: Bool = false) {
        self.info = info
        self.size = size
        self.showsShadow = showsShadow
        self.usesStaticAsset = usesStaticAsset
    }

    @Environment(\.colorScheme) private var colorScheme

    private var corner: CGFloat { size * 0.29 }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        // 🔴 用 `if` 分支而不是「透明阴影」：`.shadow(color: .clear)` 依然会建图层，
        //    网格里几十个就是几十个多余的合成层 —— 要么画，要么干脆不加这个修饰符。
        if showsShadow {
            base.shadow(color: Color(hex: info.resolvedFrom)
                            .opacity(isDark ? 0.42 : 0.28),
                        radius: size * 0.14, x: 0, y: size * 0.06)
        } else {
            base
        }
    }

    /// 图标本体（圆角裁切 + 描边），投影是可选的外挂层
    private var base: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                // 描边不能固定用白色：白底图标（顺丰、丰巢、EMS）会整片糊进浅色背景；
                // 也不宜固定用黑色：抖音、得物这类深色图标在深色模式会丢掉边界。
                // 取 .primary 的极低透明度 —— 浅色下是黑、深色下是白，两头都成立。
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.primary.opacity(isDark ? 0.22 : 0.10), lineWidth: 0.5)
            }
            .accessibilityLabel(info.name)
    }

    /// 已收录的品牌直接用官方图标；未收录的退回「品牌色渐变方块 + 白色图形」
    @ViewBuilder
    private var content: some View {
        // 🔴 2026-11-05 锁屏卡图标仍是灰方块的第二轮调查：
        //    上一版补了 `.renderingMode(.original)` 与 `.widgetAccentedRenderingMode(.fullColor)`，
        //    真机仍灰。改用 `UIImage(named:)` 在**当前进程的 bundle** 里取图再交给 SwiftUI：
        //    · 拿不到图就明确走渐变兜底（不会画成一个灰占位）；
        //    · `Image(uiImage:)` 走位图路径，accented 管线不会把它当模板重涂。
        if let asset = info.asset, usesStaticAsset {
            // 跨进程渲染：交给 SwiftUI 按资源名解析（见 usesStaticAsset 注释）。
            Image(asset)
                .renderingMode(.original)
                .resizable()
                .widgetAccentedFullColor()
                .scaledToFill()
        } else if let asset = info.asset, let image = UIImage(named: asset) {
            let _ = BrandDebug.trace("name=\(info.name) asset=\(asset) loaded=true")
            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
                .widgetAccentedFullColor()
                .scaledToFill()
        } else {
            let _ = BrandDebug.trace("name=\(info.name) asset=\(info.asset ?? "nil") loaded=false")
            ZStack {
                LinearGradient(colors: [Color(hex: info.from), Color(hex: info.to)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                glyph
            }
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch info.glyph {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)

        case let .mark(text):
            Text(text.L)
                .font(.system(size: markFontSize(for: text), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, size * 0.08)
        }
    }

    /// 字标长度自适应：单字最大，3 字以上（DHL / FedEx）收窄
    private func markFontSize(for text: String) -> CGFloat {
        switch text.count {
        case 1: size * 0.56
        case 2: size * 0.42
        default: size * 0.28
        }
    }
}
