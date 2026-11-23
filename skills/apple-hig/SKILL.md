---
name: apple-hig
description: Apple 人机界面指南（HIG）的离线镜像与提炼，覆盖 Apple HIG 全站 167 篇主题页原文（基础：布局/材质/字体排印/颜色/图标/图像/深色模式/动效/触感/无障碍/包容性/编写/品牌/RTL；组件：标签页栏/工具栏/列表/按钮/面板/弹窗…；模式：启动/加载/设置/搜索/数据输入/反馈…；技术：小组件/实时活动/通知…；以及 iPhone Duo 与其它平台专属页）。用于：改任何一屏 UI 前确认官方口径；判断某个做法「是我们自创的」还是「Apple 本来就要求这样」；写文案、挑图标、定字号、加动效、做权限请求时找依据；以及给评审/审核准备解释。
license: 内部使用（Codelumi 项目自有）。官方原文版权归 Apple，此处仅作离线查阅与引用。
sources: https://developer.apple.com/cn/design/human-interface-guidelines/ 全部 167 个主题页（2026-11-21 抓取，正文取自 Apple 文档 JSON）；液态玻璃一篇取自 developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
---

# apple-hig

**这是设计规范的「事实来源」，不是意见集合。** `references/` 里每个文件都是 Apple 官方页面正文的逐字镜像
（去脚本、表格转 Markdown，未改写）；`SKILL.md` 只做两件事：**索引**，以及**把规则翻译成本项目的判断**。

> 用法：改 UI 前先看下面「本项目必须守的 12 条」；要原文依据时 `grep` 对应 `references/*.md`。
> 折叠设备（iPhone Duo）的专项做法在 `skills/iphone-duo/`，那一篇是本技能树里唯一带实测探针的一支。

## 什么时候用

- 要改任何一屏 UI、文案、字号、图标、动效、权限请求 —— **先在这里确认口径**；
- 有人（包括我）主张某个做法「Apple 就是这么设计的」时 —— **在 `references/` 里找到原文再说话**；
- 做视觉收口 / 上架前整屏过一遍（配合 `skills/unslop-ios` 去 AI 味）；
- 写 App Review 回复、隐私政策、商店文案时找官方措辞。

## 索引（167 篇，`references/` 全量）

抓取范围：`developer.apple.com/cn/design/human-interface-guidelines/` 全站**所有**主题页
（含组件、模式、输入、技术四类子页，以及 macOS / tvOS / watchOS / visionOS / 游戏等平台专属页）。
平台专属那些本项目不做，留着是为了「别人家的做法别照搬」时能查到原文。

抓取/更新：`python3 tools/fetch-hig.py --missing`（新主题）或 `--all`（全量重抓）。
**原文只替换不改写。**

### 最常用的 20 篇

| 主题 | 文件 | 什么时候翻 |
|---|---|---|
| 布局 | `references/layout.md` | 尺寸分类、安全区、控制与内容分层 |
| 材质 | `references/materials.md` | Liquid Glass 与标准材质怎么选 |
| 字体排印 | `references/typography.md` | 字号/字重/层级、动态字体 |
| 颜色 | `references/color.md` | 语义色、系统色、Liquid Glass 配色 |
| App 图标 | `references/app-icons.md` | 分层设计、四种外观 |
| SF 符号 | `references/sf-symbols.md` | 渲染模式、变体、符号动画 |
| 深色模式 | `references/dark-mode.md` | 语义色与外观切换 |
| 动态效果 | `references/motion.md` | 动效该不该加、能否关闭 |
| 提供触感反馈 | `references/playing-haptics.md` | 何时用系统触感 |
| 隐私 | `references/privacy.md` | 权限请求时机、数据最小化 |
| 编写 | `references/writing.md` | 语气与文案结构 |
| 包容性 | `references/inclusion.md` | 用词、刻板印象、无障碍 |
| 无障碍 | `references/accessibility.md` | VoiceOver、大字号、对比度 |
| 小组件 | `references/widgets.md` | 小组件尺寸/渲染模式/时间线 |
| 实时活动 | `references/live-activities.md` | 实时活动与灵动岛 |
| 通知 | `references/notifications.md` | 通知权限与内容 |
| 标签页栏 | `references/tab-bars.md` | 标签页栏（含侧边竖排） |
| 工具栏 | `references/toolbars.md` | 工具栏与竖排行为 |
| 列表和表格 | `references/lists-and-tables.md` | 列表密度与分组 |
| 按钮 | `references/buttons.md` | 按钮层级与语义 |

