# Codelumi（珞米）— 项目指令

iOS 取件码收纳 App。核心承诺：**数据只在本机，不联网、不上传、不需要注册**。
SwiftUI + iOS 27 SDK，纯 Xcode 工程，零第三方依赖、零 SPM 包。

> 🔴 **品牌名（2026-11-21 主人定）**：对外名称 **Codelumi**，中文名「珞米」，**主要用英文名**。
> 界面文案（简中 / 繁中 / 英文）一律写 `Codelumi`；「珞米」只出现在两处：设置 › 关于页名字
> 下方那一行、App Store 中文页。档位名是 `Codelumi Pro`。
>
> **技术标识符仍叫 `codelumi`，永远不改**：Bundle ID `com.jikezhang.codelumi`、App Group、
> iCloud 容器 `iCloud.com.jikezhang.codelumi`、记录子目录 `Documents/`、小组件 kind
> `CodelumiPickupWidget`、资源名（`CodelumiPickup.mlmodel`、`Codelumi.storekit`）、
> 仓库与工程目录 `Codelumi/`、Swift 类型名（`CodelumiApp`、`CodelumiWidget`、`AboutCodelumiView`、
> `aboutCodelumi` 等）、UserDefaults 键 `codelumi.*`。
> 改了其中任何一个 → 老用户的数据容器换新 / 云端记录读不到 / 已加的桌面小组件失配。
>
> 更名链路：拾码 → Codelumi → **Codelumi**。版本历史里 0.x 那几条**保留 Codelumi 原名**（史实），
> 1.0.0 那条写「拾码 → Codelumi → Codelumi（珞米）」。

> 🔴 **对外不表述收费（2026-11-21 主人定）**：隐私政策、使用条款、版本历史、App Store
> 文案与支持页里**不出现价格、档位名（Codelumi Pro）、订阅 / 买断 / 恢复购买、iPadOS 适配**
> 这类表述。本节下面的商品信息只作开发者内部备查（App Store Connect 里两条商品仍在，
> 是否继续售卖待定）；改动对外文案前先按这条口径过一遍。

商业模式（内部备查）：**免费下载 + 分级解锁**，同一权益。2026-11-08 主人定：**只卖两档**：

| 商品 | Product ID | 定价 | 说明 |
|---|---|---|---|
| 每年 | `com.jikezhang.codelumi.pro.annual` | $1.99 / 年 | 自动续期订阅（⚠️ 不叫 `...yearly`：那个 ID 2026-11-11 被误建成非消耗型后删除，苹果永不复用） |
| 终身 | `com.jikezhang.codelumi.pro.lifetime` | $9.99 | 非消耗型买断，**主推**（≈ 五年年费） |

`pro.monthly` 已从 App Store 下架，`PurchaseStore.Plan.monthly` 只为解码旧数据保留
（`displayedPlans` 只有 `[.lifetime, .yearly]`）。走 StoreKit 2，价格一律取 `Product.displayPrice`。
订阅会过期 → 权益快照必须写 `expiresAt`，否则小组件会一直按完整版渲染。

> 隐私政策与使用条款有**三份副本要同步**：GitHub Pages（`Zhangwangning/codelumi-legal`，
> App Store 表单填这个地址）、Gitee 镜像（`zhang_wangning/codelumi-legal`，国内可访问），
> 以及 App 内打包的 `Codelumi/Legal/{privacy,terms}.html`（WKWebView 离线读，不跳浏览器）。
> 改文档必须三处一起改，否则用户看到的和商店页面写的会不一致。

> 托管地址：
> 地址集中写在 `Codelumi/Models/LegalLinks.swift`。这三个 URL 已经要填进
> App Store Connect 的审核表单 —— **不要改**，确需更换必须先让旧地址 301 过去。

> ✅ **激活入口已于 2026-11-07 从设置页移除**（App Review 3.1.1）。
> `ActivationView` 代码与 `SCREEN=activation` 截图脚手架还在，但设置里已没有任何入口；
> 上架前可以整页删除，**不要再把粘贴凭证的入口加回来**。
> `tools/license-gen` 只用于给内测用户签发凭证、读老快照里的 `license` 字段。

> 旧的「离线签名凭证 / 绑定设备」体系已于 2026-10-31 停用（从未对外售卖）。
> `LicenseVerifier` / `license-gen` 工具**仍在**，只为读得懂老快照里的 `license` 字段；
> 界面上已经没有粘贴凭证的入口，别再把它加回来（那是 App Store 3.1.1 的靶子）。

---

## 命名与对外口径（2026-11-24 定）

- 全项目**只有一个名字**：`Codelumi`（中文「珞米」）。目录、Xcode 工程、Target、
  Scheme、Bundle ID、App Group、iCloud 容器、小组件扩展、仓库名全部是它。
  旧名 `Allude` 只作为历史出现在更名链里，不再出现在任何标识符中。
- 🔴 **任何地方都不提"借鉴 / 参考 / 竞品 / 抄"**：仓库 README、App 内文案、
  代码注释、提交信息、TestFlight 文案一律不提别的 App 的功能或界面。
- 对外定位固定这一句：**Codelumi 源自作者本人开源的「快递取件码」快捷指令项目，
  是一款纯离线的取件码收集与管理工具，不需要联网，基于快捷指令自动化使用。**

## 硬规则（违反会出事故）

### 1. 构建带上 `-disable-sandbox`

这个参数是**防沙箱，不是修代码**。宏插件（`FoundationModelsMacros`）要让
`swift-plugin-server` 拉起一个子进程；**只要 xcodebuild 本身被沙箱包住**
（agent 运行时 / CI / Xcode 的 User Script Sandboxing），子进程起不来，就会报
`could not be found` / `swift-plugin-server produced malformed response`，
并连带抛出一堆**假错误**（典型是 `SwipeActionRow.swift` 里的 `'self' is immutable`）。

**那是工具链问题，不是代码问题。** 不要为了让这些报错消失去改业务代码 ——
先确认构建进程是不是被沙箱包着，把参数补上重跑一次。

> 2026-10-30 实测，别被两种情形搞混：在**普通 shell** 里（不经 agent 沙箱）
> 不带宽也照样 0 warning 构建通过，产物二进制与带宽版本 sha 完全相同。
> 所以「没带宽却过了」不代表这条规则错了，只代表这次没被沙箱包住；
> 反过来「带宽了还报假错误」才是真正需要排查的信号。

### 2. 这四项内部标识绝不能改

| 项 | 值 | 改了会怎样 |
|---|---|---|
| App Bundle ID | `com.jikezhang.codelumi` | 数据容器换新，用户记录全丢 |
| Widget Bundle ID | `com.jikezhang.codelumi.CodelumiWidget` | 系统判成新扩展，小组件需全部重加 |
| App Group | `group.com.jikezhang.codelumi` | 主 App 与小组件的数据通道断 |
| Widget `kind` | `CodelumiPickupWidget` | 已添加的桌面小组件失配 |

这些是用户看不见的内部标识。对外名称是「Codelumi」，对外显示名改 `CFBundleDisplayName` 即可。

### 3. 权益枚举只增不删

`MembershipPlan` 里**删掉任何一个 case**，老快照会在 `JSONDecoder` 解码时失败 →
被判 `malformed` → 用户当场掉回免费版。权益快照（`entitlement.json`）里新增字段
一律 `decodeIfPresent` 给默认值，否则一次解码失败就是静默降级。

⚠️ 现状（2026-11-10 核对）：`MembershipPlan` 里已经没有 `monthly` / `yearly`
（2026-10-30 删除），只剩 `none / trial / lifetime`；老快照解码由
`EntitlementSnapshot.init(from:)` 按 `isPro` 兜底反推。**不要再往枚举里加 case 又删 case。**

### 4. 签名私钥绝不入库

`tools/license-gen/private-key.pem` 已在 `.gitignore`。
它一旦进仓库（哪怕私有仓），整套买断制作废——谁拿到都能自己签。

### 5. 其它纪律

- **clean build 必须 0 warning**，弃用 API 当场迁移，不留 `@available` 兜底。
- **不要提交构建产物**：`build/`、`build-sim/`、`DerivedData/` 已忽略。
- **价格只能来自 StoreKit**：内购（`PurchaseStore`，每年 + 终身两档）必须展示
  `Product.displayPrice`，不要写死价格 —— 上架定价改了代码就对不上。
  除此之外不做销售催促、不做防盗宣示。


---

## 路径结构（三层同名，别数错）

```
Codelumi/                    ← 仓库根（.git 在这里）
└── Codelumi/                ← 工程根
    ├── Codelumi.xcodeproj
    ├── Codelumi/            ← App 源码（Views / Models）
    ├── CodelumiShared/      ← App 与小组件共用的代码
    ├── CodelumiWidget/      ← 小组件扩展
    ├── Config/               ← entitlements
    └── tools/
```

仓库根下另有 `tools/`（构建、安装、签发、自检脚本）与若干规格 `.md`。

---

## 构建与运行

