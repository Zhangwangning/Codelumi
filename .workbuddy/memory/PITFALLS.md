# Codelumi 踩坑手册 · 给下一个接手的人

> 这份文件只写**教训、判断原则、验证方法、协作红线**。
> 事实与口径（路径 / 标识 / 字号档位）看 `MEMORY.md`；发版与真机流程看 `OPS.md`；时间线看 `YYYY-MM-DD.md`。
> 冲突时以本文件为准 —— 这里每一条都是真踩过的。

---

## 0. 五分钟上手

```bash
cd /Volumes/ZWN/Downloads/Project/Allude/Allude
mv Allude/Resources/AlludePickup.mlmodel Allude/Resources/AlludePickup.mlmodel.bak
xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
mv Allude/Resources/AlludePickup.mlmodel.bak Allude/Resources/AlludePickup.mlmodel
```

界面验收一律走脚手架，**命令行点不了屏幕**（没 idb，AppleScript 被辅助功能权限拒）：

```bash
xcrun simctl install <UDID> /tmp/allude-verify/Build/Products/Debug-iphonesimulator/Allude.app
SIMCTL_CHILD_SCREEN=notify xcrun simctl launch --terminate-running-process <UDID> com.jikezhang.allude
sleep 7 && xcrun simctl io <UDID> screenshot /tmp/x.png
```

常用 `SCREEN`：`widgetSettings` / `widgetPreset`（配 `WIDGET_PRESET=<kind>`）/ `notify` /
`appearance` / `appearanceGroup` / `about` / `openSource` / `aiCapability` / `settings` /
`add`（配 `SEED`）/ `notify`。更多见 `AlludeApp.swift` 的 `switch environment["SCREEN"]`。

---

## 1. 环境与构建：这些坑一次能耗掉几小时

| 症状 | 根因 | 对策 |
|---|---|---|
| 一堆假错：`'self' is immutable`、`StateMacro could not be found` | 构建进程被沙箱包住，宏插件子进程起不来 | 加 `OTHER_SWIFT_FLAGS="-disable-sandbox"`。**这是工具链问题，不要改业务代码去迎合** |
| `sandbox-exec: sandbox_apply: Operation not permitted`（coremlc） | Xcode 硬编码包了 CoreML 编译步骤 | 临时 `mv` 掉 `AlludePickup.mlmodel` 再构建，完了还原。`ENABLE_USER_SCRIPT_SANDBOXING=NO` 无效 |
| 改了代码，截图却还是旧界面 | `simctl install` / `terminate` 是异步的，旧进程没死就 launch | 必须 `launch --terminate-running-process`；先 terminate → 等 4s → install → 再 terminate → 再 launch |
| 启动后白屏（前 3 秒） | 冷启动未完成 | 睡 6–8 秒再截，别急着判"崩了" |
| 改 App Group plist 不生效 | 模拟器 `cfprefsd` 缓存该域 | `simctl spawn <udid> killall -9 cfprefsd`，或关机重启模拟器 |
| 行为依赖某个开关，但模拟器上开关点不动 | 非 Pro 时 `gatedToggle` 用 `.constant(false)` 强制关，**UI 关但 model 值仍可读** | 取证用 `simctl spawn <udid> defaults write com.jikezhang.allude <key> -bool YES` |
| 改 `project.pbxproj` 后文件变 0 字节 | 内联读写截断 | 先读进变量、改完再整份写回 |

---

## 2. 小组件：坑最密的一块

**编译期硬约束**
- `@WidgetBundleBuilder` **不支持 `ForEach`**。每个 kind 必须字面写一行 `PickupWidget(preset: …)`。
- `Widget` 协议要求**无参 `init()`**。缺了只报「does not conform」，错误指向 bundle，看不出真凶。
- `kind` 发出去就**不能改**。改 = 换组件，老用户桌面上那个变「无法载入」。

**跨进程与意图**
- `Button(intent:)` 里只有 **`@Parameter`** 会进归档；普通存储属性在扩展进程还原后变默认值，表现为「点了没反应」。
- `Button(intent:)` **没有真正的 disabled 语义**：`.disabled` 只改视觉，系统照样执行。到头要停就改画一个不可交互的置灰 `Image`。
- 小组件里取图必须 `CourierLogo(usesStaticAsset: true)`，动态 `UIImage(named:)` 跨进程会退成灰块。
- 工程**没有注册 `CFBundleURLTypes`** → `Link(destination:)` 打不开自定义 scheme。跨进程动作只能走 App Group 信箱 + `AppIntent(openAppWhenRun:)`。

