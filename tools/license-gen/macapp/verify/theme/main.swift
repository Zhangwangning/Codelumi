import AppKit

// ============================================================================
// 主题 / 布局验证 harness
//
// 跑法：verify/run.sh
//
// 为什么需要它：主窗口的层级较深（玻璃卡片 → 滚动区 → 结果行），
// 而 AppKit 的长度分配在缺约束时会给出「能跑但难看」的结果 ——
// 光看代码判断不出来。这个 harness 创建真实窗口、跑完 run loop，
// 然后 ① 量化测量布局 ② 抓真实渲染出图 ③ 验证外观切换时颜色是否跟随。
//
// 输出：$CC_VERIFY_OUT（默认 /tmp/ccui-verify）下的 L*/D* PNG
// ============================================================================

let OUT = ProcessInfo.processInfo.environment["CC_VERIFY_OUT"] ?? "/tmp/ccui-verify"
try? FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)

var problems: [String] = []

// MARK: - 工具

func rs(_ r: NSRect) -> String {
    "\(Int(r.origin.x)),\(Int(r.origin.y)) \(Int(r.width))×\(Int(r.height))"
}

func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let hit = view as? T { return hit }
    for sub in view.subviews {
        if let found = find(type, in: sub) { return found }
    }
    return nil
}

func findAll<T: NSView>(_ type: T.Type, in view: NSView, into acc: inout [T]) {
    if let hit = view as? T { acc.append(hit) }
    for sub in view.subviews { findAll(type, in: sub, into: &acc) }
}

/// 在指定外观下解析动态色。直接用 .cgColor 会按「当前绘制外观」解析，离屏环境下不可靠。
func resolve(_ color: NSColor, in appearance: NSAppearance) -> CGColor {
    var result: CGColor = color.cgColor
    appearance.performAsCurrentDrawingAppearance {
        result = color.cgColor
    }
    return result
}

/// 读 layer 背景色。注意：动态色的 CGColor 可能无法直接取 components，要先转回 NSColor。
func layerColor(_ view: NSView) -> String {
    guard let cg = view.layer?.backgroundColor else { return "nil（未设置）" }
    guard let ns = NSColor(cgColor: cg) else { return "无法转 NSColor" }
    let c = ns.usingColorSpace(.sRGB) ?? ns
    return String(format: "rgba(%.3f,%.3f,%.3f,%.2f)",
                  c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

func snapshot(_ view: NSView, to name: String) {
    // 窗口背景不会被 cacheDisplay 画进来，先铺一层（用视图自身外观解析，才代表真实底色）
    view.wantsLayer = true
    view.layer?.backgroundColor = resolve(NSColor.windowBackgroundColor, in: view.effectiveAppearance)
    view.layoutSubtreeIfNeeded()

    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        print("  ✗ 无法创建位图 \(name)"); return
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("  ✗ PNG 编码失败 \(name)"); return
    }
    let path = "\(OUT)/\(name)"
    try? data.write(to: URL(fileURLWithPath: path))
    print("  已出图 \(path)  \(Int(view.bounds.width))×\(Int(view.bounds.height))")
}

/// 布局塌陷检测：有文字/按钮但尺寸为 0
func auditZeroSize(_ view: NSView, path: String = "") {
    let here = path + "/" + String(describing: type(of: view))
    if view.frame.width <= 0 || view.frame.height <= 0 {
        let hasText = (view as? NSTextField)?.stringValue.isEmpty == false
        let hasButton = (view as? NSButton)?.title.isEmpty == false
        if hasText || hasButton {
            problems.append("尺寸塌陷：\(here) \(rs(view.frame))")
        }
    }
    for sub in view.subviews { auditZeroSize(sub, path: here) }
}

// MARK: - 启动

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()

func buildWindow(_ controller: NSViewController, size: NSSize, title: String, light: Bool) -> NSWindow {
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                       styleMask: [.titled, .closable, .miniaturizable, .resizable],
                       backing: .buffered, defer: false)
    win.title = title
    win.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    win.contentViewController = controller
    win.setContentSize(size)
    win.makeKeyAndOrderFront(nil)     // 成为 key window，系统控件才呈现"活动态"外观
    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    win.layoutIfNeeded()
    return win
}

