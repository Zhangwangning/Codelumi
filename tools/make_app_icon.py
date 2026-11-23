#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Codelumi · App 图标生成器
================================

设计口径（2026-09-21 定稿）
--------------------------
图标不另起一套插画语言，而是**把 App 内的卡片抽象成 60pt 就能认出的符号**：

    品牌墨绿对角渐变底  +  白色圆角卡片  +  卡片内「圆形勾选框」+ 两根信息行

三段元素分别对应界面里的：勾选框（行首）、取件码（主信息）、取件码／地址（次信息）。
配色沿用 AppTheme 品牌色系（accent #FF5000 淘宝橙），并额外提供深色外观变体。

小尺寸可读性
------------
iPhone 桌面图标约 60pt，1024 源图会被缩到约 1/17。因此所有元素都按
「缩到 60pt 后仍 ≥ 2pt」反推尺寸：

    勾选圈外径 240px → 14.0pt     环宽 46px → 2.7pt
    信息行高    74px →  4.3pt     行间距 46px → 2.7pt

细于此的装饰（描边细节、纹理、多层阴影）一律不加 —— 缩略后会糊成脏点。

用法
----
    # 依赖 pillow + numpy，装在 WorkBuddy 的隔离 venv 里
    /Users/zhangwangning/.workbuddy/binaries/python/envs/default/bin/python \
        tools/make_app_icon.py              # 生成并写入 AppIcon.appiconset
    ... tools/make_app_icon.py --preview    # 只出预览拼图，不动工程
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- 常量

SS = 3                      # 超采样倍数（3072 绘制 → 1024 输出）
BASE = 1024                 # 输出边长
N = BASE * SS               # 绘制画布边长

HERE = os.path.dirname(os.path.abspath(__file__))
APPICONSET = os.path.normpath(
    os.path.join(HERE, "..", "Codelumi", "Codelumi", "Assets.xcassets", "AppIcon.appiconset")
)

# 几何比例全部以 1024 为基准书写，绘制时统一乘 SS
CARD = (182, 182, 842, 842)     # 白卡片 660×660，居中
CARD_RADIUS = 150
RING = (322, 272, 562, 512)     # 勾选圈外框：直径 240
RING_WIDTH = 46
BAR1 = (322, 558, 702, 632)     # 信息行 1：380×74
BAR2 = (322, 678, 582, 752)     # 信息行 2：260×74

THEMES = {
    "AppIcon-1024.png": {
        "label": "浅色外观",
        "bg": ((0xFF, 0x8A, 0x4C), (0xD9, 0x33, 0x00)),
        "glow": 0.22,
        "card": (0xFF, 0xFF, 0xFF),
        "ink": (0xE0, 0x45, 0x00),
        "shadow": (0x22, 0x05, 0x00, 110),
    },
    "AppIcon-1024-dark.png": {
        "label": "深色外观",
        "bg": ((0x5C, 0x24, 0x08), (0x24, 0x0C, 0x02)),
        "glow": 0.10,
        "card": (0xFF, 0xF0, 0xE6),
        "ink": (0xD9, 0x3A, 0x00),
        "shadow": (0x00, 0x00, 0x00, 160),
    },
}


# ---------------------------------------------------------------- 工具

def scaled(box):
    """把 1024 基准坐标放大到绘制画布"""
    return tuple(int(round(v * SS)) for v in box)