```bash
cd Codelumi
xcodebuild -project Codelumi.xcodeproj -scheme Codelumi \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/codelumi-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

真机安装：`bash tools/install-device.sh`
（自动探测 Team、构建、用 devicectl 装机。2026-11-10 起改用付费开发者账号
`8499X3S9X8`（zhang_wangning@126.com），描述文件 1 年有效；
下文「免费签名的 7 天」只适用于旧的免费团队 `SW725KU49U`。）

---

## 怎么验证 UI（重要：命令行点不了屏幕）

本机没有 idb / applesimutils，AppleScript 驱动模拟器会被辅助功能权限拒绝
（`-10004 权限违例`）。**所有面板类界面都靠 `SCREEN` 环境变量直渲**：

```bash
xcrun simctl launch <UDID> com.jikezhang.codelumi   # 需先 SIMCTL_CHILD_SCREEN=xxx
xcrun simctl io <UDID> screenshot /tmp/x.png
```

常用 `SCREEN` 值：
`settings`（设置页，配 `SETTINGS_ANCHOR=about` 滚到底）、`add`（添加面板，配 `SEED=<短信>`）、
`license`（完整版/订阅页）、`scan` / `scanPhoto`、`share`、`pickedUp`、`stats`、
`detail`、`detailPicked`、`notify`、`gallery`、`activation`（激活页）、
`help`（帮助与反馈）、`about`（关于）、`legal`（隐私政策页）。

🔴 **装完先核对版本号再截图**：`simctl install` 与 `terminate` 是异步的，
旧进程没死就 `launch`，会**静默沿用旧进程**——截到的是上一版界面，
看起来像"改的代码没生效"。2026-10-31 因此误判过一次选中态。
```bash
xcrun simctl terminate UDID com.jikezhang.codelumi; sleep 4
xcrun simctl install UDID …/Codelumi.app; sleep 2
xcrun simctl terminate UDID com.jikezhang.codelumi; sleep 4
# 确认装上去的是新构建，再 launch + 截图
```

环境变量必须带 **`SIMCTL_CHILD_`** 前缀。截图建议同时注入
`SIMCTL_CHILD_SKIP_PERM=1`、`SIMCTL_CHILD_SKIP_ONBOARDING=1`，冷启动等 6–8 秒。

🔴 **`launch` 必须带 `--terminate-running-process`**（2026-11-01 踩了一整轮）：
App 还在后台时，`simctl launch` 只把它**切回前台**，`SIMCTL_CHILD_*` 一个都不传
—— 表现为"截图落到了列表页，脚手架像坏了一样"。实测探针：
不加参数时 `SCREEN=nil`，加上后 `SCREEN=settings`。
```bash
SIMCTL_CHILD_SCREEN=settings xcrun simctl launch --terminate-running-process <UDID> com.jikezhang.codelumi
```

真机回归基准模拟器：iPhone 16 Pro `272DD31C-D94F-46B4-9CC7-974A61439777`。
iPhone 直板机已完工（0.3.3）；**iPhone Duo 折叠屏适配已开工**，规矩见「里程碑」一节。iPad 暂不维护。

---

## 字号（设置类界面统一标准）

全 App 的设置/教程/二级页**只用 `AppTheme.TypeScale` 里的档位**，不要再写
`.system(size: 11.5)` 这类随手值。起因：2026-11-01 主人指出"教程字号太小、
设置里大大小小随意来"，盘出来 9–24 之间散着 18 种字号（含 10.5 / 11.5 / 12.5）。

| 档位 | 字号 | 用途 |
|---|---|---|
| `rowTitle` | 17 | 行标题、行尾值（对齐系统设置） |
| `rowSubtitle` | 13 | 行副标题、分区说明 |
| `body` | 15 | 教程步骤说明、卡片内长文 |
| `section` | 13 | 分区标题 |
| `note` | 12 | 注解、页脚、卡片下小字 |
| `badge` | 11 semibold | 徽章、角标 |

需要强调时**只加 weight，不加字号**（`AppTheme.TypeScale.body.weight(.semibold)`）。

例外只有两类，它们不是"字号"，是图形尺寸：chevron / 锁图标（12–13pt）、
等宽码（设备 UUID、凭证输入框，15/13pt 等宽）—— 改它们等于改图形比例，别动。

---

## App 图标切换

**十五套内置图标**（2026-11-21 精简 + 追加后的形态）。演进：
2026-11-15 按「从上到下、从左到右」重排为 01–16，11-16 补「皮革卡包」成 17，
11-21 删掉 6 套（包裹 / 蓝牌 / 黑牌 / 暗牌 / 光泽黑标 / 白盒平涂 —— 其中 5 套图面上
印着「ALLUDE」，品牌改名 Codelumi 后不能用），剩 11 套按原相对顺序重排为 **01–11**。
同日晚在 11 套后面**追加 12–15**（用户给的「优化App图标」四张：黑牌微笑 / 蓝牌微笑 /
玻璃立方 / 四格蓝柱）—— 纯追加、不动已有序号，所以 `currentScheme` 仍是 `"3"`。
**默认是第 6 套「黑盒立体」**（原来是第 7 套，删完往前挪一位；再往前是第 4 套「C 标」、
第 2 套「取件袋」）。
🔴 **编号与网格顺序严格一致（01…15 连续）**。重排会让老用户存的 `rawValue`
指向另一张图（新旧 iconNN 同名不同图），所以 `AppIconStore` 里有一套
**链式一次性迁移** `migrateLegacyNumberingIfNeeded()`：靠 `codelumi.appIcon.scheme`
版本标记（当前 `"3"`）+ 两张序号表（方案1→2、方案2→3）换算，冷启动时执行一次并同步系统图标。
⚠️ 以后再改编号，必须同步扩这两张序号表并升 `currentScheme`，否则老用户选择错位。
**表里存的是序号不是 case 名** —— `icon09` 在三个方案里是三种不同的图，只有序号能跨版本对齐。
设置 › 外观与个性化 › 自定义 App 图标可切换（版式同快递公司页的网格）。
原主图标「取件袋」现在作为 alternate icon `Icon02` 保留，仍可在设置里选。

- 主图标：`Codelumi/Assets.xcassets/AppIcon.appiconset`（1024，**不能有透明通道、不能自带圆角**）。
- 🔴 **15 套 `AppIconNN.imageset`（App 内预览 / 灵动岛 / 关于页 / 分享卡共用）
  统一放 `CodelumiShared/Assets.xcassets`**（2026-11-15 从 App 的 catalog 迁过来）。
  理由：共享 catalog 被 App 与小组件**两个 target 各编译一次**，扩展进程才查得到；
  放在 App 的 catalog 里，小组件取不到图，`Image("AppIconNN")` 会**静默渲染成灰块**
  —— 1.0.0(312) 灵动岛不显示 App 图标就是这个原因。每份 imageset 必须带
  `"template-rendering-intent": "original"` + 1x(60)/2x(120)/3x(180) 三档。
- 除默认那套（`Icon06` = 黑盒立体 = 主图标，不注册为 alternate）以外，全部由
  **真实 `Codelumi/Info.plist`** 的 `CFBundleIcons › CFBundleAlternateIcons`
  声明 `Icon01`…`Icon15` 中的 **14 条**（去掉 `Icon06`），文件是 bundle 根目录的
  `IconNN@2x.png`(120) / `@3x.png`(180)（纯 iPhone 工程，不需要 `~ipad`）。
  换默认图标也要同时动三处：`AppIcon.appiconset` 三张 1024、Info.plist 里新旧两条
  alternate 互换、`AppIconChoice.fallback`。新增一套要同时动三处：imageset、`AppIcons/IconNN*.png`、Info.plist 声明，
  再加 `AppIconChoice` 的 case、`number`、`title`（`assetName`/`alternateName` 由 `number` 自动拼）。
- 🔴 **工程是 Xcode 16 同步文件夹**（`PBXFileSystemSynchronizedRootGroup`）：
  `Codelumi/` 下新增 Swift 与 PNG 都**不用改 pbxproj**，自动进包。
- ⚠️ `setAlternateIconName` 密集连切会被系统限流（模拟器 `LSIconAlertManager` Code=35
  "Resource temporarily unavailable"，真机表现为静默不生效）。验图标一次只切一个、间隔 20s 以上。
- ⚠️ `simctl launch` 的脚手架环境变量必须写成 `SIMCTL_CHILD_SCREEN=x xcrun simctl launch …`，
  写在 bundle id 后面会被当成 argv 丢弃；真机对应 `DEVICECTL_CHILD_SCREEN=x`。
  `AppIcons/` 与 `Codelumi/` 都在 Xcode 的同步组里，**不用改 pbxproj**。
- 图源自满幅方图，**不再裁切**（早期那批是白底圆角，裁过角）。
  ⚠️ `sips -z` 只改尺寸、**不改格式**：源是 JPEG 时要显式加 `-s format png`，
  否则 `.png` 文件里装的是 JPEG 数据。
  ⚠️ 工程已改为 `GENERATE_INFOPLIST_FILE = NO` + `INFOPLIST_FILE = Info.plist`，
  增删 Info.plist 键要改那个真实文件，`INFOPLIST_KEY_*` 不再生效。
- 选择状态存 **App Group**（`codelumi.appIcon`），但 🔴 **灵动岛/锁屏不靠它**：
  选择随 `ContentState.appIconRaw` 过进程边界（2026-11-15 修）。扩展进程自己读
  共享偏好域那条链一断就回落到默认图标（第 6 套黑盒立体），表现为「桌面换了、岛里还是旧图标」。
- `AppMarkIcon(choice:)`（灵动岛/锁屏）、关于页顶部、设置网格读同一份选择。
- 🔴 **给灵动岛用的图片资源，`Contents.json` 必须写两样**，否则折叠态会渲染成
  一个纯色方块（2026-11-01 真机修复）：
  ```json
  "properties": { "template-rendering-intent": "original" },
  "images": [ 1x(60) / 2x(120) / 3x(180) 三档 ]
  ```
  WidgetKit 的 accented 渲染管线会把"没声明渲染意图的图"当模板涂成单色，
  方形图标被涂完就是一个灰方块；只给 1x 一张也会踩到。旧的 `AppMark.imageset`
  一直带着这两样，所以当年没暴露 —— 新加资源要照抄这个规格。
- ⚠️ `setAlternateIconName` 在 `App.init()` 里调用太早（场景未连、连回调都不给），
  必须在视图出现之后调用。
- 截图验收：`SCREEN=appicon` 看选择页，`APP_ICON=envelope|cards|hand` 强制切换；
  切完**必须重启 SpringBoard** 才看得到主屏图标变化（`simctl spawn <udid> killall SpringBoard`）。

---

---

## 来源与第三方标识（对外口径，改文案前先看）

App 内「关于 › 声明与免责」（`StatementView`）是唯一的对外表述来源，四段：

1. **来源**：Codelumi 由极客ZHANG 独立开发，衍生自开发者本人制作的
   「快递取件码」快捷指令；App 把那套取码逻辑搬进原生应用，没有第二个来源。
2. **技术**：全部 Apple 官方工具与框架（Xcode / Swift / SwiftUI / WidgetKit /
   ActivityKit / StoreKit），零第三方依赖、零第三方 SDK。
3. **设计来源**：产品形态、交互、视觉均自设计，未使用其他应用的内容或素材；
   解析规则来自真实短信整理与回归测试，语料与基线可复核。
4. **第三方标识**：快递公司/驿站图标只用于**标识取件来源**，版权归各品牌方；
   不表示授权或合作；权利人异议即移除。侵权联系邮箱同「联系方式」。

🔴 修改这四段时保持事实准确：
- 不要再写"参考了某 App"之类的话（与第 3 条冲突）；
- 品牌图标只能出现在「快递公司 / 驿站管理」这类标识场景，别拿去做宣传图。

## 里程碑：iPhone 直板机 v0.3.3（2026-11-01）

直板机（iPhone 16 Pro 及其同类）的功能与视觉验收到此**全部完成**，基线是
`0.3.3 (58)`。当前涵盖：

取码与列表 · 桌面小组件（小/中）· 灵动岛与锁屏实时活动 · 统计 · 搜索与排序 ·
截图收件 · 通知提醒 · 快递公司与驿站管理 · 使用教程 · 诊断日志 · 反馈邮件 ·
八套 App 图标 · 权益与订阅页 · 声明与免责 · 联系方式 · 首启同意与引导 ·
破坏性操作的随机数确认。

### 🔴 从这里开始做 iPhone Duo，**不得影响直板机**

规矩（违反即回退）：

1. **只增不改**：Duo 的版式、断点、状态**新增**文件或分支，不改直板机现用的
   布局代码与常量。确需共用一处，先在直板机上跑一遍回归。
2. **调用点判设备**，不在视图内部到处塞 `if foldable`：尺寸判定集中在
   `DeviceClass`（新建），视图只读它的结果。
3. **直板机回归清单**（每次改完 Duo 都要过）：
   - `SCREEN=settings / help / about / consent / contact / appicon / widgets` 截图；
   - 首启同意 → 引导 → 进列表，全流程一次；
   - 待取/已取列表条数仍是 4，卡片配色与取件码字号不变；
   - 桌面小组件小/中尺寸正常，灵动岛折叠态图标正常（真机）；
   - `bash tools/install-device.sh` 装机后 `devicectl` 核对版本号。
4. **版本号不混**：Duo 的实验性改动不跟着直板机一起发，合并前确认直板机构建 0 warning。

## iPhone Duo 模拟器（2026-11-01 首次装机）

- 设备类型：`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`
- UDID：`C1B11E62-C700-4065-BFAE-E65D2BA42071`（iOS 27.2）
- 两个显示：`--display=1` 是**折叠态外屏**（1398×2034，约 466×678pt），
  `--display=3` 是展开态内屏（2007×2853）。折叠时内屏是黑的。
- 截图必须带 `--display=`：不带参数会报 `Invalid argument`。
- ⚠️ **`simctl` 没有 fold/unfold 命令**，展开态只能在模拟器菜单里手动切；
  命令行验收先按折叠态做，展开态靠人工截图校对。
  （不存在 `CODEPOUCH_DEVICE` / `ALLUDE_DEVICE` 这种切设备脚手架；`DUO_OUTER=1|0`
  只强制灵动岛紧凑态的样式，不切屏。）

### 🔴 官方设计规范（2026-11-01 查证，优先于一切猜测）

完整笔记在 **`iPhone Duo 官方设计规范笔记_v1.md`**，来源是 Apple 三场 Tech Talks：
[Prepare your app](https://developer.apple.com/videos/play/tech-talks/111461/) ·
[Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/) ·
[Strike a pose](https://developer.apple.com/videos/play/tech-talks/111463/)。

三条最容易搞错的官方口径：

1. **侧边竖排标签栏是设计意图，不是 bug。**
   官方："position your toolbars, tab bars and controls along the side"。
   ⚠️ 我在 0.3.3 把它记成"问题"，**已撤回**。
2. **只为两种 size class 设计**（外屏 compact / 内屏 regular），
   内屏**不遵循 supportedInterfaceOrientations**，布局只看 size class。
3. **折痕与摄像头是「保留区域」**，有 API 可查，不要写死像素：
   `proxy.reservedRegions(kind: .division / .occlusion)`（iOS 27.1+）。

### 折叠态首装实测（0.3.3）真正要改的

1. ~~标签栏变右侧竖排~~ → **符合官方意图，不改**。
2. **单列列表被拉宽**：官方要求 regular 宽度下用两列或分栏，这条要做。
3. ✅ 已改：自绘面板改用 `reservedRegions(kind: .occlusion)` 拿摄像头区域
   （不再写死 84pt）。⚠️ 但 `ConcentricRectangle` 在根 overlay 里会裁成直角
   （容器没有 cornerConfiguration），圆角仍按屏幕半径显式算。

### 已修：外屏「分享取件码」面板（0.3.3 build 59）

`SharePreviewSheet` 现在按**窗口高度**分流：`< 720pt` 走紧凑版式（直板机 ≥ 850pt，
永远不进这个分支）。紧凑态做了四件事：

1. 面板尺寸改从**窗口**读（`Self.windowSize`）——原来用 GeometryReader，
   在被 `ignoresSafeArea` 的层级里仍报"安全区内"尺寸，Duo 上面板少掉上下两条。
2. **隐藏系统状态栏**（`.statusBarHidden(compact)`）：Duo 外屏的状态栏时间画在
   面板内部右上角，正压「完成」胶囊上。
3. 顶栏左右留白让到面板大圆角之内（`corner * 0.86`），「完成」不再被弧线切掉。
4. 卡片收窄（左右 40）并下移 12pt，两侧与顶部留出呼吸。
5. 🔴 **按真实安全区内缩**（2026-11-01 主人："右侧是摄像头和 dock，遮挡了"）：
   Duo 外屏实测 `window=466x678 inset t=0 l=0 r=84 b=34` ——
   右侧 84pt 是摄像头/dock 区、底部 34pt 是 Home 条。
   面板挂在 RootView 顶层且 `ignoresSafeArea`（为了盖住标签栏），
   所以必须自己把这四边补回来，否则内容会被摄像头压住。
6. 🔴 **圆角按 D 型屏分边**：铰链侧（左）16pt 小圆角、机身外缘（右）大圆角
   （`corner = displayCornerRadius − 8`），用 `UnevenRoundedRectangle`。
   四角同半径在 D 型屏上一定错位。直板机仍是统一 `RoundedRectangle`。
7. ⚠️ **底部与顶部留白要一致**（2026-11-01 主人两次指出底部间隙太大）：
   面板四边一律只留 `inset = 8`（底部**不再**额外让 34pt），
   Home 指示条由**内部按钮条**的 26pt padding 让开。
   也不要再叠加 `safeBottom + x`，那会翻倍。
8. **铰链在左、摄像头在右**（主人确认）：所以圆角是「左 16 / 右 55」，
   不要反过来。

9. **操作按钮改「三个圆形悬浮按钮」**（2026-11-01 主人，方案 B）：
   紧凑态不再有整条底栏，三个 48pt 圆钮 + 26pt 间距，图标 + 无障碍标签，
   底部留 72pt 让它离开 Home 条。省下的高度与左右留白（40 → 24）让卡片变大。

⚠️ 直板机的分享面板**没有改**（`compact == false` 走原参数）。
每次改完用**逐像素对比**确认：`ImageChops.difference` 只允许状态栏时钟区域有差异。

## 灵动岛紧凑态：只有 Duo 外屏改（2026-11-01）

主人要求：**只改 iPhone Duo 外屏**的灵动岛，不要动其他设备。

- 判断收在 `DuoOuterDisplay.isActive`：主 App 启动时按 **窗口高度 < 720pt**
  判定并写进 App Group（`codelumi.duoOuter`），灵动岛由小组件进程渲染，读同一份。
  ⚠️ 不能靠 `UIScreen.main`（已弃用）或 `horizontalSizeClass`（直板机也是 compact）。
- Duo 外屏：只剩数字、居中、>99 显示 `99+`；
  直板机：保持「待取 N」横排（原口径 2026-09-22 定调，别动）。
- 截图脚手架：`DUO_OUTER=1|0` 强制覆盖，可在任意模拟器上拍两种形态。
- ⚠️ **真灵动岛在模拟器截图里抓不到**（连 Duo 也一样）：`Activity.request` 成功、
  日志有 `requested id=...`，但 `simctl io screenshot` 截出来没有岛
  —— 与 iPhone 16 Pro 模拟器那个 `suppressionForSuppressSystemApertureCompletely`
  是同一类问题。**真岛屿呈现只能让主人在 Simulator 里自己看，或真机上看。**
- 数字居中不能靠 `.frame(maxWidth: .infinity)`：trailing 区域宽度由系统决定，
  撑开的是内容不是区域。用 `GeometryReader` 拿到区域真实尺寸再居中。

🔴 **教训**：改灵动岛前先想清楚"这个视图是不是所有设备共用"。
第一次改的时候直接动了 `IslandCompactTrailing`，直板机也一起变了，
主人当场指出"乱改的啥"。共用组件一律按设备分流。

## 实时活动页：Duo 折叠态换官方机模（2026-11-01）

- 素材：`DuoFrameHome` / `DuoFrameLock`（主人给的 1574×2194 带壳图，白底已抠成透明）。
- 判定：**没有公开的"是否折叠" API**。Apple 只按 size class / 尺寸表达，
  我们用窗口宽度分档：直板机 ≈370pt / Duo 外屏 ≈466pt / Duo 内屏 ≈669pt。
  页面随折叠重绘时会重新读窗口宽度，所以状态能跟上。
- ⚠️ **不要在读机模尺寸的地方判断**：`stage` 上有 `aspectRatio(450/920)`，
  机模宽度被锁在 ~215pt，用它判断永远不成立（踩过一次）。
- **岛的位置是量出来的**，不是猜的：在主人给的外屏实拍（572×787）上测岛体
  bbox = x 0.757…0.809 / y 0.176…0.303，换算成机模上的比例后再微调到：
  **宽 6.2%、高 17.2%、中心 (78.4%, 28.8%)**，竖排（上图标 16pt、下数量 13pt）。
  与参考图并排比对过，垂直位置基本吻合。
- 🔴 **最终方案：Duo 折叠态用截图展示，不渲染**（2026-11-01 主人决定）。
  叠渲染试过三轮（对准、覆盖、模糊修补）都不理想：Duo 的岛是侧边竖排形态，
  和 iPhone 横向岛不是一套几何，还总和机模里烤进去的时间/Wi-Fi 打架。
  · 素材约定：把截图丢进 Assets 即可生效，**无需改代码**——
    `DuoActivityHome`（主屏 + 岛）、`DuoActivityLock`（锁屏 + 卡片）；
    没放时回落 `DuoFrameHome` / `DuoFrameLock` 官方机模。
  · 容器比例也要跟着换：Duo 图是 0.717，iPhone 是 0.489，否则图会被宽度压成一小块。
  · 直板机**继续渲染**，一行没动。
- 🔴 **最终定案（2026-11-01 晚）：Duo 折叠态干脆不做预览**，只保留开关 + 一段说明：
  「由于开发者没有 iPhone Duo 真机，无法进行 iPhone Duo 的实时活动渲染。」
  理由：贴截图、叠渲染都不好看，与其给一个"看起来像"的预览，不如老实说明。
- 🔴 **判定必须同时看设备与宽度**：最初只写了宽度带 `400…520`，
  而 iPhone 16 Pro 的窗口宽正好是 **402pt** —— 直板机被误判成 Duo，
  预览整块消失（2026-11-01 主人："非折叠机要能正常显示"）。
  现在用几何判定 `isDuoDevice`，**折叠与展开都算 Duo**（主人：内屏也不给预览）：
  ```
  Duo 折叠态  466 × 678  → 高 < 720
  Duo 展开态  669 × 951  → 宽 > 600（iPhone 最宽 440）
  直板机      402 × 874 / 440 × 956 → 两条都不满足
  ```
  实测：展开态（内屏 669pt 宽）已正确显示「暂不提供预览」。

### 能不能直接读机型？（2026-11-01 实测结论：不能靠它）

同一份探针在两台模拟器上的输出：

| 取值 | 直板机（iPhone 16 Pro） | Duo 折叠态 |
|---|---|---|
| `UIDevice.model` | `iPhone` | `iPhone` —— **区分不了** |
| `uname().machine` | `arm64` | `arm64` —— 模拟器里是宿主架构 |
| `UIDevice.name` | `iPhone 16 Pro` | `iPhone Duo` —— **但真机上是用户改的名字**（如"张三的 iPhone"） |
| `window bounds` | 402×874 | 466×678 —— ✅ 唯一可靠 |

结论：`machine` 在真机上是 `iPhone17,1` 这类标识，但 Apple 不公开映射表、
新机型还认不出来；`name` 可被用户改；`model` 恒为 iPhone。
**所以继续用尺寸判定**，这也正是 Apple 的口径（按 size class / 几何适配，不按机型分支）。

## 首次启动（同意条款 → 引导）

2026-11-01 主人要求：首启**必须先读并同意《使用条款》《隐私政策》**，再看使用教程。

顺序（`RootTabModel` 控制，两个都是 fullScreenCover，不叠加）：
1. `LegalConsentView`：条款链接（`LegalDocumentView`，App 内读）+ 「我已阅读并同意」
   勾选 + 「同意并继续」（未勾选置灰）+ 「不同意」（弹说明）。
2. 同意后写 `legal.consent.v1`，接着进 `OnboardingView`（三页速览），
   完成写 `onboarding.completed.v1`。

这一页还有一条**必须写清**的事：数据只在本机，
**卸载 App 或删除记录后 App 内无法恢复**（没有云端备份、没有回收站）。
文案在 `LegalConsentView.dataNotice`，别弱化成"请注意"。

同理，「清空已取件记录」在 2026-11-01 前是**直接删、没有确认**的。
现在要先过一道**随机四位数字**：弹窗里显示一个随机数，用户照着输入，
输对了「清空」才变红可点（`DestructiveConfirmDialog` + `.destructiveConfirm(...)`）。
- 🔴 是**盖在当前页上的居中弹窗**（版式照系统 alert），不是新页面。
- 「清空」**常亮红色**，点下去才校验：输对就删；输错给一行红字、清空输入、
  并换一个新数字（2026-11-01 主人："按钮常亮也行，反正输不对删不掉"）。
- 数字每次弹出/每次输错都重新生成，防止记住上一轮闭眼输。
- 截图验收：
  · `SCREEN=confirmClear` —— 纯色底上的弹窗（只看版式，**背景一定是空的，不代表真机**）；
  · `CONFIRM_DEMO=1` —— 在真实列表上自动亮起弹窗，这才是用户看到的样子。
  · `CONFIRM_MATCH=1` —— 预填正确数字。
- 蒙层用 `Color.black.opacity(0.20)`：再深就把后面的卡片压没了
  （2026-11-01 主人要求"后面的列表卡片内容要显示"）。

截图验收：`SCREEN=consent`；不带 `SKIP_ONBOARDING` 冷启动可看真实首次流程。

## 联系方式页（`ContactView`）

2026-11-01 第二版口径（主人定的）：

- 每行显示**平台名 + 账号名**，不显示那串 ID（`zwn1652503532` 对用户没有意义）。
  邮箱例外：地址本身就是账号，保留 `zhang_wangning@126.com`。
- 行尾动作写明白：`复制邮箱` / `去小红书` / `去抖音`。
- **不展示二维码**。小红书 `https://xhslink.cn/o/7EXKCLCJzB0`、
  抖音 `https://v.douyin.com/jUUUICs4WuY/` 点击直接跳主页（打不开会提示）。