// ============================================================================
print("===== ① 主窗口 · 浅色 · 布局与玻璃 =====")
let mainLight = MainViewController()
let winL = buildWindow(mainLight, size: NSSize(width: T.windowWidth, height: T.windowHeight),
                       title: "Codelumi · 发码工具", light: true)
let viewL = winL.contentView!
viewL.layoutSubtreeIfNeeded()
auditZeroSize(viewL)

print("  内容区 = \(rs(viewL.frame))")
if let pane = find(ScrollPane.self, in: viewL) {
    print("  结果区 = \(rs(pane.frame))")
    if pane.frame.height < 120 {
        problems.append("结果区被压扁：高度 \(Int(pane.frame.height))（应 ≥120，否则窗口下方留大片空白）")
    }
}

var glasses: [NSGlassEffectView] = []
findAll(NSGlassEffectView.self, in: viewL, into: &glasses)
print("  液态玻璃视图 = \(glasses.count) 个")
for (i, g) in glasses.enumerated() {
    print("    [\(i)] \(rs(g.frame)) cornerRadius=\(Int(g.cornerRadius)) "
          + "style=\(g.style == .regular ? "regular" : "clear")")
}
if glasses.isEmpty { problems.append("没有找到 NSGlassEffectView —— 液态玻璃未生效") }

// 顶栏/底栏高度必须钉死，否则没有 intrinsicContentSize 的 NSStackView 会抢走内容区高度
let rootChildren = mainLight.view.subviews
if rootChildren.count >= 5 {
    let headerH = Int(rootChildren[0].frame.height)
    let contentH = Int(rootChildren[2].frame.height)
    let footerH = Int(rootChildren[4].frame.height)
    print("  顶栏 \(headerH) / 内容区 \(contentH) / 底栏 \(footerH)")
    if headerH > Int(T.headerHeight) + 2 { problems.append("顶栏被撑高到 \(headerH)（设计值 \(Int(T.headerHeight))）") }
    if footerH > Int(T.footerHeight) + 2 { problems.append("底栏被撑高到 \(footerH)（设计值 \(Int(T.footerHeight))）") }
}

snapshot(viewL, to: "L1-主窗口-批量签发.png")

// ============================================================================
print()
print("===== ② 外观切换验证（layer 颜色必须跟随外观）=====")
print("  原理：`layer.backgroundColor = 动态色.cgColor` 会把「当时外观」的颜色固化；")
print("        若不实现 viewDidChangeEffectiveAppearance，切浅色后仍是深色底。")

let fieldProbe = find(MultilineField.self, in: viewL)!
let rowProbe = find(ResultRowView.self, in: viewL)!
let beforeField = layerColor(fieldProbe)
let beforeRow = layerColor(rowProbe)
print("  浅色 · 输入框 = \(beforeField)")
print("  浅色 · 结果行 = \(beforeRow)")

winL.appearance = NSAppearance(named: .darkAqua)
RunLoop.current.run(until: Date().addingTimeInterval(0.8))
viewL.layoutSubtreeIfNeeded()

let afterField = layerColor(fieldProbe)
let afterRow = layerColor(rowProbe)
print("  深色 · 输入框 = \(afterField)")
print("  深色 · 结果行 = \(afterRow)")

if beforeField == afterField { problems.append("输入框底未跟随外观切换：都是 \(beforeField)") }
else { print("  ✓ 输入框底已跟随") }
if beforeRow == afterRow { problems.append("结果行底未跟随外观切换：都是 \(beforeRow)") }
else { print("  ✓ 结果行底已跟随") }

