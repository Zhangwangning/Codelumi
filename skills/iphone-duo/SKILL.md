---
name: iphone-duo
description: iPhone Duo（折叠 iPhone）适配的完整做法。用于：App 在 Duo 上出现「看得见点不动 / 布局被拉宽 / 控件压在摄像头或折痕上 / 分栏与单列乱跳 / 侧边竖排标签栏行为不对」；要给一块界面做「外屏 compact / 内屏 regular / 横竖 / 折叠态」四态适配；或者要在没有真机的情况下用模拟器 + 探针取证。按 尺寸判定 → 系统容器 → 保留区 → 垂直控制 → 排列视图 → 验收 的次序做，每一步都给出可执行命令与判据。
license: 内部使用（Codelumi 项目自有）
sources: Apple HIG《针对 iPhone Duo 设计》(2026-09-09) + HIG《布局》(2026-09-09) + 《Preparing your app for iPhone Duo》 + 本项目 2026-11 的模拟器实测
---

# iphone-duo

iPhone Duo 不是「又一个屏幕尺寸」，它是**两块屏 + 一个会变形的折痕**。
绝大多数事故都来自同一个错误：**把某一种姿态当成默认，然后用固定尺寸/自绘控件去凑它。**

正确的路径几乎总是反过来的：**只喂系统容器，让系统去变形**；我们只负责在系统变不了的那几处（保留区、折痕、自定义面板）补一刀。

> 官方原话（HIG）：*「如果你使用标准系统组件，且在设计时已考虑到支持调整大小，则无需进行太多调整，就能自动适配设备的各种姿态。」*
> 换句人话：**Duo 上真正需要写代码的地方很少，写多了就是 bug 来源。**（本项目吃过两次大亏，见 `references/pitfalls.md`）

> 本篇只讲**折叠设备**的专项做法。iOS 全量设计规范（布局/材质/字体排印/图标/隐私/编写…）
> 在 `skills/apple-hig/`，其中 `references/designing-for-iphone-duo.md` 是本文的官方底稿。

## 什么时候用这个 skill

- App / 某个页面在 Duo 外屏、内屏竖屏、内屏横屏里**任一姿态**出现异常；
- 要做分栏、双列、面板、悬浮控件，需要判断「该交给系统还是自己画」；
- 控件被前置相机、状态栏、折痕压住，或**看起来在那里但点不动**；
- 要拍板「这个界面在 regular 宽度下显示什么」，又不想为 Duo 单独写一套布局；
- 没有真机，需要**用模拟器 + 探针拿到证据**再改。

## 三条铁律

1. **按几何判据，不按机型。** 不要 `userInterfaceIdiom`、不要机型名、不要 `UIScreen.main`。
   Apple 明确禁止用 `userInterfaceIdiom` / `UIInterfaceOrientation` 做布局判断。
   本项目用的判据是「窗口 bounds + size class」，见 `references/poses.md`。
2. **系统能做的绝不自己画。** 标签栏、工具栏、导航栏、分栏、sheet、上下文菜单、排列视图 —— 全走系统组件。
   自己用 `UITabBar` / `UIToolbar` 复制一份，等于放弃了系统对四态与保留区的全部适配。
3. **改布局只做「小幅调整」。** HIG：*「当用户折叠设备时，应避免极端的布局变化。仅移动必要的元素……突然消失或大幅移位的控制更难查找和追踪。」*
   折叠态优先「同一套布局被压缩」，而不是「换成另一套布局」。

## 布局基线（HIG《布局》，2026-11-21 补）

Duo 不是特例 —— 它只是把《布局》里几条常年被忽略的规则**放大到看得见**。原文见
`references/hig-layout.md`，这里是能直接落到代码的六条：

1. **按尺寸分类定布局，不按设备类型或方向。**
   官方原话：「设备的方向和类型（也称为其习惯用法）对布局决策无益，因为它们没有向 App
   提供有关可用空间量的信息。」→ 判据只用 `horizontalSizeClass` + 窗口 bounds。
