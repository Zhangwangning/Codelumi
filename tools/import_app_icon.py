#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Codelumi · App 图标导入器
================================

把设计稿导出的图标（圆角方形 PNG、圆角外透明）规范化为 iOS 要求的
1024×1024 **不透明方图**，并写入 AppIcon.appiconset。这是当前图标的唯一入口
（旧的自绘方案 make_app_icon.py 已被设计稿取代）。

为什么不能直接拖进 Xcode
------------------------
iOS 的 AppIcon 必须是「正方形 + 无 alpha 通道」，圆角一律由系统统一裁切。
直接把圆角设计稿塞进去会有两个问题：

  1. 含 alpha 通道 → App Store 校验直接拒绝（无效的图标）
  2. 圆角外是透明的 → 系统不管，桌面上圆角外会露出底色／出现双重圆角

处理办法
--------
圆角外的透明区用**最近邻外推**填满：从实心像素出发逐层向外扩散，每个新像素
继承最近实心像素的颜色。因为图标底本身就是平滑对角渐变，径向延展出来的颜色
与原图几乎无差。

填充完再放大到 1024。放大用 LANCZOS（升采样下振铃很弱，且对边缘有轻微锐化
作用），最后补一道很轻的 UnsharpMask 抵消插值带来的软化。

顺带一个有利事实：iOS 的圆角半径（≈ 宽的 22.4%）**略大于**常见设计稿圆角
（≈ 21.4%），也就是说系统裁切后露出的区域完全落在设计稿原来的实心区内 ——
连填充出来的那圈颜色都看不见，天然无接缝。

用法
----
    PY=/Users/zhangwangning/.workbuddy/binaries/python/envs/default/bin/python

    $PY tools/import_app_icon.py                 # 用仓库内默认设计稿，直接写入工程
    $PY tools/import_app_icon.py <自己的.png>     # 指定设计稿
    $PY tools/import_app_icon.py --preview       # 只出预览拼图，不动工程

设计稿默认位置：tools/appicon-source/icon-source.png（换图标时覆盖它再重跑即可）
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- 常量

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DEFAULT_SOURCE = os.path.join(HERE, "appicon-source", "icon-source.png")
APPICONSET = os.path.join(
    ROOT, "Codelumi", "Codelumi", "Assets.xcassets", "AppIcon.appiconset"
)

TARGET = 1024          # iOS AppIcon 交付尺寸
SOLID_ALPHA = 250      # 高于此值才算「实心」，用作外推种子（避开抗锯齿污染色）
ALPHA_FLOOR = 8        # 低于此值视为透明
UNSHARP = dict(radius=1.6, percent=70, threshold=3)   # 极轻的补偿锐化

# iOS 圆角半径比例（用于预览时模拟系统裁切）：22.37% 是 iPhone 的 squircle 近似值
IOS_CORNER_RATIO = 0.2237


# ---------------------------------------------------------------- 核心

def fill_transparent(rgba: np.ndarray) -> np.ndarray:
    """把圆角外的透明区用最近邻实心像素的颜色填满，返回 RGB 数组。

    做法是从所有「实心且四邻有空白」的像素出发做 BFS，逐层向外扩散，
    每个新像素直接继承来源像素的颜色。因为扩散是按层推进的，结果等价的
    就是「取最近实心像素的颜色」。
    """
    alpha = rgba[:, :, 3]
    solid = alpha > SOLID_ALPHA
    if not solid.any():
        raise ValueError("设计稿里找不到实心像素 —— 检查图片是否整体透明")

    h, w = alpha.shape
    out = rgba[:, :, :3].copy()
    filled = solid.copy()

    # 种子：实心、且四邻中至少有一个非实心（即区块的外沿）
    q: deque[tuple[int, int]] = deque()
    for y, x in zip(*np.where(solid)):
        if (
            y == 0 or not solid[y - 1, x]
            or y == h - 1 or not solid[y + 1, x]
            or x == 0 or not solid[y, x - 1]
            or x == w - 1 or not solid[y, x + 1]
        ):
            q.append((int(y), int(x)))

    while q:
        y, x = q.popleft()
        c = out[y, x]
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not filled[ny, nx]:
                out[ny, nx] = c
                filled[ny, nx] = True
                q.append((ny, nx))

    return out


def build_icon(src_path: str) -> Image.Image:
    """读设计稿 → 填边 → 放大到 1024 → 轻锐化，返回 RGB 模式的 1024 方图。"""
    im = Image.open(src_path).convert("RGBA")
    rgba = np.array(im)

    rgb = fill_transparent(rgba)

    icon = Image.fromarray(rgb, mode="RGB").resize((TARGET, TARGET), Image.LANCZOS)
    icon = icon.filter(ImageFilter.UnsharpMask(**UNSHARP))
    return icon


# ---------------------------------------------------------------- 校验 / 预览

def corner_ratio(im: Image.Image) -> float:
    """估算圆角半径占宽度的比例（沿顶边找第一个不透明像素）。"""
    a = np.array(im.convert("RGBA").getchannel("A"))
    row = np.where(a[0] > ALPHA_FLOOR)[0]
    if not len(row):
        return float("nan")
    return float(row.min()) / im.size[0]