- 微信公众号**无法跳转**：`weixin://` 只能打开微信本体，公众号二维码里是微信私有
  ticket，第三方拼不出来。所以**只放那一张横幅图**（`QRWeChatBanner`），
  不加卡片边框、不加标题、不加微信图标（2026-11-01 主人：图里信息已完整）。
  图下那句话是**引导反馈**（"有使用上的问题，可以在公众号后台留言"），
  不是引导关注 —— 措辞克制，别写成"欢迎关注"。
- 行首用平台官方图标（`IconMail` / `IconXiaohongshu` / `IconDouyin` / `IconWeChat`），
  `SettingsRow.imageAsset` 支持图片图标。
  ⚠️ `IconMail` 是 Apple「邮件」App 的图标，属 Apple 商标；仅在自家 App 里指代
  "发邮件"这一动作，不暗示与 Apple 的合作关系。

## 产品命名（2026-11-01 主人定）

界面上**不出现「免费版」「付费版」**这两个词，只用两个产品名：

| 档位 | 对外名称 |
|---|---|
| 未解锁 | **Codelumi** |
| 已解锁 | **Codelumi Pro**（完整名 Codelumi Pro） |

小组件头部空间窄，截断提示用最短的「Pro」（配锁图标），不再写「免费版」。

额度：**同屏 4 条**（`PickupLimits.freeVisible`，App 列表与小组件同源；
2026-11-01 主人从 3 改成 4）。不再限制"每种尺寸只能加一个"——那条是文案，
WidgetKit 也不暴露实例数量，说不清就别写。