2. **遵守安全区**，因为「安全区定义了窗口内不会被硬件功能或窗口内其他视图（工具栏、
   标签页栏、状态栏）遮挡的边缘」。→ 内容控件永远在安全区内；**浮在内容上的自绘控件要自己算**。
3. **控制与内容分离靠材质与滚动边缘效果，不靠给控制垫一块底色。**
   官方：「与其在控制下方应用纯色或半透明背景颜色，不如使用滚动边缘效果」。
   → 底栏/悬浮按钮用 `appGlass()`，**不要**再垫一层 `.bar` 或用不透明矩形（本项目踩过：
   首启页底栏垫材质得到一条突兀白板）。
4. **全屏背景内容要延伸到边栏、工具栏、标签页栏下方**，而不是被它们截断。
   → 背景图 `.ignoresSafeArea()`；但上面的**可点元素**不能跟着进去。
5. **尺寸分类变大时允许「显示多少」，不允许「改变功能」。**
   官方举例：空间变大可以「从标签页栏切换到边栏」。→ 这就是我们在 Duo 内屏横屏
   换底部栏 / iPad 用 `NavigationSplitView` 的依据；但功能集合必须一致。
6. **提前应对动态字体**：水平相邻的视图可能要竖直叠放、行高要能长高。
   → 本项目有全局 `FontScale` + `TypeScale`，别写死行高。

⚠️ 还有一条常被误用的：`userInterfaceIdiom` 在 Duo 上**内外屏都是 `.phone`**，
拿它判「该不该分栏」必然错。

## 开工前：把四态列出来

任何一次改版，先写下这四行再动手（缺一行就会在真机上翻车）：

| 姿态 | 典型几何 | size class | 本项目的期望 |
|---|---|---|---|
| 外屏（折叠） | 466×678 | compact | 单列，底部标签栏 |
| 内屏 · 竖屏 | 669×951 | regular | 单列（本项目故意不分栏：两栏各 330pt 会挤成一团） |
| 内屏 · 横屏 | 951×669 | regular | 分栏（列表 + 详情），**侧边/底部控制都不许进保留区** |
| 部分折叠 | 折痕把内屏切两半 | regular | 只做小幅位移，不重排 |

几何真值以**实测**为准，别抄本文档：`references/poses.md` 给了取数命令。

## 流程

### 1) 先取证，再判断

```bash
# 外屏（折叠态）
xcrun simctl io <UDID> screenshot --display=1 /tmp/duo-outer.png
# 内屏（展开态；设备已展开时直接给横向 2853×2007）
xcrun simctl io <UDID> screenshot --display=3 /tmp/duo-inner.png
```

- `--display=` **必须写在 `screenshot` 之后**，写在前面报 `Invalid argument`。
- `simctl` **没有** fold/unfold/rotate 命令；`screenConfig ... geometry` 会报 `No mode found`，别试。
- 展开/折叠只能在 Simulator（本机是 DeviceHub）里手动切；CLI 侧只能用 `--display=3` 拍结果。

### 2) 判定当前姿态

只读**窗口**，不读屏幕：

```swift
// 窗口尺寸（多窗口 / 投屏 / Duo 折叠都会变，UIScreen.main 会取错）
let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
let size = window?.bounds.size ?? .zero
```

判据（本项目 `PadLayout`，两行就够）：

```swift
// 内屏横屏：最短边 > 600 且 宽 > 高
min(size.width, size.height) > 600 && size.width > size.height
```

理由：直板机横屏 874×402（最短边 402）、外屏 678×466（466）、内屏竖屏 669×951（宽 < 高）都不命中；
只有内屏横屏 951×669 命中。**任何时候都别加"机型名"作为条件。**

### 3) 系统容器优先

| 你要的东西 | 用什么 | 不要用什么 |
|---|---|---|
| 列表 → 详情 | `NavigationSplitView` / `UISplitViewController` | 手写 HStack 两列 + 自己管选中 |
| 一级导航 | `TabView`（系统标签栏） | 自绘底栏复制一份标签栏 |
| 工具栏 / 导航按钮 | `.toolbar { ToolbarItem }` | 自绘顶栏 |
| 主从两视图按规则排布 | `ArrangementView`（iOS 27.1+） | 一堆 `if 宽 > 高` 分支 |
| 画面被折痕/相机挡住 | `ReservedRegion` 查询后偏移 | 写死 84pt（本项目早期犯过） |

