#!/usr/bin/env swift
// ============================================================================
// Codelumi · 发码工具（macOS）—— App 图标生成脚本
//
// 设计口径：延续Codelumi iOS 端的品牌基因（亮蓝底 + 白色卡片叠层 + 蓝色扫描框
//          + 青绿/橙黄双色点缀），但按 macOS 规范重绘：
//            · 画布 1024×1024，图标体 824×824 居中，外围透明
//            · 图标体自绘 squircle（超椭圆 n=5），macOS 不会替 App 加圆角
//            · 元素一律正投影、大圆角、柔和渐变，便于 16px 下辨认
//
// 用法：xcrun swift icon/make_icon.swift
// 产物：icon/AppIcon-1024.png、icon/AppIcon.iconset/*、icon/AppIcon.icns
//
// 微调入口全部集中在「参数」一节，改数值重跑即可，无需改绘制逻辑。
// ============================================================================

import AppKit
import CoreGraphics
import Foundation

// MARK: - 参数

let CANVAS: CGFloat = 1024            // 画布边长
let BODY: CGFloat = 824               // 图标体边长（Apple HIG：内容体占画布 824/1024）
let BODY_INSET = (CANVAS - BODY) / 2  // 四周边距 = 100
let SQUIRCLE_N: Double = 5.0          // 超椭圆指数，n=5 近似 Apple 圆角方

// 品牌色
let BLUE_TOP    = rgba(78, 158, 255)   // 底色渐变·亮端（左上）
let BLUE_BOTTOM = rgba(19, 95, 203)    // 底色渐变·深端（右下）
let CARD_TOP    = rgba(255, 255, 255)  // 卡片渐变·亮端
let CARD_BOTTOM = rgba(231, 240, 255)  // 卡片渐变·深端
let SCAN_BLUE   = rgba(27, 111, 224)   // 扫描框
let TEAL_TOP    = rgba(64, 226, 208)   // 青绿卡
let TEAL_BOTTOM = rgba(26, 190, 176)
let AMBER_TOP   = rgba(255, 192, 64)   // 橙黄卡
let AMBER_BOTTOM = rgba(242, 154, 14)

// 卡片堆叠几何：由后到前，每层向左下偏移
struct CardSpec {
    let center: CGPoint
    let size: CGSize
    let radius: CGFloat
    let top: CGColor
    let bottom: CGColor
}

let CARDS: [CardSpec] = [
    CardSpec(center: CGPoint(x: 576, y: 574), size: CGSize(width: 536, height: 412),
             radius: 62, top: AMBER_TOP, bottom: AMBER_BOTTOM),
    CardSpec(center: CGPoint(x: 522, y: 520), size: CGSize(width: 556, height: 426),
             radius: 62, top: TEAL_TOP, bottom: TEAL_BOTTOM),
    CardSpec(center: CGPoint(x: 468, y: 466), size: CGSize(width: 576, height: 440),
             radius: 62, top: CARD_TOP, bottom: CARD_BOTTOM),
]

// 扫描框（画在主卡上）
let SCAN_W: CGFloat = 340
let SCAN_H: CGFloat = 310
let SCAN_RADIUS: CGFloat = 50
let SCAN_LINE: CGFloat = 32
let SCAN_ARM: CGFloat = 138           // 角块边长 = 圆角 + 直臂；须满足 2×ARM < 框宽

// 小尺寸变体（16/32px 专用）：叠层在 16px 下会糊成一片，改用单卡 + 加粗扫描框
let COMPACT_CARD = CardSpec(center: CGPoint(x: 512, y: 500),
                            size: CGSize(width: 640, height: 500),
                            radius: 72, top: CARD_TOP, bottom: CARD_BOTTOM)
let COMPACT_SCAN_W: CGFloat = 400
let COMPACT_SCAN_H: CGFloat = 350
let COMPACT_SCAN_RADIUS: CGFloat = 56
let COMPACT_SCAN_LINE: CGFloat = 50
let COMPACT_SCAN_ARM: CGFloat = 155