def mask_ios_rounded(img: Image.Image, ratio: float = IOS_CORNER_RATIO) -> Image.Image:
    """按 iOS 圆角比例裁一张预览图，模拟桌面图标的样子（仅用于验证）。"""
    size = img.size[0]
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * ratio), fill=255
    )
    m = m.resize((size, size), Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(m)
    return out


def make_preview(icon: Image.Image, src_path: str, out_dir: str) -> str:
    """生成验证拼图：桌面尺寸 / 系统圆角模拟 / 小尺寸可读性 / 与源图往返对比。"""
    os.makedirs(out_dir, exist_ok=True)
    tiles: list[tuple[str, Image.Image]] = []

    tiles.append(("设计稿原图", Image.open(src_path).convert("RGB")))

    rounded = mask_ios_rounded(icon).convert("RGB")
    tiles.append(("1024 输出（系统圆角模拟）", rounded))

    # 桌面显示尺寸（60pt @3x = 180px）
    tiles.append(("桌面 60pt（180px）", icon.resize((180, 180), Image.LANCZOS)))

    # 往返回源尺寸，和原图逐像素比差异
    back = icon.resize(Image.open(src_path).size, Image.LANCZOS)
    diff = np.abs(
        np.array(back, dtype=np.int16)
        - np.array(Image.open(src_path).convert("RGB"), dtype=np.int16)
    )
    print(f"  · 往返对比：平均差 {diff.mean():.2f}/255，最大差 {diff.max()}")
    tiles.append(("缩小回源尺寸（对比用）", back))

    PAD, LABEL_H = 24, 34
    cell = max(t[1].size[0] for t in tiles), max(t[1].size[1] for t in tiles)
    W = PAD + sum(cell[0] + PAD for _ in tiles)
    H = PAD * 2 + LABEL_H + cell[1]
    canvas = Image.new("RGB", (W, H), (28, 30, 34))
    d = ImageDraw.Draw(canvas)
    x = PAD
    for label, t in tiles:
        canvas.paste(t, (x, PAD + LABEL_H + (cell[1] - t.size[1]) // 2))
        d.text((x, PAD + 8), label, fill=(230, 232, 236))
        x += t.size[0] + PAD

    path = os.path.join(out_dir, "icon-preview.png")
    canvas.save(path)
    return path


# ---------------------------------------------------------------- 主流程

def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview_only = "--preview" in sys.argv

    src = args[0] if args else DEFAULT_SOURCE
    if not os.path.exists(src):
        print(f"✗ 找不到设计稿：{src}", file=sys.stderr)
        return 1

    print(f"设计稿：{src}")
    raw = Image.open(src)
    print(f"  · 源规格 {raw.size[0]}×{raw.size[1]} {raw.mode}")
    ratio = corner_ratio(raw)
    print(f"  · 圆角半径 ≈ 宽度 {ratio * 100:.1f}%（iOS 系统 ≈ {IOS_CORNER_RATIO * 100:.1f}%）")
    if ratio < IOS_CORNER_RATIO:
        print("  · 系统圆角更大 → 裁切后全部落在设计稿实心区内，无接缝 ✓")
    else:
        print("  · ⚠ 设计稿圆角大于系统圆角，边缘可能露出填充色，需目视确认")

    icon = build_icon(src)
    print(f"  · 输出 {icon.size[0]}×{icon.size[1]} {icon.mode}（无 alpha ✓）")

    shot_dir = "/tmp/codelumi-icon"
    p = make_preview(icon, src, shot_dir)
    print(f"  · 预览拼图 {p}")

    if preview_only:
        print("（--preview 模式，未写入工程）")
        return 0

    if not os.path.isdir(APPICONSET):
        print(f"✗ 找不到 AppIcon.appiconset：{APPICONSET}", file=sys.stderr)
        return 1

    # 设计稿留档到仓库内，保证脚本输入可复现
    if os.path.abspath(src) != os.path.abspath(DEFAULT_SOURCE):
        os.makedirs(os.path.dirname(DEFAULT_SOURCE), exist_ok=True)
        shutil.copy2(src, DEFAULT_SOURCE)
        print(f"  · 设计稿已留档 {DEFAULT_SOURCE}")

    # 写入图标 + 收敛为单一 universal 条目（深色外观沿用同一张，故不再单列）
    icon.save(os.path.join(APPICONSET, "AppIcon-1024.png"), format="PNG")
    stale = os.path.join(APPICONSET, "AppIcon-1024-dark.png")
    if os.path.exists(stale):
        os.remove(stale)
        print("  · 已移除旧的自绘深色变体 AppIcon-1024-dark.png")

    contents = {
        "images": [
            {
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(APPICONSET, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"  · 已写入 {APPICONSET}")

    # 桌面尺寸落一张，方便直接看
    icon.resize((180, 180), Image.LANCZOS).save(
        os.path.join(shot_dir, "icon-180.png"), format="PNG"
    )
    print("完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