winL.appearance = NSAppearance(named: .aqua)
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
let backField = layerColor(fieldProbe)
print("  切回浅色 · 输入框 = \(backField)")
if backField != beforeField { problems.append("切回浅色未还原：期望 \(beforeField)，实得 \(backField)") }
else { print("  ✓ 切回浅色可正确还原") }
winL.orderOut(nil)

// ============================================================================
print()
print("===== ③ 两个外观 × 三个内页 =====")
for light in [true, false] {
    let tag = light ? "L" : "D"
    let vc = MainViewController()
    let win = buildWindow(vc, size: NSSize(width: T.windowWidth, height: T.windowHeight),
                          title: "Codelumi · 发码工具", light: light)
    let v = win.contentView!
    v.layoutSubtreeIfNeeded()
    auditZeroSize(v)
    snapshot(v, to: "\(tag)1-主窗口-批量签发.png")

    guard let seg = find(NSSegmentedControl.self, in: v) else {
        problems.append("主窗口里找不到分段控件")
        continue
    }
    for (idx, name) in [(1, "凭证验签"), (2, "签发台账")] {
        seg.selectedSegment = idx
        seg.sendAction(seg.action, to: seg.target)
        v.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        auditZeroSize(v)
        snapshot(v, to: "\(tag)\(idx + 1)-主窗口-\(name).png")
    }
    win.orderOut(nil)
}

// ============================================================================
print()
print("===== ④ 菜单栏面板 · 两个外观 =====")
for light in [true, false] {
    let panel = SignPanelController()
    _ = panel.view
    let h = panel.view.fittingSize.height
    let win = buildWindow(panel, size: NSSize(width: T.panelWidth, height: h),
                          title: "菜单栏面板", light: light)
    let v = win.contentView!
    v.layoutSubtreeIfNeeded()
    auditZeroSize(v)
    if Int(panel.preferredContentSize.width) != Int(T.panelWidth) {
        problems.append("面板宽度不符：\(panel.preferredContentSize.width) ≠ \(T.panelWidth)")
    }
    if panel.preferredContentSize.height < 300 {
        problems.append("面板高度异常偏小：\(panel.preferredContentSize.height)")
    }
    print("  \(light ? "浅色" : "深色") · \(Int(panel.preferredContentSize.width))×\(Int(panel.preferredContentSize.height))")
    snapshot(v, to: light ? "L4-菜单栏面板.png" : "D4-菜单栏面板.png")
    win.orderOut(nil)
}

// ============================================================================
print()
print("===== ⑤ 台账 · 凭证展开态（点「查看」→ 出全文 → 拷贝）=====")

let vc5 = MainViewController()
let win5 = buildWindow(vc5, size: NSSize(width: T.windowWidth, height: T.windowHeight),
                       title: "Codelumi · 发码工具", light: true)
let v5 = win5.contentView!
v5.layoutSubtreeIfNeeded()

if let seg = find(NSSegmentedControl.self, in: v5) {
    seg.selectedSegment = 2                       // 第 3 段 = 签发台账
    seg.sendAction(seg.action, to: seg.target)
    v5.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
}

var rows5: [ResultRowView] = []
findAll(ResultRowView.self, in: v5, into: &rows5)
print("  台账渲染行数 = \(rows5.count)")

var targetRow: ResultRowView?
var viewButton: PillButton?
for row in rows5 {
    var buttons: [PillButton] = []
    findAll(PillButton.self, in: row, into: &buttons)
    if let b = buttons.first(where: { $0.title == "查看" }) {
        targetRow = row; viewButton = b
        break
    }
}