// MARK: - 基础工具

func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: a)
}

/// 超椭圆（squircle）路径。参数方程 x = a·sgn(cos t)·|cos t|^(2/n)
func squirclePath(rect: CGRect, n: Double) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2.0
    let b = rect.height / 2.0
    let cx = rect.midX
    let cy = rect.midY
    let steps = 1440
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2.0 * Double.pi
        let ct = cos(t)
        let st = sin(t)
        let x = cx + a * CGFloat(pow(abs(ct), 2.0 / n) * (ct < 0 ? -1 : 1))
        let y = cy + b * CGFloat(pow(abs(st), 2.0 / n) * (st < 0 ? -1 : 1))
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// 先落阴影实心填充，再裁切填渐变 —— CG 的 drawLinearGradient 不产生阴影，须两步
func fillCard(_ ctx: CGContext,
              rect: CGRect,
              radius: CGFloat,
              top: CGColor,
              bottom: CGColor,
              shadow: (offset: CGSize, blur: CGFloat, color: CGColor)?) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let space = CGColorSpaceCreateDeviceRGB()

    if let s = shadow {
        ctx.saveGState()
        ctx.setShadow(offset: s.offset, blur: s.blur, color: s.color)
        ctx.addPath(path)
        ctx.setFillColor(top)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if let g = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
        // 左上亮 → 右下深
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY),
                               options: [])
    }
    ctx.restoreGState()
}

// MARK: - 绘制主图

/// 扫描框绘制（四角括号）。抽出来供完整版与小尺寸变体共用
func drawScanFrame(_ ctx: CGContext, center: CGPoint,
                   w: CGFloat, h: CGFloat, radius: CGFloat,
                   lineW: CGFloat, arm: CGFloat) {
    let frameRect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    let framePath = CGPath(roundedRect: frameRect, cornerWidth: radius,
                           cornerHeight: radius, transform: nil)

    // 裁到四个角块，只留下角括号，中段被切掉
    let mask = CGMutablePath()
    let pad = lineW
    mask.addRect(CGRect(x: frameRect.minX - pad, y: frameRect.minY - pad,
                        width: arm, height: arm))
    mask.addRect(CGRect(x: frameRect.maxX + pad - arm, y: frameRect.minY - pad,
                        width: arm, height: arm))
    mask.addRect(CGRect(x: frameRect.minX - pad, y: frameRect.maxY + pad - arm,
                        width: arm, height: arm))
    mask.addRect(CGRect(x: frameRect.maxX + pad - arm, y: frameRect.maxY + pad - arm,
                        width: arm, height: arm))

    ctx.saveGState()
    ctx.addPath(mask)
    ctx.clip()
    ctx.addPath(framePath)
    ctx.setStrokeColor(SCAN_BLUE)
    ctx.setLineWidth(lineW)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

/// 渲染图标。
/// - Parameters:
///   - compact: true 时出「小尺寸变体」——单张白卡 + 加粗扫描框，供 16/32px 使用
///   - scale: 输出像素 = 1024 × scale（几何仍按 1024 设计坐标绘制，保矢量清晰度）
func renderIcon(compact: Bool = false, scale: CGFloat = 1.0) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let px = Int((CANVAS * scale).rounded())
    guard let ctx = CGContext(data: nil,
                              width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("无法创建位图上下文")
    }
    ctx.scaleBy(x: scale, y: scale)   // 后续一律使用 1024 设计坐标
    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let bodyRect = CGRect(x: BODY_INSET, y: BODY_INSET, width: BODY, height: BODY)
    let shell = squirclePath(rect: bodyRect, n: SQUIRCLE_N)

    ctx.saveGState()
    ctx.addPath(shell)
    ctx.clip()

    // ① 底色渐变
    if let g = CGGradient(colorsSpace: space,
                          colors: [BLUE_TOP, BLUE_BOTTOM] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: bodyRect.minX + BODY * 0.10, y: bodyRect.minY + BODY * 0.94),
                               end: CGPoint(x: bodyRect.minX + BODY * 0.92, y: bodyRect.minY + BODY * 0.06),
                               options: [])
    }

    // ② 左上柔光，避免大面积纯色显得平板
    if let g = CGGradient(colorsSpace: space,
                          colors: [rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.0)] as CFArray,
                          locations: [0, 1]) {
        let c = CGPoint(x: bodyRect.minX + BODY * 0.28, y: bodyRect.minY + BODY * 0.82)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: BODY * 0.82, options: [])
    }

    // ③ 卡片（由后到前）：完整版为三层叠放，小尺寸变体只留一张
    let cards = compact ? [COMPACT_CARD] : CARDS
    for card in cards {
        let rect = CGRect(x: card.center.x - card.size.width / 2,
                          y: card.center.y - card.size.height / 2,
                          width: card.size.width,
                          height: card.size.height)
        fillCard(ctx, rect: rect, radius: card.radius, top: card.top, bottom: card.bottom,
                 shadow: (CGSize(width: 0, height: -16), 38, rgba(0, 30, 76, 0.30)))
    }

    // ④ 扫描框
    let front = compact ? COMPACT_CARD : CARDS[CARDS.count - 1]
    if compact {
        drawScanFrame(ctx, center: front.center,
                      w: COMPACT_SCAN_W, h: COMPACT_SCAN_H,
                      radius: COMPACT_SCAN_RADIUS,
                      lineW: COMPACT_SCAN_LINE, arm: COMPACT_SCAN_ARM)
    } else {
        drawScanFrame(ctx, center: front.center,
                      w: SCAN_W, h: SCAN_H,
                      radius: SCAN_RADIUS,
                      lineW: SCAN_LINE, arm: SCAN_ARM)
    }

    ctx.restoreGState()   // 解除 squircle 裁剪

    guard let image = ctx.makeImage() else { fatalError("无法生成位图") }
    return image
}