## 模拟器里看不到灵动岛（已知环境限制）

实时活动**能起来**，但**灵动岛不显示**——这是模拟器 SpringBoard 的行为，不是 App 的问题。
2026-11-01 实测取证（iPhone 16 Pro / iOS 27 模拟器）：

- App 侧三道门全过，`Activity.request` 成功：
  `converge pending=34 enabled=true pro=true auth=true` → `requested id=...`
- SpringBoard 也登记了这张活动，并创建了 compact 布局断言：
  `<activity:…com.apple.chrono.WidgetRenderer-Activities>` / `preferredLayoutMode: compact`
- 随后整个 SystemAperture 被压掉：
  `invalidation reason: SBSystemApertureCoordinator suppressionForSuppressSystemApertureCompletely`

排查过：把 App 切后台、激活 Simulator 窗口、换全新 iPhone 18 Pro Max 模拟器、
写 `SBSystemApertureSuppressCompletely` / `SBSuppressSystemApertureCompletely` 默认值 —— 均无效。

✅ 所以灵动岛相关的验收走两条路：
1. **版式/着色**：设置 › 实时活动页里的灵动岛预览（`SCREEN=activity`，配
   `ACTIVITY_PAGE=1` 落到折叠态），它用**同一套视图**渲染，能看到图标、描边、计数；
