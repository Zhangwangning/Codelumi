#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Codelumi · 品牌调色板提取器
==================================

从各品牌的官方图标里提取主色，生成 `CodelumiShared/BrandPalette.swift`，
供详情页做「跟着品牌走的磨砂玻璃卡片」。

为什么提取而不是手填
--------------------
详情页卡片底要「按品牌重构」——淘宝是橙玻璃、星巴克是绿玻璃、抖音是黑玻璃。
手填一套品牌色固然可行，但图标一换就失真；从图标本身提取，永远与图标一致，
而且能拿到**多色**（底色 + 点缀色），做渐变比单色有层次。

提取方式
--------
**从 Asset Catalog 里已处理好的成品图提取**（`Assets.xcassets/Brands/*.imageset/*.png`），
而不是 `brand-source/` 里的原始图。两个理由：
  · 成品图已经把「圆底图标」外扩成满底方图，原始图带 alpha，
    直接 `convert("RGB")` 会让透明区变**黑**，黑色会被当成品牌色混进调色板；
  · 提取的对象与用户实际看到的那张图**完全同一张**，不存在两处口径。

缩到 64×64 后走 PIL 的中位切分量化（MEDIANCUT），取「面积最大的彩色簇」为首的 3 色。

🔴 **排序口径 = 剔除白底后，取面积最大的一块**（2026-10-28 二次修订）
---------------------------------------------------------------
主人原话：「我们读图标的主题色……你把图标模糊掉，那个颜色一般就是了」。
模糊的数学含义就是「按面积加权」，只是整图平均会被白底和黑字稀释
（实测：丰巢 → `#D5C999` 米黄、顺丰 → `#8D8989` 灰，都不像品牌色）。
所以这里**只去掉近白，再按面积取首色** —— 等价于「模糊掉白底之后的那一块」。

⚠️ 为什么不按「饱和度优先」：试过，会被小面积点睛色带跑。
   安能物流是黑底 + 白字 + 一个橙箭头（橙只占 2.4%），抖音是黑底 + 彩色音符，
   按饱和优先会读成橙 / 粉红，可图标给人的第一印象明明是黑。

⚠️ **量化档数必须是 24 色、最小占比 0.5%**（2026-10-28 实测）：
   旧参数是 8 色 / 2%，顺丰那个米粒大的红点会被并进黑档，整图读出来是
   `#322222` 暗褐；提到 24 色 / 0.5% 后，安能橙、淘宝闪购橙、熊猫快收橙才浮得出来。
   仍读不准的极少数（顺丰：黑环黑字 + 极小红点，红色才是识别色）走
   `CourierBrand.manualColors` 人工覆盖 —— 那是**例外表**，不是常态。

对比度交给 UI 侧控制（渐变色一律压到低透明度），不靠这里筛色。

用法
----
    PY=/Users/zhangwangning/.workbuddy/binaries/python/envs/default/bin/python
    $PY tools/extract_brand_palette.py             # 提取并写入工程
    $PY tools/extract_brand_palette.py --dry-run   # 只打印，不写文件