// MARK: - 输出

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDir = here.appendingPathComponent("icon")
try? FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)

func writePNG(_ image: CGImage, to url: URL) -> Int {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 编码失败")
    }
    try? data.write(to: url)
    return data.count
}

let master = iconDir.appendingPathComponent("AppIcon-1024.png")
let masterBytes = writePNG(renderIcon(), to: master)
print("▸ 主图：\(master.lastPathComponent)（\(masterBytes / 1024) KB）")

// 小尺寸变体：以 256px 矢量渲染（供 16/32 使用）。16px 下三层叠片会糊成一团，
// 故改用单卡 + 加粗扫描框，保证极小尺寸仍有明确轮廓。
let compactMaster = iconDir.appendingPathComponent("AppIcon-compact.png")
let compactBytes = writePNG(renderIcon(compact: true, scale: 256.0 / CANVAS), to: compactMaster)
print("▸ 小尺寸变体：\(compactMaster.lastPathComponent)（\(compactBytes / 1024) KB，256px）")

// 由主图降采样出 iconset（sips 用高质量重采样）
let iconset = iconDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

for (name, px) in variants {
    let dst = iconset.appendingPathComponent(name)
    if px == 1024 {
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: master, to: dst)
        continue
    }
    let source = px <= 32 ? compactMaster : master   // ≤32px 走简化变体
    run("/usr/bin/sips", ["-z", "\(px)", "\(px)", source.path, "--out", dst.path])
}
print("▸ iconset：\(variants.count) 个尺寸（≤32px 用简化变体）")

let icns = iconDir.appendingPathComponent("AppIcon.icns")
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icns.path])
guard FileManager.default.fileExists(atPath: icns.path) else { fatalError("iconutil 生成失败") }
let attrs = try? FileManager.default.attributesOfItem(atPath: icns.path)
let icnsSize = (attrs?[.size] as? NSNumber)?.intValue ?? 0
print("▸ icns：\(icns.lastPathComponent)（\(icnsSize / 1024) KB）")