### 全部主题（167 篇，按中文标题排序）

| 主题 | 文件 | 字节 |
|---|---|---|
| App 图标 | `references/app-icons.md` | 5,890 |
| App 快捷指令 | `references/app-shortcuts.md` | 3,759 |
| Apple App 内购买 | `references/apple-in-app-purchase.md` | 6,858 |
| Apple Pay | `references/apple-pay.md` | 10,760 |
| Apple Pencil 和随手写 | `references/apple-pencil-and-scribble.md` | 5,146 |
| CarPlay 车载 | `references/carplay.md` | 3,375 |
| CareKit | `references/carekit.md` | 6,076 |
| Game Center | `references/game-center.md` | 6,272 |
| HealthKit | `references/healthkit.md` | 3,656 |
| HomeKit | `references/homekit.md` | 7,971 |
| Mac Catalyst | `references/mac-catalyst.md` | 5,095 |
| NFC | `references/nfc.md` | 1,194 |
| ResearchKit | `references/researchkit.md` | 2,440 |
| SF 符号 | `references/sf-symbols.md` | 6,644 |
| ShazamKit | `references/shazamkit.md` | 869 |
| Siri | `references/siri.md` | 5,323 |
| Tap to Pay on iPhone | `references/tap-to-pay-on-iphone.md` | 5,777 |
| iCloud | `references/icloud.md` | 1,825 |
| iMessage 信息 App 和贴纸 | `references/imessage-apps-and-stickers.md` | 2,275 |
| 上下文菜单 | `references/context-menus.md` | 3,168 |
| 下拉式按钮 | `references/pull-down-buttons.md` | 1,634 |
| 主屏幕快速操作 | `references/home-screen-quick-actions.md` | 1,233 |
| 从右到左 | `references/right-to-left.md` | 3,294 |
| 令牌栏 | `references/token-fields.md` | 903 |
| 仪表 | `references/gauges.md` | 1,255 |
| 体能训练 | `references/workouts.md` | 1,912 |
| 健身圆环 | `references/activity-rings.md` | 2,326 |
| 入门指南 | `references/getting-started.md` | 1,210 |
| 全天候显示 | `references/always-on.md` | 1,729 |
| 全屏显示 | `references/going-full-screen.md` | 2,526 |
| 分栏视图 | `references/column-views.md` | 818 |
| 分段控制 | `references/segmented-controls.md` | 2,070 |
| 切换 | `references/toggles.md` | 2,798 |
| 列表和表格 | `references/lists-and-tables.md` | 2,734 |
| 加载 | `references/loading.md` | 1,423 |
| 动态效果 | `references/motion.md` | 3,049 |
| 包容性 | `references/inclusion.md` | 5,141 |
| 协作和共享 | `references/collaboration-and-sharing.md` | 2,490 |
| 反馈 | `references/feedback.md` | 1,479 |
| 同播共享 | `references/shareplay.md` | 5,834 |
| 启动 | `references/launching.md` | 1,978 |
| 呈现方式 | `references/presentation.md` | 753 |
| 品牌 | `references/branding.md` | 1,561 |
| 图像 | `references/images.md` | 5,160 |
| 图像视图 | `references/image-views.md` | 1,688 |
| 图标 | `references/icons.md` | 4,566 |
| 图表 | `references/charts.md` | 6,317 |
| 地图 | `references/maps.md` | 5,206 |
| 基础 | `references/foundations.md` | 1,774 |
| 增强现实 | `references/augmented-reality.md` | 7,481 |
| 复杂功能 | `references/complications.md` | 10,684 |
| 多任务处理 | `references/multitasking.md` | 2,997 |
| 大纲视图 | `references/outline-views.md` | 1,588 |
| 字体排印 | `references/typography.md` | 9,936 |
| 实况照片 | `references/live-photos.md` | 1,118 |
| 实时活动 | `references/live-activities.md` | 10,187 |
| 将液态玻璃（Liquid Glass）应用到自定义视图 | `references/adopting-liquid-glass.md` | 18,284 |
| 小组件 | `references/widgets.md` | 15,337 |
| 工具栏 | `references/toolbars.md` | 5,282 |
| 布局 | `references/layout.md` | 6,940 |
| 布局和组织 | `references/layout-and-organization.md` | 932 |
| 弹出式按钮 | `references/pop-up-buttons.md` | 1,159 |
| 弹出窗口 | `references/popovers.md` | 1,803 |
| 手势 | `references/gestures.md` | 6,853 |
| 打印 | `references/printing.md` | 1,348 |
| 技术 | `references/technologies.md` | 3,046 |
| 拆分视图 | `references/split-views.md` | 2,655 |
| 拖放 | `references/drag-and-drop.md` | 4,877 |
| 挂饰 | `references/ornaments.md` | 1,358 |
| 指针设备 | `references/pointing-devices.md` | 9,400 |
| 按钮 | `references/buttons.md` | 5,928 |
| 控制 | `references/controls.md` | 2,193 |
| 推荐项目 | `references/top-shelf.md` | 3,515 |
| 提供帮助 | `references/offering-help.md` | 2,510 |
| 提供触感反馈 | `references/playing-haptics.md` | 3,424 |
| 提醒 | `references/alerts.md` | 3,566 |
| 搜索 | `references/searching.md` | 1,985 |
| 搜索栏 | `references/search-fields.md` | 4,482 |
| 摘要卡片 | `references/snippets.md` | 1,557 |
| 撤销和重做 | `references/undo-and-redo.md` | 1,608 |
| 播放视频 | `references/playing-video.md` | 5,294 |
| 播放音频 | `references/playing-audio.md` | 4,735 |
| 操作按钮 | `references/action-button.md` | 1,781 |
| 操作表单 | `references/action-sheets.md` | 1,533 |
| 数据图表化 | `references/charting-data.md` | 2,484 |
| 数据输入 | `references/entering-data.md` | 1,718 |
| 数码旋钮/表冠 | `references/digital-crown.md` | 1,922 |
| 文件管理 | `references/file-management.md` | 4,019 |
| 文本栏 | `references/text-fields.md` | 1,939 |
| 文本视图 | `references/text-views.md` | 1,125 |
| 方框 | `references/boxes.md` | 774 |
| 旁白 | `references/voiceover.md` | 2,304 |
| 无障碍 | `references/accessibility.md` | 6,344 |
| 显示控制 | `references/disclosure-controls.md` | 1,220 |
| 机器学习 | `references/machine-learning.md` | 11,923 |
| 材质 | `references/materials.md` | 4,637 |
| 标签 | `references/labels.md` | 1,672 |
| 标签页栏 | `references/tab-bars.md` | 3,804 |
| 标签页视图 | `references/tab-views.md` | 1,272 |
| 模式 | `references/patterns.md` | 2,291 |
| 模态化 | `references/modality.md` | 2,165 |
| 步进器 | `references/steppers.md` | 691 |
| 沉浸式体验 | `references/immersive-experiences.md` | 5,463 |
| 活动视图 | `references/activity-views.md` | 2,406 |
| 深色模式 | `references/dark-mode.md` | 2,761 |
| 游戏控制 | `references/game-controls.md` | 4,036 |
| 滑块 | `references/sliders.md` | 1,901 |
| 滚动视图 | `references/scroll-views.md` | 4,278 |
| 照片编辑 | `references/photo-editing.md` | 830 |
| 状态栏 | `references/status-bars.md` | 799 |
| 生成式 AI | `references/generative-ai.md` | 5,683 |
| 用户引导 | `references/onboarding.md` | 1,882 |
| 直播观看 App | `references/live-viewing-apps.md` | 2,280 |
| 相机控制 | `references/camera-control.md` | 1,659 |
| 眼睛 | `references/eyes.md` | 3,651 |
| 程序坞菜单 | `references/dock-menus.md` | 843 |
| 空间布局 | `references/spatial-layout.md` | 3,385 |
| 窗口 | `references/windows.md` | 5,609 |
| 管理账户 | `references/managing-accounts.md` | 3,113 |
| 管理通知 | `references/managing-notifications.md` | 2,388 |
| 系统体验 | `references/system-experiences.md` | 973 |
| 组件 | `references/components.md` | 551 |
| 组合框 | `references/combo-boxes.md` | 653 |
| 编写 | `references/writing.md` | 3,514 |
| 编辑菜单 | `references/edit-menus.md` | 2,254 |
| 网页视图 | `references/web-views.md` | 652 |
| 联锁 | `references/lockups.md` | 1,148 |
| 聚焦和选择 | `references/focus-and-selection.md` | 3,965 |
| 菜单 | `references/menus.md` | 5,097 |
| 菜单和操作 | `references/menus-and-actions.md` | 1,124 |
| 菜单栏 | `references/the-menu-bar.md` | 10,149 |
| 虚拟键盘 | `references/virtual-keyboards.md` | 3,408 |
| 表单 | `references/sheets.md` | 3,791 |
| 表盘 | `references/watch-faces.md` | 1,418 |
| 设置 | `references/settings.md` | 2,484 |
| 设计原则 | `references/design-principles.md` | 2,400 |
| 证件校验器 | `references/id-verifier.md` | 1,859 |
| 评分和评论 | `references/ratings-and-reviews.md` | 1,269 |
| 评分指示符 | `references/rating-indicators.md` | 602 |
| 轻 App | `references/app-clips.md` | 10,839 |
| 输入 | `references/inputs.md` | 1,275 |
| 边栏 | `references/sidebars.md` | 2,758 |
| 进度指示符 | `references/progress-indicators.md` | 2,311 |
| 选择和输入 | `references/selection-and-input.md` | 1,003 |
| 选择器 | `references/pickers.md` | 2,121 |
| 通知 | `references/notifications.md` | 4,860 |
| 通过 Apple 登录 | `references/sign-in-with-apple.md` | 6,645 |
| 遥控器 | `references/remotes.md` | 2,307 |
| 针对 Apple tvOS 设计 | `references/designing-for-tvos.md` | 1,246 |
| 针对 iOS 设计 | `references/designing-for-ios.md` | 1,345 |
| 针对 iPadOS 设计 | `references/designing-for-ipados.md` | 1,311 |
| 针对 iPhone Duo 设计 | `references/designing-for-iphone-duo.md` | 6,122 |
| 针对 macOS 设计 | `references/designing-for-macos.md` | 1,583 |
| 针对 visionOS 设计 | `references/designing-for-visionos.md` | 2,782 |
| 针对 watchOS 设计 | `references/designing-for-watchos.md` | 1,647 |
| 针对游戏设计 | `references/designing-for-games.md` | 6,458 |
| 钱包 | `references/wallet.md` | 11,265 |
| 键盘 | `references/keyboards.md` | 8,421 |
| 陀螺仪和加速计 | `references/gyro-and-accelerometer.md` | 848 |
| 附近交互 | `references/nearby-interactions.md` | 2,105 |
| 隐私 | `references/privacy.md` | 5,776 |
| 隔空播放 | `references/airplay.md` | 2,803 |
| 集合 | `references/collections.md` | 863 |
| 面板 | `references/panels.md` | 2,073 |
| 页面控制 | `references/page-controls.md` | 2,722 |
| 颜色 | `references/color.md` | 8,631 |
| 颜色池 | `references/color-wells.md` | 732 |