if let row = targetRow, let button = viewButton {
    let beforeH = row.frame.height

    // 台账行必须是单行（信息横向排开），不能主/明细上下堆叠
    var rowFields: [NSTextField] = []
    findAll(NSTextField.self, in: row, into: &rowFields)
    if let p = rowFields.first(where: { $0.stringValue.count == 32 }),
       let s = rowFields.first(where: { $0.stringValue.contains("月付") }) {
        let dy = abs(p.frame.midY - s.frame.midY)
        print("  台账行 主/明细中心差 = \(Int(dy))pt  行高 = \(Int(beforeH))")
        if dy > 6 {
            problems.append("台账行仍是上下两行布局（中心差 \(Int(dy))pt）")
        }
    } else {
        problems.append("台账行里没找到设备码或档位明细")
    }

    button.performClick(nil)
    v5.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    v5.layoutSubtreeIfNeeded()

    let afterH = row.frame.height
    print("  展开前后行高：\(Int(beforeH)) → \(Int(afterH))")
    // 展开区必须与行同宽，否则右边缘会缩进一截（视觉上像"没对齐"）
    if let outerStack = row.subviews.first as? NSStackView {
        for b in outerStack.arrangedSubviews where b.frame.height > T.rowHeightInline + 10 {
            print("  展开区 = \(rs(b.frame))  行宽 = \(Int(row.frame.width))")
            if Int(b.frame.width) != Int(row.frame.width) {
                problems.append("展开区宽度 \(Int(b.frame.width)) ≠ 行宽 \(Int(row.frame.width))")
            }
        }
    }
    if afterH <= beforeH + 4 {
        problems.append("点「查看」后行高没变化（\(Int(beforeH)) → \(Int(afterH))）—— 详情区没展开")
    }
    if button.title != "收起" {
        problems.append("展开后按钮标题应变为「收起」，实得「\(button.title)」")
    }

    // 凭证全文文本：必须存在、可选中、且真的换了行（一条 190+ 字符的长串）
    var fields: [NSTextField] = []
    findAll(NSTextField.self, in: row, into: &fields)
    if let code = fields.first(where: { $0.stringValue.hasPrefix("CLIP1.") }) {
        print("  凭证文本区 = \(rs(code.frame))  可选中=\(code.isSelectable)  字数=\(code.stringValue.count)")
        if !code.isSelectable { problems.append("凭证全文不可选中 —— 「能看不能选」体验不完整") }
        if code.frame.width < 300 { problems.append("凭证文本宽度异常：\(Int(code.frame.width))") }
        if code.frame.height < 25 {
            problems.append("凭证文本只有 \(Int(code.frame.height))pt 高 —— 没有换行，长串会溢出被裁")
        }
    } else {
        problems.append("展开后没找到凭证全文文本（CLIP1. 开头）")
    }

    // 拷贝按钮：必须存在 + 立即反馈 + 剪贴板真的写进去了
    var buttons5: [PillButton] = []
    findAll(PillButton.self, in: row, into: &buttons5)
    if let copyBtn = buttons5.first(where: { $0.title == "拷贝" }) {
        copyBtn.performClick(nil)
        print("  点「拷贝」后按钮标题 = \(copyBtn.title)")
        if copyBtn.title != "已拷贝" {
            problems.append("拷贝按钮没有即时反馈（标题仍为「\(copyBtn.title)」）—— 用户会以为按钮失灵")
        }
        let board = NSPasteboard.general.string(forType: .string) ?? ""
        print("  剪贴板内容 = \(board.prefix(24))…（\(board.count) 字符）")
        if !board.hasPrefix("CLIP1.") {
            problems.append("拷贝后剪贴板里不是凭证：\(board.prefix(40))")
        }
    } else {
        problems.append("展开区里没有「拷贝」按钮")
    }

    snapshot(v5, to: "L5-台账-凭证展开.png")

    // 深色下也出一张：详情区在深色用的是压暗底（black 0.28），对比度得眼见为实
    win5.appearance = NSAppearance(named: .darkAqua)
    RunLoop.current.run(until: Date().addingTimeInterval(0.7))
    v5.layoutSubtreeIfNeeded()
    snapshot(v5, to: "D5-台账-凭证展开.png")
} else if rows5.count > 1 {
    problems.append("台账有 \(rows5.count) 行却没有「查看」按钮 —— 凭证解析失败或按钮被误隐藏")
} else {
    print("  （台账为空，跳过展开验证）")
}
win5.orderOut(nil)

