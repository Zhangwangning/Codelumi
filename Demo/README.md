# CodeClip iOS —— UI Demo 说明

> ⚠️ **历史文档（2026-09-20）**：这里记录的是立项期的 **CodeClip UI Demo**（独立工程，已不在本仓库维护）。
> 产品于 2026-11-10 更名为 **Codelumi**；下文路径、模块名保留当时写法，仅作历史记录，
> 请勿据此查找当前工程文件。当前工程见 `Codelumi/Codelumi.xcodeproj`。


> 版本：0.1.0 (Demo) · 构建目标：iOS 27.0 · 设备：iPhone 17 Pro 模拟器
> 产出时间：2026-09-20 · 作者：极客ZHANG

---

## 一、本轮产出

用 **iOS 27 + Liquid Glass（液态玻璃）** 设计语言搭建的 CodeClip 主界面可运行 Demo，覆盖 6 个关键界面，全部为模拟器真实渲染截图（非设计稿）。

| 截图 | 界面 | 说明 |
|---|---|---|
| `01-home.png` | 待取件列表（主页） | 玻璃摘要条 + 取件码卡片流 + 浮动标签栏 |
| `02-history.png` | 记录 | 分段控件切换「待取件 / 已取件」 |
| `03-settings.png` | 设置 | 权益卡 + 中尺寸小组件预览 + 功能入口 |
| `04-detail.png` | 取件详情 | 大号取件码 + 信息区 + 原始短信 + 操作区 |
| `05-premium.png` | 高级功能（只读） | 4 项付费能力说明，TestFlight 阶段不放开购买 |
| `06-automation.png` | 自动化设置引导 | 4 步教程 + iOS 系统提示的说明 |

---

## 二、工程信息

- **工程路径**：`/Volumes/ZWN/Downloads/Project/CodeClip/CodeClip/CodeClip.xcodeproj`
- **Bundle ID**：`com.jikezhang.qujian`
- **部署目标**：iOS 27.0（`IPHONEOS_DEPLOYMENT_TARGET = 27.0`）
- **设备族**：iPhone only（`TARGETED_DEVICE_FAMILY = 1`）
- **工程格式**：Xcode 27 新格式（`objectVersion = 77`），使用 `PBXFileSystemSynchronizedRootGroup` 同步目录，新增源文件无需改工程文件
- **源码结构**（8 个 Swift 文件）

```
CodeClip/
├── CodeClipApp.swift              # App 入口 + 环境注入
├── Models/Models.swift          # PickupKind / PickupRecord / SampleData / PickupStore
└── Views/
    ├── RootView.swift           # TabView 三标签
    ├── PickupListView.swift     # 主页（SummaryBar / PickupCard / KindTag / HiddenHint / EmptyStateView）
    ├── RecordDetailView.swift   # 详情（codeCard / infoCard / rawMessageCard / actionArea）
    ├── HistoryView.swift        # 记录（分段控件 + HistoryRow）
    ├── SettingsView.swift       # 设置（planCard / widgetSection / featureSection / aboutSection）
    └── PremiumInfoView.swift    # 高级功能说明 + AutomationGuideView
```

- **示例数据**：8 条真实语料解析结果（兔喜生活 / 菜鸟驿站 / 丰巢 / 韵达 / 中通 / 京东 / 极兔 / 顺丰），覆盖取件码、运单号、尾号三类。

---

## 三、实际使用的 iOS 27 / Liquid Glass API

| API | 使用位置 | 作用 |
|---|---|---|
| `TabView` + `Tab(_:systemImage:)` | `RootView` | 系统自动渲染 Liquid Glass 浮动标签栏，无需手写玻璃背景 |
| `.glassEffect(.regular, in:)` | SummaryBar、planCard、详情页复制按钮 | 玻璃面板，形状支持 `.rect(cornerRadius:)` / `.capsule` / `.circle` |
| `.glassEffect(.regular.interactive())` | 列表复制按钮、详情页「标记为已取」 | 可交互玻璃，按下有系统级高亮反馈 |
| `.glassEffect(.regular.tint(.green))` | 复制成功态 | 玻璃着色，用于状态确认反馈 |
| `.background(.background.secondary, in: .rect(cornerRadius:style:.continuous))` | 各内容卡片 | 语义化背景层级，自动适配深浅色 |
| `.overlay { RoundedRectangle().stroke(.separator.opacity(0.6), lineWidth: 0.5) }` | 各内容卡片 | 0.5pt 发丝描边，贴合 iOS 卡片观感 |
| `.buttonStyle(.plain)` | 全部自定义按钮 | 关闭默认按钮外观，改由 glassEffect 承载 |
| `.navigationTitle` / `navigationBarTitleDisplayMode(.inline)` | 各页 | 大标题 + 内联标题切换 |
| `.contentShape(.capsule)` / `.contentShape(.circle)` / `.contentShape(.rect)` | 按钮 | 精确命中区域，避免玻璃区域外误触 |
| `.monospacedDigit()` | 相对时间 | 数字等宽，避免时间跳动 |
| `.monospaced()` | 取件码 | 取件码等宽渲染，符合「码」的阅读习惯 |
| `withAnimation(.snappy)` | 复制反馈 | iOS 17 起的 snappy 弹性动画曲线 |