## 本项目必须守的 12 条

每条都是「官方原话 → 我们的做法」。**违反的会标 ⚠️。**

1. **按尺寸分类布局，不按设备类型或方向。**
   > 「设备的方向和类型（也称为其习惯用法）对布局决策无益，因为它们没有向 App 提供有关可用空间量的信息。」（`layout.md`）
   → 判据只用 `horizontalSizeClass` + 窗口 bounds。`userInterfaceIdiom` 在 Duo 内外屏都是 `.phone`。

2. **遵守安全区。**
   > 「安全区定义了窗口内不会被硬件功能或窗口内其他视图（工具栏、标签页栏、状态栏）遮挡边缘的区域。」（`layout.md`）
   → 内容控件在安全区内；**浮在内容上的自绘控件要自己算**（详见 `iphone-duo/references/pitfalls.md` 第一条）。

3. **控制与内容靠材质/滚动边缘效果分层，不给控制垫底色。**
   > 「与其在控制下方应用纯色或半透明背景颜色，不如使用滚动边缘效果，从视觉上将控制提升至内容之上。」（`layout.md`）
   → 底栏、悬浮按钮一律 `appGlass()`；**不要**再叠 `.bar` 或不透明矩形（首启页踩过：垫材质得到一条白板）。

4. **玻璃/材质只用来分层，不当装饰。**
   > 「Liquid Glass 为控制和导览元素构建了悬浮在内容层上方的独特功能层……允许内容从这些元素下方滚动和透视出来。」（`materials.md`）
   → 卡片不加左侧竖条、不加无意义描边；层次由品牌色淡染（`cardTintOpacity = 0.06`）+ 发丝描边 + 圆角表达。