**渲染（2026-11-22 血泪）**
- 🔴 **小组件容器背景里不要用 `.glassEffect`**。iOS 26 的液态玻璃在 widget 里完全由系统按桌面主题决定，第三方硬套不会被采纳；轻则无效果，重则**整块渲染失败，桌面显示模糊骨架占位**（用户报「添加了之后不显示」）。小组件可用的是 `Material`：`.ultraThinMaterial`。
- `scaleEffect` 只改渲染、**不改布局尺寸**，必须再用 `.frame` 把缩放后的尺寸报出去，否则网格按真实尺寸排、一行放不下。
- 缩略图**宽度优先填满**，别封 `1.0` 上限 —— 封了就会左右多留白，用户的量尺立刻对不上。
- 同一个容器里给缩略图加**高度上限**（如 `×1.2`）会反向生效：高度先到顶 → 缩放比由高度定 → 宽度只占一半，左右两条大白边。超大竖版必须按真实比例。

**状态与刷新**
- 写 App Group 只是写文件，**桌面不会自己知道** → 必须 `WidgetCenter.shared.reloadAllTimelines()`。
- 游标/页码读的时候要**按实际条数夹紧**（用户取走几件后旧游标会越界，画出来是空白）。

---

## 3. 数据与解析

- 新正则必须注册进 `regexes` 预编译表，否则**静默 nil**，不报错。
- 三层误判防线不能省：`isPendingDeliveryOnly` / `isPromotionalOnly`（营销话术**且**零取件线索）/ `isVersionLikeCode`（`glm-5`、`gpt-4` 不是取件码）。
- 🔴 **升级 App 不会重解析存量记录**。解析逻辑修好只对之后 ingest 的生效，旧卡片仍然错 → 只能删掉重加。别在 issue 里承诺「更新就好了」。
- `MembershipPlan` **只增不删**。删 case = 老快照解码失败 = 用户当场掉回免费版。权益快照新字段一律 `decodeIfPresent`。
- 并列必须走 `PickupSortLogic.tieBreak`：Swift `sorted` 不稳定，同一秒的多条在 App 与小组件里会排出两种顺序。规则是时间相同 → 取件码自然序（数字段按**数值**比，不是逐字符）。
- 时间戳别自己算，用 `date` 命令取。

---

## 4. 界面与设计判断

**数值口径**
- 字号只用 `AppTheme.TypeScale`（rowTitle 17 / rowSubtitle 13 / body 15 / section 13 / note 12 / badge 11）。强调只加 weight。
- 圆角、边距这类值**必须同源**，一处定义、多处引用（例：`WidgetCanvasMetrics.cornerRadius`）。
- 🔴 **「数值相同」≠「观感相同」**。缩略图被 `scaleEffect` 缩到 0.56 倍后，24pt 的圆角屏上只剩 13.4pt；容器还按 24pt 画，两层弧就不一样。容器圆角要取**缩放后的视觉半径**。

**交互**
- 菜单带对号：用 `Menu { Picker(...).pickerStyle(.inline) }`。手写 `Label(_, systemImage: "checkmark")` 只给选中项图标 → 未选中项少了图标位，**每行文字起点都不一样**。
- 自绘 popover 同理：对号要占**固定宽度的槽**（`opacity` 控制显隐），不能让有无对号改变文字位置。
- `Section` header 里 `listRowInsets` 不生效 → 分组标题当普通行塞进首行。
- 详情页里 `Entry.id` **不能用 `UUID()`**（视图重建换 ID，与 `@State` 存的旧 ID 对不上，折叠弹回）。

**文案（2026-11-22 定的规矩）**
- **标题已说明「做什么」→ 提示直接删。**
- 提示只写标题说不出来的三样：**限制 / 代价 / 例外**（需重启、最多几个、实验性会延迟、取完才停）。
- 不写实现过程、不写结果预告（"关掉后底栏只剩三项"）、不自证清白（"不经过开发者服务器"）。
- 开关类设置项：**只留标题 + 开关**，标题下面不挂说明。设备不支持就置灰，点不动本身就是答案。
- 🔴 **不能写还没做的功能**。曾在卡片里写「也可以在快捷指令里用『添加到 Codelumi』自己拼一条」，
  而那个 AppIntent 根本不存在 —— 这类假承诺比不写更糟。