2. **真实呈现**：以真机为准（2026-11-01 主人已确认折叠态图标正常）。

## 诊断日志（反馈用）

`DiagnosticsLog` 在 `Application Support/Diagnostics/log.txt` 滚动记录（上限 256 KB，
超过滚成 `log.1.txt`，只留一代）。用户点「反馈 › 发送邮件反馈」时，日志作为
`codelumi-log.txt` **附件**随邮件发出（走 `MFMailComposeViewController`，
`mailto:` 带不了附件）；用户可关闭「附带诊断日志」开关。

🔴 **日志绝不记录用户内容**：不写短信原文、取件码、地址、电话、设备 UUID。
只写"发生了什么"：版本、系统、解析长度与条数、错误码、耗时、权益档位。
这是本 App 唯一会离开设备的数据，写日志前先问一句"这句能不能给外人看"。

⚠️ 模拟器里 `canSendMail()` 为假，只能验证到"复制邮箱兜底"分支；
带附件的编辑器必须在真机上验。

---

## 数据安全红线

`enforceStorageLimit()` **只在 `ingest()`（收到新短信解析入库）时触发**，
按免费档 50 条 FIFO 淘汰最旧的；启动时不会删。

改任何与权益、限额、存储相关的逻辑前，先确认：**会不会让已在用的用户掉数据**。
这个 App 的价值全在"用户攒了几个月的那堆取件记录"。

---

## 既有领域约定（改之前先看）

- **字段口径**：一条短信里多个取件码 → 拆成多张卡（`parseAll` 的 `codeChainParts`），
  但链式段必须与首段同形（`codeShape` 指纹），否则会把柜位号误判成第二条。
- **主名口径**：`titlePrimary = courier ?? company`，驿站不进主名位。
- **解析器**：四套独立正则 + 优先级链（code → waybill → tail → special）。
  **新增正则必须注册进 `regexes` 预编译表**，否则 `firstMatch` 恒 nil 且不报错。
- **颜色**：卡面用品牌色，取件码恒用 `iconBrand`（`CourierBrand.color(for: titleIconSource)`）。
- 更细的历史决策见 `.workbuddy/memory/MEMORY.md` 与按日期的日志（同目录），
  那是逐轮迭代积累的踩坑记录，改动相关模块前值得一读。

---

## 自检脚本

```bash
# 短信解析回归 —— **必须传语料路径**，省略会直接报「读不到语料文件」并 exit 1。
# 精选库（64 条，基线：识别 64 / 地址 60），语料在**仓库外**，换机器可能不存在
swiftc -O -o /tmp/parser-regression \
  Codelumi/Codelumi/Models/PickupParser.swift \
  tools/parser-regression/main.swift && \
/tmp/parser-regression "/Volumes/ZWN/Downloads/Project/shortcuts-toolkit-master/快递取件码短信库.md"

# 全量库（514 段，基线：识别 192 / 地址 189），语料就在仓库根，长期可用
/tmp/parser-regression 短信语料库_v1.md

# 驿站匹配自检（精选 63 条 + 对抗样本 14 条，逐条比对「这条应该判成哪个驿站」）
# ⚠️ 必须用**绝对路径**编译：工具靠 #filePath 推自己的目录找语料，
#    用相对路径编译后换工作目录运行会报「读不到 cases.txt」。
# `tools/swift-cli-shim.swift` 是 macOS 垫片：CourierBrand 里的 SwiftUI 图标渲染
# （Image(uiImage:)、.widgetAccentedRenderingMode）与 BrandDebug 的 App Group 依赖
# 在 macOS 目标下编不过，垫片只补最小定义、不改匹配逻辑。
swiftc -O -o /tmp/station-check \
  "$PWD/Codelumi/CodelumiShared/CourierBrand.swift" \
  "$PWD/Codelumi/CodelumiShared/BrandPalette.swift" \
  "$PWD/Codelumi/CodelumiShared/Localization.swift" \
  "$PWD/tools/swift-cli-shim.swift" \
  "$PWD/tools/station-check/main.swift" && /tmp/station-check
# 退出码 0 = 全符合基线；1 = 有差异并逐条打印。
# 🔴 改匹配规则时不要为了让它是绿的而改基线文件 —— 先确认每处变化都符合预期。
# 🔴 自由文本匹配**只用 name + aliases，不用 key**：key 是给用户改名归一化用的短名
#    （中邮/菜鸟/兔喜…），拿去扫正文会把「中邮大厦」「熊猫便利超市」判成驿站。
#    某条短信确实只写短名时，把那个写法补成该条目的 alias，不要放 key 回循环。

# 品牌表 + 资源落盘自检（必须用绝对路径编译，它靠 #filePath 推仓库根）
swiftc -O -o /tmp/brand-check \
  "$PWD/Codelumi/CodelumiShared/CourierBrand.swift" \
  "$PWD/Codelumi/CodelumiShared/BrandPalette.swift" \
  "$PWD/Codelumi/CodelumiShared/Localization.swift" \
  "$PWD/tools/swift-cli-shim.swift" \
  "$PWD/tools/brand-check/main.swift" && /tmp/brand-check
# 这条目前会 exit 1。2 项失败是**既有业务差异**，不是回归，别去「修」：
#   ① 「某某冷门驿站」期望映射到「快递驿站」；
#   ② 品牌表多挂 5 个未登记资产（brand-duoduodaishou / miaozhan /
#     shoujianbao / tiantian / yundakuaichaoshi）。
# 除这两项外必须全 ✓；要让脚本变绿，改的是期望值，不是品牌表。

# 签发 / 验签凭证（未上架期间给测试者发凭证用）
python3 tools/license-gen/issue-openssl.py --plan 7d       --device <32位HEX>
python3 tools/license-gen/issue-openssl.py --plan 30d      --device <码>
python3 tools/license-gen/issue-openssl.py --plan 180d     --device <码>
python3 tools/license-gen/issue-openssl.py --plan 1y       --device <码>
python3 tools/license-gen/issue-openssl.py --plan forever  --device <码>
# 也认 --plan 7天 / 30天 / 半年 / 一年 / 永久；旧写法 --service trial --days N 仍可用。
# 限时凭证靠 payload 里的 `e`（到期时间）在**读侧**降级：过期即 free，App 与小组件同口径。

python3 tools/license-gen/issue-openssl.py --check "<凭证>"
```

---

## 内测分发包的防护（2026-11-01）

把 IPA 发给别人，**防的是"拿了包就能白嫖 / 反编译看懂内部"**，不是防专业逆向 ——
离线 App 做不到绝对防伪，目标是"成本高于价值"。

已经做到的（不用改）：

- **凭证是非对称签名**（ECDSA P-256）。App 里只有公钥，`private-key.pem` 不入库、
  不进包（实测包内无任何 `.pem`、无私钥字样）。
- **一机一凭证**：载荷里的 `d` = 设备码（32 位 HEX，随机生成、存 Keychain），
  转发给别人无效。这是离线体系里唯一能挡"一码多卖"的机制。
- **每次读取都重新验签**（`EntitlementSnapshot.load()`），手改
  `entitlement.json` 里的 `plan`/`isPro` 会当场降级。
- 到期在**读侧**判定，并把时间水位（`lastSeenAt`）往前推 —— 调系统时间回不到过去。

2026-11-01 新增：

- `BuildFlags.scaffoldsEnabled`：**只有 Debug 为真**。Release 包不再带 `SCREEN=…`
  那套脚手架（实测包内 `colorCheck` / `activityRace` / `couponGallery` 字符串已消失）。
  自己真机 / 模拟器截图走 Debug 构建（`tools/install-device.sh` 就是 Debug），不受影响。

做不到 / 别自欺的：

- 别人拿到 ipa 一定可以反编译看逻辑；Swift 没有可靠的商业级混淆。
- 他们可以**改自己的包**绕过判断 —— 但改完只是他自己免费用，不会影响别人
  （凭证仍绑设备码，改动也签不出新凭证）。
- 真正的风险是**私钥泄漏**，不是二进制被看。私钥只在本机 `tools/license-gen/`。

## 外观 / 字体大小 / 语言（2026-11-04 主人定）

设置页「通用」最前面三行：

1. **外观**：自动（跟随系统）/ 浅色 / 深色，二级页三选一，打勾。
   实现：`AppearanceSettings.mode` 存 App Group，根视图 `AppearanceHost`
   用 `.preferredColorScheme` 生效。
   🔴 **不能在子层再设一次 `preferredColorScheme`**：子层设 nil 会把父层的
   "深色"重置回跟随系统（踩过一次，页面明明选了深色却不黑）。
2. **字体大小**：二级页 = 预览卡（右上"预览文字大小"气泡 + 两行示例）+
   「跟随系统」开关 + A—A 滑块（7 档，1.0 标准）+ 当前档位文案。
   实现：**全局倍率** `FontScale.value`，`AppTheme.TypeScale` 每档都乘它。
   🔴 `TypeScale` 由 `static let` 改成 `static var` 计算属性，否则设置改完不生效；
   🔴 SwiftUI 不会因为 static 变量变了就重算 body，根视图用 `.id(generation)` 强制重建。
   「跟随系统」把 `DynamicTypeSize` 映射成同一量级倍率（0.88…1.62）。