// ============================================================================
print()
print("===== ⑥ 结果行控件 · 批量签发页复用路径（不写盘）=====")

let win6 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 976, height: 240),
                    styleMask: [.titled], backing: .buffered, defer: false)
win6.appearance = NSAppearance(named: .aqua)
let host6 = win6.contentView!

let probe = ResultRowView(inline: true)              // 批量签发页的用法（单行）
probe.onCopy = { copyToPasteboard("PROBE-OK") }      // 必须在 configure 之前设，否则按钮仍是隐藏态
probe.translatesAutoresizingMaskIntoConstraints = false
host6.addSubview(probe)
NSLayoutConstraint.activate([
    probe.leadingAnchor.constraint(equalTo: host6.leadingAnchor, constant: 10),
    probe.trailingAnchor.constraint(equalTo: host6.trailingAnchor, constant: -10),
    probe.topAnchor.constraint(equalTo: host6.topAnchor, constant: 10),
])
probe.configure(iconText: "✓", iconColor: C.ok,
                primaryText: "5028DE2F41874CD59F94A6F8EC488EBA",
                secondaryText: "月付（30 天） · 至 2026-10-24 · 已记账 #0003",
                trailingText: "237 字符")
host6.layoutSubtreeIfNeeded()
print("  行尺寸 = \(rs(probe.frame))")
if probe.frame.height < 30 || probe.frame.height > 56 {
    problems.append("批量签发结果行高度异常：\(Int(probe.frame.height))（应在 30~56）")
}

// 核心断言：主信息（设备码）与明细必须在**同一条水平线**上，而不是上下堆成两行
var probeFields: [NSTextField] = []
findAll(NSTextField.self, in: probe, into: &probeFields)
if let p = probeFields.first(where: { $0.stringValue.hasPrefix("5028DE") }),
   let s = probeFields.first(where: { $0.stringValue.contains("月付") }) {
    let dy = abs(p.frame.midY - s.frame.midY)
    print("  主/明细中心差 = \(Int(dy))pt（同一行应 ≤6）")
    if dy > 6 {
        problems.append("主信息与明细没有排在同一行（中心差 \(Int(dy))pt）—— 仍是上下两行布局")
    }
} else {
    problems.append("结果行里没找到设备码或明细文本")
}

var probeButtons: [PillButton] = []
findAll(PillButton.self, in: probe, into: &probeButtons)
if probeButtons.count != 1 {
    problems.append("批量签发结果行的按钮数量异常：\(probeButtons.count)（应恰好 1 个）")
} else if probeButtons[0].isHidden {
    problems.append("批量签发结果行的拷贝按钮被误隐藏 —— 改了 ResultRowView 后行为回退了")
} else {
    print("  按钮「\(probeButtons[0].title)」= \(rs(probeButtons[0].frame))")
    probeButtons[0].performClick(nil)
    let got = NSPasteboard.general.string(forType: .string) ?? ""
    if got != "PROBE-OK" {
        problems.append("结果行拷贝按钮点击无效（剪贴板 = \(got)）")
    } else {
        print("  ✓ 点击后剪贴板已更新")
    }
}
win6.orderOut(nil)

// ============================================================================
print()
print("===== ⑥ 主菜单结构审计（快捷键行为见 verify/menu/run.sh）=====")

// 这里**只做结构审计**：装菜单 → 摊平打印 → 断言标题与快捷键。
// ⌘C / ⌘V 的实际分发行为不在这里测 —— harness 是命令行进程（无 bundle），
// 拿不到 key window（实测 isKeyWindow 恒为 false），`target(forAction:)`
// 找不到 NSTextView，测出来必然是假警报。那部分交给 verify/menu/run.sh：
// 它把真实验证入口打包成 .app 运行，顺带还能测右键菜单的本地化。

let savedMainMenu = NSApp.mainMenu