5. **字号只用系统文本样式的档位，靠字重和颜色表达层级。**
   > 「尽量减少字样的使用数量……使用大多数用户都可轻松阅读的字号。」（`typography.md`）
   → `AppTheme.TypeScale` 六档 × 全局 `FontScale`，不写 `.system(size: 11.5)`。

6. **少让人打字。**
   > 「尽可能从系统获取信息。不要让用户输入你可以自动收集……的信息。」（`entering-data.md`）
   → 这就是「粘贴短信 / 拍照识别 / 快捷指令自动化」三条入口的依据；手动输入是兜底，不是主路径。

7. **加载要立刻有东西看，别让用户对着空白。**
   > 「尽快显示内容……考虑随内容加载显示占位符文本、图形或动画。」（`loading.md`）
   → 列表首帧就给本机数据（我们不联网，所以基本恒为 0 延迟）；解析/OCR 期间给进度，不给转圈干等。

8. **启动即用，不要启动画面拖时间。**
   > 「立即启动。用户希望可立即开始与 App 或游戏交互，有时甚至几秒钟都不想等待。」（`launching.md`）
   → 首启只有一次同意页 + 三页速览，之后冷启动直奔列表。

9. **设置里只放「不常改的东西」，任务级选项留在现场。**
   > 「如果可能，首选让用户无需前往设置区域，即可修改任务特定的选项。」（`settings.md`）
   → 排序、筛选、显示哪些字段，都在列表/面板现场；设置页只放全局偏好。（用户 2026-11-14 也要求过同一件事。）