3. **语言**：不在 App 内做切换。点行 → `UIApplication.openSettingsURLString`
   跳到 设置 › App › Codelumi › 语言。界面显示「简体中文」。
   注：系统里那条语言项只有当 App 带多个本地化时才有可选项；当前只有简体中文，
   所以入口是"能到那儿"，暂时没有可切换项。

截图脚手架：`SCREEN=appearance` / `SCREEN=fontSize`，配 `APPEARANCE=system|light|dark`、
`FONT_STEP=0…6` 强制取值。

## 繁体中文（zh-Hant，2026-11-04）

系统语言是繁體中文时界面显示繁体；简体环境完全不受影响。

做法（自动化，非人工润色）：

- 文案表：`Codelumi/Codelumi/zh-Hant.lproj/Localizable.strings`（App）
  与 `Codelumi/CodelumiWidget/zh-Hant.lproj/Localizable.strings`（小组件）。
  **键 = 简体原文，值 = 繁体**。来源脚本：扫全部 Swift 里不带 `\(` 插值的中文字面量，
  用 `StringTransform("Hans-Hant")` 转换，再过一张术语表
  （設置→設定、短信→簡訊、默認→預設、保存→儲存、文件→檔案、信息→訊息、網絡→網路…）。
  当前 789 条映射 / 913 条候选 ≈ 86%。
- `Info.plist` 增加 `CFBundleLocalizations = [zh-Hans, zh-Hant]`，
  系统「设置 › App › Codelumi › 语言」里才会出现两个选项。

🔴 **坑：`Text(String)` 不查表**。`Text("字面量")` 会用 `LocalizedStringKey` 查表，
但我们的标题/详情/卡片多是**动态 String**（枚举、模型），必须显式 `x.L`。
目前已经接上的：`SettingsRow`（title/subtitle/detail）、`SectionHeader`。
其余页面里的动态字符串仍是简体 —— 要扩覆盖就在处加 `.L`（helper 在
`CodelumiShared/Localization.swift`）。

🔴 业务数据**不能进表**：快递公司名、驿站名、解析正则、OCR 关键词。
生成脚本已跳过 `PickupParser.swift` / `CourierBrand.swift` / `BrandPalette.swift` / `PickupAICheck.swift`。

验收：`xcrun simctl launch ... -AppleLanguages "(zh-Hant)" -AppleLocale zh_TW`
（`-AppleLanguages` 要放在 bundle id 之后，作为 App 参数传入）。

## 快捷指令自动化（2026-11-05）

设置 › 快捷指令自动化：把「收到短信 → 添加到Codelumi」的自动化导进系统。

🔴 **一键添加（iCloud 链接 / 文件导入）只在 iOS 27 及以上可用**（2026-11-11 主人定）。
iOS 26 及更早的系统不支持导入带触发器的自动化 → 引导页与设置页按
`if #available(iOS 27.0, *)` 分流：低版本不显示「添加 / 一键导入」按钮，
改为提示「照教程手动新建一条」。别为了好看在低版本也摆一个点不动的按钮。

**能力边界（都是实测结论，别再重试）**：

- 导出/导入的 `.shortcut` 文件**带触发器**（`WFWorkflowTriggers` = WFMessageTrigger
  +「信息 包含 关键词」），所以整条自动化可以导入；导入后**默认关闭**，
  必须用户自己去「快捷指令 › 自动化」打开开关。
- **未签名文件导入失败** → 必须 `shortcuts sign` 签名；签名只能在 Mac 上做，
  App 里无法当场生成自定义关键词的文件。
- **`WFWorkflowImportQuestions` 对触发器不生效**（B1/B2 两种 Category 都试过，
  能添加但不弹输入框）→ 自定义关键词这条路关闭，只能预定几个词。
- `shortcuts sign` 会**剥掉 `WFWorkflowName`** → 导入后的名称只能靠**文件名**，
  所以文件名必须是「Codelumi 取件码解析「关键词」.shortcut」。
- 🔴 生成脚本要**同时**写名称、关键词、UUID：2026-11-05 曾漏了关键词赋值，
  四个文件全是「【」，导致主人分享出去的三条链接全是错的（下载回来验过才发现）。
- 🔴 **动作参数的输入绑定不要写死成「触发器输出」**：2026-11-10 那批 wflow 里
  `text` 绑定的是 `{"Type": "TriggerOutput", "TriggerIdentifier": "WFMessageTrigger"}`，
  用户点开字段只能看到「输入」且无法改选（2026-11-11 主人反馈）。
  正解是绑 `{"Type": "ExtensionInput"}`（快捷指令输入），用户就能改成
  「输入快捷指令的信息 / 信息 / 剪贴板」任意一个。
- 🔴 **`inputOptions` / `inputConnectionBehavior` 是 iOS 16 起的 API**，
  别再说「iOS 18 才有」：那是 `AppEntity` / `FileEntity` 的 iOS 18 重载；
  `IntentParameter where Value.ValueType == String` 的初始化器在
  iPhoneOS27.2.sdk 里明确标 `@available(iOS 16.0, *)`，
  部署目标 iOS 17 可以直接写 `inputConnectionBehavior: .connectToPreviousIntentResult`。
  （2026-11-11 曾因此错误地把它删掉，导致手动添加动作时不会自动接上一环输出。）

**关键词与通知**：`【` 是默认推荐，`取 / 快递 / 包裹` 收进「可选关键词」。
理由：每多一条自动化就多一条系统「自动化已运行」通知，而 **iOS 27.2 起这条通知
已无法关闭**（此前可在「设置 › 屏幕时间」里关），所以默认只推一条。

**iCloud 链接（2026-11-10 已换新）**：改名成 Codelumi 后，4 个 `.shortcut` 资源已全部拆包、
把 App Intent 的 bundle id / 名称 / Team 改掉，并用 `shortcuts sign -m anyone` 重新签名
（`Codelumi/Codelumi/Resources/Automations/`）。主人用快捷指令 App 重新分享后，
`ShortcutAutomation.icloudLinks` 里的 4 条已全部回填为新包链接（均验证 HTTP 200 可下载）。
⚠️ 旧包（含 `com.jikezhang.codeclip`）的 4 条链接已作废，别再把它们填回去；
以后换 bundle id 或改动作定义，这 4 条必须重新分享。

## 免费签名的 7 天怎么算（2026-11-05 踩坑）

> ⚠️ 2026-11-10 起已改用**付费开发者账号**（Team `8499X3S9X8`），描述文件 1 年有效，
> 下面这段「7 天」是付费账号到位之前的记录，只在重新退回免费 Personal Team 时才有参考价值。

主人问「为什么不到 7 天就不能用了」。真相：**7 天从苹果签发描述文件那一刻算，
不是从装机算。**

实测证据：导出的 0.3.3(80) 包里 profile

```
CreationDate   2026-10-27T16:08Z
ExpirationDate 2026-11-03T16:08Z
```

11-01 装上去，11-03 就失效 —— 装机时只剩 2 天多。原因是 Xcode 会**复用缓存里的
profile**，只要没过期就不重新签发。

对策（已写进 `tools/install-device.sh`）：

- 构建前删掉缓存里属于本 bundle 的 `.mobileprovision`；
  ⚠️ **2026-11-05 实测：这并不会让苹果提前签发新的** —— 旧 profile 没过期时，
  重新下载拿回的是同一份，到期日不变。删缓存只清得掉"已过期的"。
- 安装完成后打印描述文件到期时间（`${EXP}` 必须带花括号，后面紧跟全角括号会吞字节）。

另加 `tools/profile-expiry.sh`：

```bash
tools/profile-expiry.sh                      # 看真机构建产物还剩几天
tools/profile-expiry.sh path/to/X.ipa         # 看某个 ipa
```

长期方案还是 SideStore / 付费开发者账号（1 年）。

**App 内也能看到剩余天数**：设置 › 激活 › 当前状态 ›「iOS 签名」。
⚠️ 2026-11-07 起设置里已没有「激活」入口，这一行现在只有 `SCREEN=activation` 脚手架可见。
实现是 `SigningProfile` 直接读 bundle 里的 `embedded.mobileprovision`
（CMS 里原样嵌着 XML plist，切出 `<?xml … </plist>` 解析 `ExpirationDate`，不联网）。
App Store 版没有这个文件 → 整行自动不显示。

**到期前一天会推本地通知**（`SigningExpiryNotifier`）：每次冷启动用固定 identifier
重排一次「到期前 24 小时」的提醒，重复启动不会堆叠。
真机日志可验证：`[signingNotify] scheduled at=2026-11-10T17:07:24Z`（到期 11-11）。

## 端侧 AI 与地址兜底（2026-11-05）

🔴 **定位（2026-11-21 主人再次明确）**：端侧智能是**正则解析的辅助**，不是二选一。
`PickupParser` 的正则负责主解析（快、稳定、可回归），端侧模型只在**正则没捞到某个字段**时补一刀，
把结果补完整；两条红线不变：**只填空不覆盖**（尤其取件码）、**不可用就当没有**。
对外文案不要写成「能用 AI 就用 AI、不能用退回正则」——正确说法是「正则为主、端侧智能辅助补齐与校对」。

