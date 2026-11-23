#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Codelumi · 品牌图标导入器
================================

把各家快递 / 驿站 / 商家的官方方形图标导进 Asset Catalog，供 `CourierLogo` 使用。

设计口径（2026-09-21）
----------------------
· **原样使用**，不做裁边：拿到的都是官方方形图标，风格天然统一，
  裁边反而会破坏「官方图标的样子」，用户也认不出来。
· 统一转 **不透明 RGB PNG**：方形直角底 + 圆角由 App 侧 `RoundedRectangle`
  裁切（与 iOS 图标观感一致），所以源图不需要自带圆角。
· **圆形图标（带 alpha）→ 外扩填色**：不少 APP 图标是「圆底 + 四角透明」
  （140×140 的 RGBA PNG，不透明区恰好是内切圆）。若直接 `convert("RGB")`，
  透明区会变成**黑色四角**，与其余满底方图风格割裂。
  `flatten_circle()` 用「逐行左右最近实色像素线性插值 + 逐列垂直补齐」把圆底
  扩张成满底方图 —— 纯色圆变成纯色方，上下渐变（如「放哈」橙→黑）也能保住。
· 单一尺度（Single Scale）；显示上限约 54pt，512px 已远超 Retina 需求。

资源命名
--------
`brand-<拼音>`，与 `CourierBrand` 里的 `asset` 字段一一对应。
映射表见下方 MAPPING —— **改文件名务必同步改这里**，否则脚本会报错而不是静默漏掉。

用法
----
    PY=/Users/zhangwangning/.workbuddy/binaries/python/envs/default/bin/python

    $PY tools/import_brand_logos.py <图片目录>
    $PY tools/import_brand_logos.py <图片目录> --check   # 只列清单，不写工程