**系统会自动做**（无需写代码）：外屏/内屏切换、横竖布局重排、标签栏与工具栏在侧边竖排、
sheet 避让折痕、分屏浏览在宽屏展开、上下文菜单/提醒随折叠移动。

**系统不会做**（必须你自己处理）：自绘面板与浮层的边缘让位、自定义控件在保留区里的可点性、
折痕把一块内容拦腰切断时的分列、以及「看起来在屏幕上但收不到触摸」的一切。

### 4) 处理保留区（`ReservedRegion`）

保留区有两类，不要把两者混为一谈：

- **occlusion（遮挡）**：前置相机。外屏**始终**存在且与灵动岛相连；内屏相机藏屏下、**启用时才显现**。
- **division（分割）**：折痕。**部分折叠**时把内屏切成两块可用区域；完全展开/折叠时**不生效**。

```swift
GeometryReader { proxy in
    let occlusions = proxy.reservedRegions(kind: .occlusion)   // iOS 27.1+
    let divisions  = proxy.reservedRegions(kind: .division)
    // region.frame / region.margins / region.isActive
}
```

- 每个 region 有 `isActive`：**不 active 的不要用它偏移布局**（折痕常驻会让完全展开态也缺一块）。
- UIKit 侧：`view.reservedRegionsOfKind:options:`（`UIViewReservedRegion`）。
- 系统组件已经处理了保留区；**只有自绘内容需要自己查**。

### 5) 垂直控制（bars 在侧边）

Duo 会把工具栏/标签页栏/导览控制**竖排到侧边**（外屏始终；内屏横屏也保持）——
这是**设计意图**，不是 bug。要做的是「让系统排好 + 按优先级取舍」：

- 位置语义：竖直轴**顶部**留给主导航（返回/关闭），随后是醒目操作（完成）。
  其余项目保持分组。SwiftUI：`ToolbarItemPlacement`、`topBarPinnedTrailing`、`cancellationAction`。
- 分组而不是加间距：`ToolbarItemGroup`（自动提供组间距）。
- 溢出取舍：`visibilityPriority(_:)`；想直接塞进溢出菜单用 `ToolbarOverflowMenu`。
- 只要图标、不要文字的项，**同时给图标和标题**：系统竖排时用图标、横排时优先图标、溢出菜单里图标+标题。
  ⚠️ **只有标题没有图标 = 系统不会把它竖排**；**自定义视图**同理。
- 想知道当前是不是竖排：`@Environment(\.toolbarVerticalEdge)` / UIKit `verticalBarEdge` trait。
- 想**禁止**竖排（如某些 sheet）：`toolbarVerticalBehavior(.disabled)`（iOS 27.1+）/ `preferredVerticalBarBehavior`。
- 背景图想延伸到竖排栏下面：`backgroundExtensionEffect()`。
- 压缩策略：`ToolbarVerticalCompressionBehavior`（任务导向 → 压缩标签栏；导航导向 → 压缩工具栏）。

### 6) 排列视图（`ArrangementView`，iOS 27.1+）

只在你**本来就是「主 + 从」两块内容**时用；不要把它塞进 split view / list / scroll view。

```swift
ArrangementView {
    PrimaryView()          // 主
} secondary: {
    SecondaryView()        // 从
}
.arrangementViewStyle(.split)                       // HStack/VStack 场景
// .arrangementViewStyle(.overlay)                  // ZStack 场景
// .arrangementViewStyle(.split.axes(.horizontal))   // 限定只在横向分
```

- `.split`：宽 > 高时左右分，高 > 宽时上下分；分不出时只显示一个。
- `.overlay`：正常时主视图压住从视图；**部分折叠时**两者分别落到折痕两侧。
- 导览（导航容器）要放在 `ArrangementView` **外面**，不要嵌套。