"""

from __future__ import annotations

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SOURCE_DIR = os.path.join(ROOT, "Codelumi", "CodelumiShared", "Assets.xcassets", "Brands")
OUT = os.path.join(ROOT, "Codelumi", "CodelumiShared", "BrandPalette.swift")

TOP_N = 3          # 每张图取几个色
SAMPLES = 64       # 量化前先缩到多少像素
QUANT_COLORS = 24  # 量化档数：24 才保得住「米粒大的点睛色」（8 会把它并进黑档）
MIN_SHARE = 0.005  # 占比低于此的碎色丢弃（0.5%，旧值 2% 会吃掉点睛色）
DISTINCT = 40      # 与已选色差异小于此的视为重复色，丢弃

NEAR_WHITE = 232   # 三通道都不低于此值 → 视为「近白」，排序时一律沉底
NEAR_BLACK = 30    # 三通道都不高于此值 → 视为「近黑」，归入无彩档（黑也可能是品牌色）
STRONG_SAT = 0.35  # 饱和度达到此值 → 品牌识别色（档 0）
WEAK_SAT = 0.20    # 饱和度达到此值 → 弱彩（档 1）
FILL_LUM = 170     # 亮度高于此且饱和度 < FILL_SAT → 视为「白/灰底切出来的浅色填充」，降级
FILL_SAT = 0.40
RESCUE_SAT = 0.30  # 降级后替补色至少要有的饱和度
CANDIDATES = 6     # 内部多留几个候选，供降级时挑选（对外仍只输出 TOP_N）


def _is_near_white(rgb: tuple[int, int, int]) -> bool:
    return min(rgb) >= NEAR_WHITE


def _is_near_black(rgb: tuple[int, int, int]) -> bool:
    return max(rgb) <= NEAR_BLACK


def _saturation(rgb: tuple[int, int, int]) -> float:
    """HSV 里的 S。近黑的分母极小会让 S 虚高，所以调用前先用 _is_near_black 挡掉。"""
    high, low = max(rgb), min(rgb)
    return 0.0 if high == 0 else (high - low) / high


def _diff(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def dominant_colors(path: str, n: int = TOP_N) -> list[tuple[int, tuple[int, int, int]]]:
    """返回 [(像素数, (r,g,b)), ...]，按「代表色」降序。

    排序规则见模块文档：**彩色簇优先**（档 0 → 档 3），同档内按面积降序。
    近白沉底、近黑并入无彩档 —— 黑只有在整张图没有任何彩簇时才会当主色。
    """
    im = Image.open(path).convert("RGB").resize((SAMPLES, SAMPLES), Image.LANCZOS)
    # 24 档：档数太少会把「点睛色」（顺丰红点、安能橙）并进黑档，整图读出来是脏灰
    quantized = im.quantize(colors=QUANT_COLORS, method=Image.Quantize.MEDIANCUT)

    palette = quantized.getpalette() or []
    counts = quantized.getcolors() or []          # [(count, palette_index), ...]

    total = SAMPLES * SAMPLES
    candidates: list[tuple[int, tuple[int, int, int]]] = []
    for count, index in counts:
        if count / total < MIN_SHARE:
            continue
        rgb = tuple(palette[index * 3: index * 3 + 3])
        if len(rgb) == 3:
            candidates.append((count, rgb))       # type: ignore[arg-type]

    def tier(rgb: tuple[int, int, int]) -> int:
        # 只剩一条排序纪律：**近白沉底，其余按面积**。
        # 试过「彩色簇优先」，结果被小面积点睛色带跑：
        # 安能是黑底 + 白字 + 一个橙箭头（橙仅 2.4%），抖音是黑底 + 彩色音符，
        # 按饱和优先会把它们读成橙/粉，而图标给人的印象就是黑。
        # 「模糊掉白底，剩下最大那块」才是主人说的那个印象色。
        return 1 if _is_near_white(rgb) else 0

    candidates.sort(key=lambda item: (tier(item[1]), -item[0]))

    out: list[tuple[int, tuple[int, int, int]]] = []
    for count, rgb in candidates:
        if any(_diff(rgb, kept) < DISTINCT for _, kept in out):
            continue
        out.append((count, rgb))
        if len(out) >= max(n, CANDIDATES):
            break

    # 降级：首色是「白底/灰底切出来的浅色填充」（EMS 的浅蓝、宅急送的浅灰）
    # 时，它不是品牌色，换成后面第一个够饱和的候选。
    if out:
        r, g, b = out[0][1]
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        if lum > FILL_LUM and _saturation(out[0][1]) < FILL_SAT:
            swap = next((i for i, (_, rgb) in enumerate(out)
                         if _saturation(rgb) >= RESCUE_SAT and not _is_near_white(rgb)), None)
            if swap is not None:
                out.insert(0, out.pop(swap))

    return out[:n]


def to_hex(rgb: tuple[int, int, int]) -> str:
    return "0x%02X%02X%02X" % rgb


def main() -> int:
    dry_run = "--dry-run" in sys.argv

    if not os.path.isdir(SOURCE_DIR):
        print(f"✗ 找不到品牌图标目录：{SOURCE_DIR}", file=sys.stderr)
        print("  先跑 tools/import_brand_logos.py 导入品牌图标。", file=sys.stderr)
        return 1

    sets = sorted(d for d in os.listdir(SOURCE_DIR) if d.endswith(".imageset"))
    if not sets:
        print(f"✗ {SOURCE_DIR} 里没有 .imageset", file=sys.stderr)
        return 1

    entries: list[tuple[str, list[str], list[tuple[int, tuple[int, int, int]]]]] = []
    for folder in sets:
        asset = folder[: -len(".imageset")]
        png = os.path.join(SOURCE_DIR, folder, asset + ".png")
        if not os.path.exists(png):
            print(f"⚠ {asset} 缺少 {asset}.png，跳过", file=sys.stderr)
            continue
        colors = dominant_colors(png)
        if not colors:
            print(f"⚠ {asset} 提取不到颜色，跳过", file=sys.stderr)
            continue
        entries.append((asset, [to_hex(rgb) for _, rgb in colors], colors))

    width = max(len(a) for a, _, _ in entries) + 4
    print(f"{'资源名':<{width}} {'调色板（按占比降序）'}")
    print("-" * (width + 46))
    for asset, hexes, colors in entries:
        shares = "  ".join(f"{c / (SAMPLES * SAMPLES):>5.1%} {h}"
                           for (c, _), h in zip(colors, hexes))
        print(f"{asset:<{width}} {shares}")

    if dry_run:
        print("\n（--dry-run，未写入）")
        return 0

    lines = [
        "import Foundation",
        "",
        "// 本文件由 tools/extract_brand_palette.py 从各品牌官方图标提取，请勿手改。",
        "// 换图标后重跑脚本即可刷新。",
        "",
        "/// 各品牌官方图标的主色调色板。",
        "///",
        "/// 用途：详情页卡片的「品牌色磨砂玻璃」底 —— 淘宝橙、星巴克绿、抖音黑，",
        "/// 一律跟着各自的官方图标走，而不是另配一套颜色。",
        "enum BrandPalette {",
        "",
        "    /// 键 = Asset 资源名，值 = 主色（按占比降序，最多 3 个）",
        "    static let table: [String: [UInt32]] = [",
    ]
    for asset, hexes, _ in entries:
        lines.append(f'        "{asset}": [{", ".join(hexes)}],')
    lines += [
        "    ]",
        "",
        "    /// 取某个品牌图标的调色板；未收录返回 nil，由调用方回落到品牌主色。",
        "    static func colors(forAsset asset: String?) -> [UInt32]? {",
        "        guard let asset, let value = table[asset], !value.isEmpty else { return nil }",
        "        return value",
        "    }",
        "}",
        "",
    ]

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"\n已写入 {OUT}（{len(entries)} 个品牌）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