def relative_luminance(rgb):
    def channel(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(float(c)) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(a, b):
    la, lb = relative_luminance(a), relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def diagonal_gradient(c0, c1):
    """左上 → 右下 的线性渐变（按 x+y 投影，保证是严格对角）"""
    axis = np.arange(N, dtype=np.float64)
    t = (axis[None, :] + axis[:, None]) / (2.0 * (N - 1))
    start = np.array(c0, dtype=np.float64)
    end = np.array(c1, dtype=np.float64)
    rgb = start[None, None, :] * (1.0 - t[..., None]) + end[None, None, :] * t[..., None]
    return Image.fromarray(np.clip(rgb, 0, 255).astype("uint8"), "RGB")


def add_glow(img, strength):
    """左上柔和高光：让纯平渐变有受光感（Apple 图标常见的做法）"""
    yy, xx = np.mgrid[0:N, 0:N]
    dist = np.sqrt((xx - N * 0.24) ** 2 + (yy - N * 0.14) ** 2) / (N * 0.92)
    alpha = np.clip(1.0 - dist, 0.0, 1.0) ** 2.2 * strength
    arr = np.asarray(img, dtype=np.float64)
    arr = arr + (255.0 - arr) * alpha[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGB")


def add_card_shadow(img, color):
    """卡片投影：独立图层做高斯模糊，再整体合成"""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = scaled(CARD)
    offset = int(20 * SS)
    draw.rounded_rectangle([x0, y0 + offset, x1, y1 + offset],
                           radius=CARD_RADIUS * SS, fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(46 * SS / 3))
    return Image.alpha_composite(img.convert("RGBA"), layer)


def draw_icon(theme):
    """按主题绘制一枚图标，返回 1024×1024 RGB"""
    img = diagonal_gradient(*theme["bg"])
    img = add_glow(img, theme["glow"])
    img = add_card_shadow(img, theme["shadow"])

    draw = ImageDraw.Draw(img)

    # 卡片
    draw.rounded_rectangle(scaled(CARD), radius=CARD_RADIUS * SS,
                           fill=theme["card"])

    ink = theme["ink"]

    # 勾选圈（空心环 = 待取件的默认状态）
    ring = scaled(RING)
    draw.ellipse(ring, outline=ink, width=RING_WIDTH * SS)

    # 两根信息行（第二根更短，模拟文字段落）
    for bar in (BAR1, BAR2):
        x0, y0, x1, y1 = scaled(bar)
        draw.rounded_rectangle([x0, y0, x1, y1],
                               radius=(y1 - y0) // 2, fill=ink)

    return img.convert("RGB").resize((BASE, BASE), Image.LANCZOS)


# ---------------------------------------------------------------- 输出

def write_contents_json(target, has_dark):
    images = [{
        "filename": "AppIcon-1024.png",
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024",
    }]
    if has_dark:
        images.append({
            "appearances": [{"appearance": "luminosity", "value": "dark"}],
            "filename": "AppIcon-1024-dark.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        })
    payload = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(target, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main():
    preview_only = "--preview" in sys.argv

    rendered = {}
    for filename, theme in THEMES.items():
        image = draw_icon(theme)
        rendered[filename] = image
        ink, card = theme["ink"], theme["card"]
        print(f"  {theme['label']:<6} 元素/卡片对比度 {contrast_ratio(ink, card):.2f}:1"
              f"   元素色 #{ink[0]:02X}{ink[1]:02X}{ink[2]:02X}")

        if not preview_only:
            os.makedirs(APPICONSET, exist_ok=True)
            out = os.path.join(APPICONSET, filename)
            image.save(out, "PNG")
            print(f"    → 已写入 {out}")

    if not preview_only:
        write_contents_json(os.path.join(APPICONSET, "Contents.json"), True)
        print("    → 已更新 Contents.json（含深色外观变体）")

    # 缩略预览：把 1024 缩到桌面真实观感（60 / 120pt @3x）
    preview_dir = os.path.normpath(os.path.join(HERE, "..", "Design-Snapshots"))
    os.makedirs(preview_dir, exist_ok=True)
    tiles = []
    for image in rendered.values():
        for px in (60, 120, 240):
            tiles.append((px, image.resize((px, px), Image.LANCZOS)))
    width = sum(px * 2 for px, _ in tiles) + 20 * (len(tiles) + 1)
    height = max(px * 2 for px, _ in tiles) + 40
    sheet = Image.new("RGB", (width, height), (245, 246, 248))
    x = 20
    for px, tile in tiles:
        sheet.paste(tile, (x, (height - px * 2) // 2), None)
        x += px * 2 + 20
    out = os.path.join(preview_dir, "AppIcon-预览.png")
    sheet.save(out, "PNG")
    print(f"  → 缩略预览拼图 {out}")


if __name__ == "__main__":
    main()