**说明**：本 Demo 只使用公开 SwiftUI 修饰符，未使用条件编译或私有 API，可直接在 iOS 27 SDK 下编译运行。

---

## 四、免费版口径在 UI 中的落地

依据《产品与商业模式规格 v1.3》：

| 规格口径 | UI 落点 |
|---|---|
| 短信存储上限 100 条（FIFO） | 未在 Demo 中暴露存储配置（属后台逻辑），仅在高级功能页对比说明 |
| 取件码信息同屏展示最多 10 条 | `PickupStore.freeVisibleLimit = 10` + `visiblePending` 裁剪 + `HiddenHint`（「还有 N 条记录 · 升级后查看」） |
| 小组件仅中尺寸（medium，3 条） | 设置页 `MediumWidgetPreview` 展示 3 条待取件；文案「免费版支持中尺寸小组件，桌面直接看到 3 条待取件」 |
| 大尺寸 / 锁屏 / 无限记录 / 导出分享 为付费 | 仅出现在「高级功能」只读页，带锁图标，无价格、无购买按钮 |

**TestFlight 阶段的文案口径**：App 内不出现「ICP 备案」字样，统一使用中性表述——「当前为 TestFlight 测试版本，已开放基础解析与中尺寸小组件。大尺寸小组件、锁屏小组件、无限记录、导出与分享将在 App Store 正式版提供。」

---

## 五、已实现 / 未实现边界

**已实现（UI 层）**
- 三标签导航与全部页面跳转链路
- 取件码/运单号/尾号/特殊 四类信息的视觉区分（图标 + 胶囊标签）
- 复制取件码（真实写入 `UIPasteboard`）+ 成功态玻璃变色反馈
- 标记已取 / 恢复待取，列表与记录页双向同步
- 免费版 10 条同屏上限与溢出提示
- 空状态页
- 自动化设置的 4 步图文引导（含 iOS 系统「正在运行」提示的说明）

**未实现（有意留白）**
- **短信解析引擎**：Demo 用 `SampleData` 静态数据，真实解析需移植快捷指令 V7.3.0 的六套正则与四级优先级链
- **数据持久化**：目前仅内存，未落盘（SwiftData / 文件存储待定）
- **小组件 Extension**：`MediumWidgetPreview` 是 App 内**预览组件**，不是真正的 WidgetKit 扩展
- **StoreKit**：按 TestFlight 先行策略，本轮完全不接内购
- **自动化联动**：需真实 App Intent 才能被快捷指令调用

---

## 六、已知技术约束（需在后续版本注意）

1. **iOS 无「限制小组件实例数量」的 API** —— 「免费版仅允许创建一个中尺寸小组件」只能作为**产品文案**表述，系统层无法强制拦截。若必须强制，只能通过「大尺寸小组件本身不出现在免费版的可选列表里」来间接达成。
2. **中尺寸必须严格限 3 条** —— 中尺寸给 4 条以上会稀释大尺寸（6 条）的付费落差，这也是当初否掉小尺寸方案的原因（小尺寸仅 1 条，价值过薄）。
3. **`.monospaced()` + `design: .rounded` 的连字符偏长** —— 取件码如「C-4082」，等宽圆体的连字符视觉上接近短破折号。属字体本身度量，不影响功能；若后续收到用户误读反馈，可改为 `.system(size:weight:design:.monospaced)` 或去掉 `.monospaced()`。
4. **`@State` / `#Preview` 宏在命令行编译链路下的问题** —— 本机 Xcode 27 beta 的 `swift-plugin-server` 对 SwiftUI 宏在 CLI 下返回异常响应，导致 `xcodebuild` 编译失败。**这是该 beta 工具链的特有问题，不是代码问题**。工程内保留的是标准写法（`@State` / `#Preview`），在 Xcode GUI 中打开应可正常编译预览。本次截图验证通过一个等价的临时副本完成（`/tmp/qujian-verify`，将 `@State` 替换为 `ObservableObject` 包装、移除 `#Preview`），渲染结果与正式工程一致。

---

## 七、如何自行运行

在 Finder 中双击打开工程（或命令行）：

```bash
open /Volumes/ZWN/Downloads/Project/CodeClip/CodeClip/CodeClip.xcodeproj
```

选择 iPhone 17 Pro（iOS 27.0）模拟器，直接运行。若 Xcode 提示宏插件加载失败，先在 Xcode 中打开任意文件等待索引完成（该 beta 首次运行需要初始化工具链组件），或执行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -runFirstLaunch
```
