# 官方开发者指南：Preparing your app for iPhone Duo（中文要点 + API 对照）

- 来源：https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo
- 抓取：2026-11-21
- 说明：**这是要点整理 + 原文关键句**，不是逐句翻译；API 名称与可用性已对 `iPhoneOS27.2.sdk` 核对。

## 总览（原文要点）

- Duo = 紧凑外屏 + 大内屏；两块屏都有前置相机，**内屏相机不用时不可见**。
- 开合、部分折叠、旋转时，内容在两种屏之间迁移并按折痕调整。
- 如果 App 已经能适配 iPad / Mac / iPhone 镜像的重 sizing，基本就走对路了。
- **用 Xcode 26 及更早构建的包，不会延伸到状态栏与相机下方** —— 必须 Xcode 27+。

## 布局与 sizing 的硬要求

原文四条，按重要性：

1. **优先系统容器**：split view、tab bar、arrangement view、navigation stack —— 它们自己处理
   外屏 / 完全展开 / 折叠 / 相机遮挡。
2. **按容器算尺寸，不按 iPhone 固定尺寸**；用 scene 或父视图的 bounds，
   **不要用屏幕尺寸**。
3. UIKit 用 Auto Layout。
4. **自动跟踪 trait**（`horizontalSizeClass` / `verticalSizeClass`）；
   **不要用 `userInterfaceIdiom` 或 `UIInterfaceOrientation` 做布局判断**。

## 垂直（侧边）栏

- 外屏（折叠）时系统把导航栏 / 工具栏 / 标签栏竖排到侧边；内屏横屏时仍保留在侧边，
  以维持一致的垂直高度。
- 前提是**用容器提供的栏支持**：SwiftUI 用 `.toolbar(content:)` 挂在 `NavigationStack` /
  `NavigationSplitView` 上；UIKit 把 toolbar items 设在 `UINavigationController` 里的 VC 上，
  **不要**自己用 `UIToolbar` / `UINavigationBar` / `UITabBar` 造一条。
- 例外：inspector 里是横排；split view 里侧栏/内容视图横排、**详情视图竖排**；
  sheet 在外屏默认竖排（可用 `toolbarVerticalBehavior(.disabled)` / `preferredVerticalBarBehavior` 关掉）。
- 自定义视图想知道是不是竖排：`toolbarVerticalEdge`（SwiftUI）/ `verticalBarEdge`（UIKit）。

## 栏内项目组织

- 竖直轴顶部：主返回/关闭（`cancellationAction` / `leadingItemGroups`），随后醒目操作
  （`topBarPinnedTrailing` / `pinnedTrailingGroup`）。
- 分组用 `ToolbarItemGroup` / `UIBarButtonItemGroup`，**不要自己加固定间距**。
- 取舍顺序：`visibilityPriority(_:)`；直接进溢出菜单：`ToolbarOverflowMenu` / `additionalOverflowItems`。
- **图标 + 标题都要给**：竖排用图标、横排优先图标、溢出菜单图标 + 标题。
  - 只有标题没有图标 → **不竖排**；
  - 自定义 view 而不是 title/icon → **不竖排**。

## 排列视图（ArrangementView / UIArrangementViewController）

- 两种样式：**split**（宽 > 高横分，否则上下分）与 **overlay**（正常叠放，部分折叠时按折痕分到两侧）。
- 都可限定轴（只想在横向分时用）。
- **不要**把 arrangement view 放进 navigation split view / list / scroll view 等容器 ——
  官方点名会让部分视图不可达。

## 保留区（Reserved Region）

- **division**：折痕把大视图切成两块可用区域；**部分折叠时 active，完全展开时 inactive**。
- **occlusion**：硬件遮挡。内屏前置相机**启用时**才挡；外屏前置相机**始终**挡。
- SwiftUI：`GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` → `[ReservedRegion]`；
  UIKit：`view.reservedRegionsOfKind:options:` → `[UIViewReservedRegion]`。
- 每个 region 有 `frame` / `margins` / `isActive`；**只在 active 时偏移**。

## 相机

- Duo 三路相机：外屏前置、内屏前置（屏下）、后置；折叠/展开/旋转会改变所在屏与朝向。
- 完全展开用后置拍摄时，可同时在**外屏**显示内容（`Registering a camera capture accessory on iPhone Duo`）。

## 与本项目的关系

- 我们**没有**自绘取景器（拍照走系统 `UIImagePickerController`），相机部分零改动。
- 我们的分栏用 `NavigationSplitView`，标签栏是系统 `TabView`（Duo 内屏横屏例外：
  系统栏被摆进保留区，改自绘底部栏，见 `pitfalls.md` 第 1 条）。