// ── 装上真实主菜单 ─────────────────────────────────────────────────────
MainMenu.install()
if NSApp.mainMenu == nil {
    problems.append("MainMenu.install() 之后 NSApp.mainMenu 仍为 nil")
}
print("  ---- 菜单结构 ----")
for line in MainMenu.describe().split(separator: "\n") { print("  " + line) }

// ── 结构断言 ───────────────────────────────────────────────────────────
// 顶级菜单标题：后两项必须是我们给的中文。
// （会命中 "NSMenuItem" 说明用了无参 NSMenuItem() 构造 —— 它不报错，但菜单栏会字面显示类名。）
let topTitles = NSApp.mainMenu?.items.map { $0.title } ?? []
print("  顶级菜单 = \(topTitles)")
if topTitles.contains("NSMenuItem") {
    problems.append("顶级菜单标题是 \"NSMenuItem\" —— 用了无参 NSMenuItem() 构造（title 会变成类名）")
}
for required in ["编辑", "窗口"] where !topTitles.contains(required) {
    problems.append("顶级菜单缺少「\(required)」：实际 \(topTitles)")
}

var menuTitles: [String] = []
if let main = NSApp.mainMenu {
    for item in main.items {
        menuTitles.append(item.title)
        if let sub = item.submenu {
            menuTitles.append(contentsOf: sub.items.filter { !$0.isSeparatorItem }.map { $0.title })
        }
    }
}
let englishLeak = ["Copy", "Paste", "Cut", "Select All", "Undo", "Redo", "Delete",
                   "Edit", "Window", "Minimize", "Zoom", "Close Window"].filter { menuTitles.contains($0) }
if englishLeak.isEmpty {
    print("  ✓ 菜单标题无英文残留（系统默认菜单是英文硬编码，出现过就说明没装我们的菜单）")
} else {
    problems.append("主菜单里仍有英文标题：\(englishLeak)")
}

if let editSub = NSApp.mainMenu?.items.first(where: { $0.title == "编辑" })?.submenu {
    let expected: [(key: String, title: String)] = [
        ("z", "撤销"), ("z", "重做"), ("x", "剪切"), ("c", "拷贝"), ("v", "粘贴"), ("a", "全选"),
    ]
    for e in expected {
        let hit = editSub.items.first { $0.keyEquivalent.lowercased() == e.key && $0.title == e.title }
        if hit == nil { problems.append("「编辑」菜单缺少 ⌘\(e.key.uppercased()) → 「\(e.title)」") }
    }
    if let redo = editSub.items.first(where: { $0.title == "重做" }),
       !redo.keyEquivalentModifierMask.contains(.shift) {
        problems.append("「重做」缺 ⇧ 修饰键，会与「撤销」的 ⌘Z 撞车")
    }
    // 只检查**我们自建的**那些项：AppKit 会自动往「编辑」菜单追加
    // AutoFill / Start Dictation… / Emoji & Symbols，它们自带 target 是正常的。
    let ours = ["撤销", "重做", "剪切", "拷贝", "粘贴", "粘贴并匹配样式", "删除", "全选"]
    let pinned = editSub.items.filter { ours.contains($0.title) && $0.target != nil }.map { $0.title }
    if pinned.isEmpty {
        print("  ✓ 自建的 \(ours.count) 个项均未钉死 target（走响应链）；系统自动追加项已排除在检查外")
    } else {
        problems.append("「编辑」菜单有项被钉死了 target：\(pinned) —— 焦点在输入框时会失效")
    }
} else {
    problems.append("主菜单里没有「编辑」子菜单 —— ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z 会全部失效")
}

// ⌘V / ⌘A / ⌘C / ⌘X / ⌘Z 的**实际分发行为**由 verify/menu/run.sh 验证
// —— 那需要真实 .app 环境（key window + 本地化资源），命令行 harness 测不了。

NSApp.mainMenu = savedMainMenu

// ============================================================================
print()
print("===== 审计结论 =====")
if problems.isEmpty {
    print("✓ 未发现布局或外观问题")
} else {
    for p in problems { print("✗ " + p) }
}
