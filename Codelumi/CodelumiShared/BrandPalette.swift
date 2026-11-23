import Foundation

// 本文件由 tools/extract_brand_palette.py 从各品牌官方图标提取，请勿手改。
// 换图标后重跑脚本即可刷新。

/// 各品牌官方图标的主色调色板。
///
/// 用途：详情页卡片的「品牌色磨砂玻璃」底 —— 淘宝橙、星巴克绿、抖音黑，
/// 一律跟着各自的官方图标走，而不是另配一套颜色。
enum BrandPalette {

    /// 键 = Asset 资源名，值 = 主色（按占比降序，最多 3 个）
    static let table: [String: [UInt32]] = [
        "brand-amazon": [0xDCB678, 0x08A7E3, 0x040303],
        "brand-anneng": [0x000000, 0xE39E1D, 0xBCBCBC],
        "brand-baishi": [0x012144, 0x8692A1, 0xDBD5CF],
        "brand-cainiao": [0x006EFF, 0x000000, 0x00E1C5],
        "brand-deppon": [0x073E84, 0xFFE903, 0xE4C633],
        "brand-dewu": [0x000000, 0xB8B8B8, 0x3A3A3A],
        "brand-dhl": [0xFFCC01, 0xE4002B, 0xD84C24],
        "brand-douyin": [0x0B0B16, 0xFD355D, 0x2CF6F1],
        "brand-duoduodaishou": [0xE0231A, 0xE7E7E6, 0x878D7F],
        "brand-ems": [0x2E71B4, 0x9FBFDD, 0x6196C8],
        "brand-fangha": [0xFF4B01, 0x060606, 0x7C2D12],
        "brand-fengchao": [0xF3C50D, 0x000000, 0xB9960A],
        "brand-guojizhuanyun": [0x03326A, 0xFF9D19, 0xE4DFD6],
        "brand-huolala": [0xFF6600, 0xFF8232, 0xFFBA8C],
        "brand-jd-express": [0xF62121, 0xEFE6DC, 0xE7AF6B],
        "brand-jd-miaosong": [0xB27738, 0xE3AA58, 0x5E3A1A],
        "brand-jd": [0xFB035C, 0xFB0424, 0xBA597A],
        "brand-jinlinbao": [0xEEBA4D, 0xF2D79C, 0xF7E9C6],
        "brand-kuaibao": [0x27CC6E, 0x63D596, 0xBEECD3],
        "brand-linli": [0xD61335, 0xF4E1E5, 0xD3425A],
        "brand-luckin": [0x162991, 0x3F96FB, 0xBFD9F8],
        "brand-mama": [0xFF7B23, 0xFFDEC8, 0xFF9C59],
        "brand-meituan": [0xFFE41F, 0x000000, 0x3D3708],
        "brand-miaozhan": [0xE75900, 0xF3D3B7, 0xEB9959],
        "brand-mixue": [0xE60012, 0x301B1E, 0x9B7E54],
        "brand-niaoxiang": [0xFFB400, 0xDD3E14, 0x666666],
        "brand-pinduoduo": [0xF40009, 0xFEE0E1, 0xF97C80],
        "brand-railway12306": [0x1D66EF, 0x18D4FC, 0x1BA0F5],
        "brand-shentong": [0xFF6700, 0x666464, 0xF2D1BB],
        "brand-shoujianbao": [0x3582DF, 0xD4B970, 0xEBE8D9],
        "brand-shunfeng": [0x000000, 0x565656, 0x2D2D2D],
        "brand-starbucks": [0x00A862, 0x4BC18F, 0xE0F4EB],
        "brand-taobao-shangou": [0xFF7703, 0x18BDFB, 0xFF4B00],
        "brand-taobao": [0xFC5900, 0xFD8832, 0xFEB78A],
        "brand-tiantian": [0x0658A3, 0x89ADD1, 0x00A7E9],
        "brand-tmall": [0xFF0036, 0x000000, 0xF5CAD3],
        "brand-tuxi": [0x363AFB, 0xECE6EC, 0xC8B4C8],
        "brand-xianyu": [0xFDFA01, 0x1A1720, 0xFFBF00],
        "brand-xiaobing": [0x399339, 0x7FB57D, 0xD0E3CE],
        "brand-xiaohongshu": [0xFF2442, 0xFF6C80, 0xFFCED5],
        "brand-xintian": [0xFF7701, 0xF3923E, 0xF8D8B8],
        "brand-xiongmao": [0xED6D00, 0x000000, 0x674126],
        "brand-yishoufa": [0x021D37, 0xF89D16, 0xFACF57],
        "brand-yousu": [0xFFAF01, 0xDFD9D3, 0x312648],
        "brand-yuantong": [0x4D148C, 0xF94616, 0xC5B2D9],
        "brand-yunda": [0xFABF01, 0x000000, 0xBB9002],
        "brand-yundakuaichaoshi": [0xFFD44A, 0x150C10, 0x4F3D20],
        "brand-zhaijisong": [0x110D0B, 0xD7D7D6, 0x6F6C6B],
        "brand-zhongtie": [0x0A2D67, 0xE5E6E8, 0x4E617F],
        "brand-zhongtong": [0x3377F6, 0xADC4EF, 0x6B97ED],
        "brand-zhuanzhuan": [0xFF0F27, 0xFFE4C6, 0xD7938E],
    ]

    /// 取某个品牌图标的调色板；未收录返回 nil，由调用方回落到品牌主色。
    static func colors(forAsset asset: String?) -> [UInt32]? {
        guard let asset, let value = table[asset], !value.isEmpty else { return nil }
        return value
    }
}