**端侧大模型（FoundationModels）在国内机型上不可用**：`SystemLanguageModel.default.availability`
返回 `.unavailable(.deviceNotEligible)`，机型 iPhone17,1 / iOS 27.3 / 地区 CN，
`supportsLocale(zh_CN)` 为 true —— 排除语言问题，是系统层面的资格判定。

- 写作工具在**任何 App** 都能用，那是系统级能力；与第三方 App 调用端侧模型是两条通道。
- 设置 ›「Apple 智能」可随时查看（`SCREEN=aiCapability` 截图脚手架）。
- 🔴 **2026-11-20 主人：第三方模型通道（BYOK：DeepSeek / 豆包 / 千问 / Kimi）整条删除**。
  App 只保留 Apple 端侧能力，**不接任何第三方服务、没有 API Key、不发起网络请求**；
  `AIProviderStore` / `AIExtensionEnhancer` / `AIUsageStore` / `AIExtensionsView` / `AIUsageView`
  已删，设置里那一页直接进「Apple 智能」检测页。别再把这条通道加回来。
- 不可用时解析链自动退回纯正则，功能不受影响。

**地址兜底改用 NaturalLanguage**（不依赖 AI 资格、纯本地）：
`PickupParser.naturalLanguageAddress(from:)` 用 `NLTagger(.nameType)` 找地名锚点，
向右扩展到句读/取件码关键字，**只在公式没抓到地址时**启用。

回归结果（改前 → 改后）：

```
全量库  识别 193/514 不变，地址 190 → 191
精选库  识别 64/64  不变，地址 60 → 62
```

🔴 改这里的铁律：兜底**只能填空**，不得覆盖已抓到的地址 —— 否则语料命中数会掉。

## 设计规范：skills/apple-hig（2026-11-21 接入）

Apple HIG **全站主题**的离线镜像（**167 篇**，基础 / 组件 / 模式 / 输入 / 技术 / 平台全覆盖），
原文逐字、未改写，放在 `skills/apple-hig/references/`；`SKILL.md` 里有索引表、**「本项目必须守的 12 条」**
和一张**「有意识的偏离」**表（App 内外观设置 / 字号滑块——官方不建议，但用户明确要了）。

抓取/更新用 `tools/fetch-hig.py`：`python3 tools/fetch-hig.py --missing` 补新主题、
`--all` 全量重抓、也可以直接列 slug（如 `… widgets tab-bars`）。**原文只替换不改写。**

🔴 改任何一屏 UI、文案、字号、图标、动效、权限请求之前，先读 `SKILL.md` 的 12 条；
要原文依据就 `grep` 对应 `references/*.md`。**别凭印象说「Apple 就是这么设计的」。**

⚠️ 官方页面是 SPA，`curl` 拿到的 HTML 只有导航壳；正文要从
`https://developer.apple.com/tutorials/data/cn/design/human-interface-guidelines/<slug>.json` 取。
Safari 存的 `.webarchive` 同样只有壳（导航卡片在、正文不在），别拿它当底稿。

## iPhone Duo 适配：skills/iphone-duo（2026-11-21 接入）

官方 HIG《针对 iPhone Duo 设计》+《Preparing your app for iPhone Duo》扒下来整理的技能包，
不是二手总结：`skills/iphone-duo/references/hig-designing-for-iphone-duo.md` 是页面原文（6.9 KB），
`references/dev-preparing-your-app.md` 是开发者指南要点 + API 对照，
`references/api.md` 的签名与可用性全部对 `iPhoneOS27.2.sdk` 核过（`ReservedRegion` /
`ArrangementView` / `toolbarVerticalBehavior` 都是 **iOS 27.1 起**）。

**动 Duo 相关代码前先读 `skills/iphone-duo/SKILL.md`**，三条铁律：
按窗口几何判据（不用 idiom / 方向 / 机型名 / `UIScreen.main`）、系统容器优先、
折叠时只做小幅调整。

🔴 两条血泪已写进 `references/pitfalls.md`，别再犯：
1. **Duo 内屏横屏的系统标签栏被系统摆进右侧 84pt 保留区，那里收不到触摸**
   → 表现是「看得见点不动」（探针 + 程序化点击已证实，见 `交接说明_dsh.md` §24.4）；
2. **不要抓 `UITabBar` 改 transform / alpha / `isUserInteractionEnabled`**
   → 系统会换实例，恢复逻辑失效，整条栏永久不可交互。

⚠️ **2026-11-21 更正**：第 1 条的成因查清了 —— 展开态
`window.reservedRegions(kind: .occlusion)` 返回 **0 个**，但 `safeAreaInsets.right` 仍是 84，
是**模拟器给的幽灵安全区**；系统据此把竖排栏摆进 `x882…951`，那带子不吃触摸。
真机完全展开无摄像头遮挡，不应出现。主人当天定：**保持系统原生竖排（方案 A），
记为环境限制**；备选 B `.toolbarVerticalBehavior(.disabled)`（iOS 27.1+）能让栏回底部横排、点得动，
但不是 Duo 的设计。详见 `交接说明_dsh.md` §27 与 `skills/iphone-duo/references/pitfalls.md` 第 8 条。

📄 仓库根另有两份 Duo 文档：`iPhone Duo 官方设计规范笔记_v1.md`（Tech Talks 逐字整理，**冲突时以它为准**）
与 `iPhone Duo 折叠屏开发实战笔记_v1.md`（代码事实层，对应构建 321）。

## 去 AI 味：skills/unslop-ios（2026-11-08 接入）