10. **权限只在你真正需要的那一刻、只请求需要的那一项。**
    > 「仅请求访问你实际需要的数据……在用户对功能表示感兴趣前请求数据，会让用户很难信任你的 App。」（`privacy.md`）
    → 位置权限只在用户打开「到达提醒」并选中驿站时才请求；通知只在开启提醒时请求。

11. **反馈走多条通道，别只靠颜色。**
    > 「确保所有反馈都可访问……颜色、文本、声音和触感反馈。」（`feedback.md`）
    → 「已取 / 待取」不只是换色，还有勾选态、图标、文字。

12. **文案有目的、说人话、第一人称克制。**
    > 「务必注重行动。主动语态和清晰的标签可帮助……」/「使用平实易懂、具有包容性的语言。」（`writing.md`、`inclusion.md`）
    → 行标题不带前缀、不写解释性脚注（用户 2026-11-20 的硬口径与本条一致）。

## 有意识的偏离（不打算改的）

官方口径与我们现有的、用户明确要的做法相冲突的地方，**记录在案，别反复重开**：

| 项 | 官方口径 | 我们的做法 | 依据 |
|---|---|---|---|
| App 内提供「外观」三档 | 「避免提供 App 特定的外观设置」(`dark-mode.md`) | 有（自动/浅色/深色） | 用户 2026-11-04 明确要求，且默认「自动」跟随系统 |
| App 内提供字号滑块 | 应主要依赖系统动态字体 (`typography.md`) | 有（7 档 + 「跟随系统」开关） | 同上；「跟随系统」是默认值，偏离幅度可控 |
| 不显示 App 备案号 | — | `PageFooter` 只显示版本号 | 单机不联网 App 走苹果豁免，见 `AGENTS.md` |

## 与本项目其它文档的关系

- **`AGENTS.md`** —— 硬规则（构建、标识、权益、图标、端侧 AI 口径）。冲突时以它为执行口径，本技能解释「为什么」。
- **`skills/iphone-duo/`** —— 折叠设备的实现细节 + 实测探针；本技能里的 `designing-for-iphone-duo.md` 是它的原文底稿。
- **`skills/unslop-ios/`** —— 把「一眼 AI」的界面改回去；收口流程在本技能之后跑。
- **`交接说明_dsh.md`** —— 每次改动的事故记录与决策沿革。

## 怎么维护

- 官方页面更新后：重跑抓取（见 `交接说明_dsh.md` §26 的命令），只替换对应 `references/*.md`，**不要手改原文**。
- 「12 条」只有在**新踩坑**或**口径变化**时才动，并同步 `AGENTS.md`。
- 发现某条规则我们做不到（技术限制/产品取舍）：写进上面「有意识的偏离」表，别留在脑子里。