**开关建模（2026-11-22 纠正过两次）**
- 🔴 **先问「这两个开关是不是同一个东西的两层」**。背景「真正透明」与「Liquid Glass」
  一开始被做成三选一互斥枚举，实际是**正交可叠加**：只透明 / 只玻璃（仍有底）/ 两个都开（全透明玻璃）。
  互斥建模会把有效组合直接做丢。
- 🔴 **能力开关不要跨功能联动**。语音录入曾绑在「Apple 智能」总开关上，而设备不支持时总开关
  本身是禁用的 → 一联动关掉就永远开不回来，功能被永久锁死。两个能力各自读写各自的键。
- 🔴 **同一个能力只能有一个真值**。「使用权限」里的「麦克风与语音识别」与 Apple 智能页的
  「语音录入取件码」是同一件事 → `PermGate` 对 `.voice` 直接复用 `AISettings.voiceKey`，
  不新存一份。两份键必然出现"这边开了那边还显示关"。
- **权限类开关要区分「劝不劝」**：系统权限（通知/相机/相册/麦克风/定位）关掉要弹确认说明代价；
  互联网类（iCloud / 网络）关就关，别拦。App 无法撤销系统授权 —— 底部给「打开系统设置」，
  不要假装 App 能替你撤。
- 🔴 **同一语义的视觉标记只能有一个组件**。「实验室」原来长出三种样子（标题前缀「实验室 · 」、
  内联胶囊、正文冒号前缀）。现已收成 `LabBadge`（DesignSystem.swift），
  `SectionHeader.isLab` / `SettingsGroup.isLab` / `SettingsPlainRow.isLab` 三处透传。
- 🔴 **标记要贴在功能本体上**。徽章曾被我放在驿站位置页底部的免责说明旁（想标"这段是实验性"），
  老大立刻指出「不应该放在到达提醒的标题中吗」。**说明文字不是标记** ——
  徽章挂功能标题（分组标题 / 行标题 / toggle 标题），代价与承诺仍写成灰字说明。

**浮层与列表（2026-11-22 踩过）**
- 🔴 右下角悬浮球（FAB）**必然压住内容**：`contentMargins(.bottom:)` 只管"滚到底"的留白，
  内容不满一屏时列表仍**顶部对齐**，末尾补空行也只会排到标签栏背后（List 内容区延伸到 tabBar 下面）。
  想让球不压卡片，只能是球不在内容层（放进标签栏）。
- 因此凡是底部浮层（toast / 撤销条 / 球）同时出现，**要给彼此让位**：球显示时提示条抬到球上方，
  否则全宽胶囊右端的按钮点不到。
- 🔴 **验证尺寸不要用染色探针**。临时把占位行涂红/涂亮会被老大当成 bug 质问
  （「这下面的红色是干啥的」）。要么用透明占位 + 像素量测，要么先说明是探针再截。

---

## 5. 验证方法（不做等于没改）

- **能 build 必须 build**；能截图必须截图。
- 像素量测不可靠（玻璃卡 ≈ 页面背景、缩略图 ≈ 卡片白）。最可靠：`crop.swift` 裁一块放大 4–8 倍肉眼核对。
- Swift 脚本崩溃时 stdout 块缓冲会整块丢 → `setbuf(stdout, nil)`。
- 动态岛/锁屏卡**模拟器截不到真实效果**，只能真机验。
- 换图标：iOS 17.4 模拟器正常，iOS 26/27 模拟器必失败（宿主 CoreServicesUI 缺 upcall bundle），**真机正常** —— 别把这个当成 bug 修。
- 本机 macOS 侧 `computer-use` 未授权（辅助功能 / 屏幕录制），**点不了菜单和按钮**。需要交互态截图时先说明，别假装验证过。

---

## 6. 与老大协作的红线

- 对话里称「老大」；**任何仓库 / 文档 / 文案的署名一律「极客ZHANG」/ 张王宁**。两者绝不混。
- 每轮交付前对照原话逐项核对，**不交半成品**。没验证就明说没验证。
- 改动范围不擅自扩大；发现缺口先报备再动手。
- 量化：间距 / 字号 / 圆角 / 尺寸一律给具体数字。
- 给方案要有判断，不要罗列一堆让他选。
- 记忆要主动写。**开发周期长、可能换人，不写就等于没发生过。**