iOS/SwiftUI 版的 unslop —— 把「一眼 AI 生成」的界面改回有设计感的界面。
改编自 Damir Sokolovsky（[@heydamir](https://x.com/heydamir)）的
[unslop](https://github.com/heydamir/unslop)（CC BY 4.0，署名保留在文件头），
针对 SwiftUI + 本项目重写。

| 文件 | 作用 |
|---|---|
| `skills/unslop-ios/SKILL.md` | 完整流程：定方向（5 行）→ 按间距→颜色→字号→图标→文案→布局→动效 修 7 遍 |
| `skills/unslop-ios/references/signs-ios.md` | iOS 专属 slop 迹象清单（含本项目踩过的坑） |
| `tools/unslop-ui-check.sh` | 能自动判的 6 条：界面 emoji、写死字号、`**` 残留、同名行、营销词、hInset 叠加 |

**什么时候用**：要新建/改版任何一个界面之前，以及每次视觉收口；上架前整屏过一遍。

```bash
bash tools/unslop-ui-check.sh     # 自动项，退出码 1 表示有命中
```

🔴 两条来自实战的硬规矩（都写进了 SKILL.md）：
- **同一功能不要两个入口**（2026-11-08：快捷指令自动化 vs 使用教程，已合并）；
- **同一事实不要写两遍**（同日：教程里的产品卖点与「关于 › 软件说明」重复，已删）。

## 质量门禁：mobile-unslop（2026-11-08 接入）

iOS/SwiftUI 专用的「AI 味代码」审计器（`npx mobile-unslop-mcp`），
查崩溃隐患、无障碍缺失、写死尺寸、release 里 print 等。

```bash
bash tools/unslop-audit.sh            # 审我们三个源码目录（默认屏蔽字号规则）
bash tools/unslop-audit.sh --all      # 不屏蔽
bash tools/unslop-audit.sh --changed  # 只审未提交改动
bash tools/unslop-audit.sh --json     # 机器可读
```

- 默认屏蔽 `SWIFT_FIXED_FONT_SIZE`：我们**故意**用数值字号（`TypeScale` 六档 ×
  `FontScale` 全局倍率），规则看不穿这层封装，会刷 220 条噪音；
- 退出码：有 ERROR 即 1（可挂 CI/pre-commit）。
- ⚠️ 同名的 `unslop`（npm 上的 JS linter）**不要用**：它只解析 JS/TS，
  扫本仓库输出 `Parsed 0 files`。

当前基线（2026-11-08，80 个文件）：**8 error / 41 warning**
（已屏蔽字号规则后）。8 个 error 是：
- 6 × `SWIFT_ICON_BUTTON_UNLABELLED`：纯图标按钮缺无障碍标签；
- 2 × `SWIFT_DEVICE_SIZE_HARDCODE`：分享卡导出图写死 390×500（有意为之，
  那是**图片尺寸**不是布局尺寸，可加注释豁免）。

## 系统兼容基线（2026-11-11 下调到 iOS 17.0）

```
部署目标：iOS 17.0（App 与小组件扩展一致）
```

| 设备 | 需要兼容 | 说明 |
|---|---|---|
| iPhone 直板机 / iPad | **iOS 17.0+** | 主力兼容范围（2026-11-11 主人要求从 18.0 下调） |
| **iPhone Duo** | **iOS 27+ 即可** | 🔴 它出厂系统就是 iOS 27，**不必适配 iOS 26 以下**；Duo 专属代码可直接用 iOS 26/27 API |

**iOS 17/18 兼容做法（2026-11-11）**：`widgetAccentedRenderingMode`（iOS 18）已收进
`Codelumi/CodelumiShared/GlassCompat.swift` 的 `Image.widgetAccentedFullColor()`（低版本原样返回）。
⚠️ `@Parameter` 的两个初始化参数要分清版本：
`inputConnectionBehavior` / `inputOptions` 属于 **`String` 参数、iOS 16.0 起**（可放心用，
2026-11-11 曾误判成 iOS 18 删掉，已恢复）；`supportedContentTypes` 只属于
`FileEntity`（iOS 18），`IntentFile` 参数没有这个参数，别再去找。
`IntentModes`（含 `.background`）是 iOS 26，部署目标 17 统一改用 `openAppWhenRun = false`。
🔴 `CodelumiShared` 在工程里是**显式 PBXGroup**（不是同步组）：新增文件必须手动加进
project.pbxproj 才会参与编译，否则报「value of type ... has no member」。

**iOS 18 实测记录（2026-11-08，iOS 18.2 模拟器 iPhone 16 Pro）**：
列表 / 详情 / 设置 / 外观 / Apple 智能 / 桌面小组件全部正常；「液态玻璃」开关在 18 上**正确隐藏**；
Apple 智能页显示低版本说明页。发现并修掉一处：`appGlass()` 的 tint 早先画在 `.overlay`
（内容之上），把详情页「标记为已取」的**白字盖住**了 —— 已改为画在 `.background` 内。

🔴 **组件口径（2026-11-08 主人两次强调）**：
- iOS 26+ 一律用 **Apple 原生的液态玻璃组件**（`glassEffect`，经 `appGlass()`）；
- iOS 18 一律用 **Apple 原生材质组件**（`ultraThinMaterial` 等）；
- **不要自创装饰**：卡片不加左侧竖条之类的东西，卡面层次由品牌色淡染
  （`AppTheme.cardTintOpacity`，2026-11-08 从 0.08 调到 0.06 更淡）+ 发丝描边 + 圆角表达。

液态玻璃的处理：

- `.glassEffect` 是 iOS 26 新增，**所有调用必须走 `appGlass()`**（`CodelumiShared/GlassCompat.swift`）：
  系统 ≥26 且用户开关打开 → 真液态玻璃；否则 → 系统毛玻璃 `.ultraThinMaterial` + 0.5pt 描边。
- 设置 › 外观 ›「液态玻璃」开关（仅 iOS 26+ 显示）控制是否启用，界面改动重启生效。
- 其它已处理的低版本 API：`tabBarMinimizeBehavior`（modifier 收起）、
  `Glass` 类型（改 `actionTint` + `appGlass`）、`SystemLanguageModel` 全家（`@available(iOS 26)` + 低版本说明页）、
  `IntentModes`（改 `openAppWhenRun`）、`systemExtraLargePortrait`（可用性判断）。

## 免费版功能边界（2026-11-07 定稿）

**只限制这三处，别的都放开**（2026-11-07 试过"点开关弹付费墙"的方案，主人当天否决）：

| 能力 | 免费版 | 说明 |
|---|---|---|
| 入库通知 / 定期提醒 / 超时提醒 | ✅ 全可用 | 不做门禁 |
| 桌面小组件显示开关 | ✅ 全可用 | 不做门禁 |
| 同屏列表条数 | 4 条 | `PickupLimits.freeVisible` |
| 存储上限 | 50 条（FIFO） | |
| 小组件可用尺寸 | 小 / 中 | 大尺寸与竖版超大仅 Pro |
| 实时活动 / 灵动岛 | 仅 Pro | |

🔴 小组件页那张「全部尺寸都在这里预览」的说明卡**只描述事实**，不要写成
"要不要解锁""订阅后可用"这类引导文案 —— 主人明确要求去掉引导订阅的措辞。

## ICP 备案（2026-11-06 通过）

```
陇ICP备2026011130号       审核通过 2026-11-06
```

- 🔴 **App 内不显示备案号**（2026-11-07 主人定）：Codelumi是无服务器、不联网的单机 App，
  唯一网络行为是 StoreKit（仅连 Apple），按官方口径「单机不联网的 App 无需备案」，
  走苹果豁免即可 —— 因此 `PageFooter` 只显示版本号。网站备案号仍留在开发者网站。
- 🔴 **网站备案 ≠ App 备案**：这次通过的是**网站/域名**备案（GitHub Pages、Gitee 镜像等
  HTTP 服务用它）。App Store 中国区上架还需要另外提交**移动互联网应用程序备案（App 备案）**，
  由接入服务商（云厂商/应用商店）通道提交，两者编号通常不同。
- 法律文档三处（GitHub Pages、Gitee 镜像、App 内 `Legal/*.html`）要一起改。

## TestFlight 发布（2026-11-11）

Apple **不会**把新构建自动挂到「外部测试」群组（内部测试组才会自动拿到所有构建），
每个构建都要「添加构建版本至群组」+ 填「测试内容」，所以做成了脚本：

```bash
/usr/bin/python3 tools/testflight-publish.py \
  --build 239 \
  --notes-file tools/testflight-notes/1.0.0-239.md
```

- 脚本做三件事（都可重复执行）：挂进外部群组「Codelumi公测」→ 写简体中文「测试内容」→
  提交 Beta App 审核（已 APPROVED / 等待审核 / 审核中会跳过）。
- 凭据：`~/.appstoreconnect/private_keys/AuthKey_34Z43R5SGY.p8`（Key ID `34Z43R5SGY`、
  Issuer `e2936bfc-e52b-4931-a763-9f03dec868e3`，可用 `ASC_KEY_ID` / `ASC_ISSUER_ID` /
  `ASC_KEY_PATH` 覆盖）。**私钥绝不入库**，`.gitignore` 已忽略 `*.p8`。
- ⚠️ 必须用 **`/usr/bin/python3`**（系统自带 3.9，带系统证书）。Homebrew / python.org 的
  3.14 会报 `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`。
- 测试内容写「本版实际改了什么 + 测试重点 + 需要哪些设备验证」，**不要写「解决了一些已知问题」**
  （2026-11-11 主人明确要求）。每版一个文件放在 `tools/testflight-notes/1.0.0-<构建号>.md`，
  和 `Codelumi/Codelumi/Views/VersionHistoryView.swift` 的版本条目同源、不要互相矛盾。
- 本机同时装了 `bsk` 浏览器工具链（`~/.local/bin/bsk`）：API 不可用时可借用户 Chrome 的
  已登录 ASC 页面兜底操作（`bsk session start` → `bsk tab borrow` → `bsk cooperate sync` →
  `bsk click/fill` → `bsk tab return` → `bsk session stop`）。

## iCloud 同步（2026-11-12 接入）

可选功能，**默认关闭**。关着的时候 App 一个字节都不碰 iCloud。

- **只走用户自己的 iCloud**（iCloud Drive 里的 `Documents/Codelumi/records.json`），
  不经过开发者服务器、不建账号；Apple 的隐私标签仍是「不收集数据」。
- **合并粒度是单条记录**：同 `id` 取 `updatedAt` 新的那份（老记录没有 `updatedAt`
  时回落 `receivedAt`）；删除用**墓碑**（`pickup-sync-tombstones.json`，90 天 TTL），
  这样另一台设备不会把删掉的记录同步回来。
- **不做后台常驻**：App 启动、回前台、数据改动后 1.5 秒、手动「立即同步」各同步一次。
  合并写回本机后压 3 秒再做下一次（`suppressScheduleUntil`），防「同步→写回→再同步」。
- 时间戳一律用**带小数秒的 ISO8601**（`PickupSyncCore.encoder/decoder`）：
  默认 `.iso8601` 会抹掉毫秒，导致「刚写完又判定有变化」的来回同步。
- 文件分工：`PickupSyncCore.swift`（纯合并规则，只依赖 Foundation + PickupRecord）、
  `PickupSyncStore.swift`（控制器 / 墓碑落盘 / 状态）、`PickupStore`（盖 `updatedAt`、
  删除记墓碑、`applySynced` 一次性写回）。
- **删除路径必须记墓碑**：`delete` / `deleteMany` / `clearPickedUp` / FIFO 淘汰，
  漏一处就会出现「删了又被另一台设备同步回来」。
- 自测脚手架（Debug，模拟器没登 iCloud 时用）：
  ```
  SIMCTL_CHILD_ALLUDE_SYNC_ENABLED=1 \
  SIMCTL_CHILD_ALLUDE_SYNC_REMOTE=/tmp/sync-test \
  xcrun simctl launch --terminate-running-process <UDID> com.jikezhang.codelumi
  ```
  两个模拟器指同一个目录就等于「两台设备」。验证点：远端改一条 → App 变已取；
  远端加墓碑 → 记录消失；连续启动两次 `records.json` 的 md5 不变（幂等）。
- ⚠️ **签名前置**：`Codelumi/Config/Codelumi.entitlements` 有
  `com.apple.developer.ubiquity-container-identifiers = iCloud.com.jikezhang.codelumi`，
  `Codelumi/Info.plist` 有 `NSUbiquitousContainers`；但**开发者账号里这个 App ID 还没开 iCloud 能力**，
  `xcodebuild archive` 会报「Provisioning profile doesn't match the entitlements file's value for
  com.apple.developer.ubiquity-container-identifiers」。需要在 Xcode › Signing & Capabilities
  里给 Codelumi target 加 iCloud（勾 iCloud Documents，容器 `iCloud.com.jikezhang.codelumi`），
  或在开发者门户里给 App ID 打开 iCloud 并建容器，之后 `-allowProvisioningUpdates` 才能过。
- 法务三处已同步（App 内 HTML、GitHub `codelumi-legal`、Gitee 镜像）：隐私政策新增
  「6. iCloud 同步（可选，默认关闭）」，使用条款新增「4A. iCloud 同步」，
  页脚/同意页改成「默认只在本机，开启 iCloud 同步后也只在你自己的 iCloud 里」。

## 提交规范

署名 `极客ZHANG <zhang_wangning@126.com>`。提交信息用中文，
前缀 `feat:` / `fix:` / `refactor:` / `style:` / `docs:` / `chore:`。

远端：`https://github.com/Zhangwangning/Codelumi`（私有）。