"""

from __future__ import annotations

import glob
import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

ASSETS = os.path.join(ROOT, "Codelumi", "Codelumi", "Assets.xcassets")
BRANDS_DIR = os.path.join(ASSETS, "Brands")
SOURCE_ARCHIVE = os.path.join(HERE, "brand-source")

SIZE = 512   # 输出边长

# 源文件名（不含扩展名） → Asset 资源名
MAPPING: dict[str, str] = {
    # ── 快递公司 ──
    "顺丰":         "brand-shunfeng",
    "京东":         "brand-jd",
    "京东快递":      "brand-jd-express",
    "中通":         "brand-zhongtong",
    "圆通":         "brand-yuantong",
    "申通":         "brand-shentong",
    "韵达":         "brand-yunda",
    "邮政:EMS":     "brand-ems",
    "德邦":         "brand-deppon",
    # ── 驿站 / 快递柜 ──
    "菜鸟裹裹":      "brand-cainiao",
    "妈妈驿站":      "brand-mama",
    "兔喜生活":      "brand-tuxi",
    "拼多多":        "brand-pinduoduo",
    "丰巢":         "brand-fengchao",
    "近邻宝":        "brand-jinlinbao",
    # ── 商家 / 电商 / 即时零售（多为取餐码、到店码场景）──
    "京东秒送":      "brand-jd-miaosong",
    "天猫":         "brand-tmall",
    "淘宝":         "brand-taobao",
    "淘宝闪购":      "brand-taobao-shangou",
    "小红书":        "brand-xiaohongshu",
    "得物":         "brand-dewu",
    "抖音":         "brand-douyin",
    "美团":         "brand-meituan",
    "星巴克":        "brand-starbucks",
    "瑞幸":         "brand-luckin",
    "货拉拉":        "brand-huolala",
    "转转":         "brand-zhuanzhuan",
    "闲鱼":         "brand-xianyu",
    # ── 2026-09-21 第二批（主人提供的 18 张官方图标）──
    "安能":         "brand-anneng",
    "百世":         "brand-baishi",
    "优速":         "brand-yousu",
    "宅急送":        "brand-zhaijisong",
    "中铁快运":      "brand-zhongtie",
    "铁路12306":    "brand-railway12306",
    "放哈":         "brand-fangha",
    "蜜雪冰城":      "brand-mixue",
    "驿收发":        "brand-yishoufa",
    "邻里驿站":      "brand-linli",
    "快宝驿站":      "brand-kuaibao",
    "熊猫":         "brand-xiongmao",
    "小兵驿站":      "brand-xiaobing",
    "心甜智能柜":     "brand-xintian",
    "鸟箱":         "brand-niaoxiang",
    "亚马逊":        "brand-amazon",
    "DHL":         "brand-dhl",
    "国际转运":      "brand-guojizhuanyun",
}

EXTS = (".png", ".PNG", ".jpeg", ".jpg", ".JPEG")


def find_sources(src_dir: str) -> dict[str, str]:
    """在目录里按 MAPPING 的键找文件，返回 {键: 绝对路径}。

    🔴 找不到时回落到 `tools/brand-source/`（按**资源名**找，因为归档文件叫
    `brand-xxx.ext` 而不是中文键名）。这条回落很关键：
    「只补一个新品牌」时 `src_dir` 里通常只有那一张新图，没有回落的话
    `keep` 集合只剩这一个资源 → 下面的孤儿清理会把其余 20 多个图标**全删掉**。
    """
    found: dict[str, str] = {}
    for key, asset in MAPPING.items():
        hit = None
        for ext in EXTS:
            p = os.path.join(src_dir, key + ext)
            if os.path.exists(p):
                hit = p
                break
        if hit is None:
            for ext in EXTS:
                p = os.path.join(SOURCE_ARCHIVE, asset + ext)
                if os.path.exists(p):
                    hit = p
                    break
        if hit is not None:
            found[key] = hit
    return found


def flatten_circle(im: Image.Image) -> Image.Image:
    """把「圆底 + 四角透明」的图标扩张成不透明满底方图。

    做法分两步，都只用**已有实色像素**推色，不引入任何新颜色：
      1. **逐行水平外扩**：每行找最左 / 最右的实色像素，行内其余像素按到两端
         的距离**线性插值**填充。纯色圆 → 整行同色；上下渐变（放哈橙→黑）
         也能把渐变带出来。
      2. **逐列垂直补齐**：首尾可能整行皆透明（圆的最上/最下几行），取上下
         最近一条已有内容的行整体复制过来。

    阈值取 alpha > 200 而非 > 0 —— 圆周边缘有半透明的抗锯齿像素，用它们
    当锚点会把半透明色带进填充结果，出现一圈脏边。
    """
    im = im.convert("RGBA")
    w, h = im.size
    src = im.load()

    out = Image.new("RGB", (w, h))
    dst = out.load()
    filled = [False] * h

    for y in range(h):
        left = next(((x, src[x, y][:3]) for x in range(w) if src[x, y][3] > 200), None)
        right = next(((x, src[x, y][:3]) for x in range(w - 1, -1, -1) if src[x, y][3] > 200), None)
        if left is None or right is None:
            continue                       # 整行透明，交给第 2 步
        lx, lc = left
        rx, rc = right
        for x in range(w):
            r, g, b, a = src[x, y]
            if a > 200:
                dst[x, y] = (r, g, b)
            elif x <= lx:
                dst[x, y] = lc
            elif x >= rx:
                dst[x, y] = rc
            else:
                t = (x - lx) / (rx - lx)
                dst[x, y] = tuple(round(lc[i] + (rc[i] - lc[i]) * t) for i in range(3))
        filled[y] = True

    for y in range(h):
        if filled[y]:
            continue
        prev = next((yy for yy in range(y - 1, -1, -1) if filled[yy]), None)
        nxt = next((yy for yy in range(y + 1, h) if filled[yy]), None)
        if prev is None and nxt is None:
            continue
        ref = prev if (nxt is None or (prev is not None and y - prev <= nxt - y)) else nxt
        for x in range(w):
            dst[x, y] = dst[x, ref]
        filled[y] = True

    return out


def write_imageset(asset: str, img: Image.Image) -> None:
    """写一个 imageset（Single Scale）。"""
    d = os.path.join(BRANDS_DIR, asset + ".imageset")
    os.makedirs(d, exist_ok=True)
    fname = asset + ".png"
    img.save(os.path.join(d, fname), format="PNG", optimize=True)
    contents = {
        "images": [{"filename": fname, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(d, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv

    src_dir = args[0] if args else os.path.expanduser("~/Downloads")
    if not os.path.isdir(src_dir):
        print(f"✗ 不是目录：{src_dir}", file=sys.stderr)
        return 1

    found = find_sources(src_dir)
    missing = [k for k in MAPPING if k not in found]

    print(f"源目录：{src_dir}")
    print(f"命中 {len(found)}/{len(MAPPING)} 张")
    if missing:
        print(f"⚠ 未找到（这些品牌将保留自绘方块）：{', '.join(missing)}")
    if check_only:
        for k, v in found.items():
            print(f"  {k:<10} → {MAPPING[k]:<22} {os.path.basename(v)}")
        return 0 if not missing else 1

    os.makedirs(BRANDS_DIR, exist_ok=True)

    for key, path in found.items():
        asset = MAPPING[key]
        im = Image.open(path)
        # 统一为不透明 RGB 方图；带 alpha 的圆底图标先外扩填色；非正方形则居中裁成正方形
        if im.mode in ("RGBA", "LA"):
            im = flatten_circle(im)
        else:
            im = im.convert("RGB")
        w, h = im.size
        if w != h:
            s = min(w, h)
            im = im.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2))
        if im.size != (SIZE, SIZE):
            im = im.resize((SIZE, SIZE), Image.LANCZOS)
        write_imageset(asset, im)

        # 源图留档，保证可复现（已经在归档里的也就无需再拷 —— copy2 同文件会抛 SameFileError）
        os.makedirs(SOURCE_ARCHIVE, exist_ok=True)
        dest = os.path.join(SOURCE_ARCHIVE, asset + os.path.splitext(path)[1])
        if os.path.abspath(path) != os.path.abspath(dest):
            shutil.copy2(path, dest)

        print(f"  ✓ {key:<10} → {asset}")

    # 清掉不再有源图对应的 imageset（避免工程里留孤儿资源）
    if os.path.isdir(BRANDS_DIR):
        keep = {MAPPING[k] + ".imageset" for k in found}
        for name in os.listdir(BRANDS_DIR):
            if name.endswith(".imageset") and name not in keep:
                shutil.rmtree(os.path.join(BRANDS_DIR, name))
                print(f"  · 清理孤儿资源 {name}")

    print(f"\n写入 {BRANDS_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