---

## 7. 值得继承的做法

- **脚手架化**：`SCREEN` / `WIDGET_BG` / `WIDGET_SECTION` / `SEED` 这类环境变量入口，让任何界面都能一条命令直渲截图。加新页面时顺手加一个。
- **注释写三件事**：为什么这么做 + 日期 + 老大原话摘录。半年后只有这三样能救你。
- **单源化**：额度、圆角、字号这类会被多处引用的值只定义一次（`PickupLimits`、`WidgetCanvasMetrics`）。
- **改完立刻收尾**：build → 装 → 截图 → 写日志，四步一起做完，别留到"下次一起验"。
- **记忆分层**：事实（MEMORY）／流程（OPS）／教训（本文件）／时间线（日期日志），新知识先判断属于哪一层再写。

---

## 8. 当前未收敛的风险

- **1.0.0 被拒（2.1 Information Needed）**，需在 Resolution Center 补说明，草稿在 `tools/appstore-review/`。
- **内购商品未过审**（lifetime `READY_TO_SUBMIT`、annual `CREATED`）→ 真机不显示价格。不是代码问题。
- **旧 kind 已退休**：老用户桌面上的旧实例会「无法载入」或显示模糊占位 → 发版说明必须写「删掉旧小组件重新添加」。
- 中尺寸目前 8 款，是否精简未拍板。
- 小组件玻璃改用 `Material` 后，**四种背景组合的桌面真实观感还没在真机上逐一看过**。

---

---

## 9. 「默认关」失效：默认值只在键不存在时生效（2026-11-22 实锤）

- **症状**：开关代码写的是 `?? false`，全新安装后仍是打开的。老大连问三次「你关不掉吗」。
- **根因**：两层。
  ① 键早就存在 —— 截图脚手架 `AI_VOICE=1` 走的是**正式 setter**，写的就是正式键；
  ② `simctl uninstall` 之后 cfprefsd 的缓存还在，重装照样读到旧值。
  所以"默认值"这件事在你自己的机器上根本验证不了。
- **对策**：
  · 需要"产品口径改默认"时，别只改 `??`，加**版本化迁移键**一次性覆写
    （本例 `allude.ai.voiceInput.reset.v1`），并且在 UI 读取之前、脚手架**之前**执行；
  · 脚手架写正式键时记得它会长驻，验完要么用迁移抹掉，要么换个 draft 键；
  · 验"默认值"必须在不带脚手架的冷启动上验，别拿截图自己骗自己。

## 10. ASC「有价格」和「能买到」是两件事（2026-11-22 我判断错过）

- **症状**：我说"ASC 没配价、沙盒取不到商品"，老大直接开骂"我已经录进去了你自己看看"。
- **事实**：价格排期（`inAppPurchasePriceSchedules` / `subscriptions/{id}/prices`）一直在，
  lifetime 有 CHN 手动价 + 177 地区自动价，annual 有 10 条地区价；
  商品 `state` 是 `READY_TO_SUBMIT`，沙盒照样能取到、页面照样渲染 `$0.99`。
- **对策**：判断"价格为什么不显示"要**分开查三层** ——
  ① 价格排期有没有条目；② 商品 state 是什么；③ 真机/模拟器 `Product.products(for:)` 实取
  （日志 `[allude-iap] storefront=… productID=displayPrice`）。
  三层里只有第三层空才会显示「—」，别拿第二层去推第三层。
  ⚠️ `inAppPurchasePricePoints` 接口 403（no allowed operations），**金额查不到，别试**。

## 11. 这份文件怎么维护

- 每踩一个新坑，当场按「症状 → 根因 → 对策」追加到对应章节，**不要只写在当天日志里**。
- 只写会重复踩的、会让下一个人浪费半小时以上的。一次性的小失误不值得占篇幅。
- 判断原则类（第 4、6 节）优先：它们比具体 API 坑更耐用，API 会变，判断方式不会。
- 旧结论被推翻时，**在原处改写并注明日期**，不要只追加一条新的 —— 两条互相矛盾的笔记比没有更糟。