- 「不要用 idiom / 方向」这条我们在 `AGENTS.md` 之前记反过一次（把侧边竖排当 bug），已撤回。

---

## 精读四篇官方文档后的内屏开发口径（2026-11-21）

来源（正文均取自 Apple 文档 JSON，`curl` 直取，见 `AGENTS.md`）：

- `documentation/technologyoverviews/preparing-your-app-for-iphone-duo`（14,435 字符，本篇最全）
- `documentation/technologyoverviews/interface-fundamentals`（7,735 字符）
- `documentation/technologyoverviews/adopting-liquid-glass`（23,684 字符，讲栏的玻璃与取样）
- `design/human-interface-guidelines/designing-for-iphone-duo`（见 `hig-designing-for-iphone-duo.md`）

### 1. 侧边竖排是「设计结果」，不是 bug

> "iPhone Duo presents navigation bars, toolbars, and tab bars together vertically on the
> side of the display in some poses." · "This happens on the outer display when the device
> is closed, and for some views in the leading or trailing position on the inner display
> when the device is open."

- 外屏（折叠态）：栏竖排。
- 内屏（展开）：**分栏里 detail 一侧的栏竖排**，sidebar / content 一侧保持水平。
- 例外：内屏**竖屏**时垂直空间够，用标准水平栏（与 HIG 一致）。

### 2. 用系统容器，遮挡由系统让

> "Prefer system-provided layouts and containers, such as split views, tab bars,
> arrangement views, and navigation stacks. These handle resizing, automatically
> adjusting for the outer display, fully open or folded inner display, and camera occlusions."

所以：**不要为了躲遮挡自己做布局**，用 `TabView` / `NavigationSplitView` / `ArrangementView` /
`NavigationStack`；`NavigationStack` / `NavigationSplitView` + `.toolbar(content:)` 才会拿到系统栏，
自定义 `UIToolbar` / `UINavigationBar` / `UITabBar` 反而不会被系统竖排。

### 3. 内屏专用 API（全部对本机 iPhoneOS27.2.sdk 核过）

| API | 可用性 | 用途 |
|---|---|---|
| `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` | `anyAppleOS 27.1` | 拿保留区 frame，`.occlusion` / `.division` |
| `ArrangementView(primary:secondary:)` | `anyAppleOS 27.1` | 主/辅视图按折叠姿态自动排（split / overlay 两种 style） |
| `EnvironmentValues.toolbarVerticalEdge` | `anyAppleOS 27.1` | 运行期知道栏是不是竖排了（`HorizontalEdge?`） |
| `View.toolbarVerticalBehavior(_:)` | `anyAppleOS 27.1` | 关掉竖排（如想强制水平） |
| `View.toolbarVerticalCompressionBehavior(_:)` | `anyAppleOS 27.1` | 竖排栏「最小化/压缩」行为 |
| `ToolbarContent.axisBehavior(_:)` / `visibilityPriority(_:)` / `ToolbarOverflowMenu` | iOS 27 系列 | 竖排栏放不下时的取舍与溢出菜单 |
| `View.backgroundExtensionEffect()` | `iOS 26.0` | 让主图/底图延伸到竖排栏下面（栏是玻璃，取样背后内容） |
| `View.presentationPlacement(_:)` | `anyAppleOS 27.0` | sheet 在内屏放哪（居中/前缘/后缘，决定栏水平还是竖排） |

### 4. 三条容易忽略的硬要求

1. **必须用 Xcode 26 及以上构建**，否则 App 不会延伸到状态栏与相机下面：
   > "When you build with Xcode 26 and earlier, your app doesn't extend under the status bar and camera."
2. **导航容器放在排列视图外面**：`ArrangementView` 只排内容，不处理导航。
3. **折叠时只做小幅调整**：HIG「避免极端的布局变化，仅移动必要元素」。

### 5. 对 Codelumi 的落点

- 内屏横屏 = `TabView`（系统栏竖排在 detail 侧）+ 每个 tab 内 `NavigationSplitView`；
  **不要再给 TabView 叠人工 chrome**（`PadTabChrome` / `AdaptiveTabBarStyle` /
  `PushTrailingSafeArea` / `tabBarMinimizeBehavior` 都已在这条路径上关掉）。
- 部分折叠（半折）将来若要做「上下分屏」，用 `ArrangementView(.split.axes(.vertical))`，
  而不是自己判折叠角度。
- 想让详情页大图延伸到竖排栏下，用 `backgroundExtensionEffect()`，不要自己铺色块。