### 7) 折叠时：只做小幅调整

- 优先「容器宽度变了，内容自己重排」（`LazyVGrid` 用**偶数列**，折叠后能对半分）。
- 必需元素被折痕切到时，用 `division` 保留区把**那一个元素**挪开，不要整页换布局。
- 不要因为折叠就隐藏控件；宁可换位置。

### 8) 验收（没有真机也要有证据）

1. **四态截图**：外屏 / 内屏竖 / 内屏横 / （能切的话）部分折叠。
2. **可点性**：对**每一个浮在内容上方的控制**，跑一次命中测试探针（模板见 `references/pitfalls.md`），
   确认点击点返回的是**这个控件**，而不是它背后的内容。**「看得见」不等于「点得到」。**
3. **直板机回归**：Duo 的改动不得影响 iPhone 16 Pro 之类（本项目 `AGENTS.md` 的硬规则）。
4. 构建 0 warning。

## 快速判断表（出了问题先查这里）

| 现象 | 最可能的原因 | 处置 |
|---|---|---|
| 控件看得见、点不动 | 控件落在 occlusion 保留区，触摸被系统吞掉 | 移出保留区 / 改由系统栏承载 |
| 竖排标签栏点了没反应 | 同上（本项目真实事故） | 同上；见 `pitfalls.md` |
| 折叠后内容被拦腰切断 | 没处理 `division` 保留区 | 查 division，把关键内容挪开或改偶数列 |
| 展开后反而少了一块 | 用了 `isActive == false` 的 region | 只在 active 时偏移 |
| 布局在 Duo 上被拉宽成一列巨宽 | 没在 regular 宽度用分栏/双列 | `NavigationSplitView` 或双列 |
| 页面在两种屏之间「跳变」 | 按屏写了两套布局 | 收敛成一套 + 尺寸适配 |
| 自绘面板上下留白不对 | 用了 `GeometryReader` 但外面 `ignoresSafeArea` | 从**窗口**读尺寸，再自己补四边 |

## 交付前 checklist

- [ ] 四态都截了图，且**没有一态是空白/半截**；
- [ ] 所有浮层控制的命中测试通过（不是「看起来对」）；
- [ ] 判定逻辑只依赖窗口几何 + size class，没有机型/idiom/方向分支；
- [ ] 没有任何地方读 `UIScreen.main`；
- [ ] 没有自绘的标签栏/工具栏/导航栏（除了系统明确不管的场景，且已记录理由）；
- [ ] 保留区查询只用 active 的 region，且没用写死像素；
- [ ] 直板机 + Duo 外屏回归通过；
- [ ] `xcodebuild` 0 warning。

## 仓库内另外两份 Duo 文档（分工别搞混）

| 文档 | 定位 | 冲突时 |
|---|---|---|
| `iPhone Duo 官方设计规范笔记_v1.md` | Apple 三场 Tech Talks 逐字整理 | **以它为准** |
| `iPhone Duo 折叠屏开发实战笔记_v1.md` | 代码里实际怎么做的、踩过什么坑、怎么验（对应 321） | 事实层，可与本文互补 |
| `references/*.md`（本技能包） | 提炼后的判据、API、坑 | 与本技能包冲突时以官方那篇为准 |

## 参考文件

- `references/api.md` —— 全部相关 API 的**签名、可用性（iOS 27.1 起居多）、最小可用示例**。
- `references/poses.md` —— 几何真值、判据推导、模拟器取数与截图命令、探针的两种写法。
- `references/pitfalls.md` —— 本项目踩过的坑（含「系统标签栏被摆进保留区」的完整证据链，
  以及第 8 条：展开态系统报告 `reservedRegions` 为空、`safeAreaInsets.right` 却仍是 84）。
- `references/hig-layout.md` —— HIG《布局》页面原文（尺寸分类 / 安全区 / 控制与内容 / Liquid Glass
  滚动边缘效果 / 平台考量），上面「布局基线」六条都出自这里。
