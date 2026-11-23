# Allude 项目移交说明（面向 dsh）

> 生成时间：**2026-11-20**，对应构建 **1.0.0 (321)**，工作区 `main` 分支干净。
> 本文所有结论都来自**本机实测 + App Store Connect 实际返回值**，不是回忆。凡标 ⚠️ 的地方，都建议你重新核对一次。
> 前一版交接文档 `交接说明_workbuddy.md`（2026-11-15，312）**已部分过时**，以本文为准。

---

## 0. 一页速览

| 项 | 现状（2026-11-20 实测） |
|---|---|
| 产品 | **Allude**：iOS 取件码收纳 App。核心承诺「数据只在本机，不联网、不上传、不需要注册」 |
| 形态 | 纯 iPhone（`TARGETED_DEVICE_FAMILY = 1`），部署目标 **iOS 17.0**，SwiftUI，零第三方依赖、零 SPM |
| 版本 | `MARKETING_VERSION = 1.0.0`，`CURRENT_PROJECT_VERSION = 321`（pbxproj 里四处同步） |
| 代码量 | **98 个 Swift 文件 / 37,273 行**（App 21,936 + 模型 7,044 + 共享 6,579 + 小组件 281 + 入口 1,391） |
| 仓库 | `https://github.com/Zhangwangning/Allude`（**私有**），分支 `main`，**430 次提交**，起点 2026-10-16（前身 CodeClip） |
| TestFlight | 构建 **321** 已 `VALID`，Beta 审核 **APPROVED**，已挂外部群组「Allude公测」，测试内容已写 |
| App Store | 1.0.0 = **REJECTED**（绑构建 309）—— 见 §2.1，这是接手后的**第一优先事项** |
| 内购 | `pro.lifetime`（非消耗型）、`pro.annual`（自动续期订阅）均为 **READY_TO_SUBMIT**，尚未随版本提交 |
| 免费额度 | 同屏 **4** 条、本机最多 **60** 条（FIFO 淘汰）、搜索到的记录打不开详情；Pro 全部放开 |

### 接手后必须立刻知道的三件事

1. **1.0.0 已被 App Review 拒了**（`appStoreState = REJECTED`，仍绑旧构建 309）。拒绝理由只能登录 App Store Connect → Resolution Center 看，公开 API 读不到。本文不臆测原因。
2. **两个内购还停在 `READY_TO_SUBMIT`**，没和任何版本一起提交过。App 免费下载 + 内购解锁是唯一商业模式，内购不提交 = 上线即无收入。
3. **中国大陆上架还缺 App 备案号**。网站 ICP（陇ICP备2026011130号）已通过，但 App 备案是**另一套流程**，见 §11.3。

---

## 1. 产品定位与商业模式

### 1.1 数据流

```
快递短信 → 快捷指令自动化（触发：信息内容包含「」/【）
        → App Intents 后台静默写入（不打开 App）
        → PickupParser 四套正则 + 优先级链解析
        → PickupStore 落盘（本机 JSON）
        → 待取列表 / 桌面小组件 / 灵动岛 / 锁屏实时活动 / 统计
```

**唯一网络行为**：① StoreKit（只连 Apple）；② 用户**自己**开的三方大模型增强（BYOK，App 直连服务商，不经开发者服务器）。没有账号体系、没有自建后端。

### 1.2 收费模型（免费下载 + 订阅解锁，按系统订阅页惯例）

| 商品 | Product ID | 形态 | 备注 |
|---|---|---|---|
| 每年 | `com.jikezhang.allude.pro.annual` | 自动续期订阅 | 定价由 ASC 配，代码只读 `Product.displayPrice` |
| 终身 | `com.jikezhang.allude.pro.lifetime` | 非消耗型买断 | **主推** |
| ~~每月~~ | `pro.monthly` | 已下架 | `PurchaseStore.Plan.monthly` 只为解码老数据保留 |

- 权益判定：**任意一档有效 = 完整版**（`EntitlementSnapshot.licensedPro`）。
- 🔴 订阅必须把 `expiresAt` 写进权益快照（`entitlement.json`）。小组件进程不联网、不查 StoreKit，只读快照；漏了到期时间，订阅过期后小组件会一直按 Pro 渲染。
- 🔴 `MembershipPlan` 枚举**只增不删**：删 case = 老快照解码失败 = 用户静默掉回免费版。

### 1.3 免费 / Pro 边界（代码里的唯一事实来源）

`AlludeShared/PickupStorage.swift` → `enum PickupLimits`：

| 常量 | 值 | 含义 |
|---|---|---|
| `freeVisible` | **4** | 列表与小组件同屏条数 |
| `freeStorage` | **50** | 本机存储上限，超出 FIFO 淘汰最旧（只在 `ingest()` 触发，启动不删） |
| `unlimited` | 9,999 | 代替 `Int.max`，避免 `count - limit` 溢出崩溃 |
| `widgetListCap` | 60 | 小组件可翻动上限（头部总数仍显真实值） |

Pro 另解锁：不限条数、全尺寸小组件、实时活动、重复提醒、到达提醒、AI 增强。

---

## 2. 当前进度（逐项实测）

### 2.1 App Store 上架：**被拒**

```
版本 1.0.0 · appStoreState = REJECTED · reviewType = APP_STORE
releaseType = SCHEDULED · earliestReleaseDate = 2026-11-30T09:00:00-08:00
关联构建 = 309（VALID）· 本地化 zh-Hans · 截图集 APP_IPHONE_67（6.7 寸）
描述长度 403 字符 · 关键词 13 个
```

**要做的事**：
1. 登录 ASC → 该 App → **Resolution Center**，读拒信原文（Guideline 条款 + 截图/录屏附件）。
2. 按拒信修；`tools/appstore-review/1.0.0-notes.md` 里有上一轮给 Apple 的说明稿，可复用。
3. 修完把版本重新绑到新构建（`appStoreVersion` → build 关系），再提交。
4. ⚠️ `earliestReleaseDate` 是 **2026-11-30**，手动放行前不会自动上架。

### 2.2 TestFlight：正常

- 构建 321：`processingState = VALID`、Beta 审核 `APPROVED`，已挂「Allude公测」(`c90099fc-1862-4b2a-8f48-a7537111fe45`)。
- 历史构建 317 已过期，318/319/320/321 均 VALID。
- 发版脚本：`tools/testflight-publish.py`（挂群组 + 写测试内容 + 提交 Beta 审核，一条命令）。

### 2.3 内购：**待提交**

`pro.lifetime` / `pro.annual` 均为 `READY_TO_SUBMIT`，各有价格配置。首次必须**随 App 版本一起**提交审核；提交前在 ASC 里确认中国区价格已生效（历史上出现过「中国区价格未生成 → 沙盒回落 USD 基准价」）。

### 2.4 法务与备案

- 隐私政策 / 使用条款有**三份副本必须同步**：GitHub Pages（`Zhangwangning/allude-legal`，App Store 表单填这个）、Gitee 镜像（`zhang_wangning/allude-legal`）、App 内打包的 `Allude/Allude/Legal/{privacy,terms}.html`。
- 地址集中写在 `Allude/Models/LegalLinks.swift`。这些 URL 已填进 ASC 审核表单，**不要改**；确需更换必须让旧地址 301 过去。
- App 备案：见 §11.3。

---

## 3. 代码结构

### 3.1 三层同名，别数错目录

```
Allude/                        ← 仓库根（.git 在这里）
├── Allude/                    ← 工程根
│   ├── Allude.xcodeproj
│   ├── Allude/                ← App 源码（同步组，新增文件不用改 pbxproj）
│   │   ├── AlludeApp.swift    ← 入口 + 脚手架（1,391 行）
│   │   ├── Views/             ← 42 文件 / 21,936 行
│   │   ├── Models/            ← 32 文件 / 7,044 行
│   │   └── Legal/*.html       ← 隐私政策与条款（WKWebView 离线读）
│   ├── AlludeShared/          ← App 与小组件共用（🔴 显式 PBXGroup，新增文件必须手动进 pbxproj 三处）
│   ├── AlludeWidget/          ← 小组件扩展（🔴 同样是显式 PBXGroup）
│   ├── Config/*.entitlements
│   ├── Info.plist             ← GENERATE_INFOPLIST_FILE=NO，改键必须改这个真实文件
│   └── tools/                 ← 工程级自检（activity-race / parse-check）
├── tools/                     ← 仓库级脚本（发版、回归、素材）
├── .workbuddy/memory/         ← 逐日踩坑日志（**改模块前必翻**）
├── AGENTS.md                  ← 项目硬规则，先读完再动手
└── 交接说明_*.md
```

### 3.2 需要认识的文件（按重要度）

| 文件 | 行数 | 职责 |
|---|---|---|
| `AlludeApp.swift` | 1,391 | 入口、环境注入、**全部 `SCREEN=` 截图脚手架**、快捷指令回传路由 |
| `Views/PickupListView.swift` | 1,886 | 待取页：搜索、四种分组、多选、撤销、驿站内排序、性能缓存 |
| `Views/HistoryView.swift` | 1,503 | 已取页 + 统计页（`StatsCache`、图表自绘 Path） |
| `Views/ProfileView.swift` | 1,464 | 设置页根（`LazyVStack`，几十行设置项） |
| `Views/RootView.swift` | 1,239 | 四 Tab 容器、分栏判定 `PadLayout`、降级卡片回收 |
| `Views/DesignSystem.swift` | 1,137 | 快递公司/驿站管理网格、通用卡片与网格组件 |
| `Views/PickupShareCard.swift` | 1,037 | 分享卡渲染（图片导出） |
| `Views/ScanPickupSheet.swift` | 892 | 拍照/相册识别 → OCR → 解析 |
| `Views/ActivityPreviewGallery.swift` | 872 | 灵动岛/锁屏实时活动预览与验收 |
| `Views/RecordDetailView.swift` | 847 | 记录详情（Pro 门禁在搜索场景生效） |
| `Views/StationGroupEditView.swift` | 737 | 驿站组编辑（图标三格 + 位置 + 成员） |
| `Models/Models.swift` | 1,081 | `PickupRecord` / `PickupStore`（唯一状态源）、`PerfProbe`、`FrameMonitor` |
| `Models/PickupParser.swift` | 971 | 解析引擎（四正则 + 优先级链 + 三层误判闸门），**只依赖 Foundation，可独立编译回归** |
| `Models/SmsLibrary.swift` | 589 | 内置语料与品牌词表 |
| `Models/PickupNotifier.swift` | 441 | 本地通知、重复提醒 |
| `Models/PurchaseStore.swift` | 271 | StoreKit 2、权益快照写盘 |
| `AlludeShared/PickupStorage.swift` | 1,112 | 本机持久化、App Group 回落、`PickupLimits`、`PickupSortLogic` |
| `AlludeShared/PickupActivityAttributes.swift` | 924 | 灵动岛/锁屏实时活动数据与尺寸 |
| `AlludeShared/CourierBrand.swift` | 765 | 品牌词表 + 图标取色 |
| `AlludeShared/WidgetVisuals.swift` | 727 | 小组件视觉与裁剪逻辑 |
| `AlludeShared/PickupModels.swift` | 718 | 跨进程共享模型（`WidgetSnapshot` 等） |
| `AlludeShared/StationGroups.swift` | 608 | **驿站组 / 驿站 ID / 驿站内排序 / 取件码自然排序** |

### 3.3 改功能的入口索引

| 想改什么 | 去哪 |
|---|---|
| 解析规则 / 误判 | `Models/PickupParser.swift` + `tools/parser-regression/`（回归必须先跑） |
| 卡片长什么样 | `Views/PickupListView.swift`（待取）与 `Views/HistoryView.swift`（已取）**必须同构，改一处同步另一处** |
| 字号 / 颜色 / 圆角 | `AlludeShared/AppTheme.swift`（`TypeScale` 是唯一字号来源） |
| 小组件 / 灵动岛 | `AlludeWidget/` + `AlludeShared/PickupActivityAttributes.swift`（尺寸只在 `IslandExpandedMetrics`） |
| 驿站 / 组 / 排序 | `AlludeShared/StationGroups.swift` + `Views/DesignSystem.swift` + `Views/StationGroupEditView.swift` |
| 内购与权益 | `Models/PurchaseStore.swift` + `AlludeShared/OfflineLicense.swift` |
| iCloud 同步 | `Models/PickupSyncCore.swift`（纯合并规则）+ `PickupSyncStore.swift`（文件与通知） |
| 通知 | `Models/PickupNotifier.swift` / `PickupNotificationPresenter.swift` / `StationLocationService.swift`（围栏） |

---

## 4. 数据与存储

| 数据 | 位置 | 说明 |
|---|---|---|
| 取件记录 | App Group `Library/Application Support/pickup-records.json` | 无 App Group 时自动回落 App 自身 `Application Support`，不崩 |
| iCloud 副本 | `<iCloud 容器>/Documents/records.json`（容器 `iCloud.com.jikezhang.allude`） | 同步用；墓碑在 `pickup-sync-tombstones.json` |
| 驿站身份表 | 同目录 `station-identity.json` | 名字 ↔ 稳定 ID，**首次发号后落盘固化** |
| 驿站组 | 同目录 `station-groups.json` | 关系挂**成员 ID**，不挂名字 |
| 驿站位置 | `UserDefaults`（App Group 域）`station.locations.v1` | key 用**驿站名 / 组名** |
| 权益快照 | `entitlement.json` | 小组件只读它，必须带 `expiresAt` |
| BYOK 密钥 | **Keychain**（service `com.jikezhang.allude.ai`） | 绝不进 JSON、不进日志 |
| 偏好 | App Group 域 | `allude.appIcon`、`allude.list.sort`、`allude.station.innerOrder` 等 |

写入一律 `.atomic`。⚠️ 模拟器用 `CODE_SIGNING_ALLOWED=NO` 构建时**没有 App Group**，扩展读不到共享域 —— 跨进程问题只能真机验。

---

## 5. 解析子系统（最容易被改坏的地方）

### 5.1 结构

- 移植自 iOS 快捷指令「快递取件码」V7.3.0 的六套 ICU 正则，**优先级链**：`code → waybill → tail → special`。
- 一码一卡原则：链式段须与首段同形（`codeShape`），纯数字段 ≥4 位。
- 字段口径：`company` = 平台（【】里的品牌），`courier` = 承运方。两者不可混。
- 新正则**必须注册进 `regexes` 预编译表**，否则静默返回 nil（踩过）。

### 5.2 三层误判防线（都是真样本逼出来的）

1. `isPendingDeliveryOnly` —— 「已发货/派送中」没取件码，不算取件。
2. `isPromotionalOnly` —— **营销话术 + 零取件线索，两条同时成立**才算推广。🔴 不能只凭「拒收请回复R」判死，真实驿站短信也常带这句。
3. `isVersionLikeCode` —— `glm-5` / `gpt-4` / `claude-3` 是版本号不是取件码。
4. 关键词闸门 `京东(?!卡)` —— 「京东卡」是营销奖品，不是承运方。

### 5.3 回归与语料

```bash
cd tools/parser-regression && swiftc -O *.swift -o /tmp/pr && /tmp/pr
```

- 语料：`短信语料库_v1.md`（509 行正文，449 段）；基线 **175 命中 / 274 正确拒绝 / 60 条去重**。
- 最近一次回归（321 前）：**64/64 识别、63/64 地址无回退**，6 条边界用例（含 2 条带「拒收请回复R」的真实驿站短信）全部通过。
- 新增品牌 / 新形态短信：先用 `标注模板*.tsv` 标注，再跑回归，**不要凭单条样本改核心公式**。

### 5.4 AI 增强（可选，默认关）

- 端侧：`Models/PickupAI.swift`（FoundationModels，系统不可用即降级）。
- 三方 BYOK：`Models/AIExtensionEnhancer.swift` + `AIProviderStore.swift`，四家（DeepSeek / 豆包 / 千问 / Kimi），**App 直连、不经服务器、不记短信原文**。
- 字段护栏：地址/驿站/柜位可采用模型值；公司名必须能归一化到已知品牌；**取件码必须原样出现在原文里**才允许改（防幻觉）。

---

## 6. 界面口径（改动前必读）

- 卡片主名 `titlePrimary = courier ?? company`；副名 `secondaryLabel`（组名/驿站）。列表卡 / 详情 / 锁屏 / 分组名 / 图标取色同一口径。
- 取件码恒用 `iconBrand`；卡面 `brand = company.isEmpty ? iconBrand : brandColor`。
- 字号只用 `AppTheme.TypeScale`：`rowTitle 17 / rowSubtitle 13 / body 15 / section 13 / note 12 / badge 11`；强调**只加 weight 不加字号**。例外仅图形类：chevron 12–13、等宽码。
- 通知：字段空就整段不出现，绝不用占位句凑行。
- 灵动岛展开必须用满 `.leading/.trailing/.bottom`，尺寸只在 `IslandExpandedMetrics` 改，改完强制 update 一次（有「内容一致跳过」分支）。
- 版本历史页 `Entry.id` **不能用 `UUID()`**（视图重建换 ID，折叠状态会弹回）。
- 图标 16 套：imageset 全部放 `AlludeShared/Assets.xcassets`（放 App catalog → 灵动岛/锁屏渲染灰块）；`Contents.json` 必须 `template-rendering-intent: original` + 1x/2x/3x。
- 岛内图标随 `ContentState.appIconRaw` 传，扩展**别自己读** `AppIconStore.current`。

更细的口径与踩坑见 `AGENTS.md` 与 `.workbuddy/memory/MEMORY.md`。

---

## 7. 驿站组 / 驿站 ID / 排序（当前最复杂的子系统）

- `AlludeShared/StationGroups.swift`（App + Widget 双 target，新增文件必须手动进 pbxproj 三处）。
- ID 前缀：内置 `NZYZ`、自定义 `DZYYZ`、组 `FZYD`，各 5 位补零，**首次发号落盘固化**，之后只追加，不能按下标实时算。
- 组数据字段：`id / name / memberIDs / createdAt / iconInheritMemberID / locationInheritMemberID`；关系挂成员 ID，改名走 `StationIdentity.rename`。
- 监控优先级三段：**组驿站 > 未归组驿站 > 组内成员**（组只监一个围栏，避免同地点推三次）。
- 图标继承两路：内置成员走 `CourierLogo`、自定义成员走 `iconFiles`；只查 `iconFiles` 会把内置驿站按组名首字画。
- `StationGroupStore.all()` **必须缓存** —— `StationLogo` 每画一格都问「这是不是组」。
- 取件码自然排序 `PickupCodeOrder`（321 新增）：切字母段/数字段，数字段去前导零后**先比位数再比字典序**（等价数值比较且不溢出 Int）；数字段排字母段前；同形回落原文。自带三态 `Order`，不用 `ComparisonResult`（纯 Swift 单文件编译不可用）；判断数字必须 `ch.isASCII && ch.isNumber`（`Character.isNumber` 对全角/罗马数字也 true）。

---

## 8. 构建、调试、取证

### 8.1 模拟器构建（**必须带 `-disable-sandbox`**）

```bash
cd Allude
xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

- 缺 `-disable-sandbox` → 宏插件拉不起子进程，报**假错误**（`StateMacro could not be found`、`SwipeActionRow.swift` 的 `'self' is immutable`）。那是工具链问题，别改业务代码。
- 🔴 **在 agent 会话内构建必定卡 CoreML**（`sandbox-exec: sandbox_apply: Operation not permitted`）。绕过：`mv Allude/Resources/AlludePickup.mlmodel{,.bak}` → 构建 → 还原。不需要生成 Swift 包装（`PickupClassifier` 按 Bundle 找 `.mlmodelc`）。
- clean build 必须 0 warning。

### 8.2 截图取证（命令行点不了屏幕）

无 idb / applesimutils，AppleScript 驱动模拟器会被辅助功能权限拒绝（`-10004`）。**所有面板靠 `SCREEN` 环境变量直渲**：

```bash
UDID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | ...)
xcrun simctl install $UDID /tmp/allude-verify/Build/Products/Debug-iphonesimulator/Allude.app
SIMCTL_CHILD_SCREEN=pending SIMCTL_CHILD_SKIP_PERM=1 \
  xcrun simctl launch --terminate-running-process $UDID com.jikezhang.allude
xcrun simctl io $UDID screenshot /tmp/shot.png
```

- 环境变量必须带 **`SIMCTL_CHILD_`**；`launch` 必须带 **`--terminate-running-process`**（否则只切前台，变量全不注入）。
- 装完**先核对 `CFBundleVersion`** 再截图，否则拍到上一版界面会误判「改动没生效」。
- 常用 `SCREEN`：`pending` / `pickedUp` / `stats` / `settings`（配 `SETTINGS_ANCHOR=about`）/ `gallery` / `stationGallery`（配 `STATION_ADD_DEMO=1`）/ `stationGroupEdit`（配 `GROUP_ID=`）/ `stationLocation` / `stationLocationPicker` / `detail` / `scan` / `share` / `notify` / `lockPreview` / `activityAudit`。
- 直写设置项的环境变量：`INNER_ORDER=codeAsc`、`CODE_OPACITY=`、`CODE_GROUP=1`、`SEED=<短信>`（配 `SCREEN=add`）、`SKIP_ONBOARDING=1`。
- ⚠️ **App Group 偏好不要用 `simctl spawn defaults write` 改**（写的是模拟器全局域，且 cfprefsd 会把旧值刷回容器 plist），用上面的环境变量接口。
- 模拟器 ID 会变，用 `xcrun simctl list devices` 现查。验 `if #available(iOS 27)` 必须用 iPhone 17 机型。

### 8.3 性能工具（DEBUG 专用）

- `PERF_LOG=1` → `PerfProbe` 统计各段耗时，写 `Documents/perf.log`（按总耗时降序）。
- `PERF_FPS=1` → `FrameMonitor` 记帧间隔分布 / 掉帧率 / 慢帧明细，写 `Documents/frames.log`。
- `xctrace record --template 'Time Profiler' --attach <pid> --time-limit 18s`，导出 `--xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'`；XML 里 frame 是 id 定义 + ref 引用，必须建表再解析。
- `Animation Hitches` 模板**模拟器不支持**，只能真机。
- 已做过的优化（321 前）：列表重计算记忆化（`displayed` 14 秒内 68 次访问只真算 1 次）、`revision` 版本号失效、设置页/统计页 `LazyVStack`、景深 blur 5→3、一键取件 O(n²)→O(n)、`windowSize` 100ms 缓存。范式：**计算属性缓存放 model（`@StateObject` 持有的 class），不放 View 的 `@State`**；缓存键用 `hashValue` 不用 `count`。

### 8.4 真机（唯一能验灵动岛的路）

```bash
DEST='platform=iOS,id=00008140-001138A92E01801C'    # iPhone 16 Pro
xcodebuild -project Allude.xcodeproj -scheme Allude -destination "$DEST" \
  -derivedDataPath /tmp/allude-device -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration OTHER_SWIFT_FLAGS="-disable-sandbox" build
```

`bash tools/install-device.sh` 已封装构建 + `devicectl` 装机。真机读写共享容器：

```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appGroupDataContainer --domain-identifier group.com.jikezhang.allude \
  --source "Library/Application Support/pickup-records.json" --destination /tmp/
```

---

## 9. 发版链路（321 实操，命令可照抄）

**前置结论：`xcodebuild -exportArchive` 在本机不可用**（无 GUI 时 `ITunesSoftwareService` 起不来）。只能手搓 ipa。

```bash
# 1) 改版本号：pbxproj 四处 CURRENT_PROJECT_VERSION（必须"先读进变量再写回"，内联 sed 会截断成 0 字节）
# 2) 归档（临时移出 mlmodel 绕开 CoreML 沙箱）
cd Allude
mv Allude/Resources/AlludePickup.mlmodel Allude/Resources/AlludePickup.mlmodel.bak
xcodebuild -project Allude.xcodeproj -scheme Allude -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/allude-archive321/Allude.xcarchive \
  -allowProvisioningUpdates OTHER_SWIFT_FLAGS="-disable-sandbox" archive
mv Allude/Resources/AlludePickup.mlmodel.bak Allude/Resources/AlludePickup.mlmodel

# 3) 包内删 .bak、补模型
APP=/tmp/allude-archive321/Allude.xcarchive/Products/Applications/Allude.app
rm -f "$APP/AlludePickup.mlmodel.bak"
xcrun coremlc compile Allude/Resources/AlludePickup.mlmodel /tmp/mlc321
cp -R /tmp/mlc321/AlludePickup.mlmodelc "$APP/"

# 4) 换描述文件 + 用「清洗过的」entitlements 重签（先 appex 后 App）
cp /tmp/AlludeApp.mobileprovision    "$APP/embedded.mobileprovision"
cp /tmp/AlludeWidget.mobileprovision "$APP/PlugIns/AlludeWidget.appex/embedded.mobileprovision"
codesign --force --sign "iPhone Distribution: Wangnjng Zhang (8499X3S9X8)" \
  --entitlements /tmp/dist-widget.entitlements "$APP/PlugIns/AlludeWidget.appex"
codesign --force --sign "iPhone Distribution: Wangnjng Zhang (8499X3S9X8)" \
  --entitlements /tmp/dist-app.entitlements "$APP"

# 5) 打包（必须传 Payload 目录，不能加 --sequesterRsrc）
rm -rf /tmp/ipa321 && mkdir -p /tmp/ipa321/Payload
cp -R "$APP" /tmp/ipa321/Payload/
cd /tmp/ipa321 && ditto -c -k --norsrc --keepParent Payload /tmp/Allude-321.ipa

# 6) 校验 + 上传
xcrun altool --validate-app -f /tmp/Allude-321.ipa -t ios \
  --apiKey 34Z43R5SGY --apiIssuer e2936bfc-e52b-4931-a763-9f03dec868e3
xcrun altool --upload-app  -f /tmp/Allude-321.ipa -t ios \
  --apiKey 34Z43R5SGY --apiIssuer e2936bfc-e52b-4931-a763-9f03dec868e3

# 7) 2–3 分钟转 VALID 后，挂群组 + 写测试内容 + 提 Beta 审核
cd /Volumes/ZWN/Downloads/Project/Allude
python3 tools/testflight-publish.py --build 321 --notes-file tools/testflight-notes/1.0.0-321.md
```

### 9.1 凭证与标识（都在本机，不入库）

| 项 | 值 / 位置 |
|---|---|
| Apple 团队 | `8499X3S9X8`（付费账号，automatic signing） |
| 分发证书 | `P76B23FF7S`，到期 **2027-11-15** |
| Provisioning Profile | App `7H29P7MJ8Q`（Name: Allude App Store 313）、Widget `4F62FDJ8K2`（M53D3TXT6B），均到期 **2027-11-15T14:55Z** |
| ASC API Key | `34Z43R5SGY`，私钥 `~/.appstoreconnect/private_keys/AuthKey_34Z43R5SGY.p8` |
| ASC Issuer | `e2936bfc-e52b-4931-a763-9f03dec868e3` |
| ASC App ID | `6833046947` |
| TestFlight 群组 | 「Allude公测」`c90099fc-1862-4b2a-8f48-a7537111fe45` |

🔴 **entitlements 不能照抄 profile**：`icloud-services = *`、`icloud-container-environment`、`ubiquity-kvstore-identifier = 团队.*` 都会被拒（90045/90046/90211）。`/tmp/dist-app.entitlements` 与 `/tmp/dist-widget.entitlements` 是清洗过的版本，**重启机器后它们是临时文件，会被清掉** —— 内容见 §9.2，请尽快拷进仓库 `tools/signing/` 并加 `.gitignore` 例外（entitlements 本身不含私钥，可以入库）。

### 9.2 清洗后的 entitlements（重建用）

App：
```xml
application-identifier = 8499X3S9X8.com.jikezhang.allude
aps-environment = production
beta-reports-active = true
get-task-allow = false
com.apple.developer.team-identifier = 8499X3S9X8
com.apple.developer.icloud-services = [CloudDocuments]
com.apple.developer.icloud-container-identifiers = [iCloud.com.jikezhang.allude]
com.apple.developer.ubiquity-container-identifiers = [iCloud.com.jikezhang.allude]
com.apple.security.application-groups = [group.com.jikezhang.allude]
keychain-access-groups = [8499X3S9X8.com.jikezhang.allude]
```
Widget：同上，去掉 iCloud / aps，`application-identifier` 与 `keychain-access-groups` 换成 `…allude.AlludeWidget`。

---

## 10. 工具脚本

| 脚本 | 用途 |
|---|---|
| `tools/testflight-publish.py` | 挂 TestFlight 群组 + 写测试内容 + 提 Beta 审核（ASC API，纯标准库） |
| `tools/parser-regression/` | 解析回归（`cases.txt` / `expected.txt`，可独立 `swiftc` 编译） |
| `tools/station-check/` | 驿站匹配回归（含对抗用例） |
| `tools/multi-parse-check/`、`dedupe-check/`、`notify-check/`、`ocr-pipeline-check/`、`brand-check/` | 各子系统自检（都能独立编译跑） |
| `tools/unslop-audit.sh`、`unslop-ui-check.sh` | 「AI 味代码 / UI」质量门禁 |
| `tools/verify-ios17.sh` | iOS 17 兼容回归 |
| `tools/widget-shots.sh` | 小组件真实渲染截图验收 |
| `tools/install-device.sh` / `dev-entitlement.sh` | 真机装机 / 真机权益切换（free↔lifetime） |
| `tools/profile-expiry.sh` | 描述文件到期检查 |
| `tools/import_app_icon.py`、`make_app_icon.py`、`extract_brand_palette.py`、`import_brand_logos.py` | 素材生成与入库 |
| `tools/license-gen/` | 旧离线凭证签发（**仅为读老快照保留**，界面上已无入口，别再加回来） |

---

## 11. 已知问题与债务

### 11.1 上架阻塞（P0）

1. **1.0.0 REJECTED**，理由待查（§2.1）。修完重新绑构建提交。
2. **内购未提交**（§2.3），首次必须随版本走。
3. **App 备案未完成**（§11.3），中国大陆区上架需备案号。

### 11.2 技术与验证债

| # | 问题 | 影响 | 建议 |
|---|---|---|---|
| 1 | 无 XCTest 单测，全靠 `tools/*-check` 可执行自检 | 重构风险靠人肉守 | 先把 parser / station / sort 三组自检接进 CI 或 pre-commit |
| 2 | 真机项未系统验证：灵动岛折叠/展开、锁屏实时活动、小组件组名、到达提醒围栏触发 | 模拟器测不出（无 App Group、无真实灵动岛） | 拿 iPhone 16 Pro 真机跑一遍 §8.4 清单 |
| 3 | iCloud 多设备一致性未充分压测 | 冲突合并可能丢状态 | 用两台真机做删除/勾选交叉测试，`PickupSyncCore` 是纯函数，可先补用例 |
| 4 | iPhone Duo 折叠屏只验了部分场景 | 分栏/竖屏标题曾出问题 | 用 iPhone Duo 模拟器三态（折叠/展开竖/展开横）各截一遍 |
| 5 | 解析误判依赖语料分布 | 新品牌/新话术可能误收 | 新样本先标注进 `标注模板*.tsv`，跑回归再改代码 |
| 6 | `BetaBuildLog.swift` / `VersionHistoryView.swift` 里的构建记录是**手写**的 | 发版容易忘加条目 | 发版 checklist 里固定一步 |
| 7 | 法务文本三副本 | 只改一处会造成商店页与 App 内不一致 | 改之前先 grep `LegalLinks.swift` |
| 8 | 性能只在模拟器量化过 | 真机可能不同 | 用 `PERF_LOG=1` / `PERF_FPS=1` 在真机取一轮基线 |
| 9 | `tools/station-check` 跑不起来（实测） | 驿站匹配回归缺一块 | 直接 `swiftc *.swift` 报 `cannot find 'CourierBrand' in scope`；把 `AlludeShared/CourierBrand.swift` 一起编译又报 `cannot find 'BrandPalette' / 'UIImage' / 'BrandDebug'`（该文件混了 UIKit 绘制层）。建议把驿站名匹配（`stationMatch`）拆成只依赖 Foundation 的 `StationMatch.swift`，`CourierBrand` 转发调用 |
| 10 | 模拟器构建必须手动移出 `.mlmodel` | 自动化流水线会被卡 | 给 CI 加一步预处理，或改用 `coremlc` 预编译后走 `-skipPackagePluginValidation` 之外的方案 |

### 11.3 App 备案（中国大陆）

- 网站 ICP：**陇ICP备2026011130号**（2026-11-06 通过，甘肃）。
- App 备案是**另一套编号**，在 `beian.miit.gov.cn` 提交（主体信息 + App 信息 → 省通信管理局审核）。详见 `App备案准备清单_v1.md`。
- 单机不联网 App 在 App 内不显示 ICP 号；但 **App Store 中国区表单需要填备案号**。

---

## 12. 交接清单

### 12.1 账号与仓库

- GitHub：`Zhangwangning/Allude`（私有，HTTPS + `gh auth login`，**不用 SSH**）。
- Gitee 镜像：`zhang_wangning/*`（历史遗留，Gitee 侧常落后；`~/.workbuddy/bin/gitee-github-sync.sh` 为手动同步脚本）。
- App Store Connect：App ID `6833046947`，Team `8499X3S9X8`（zhang_wangning@126.com）。
- 法务仓库：`Zhangwangning/allude-legal`（GitHub Pages）。

### 12.2 本机环境

- **Xcode 27.2（27B52）+ iOS SDK 27.2**，部署目标仍为 iOS 17.0；`xcrun simctl` / `devicectl` / `altool` / `coremlc` 均可用。
- 模拟器参考：iPhone 16 Pro（iOS 26.1）作日常回归；iPhone 17（iOS 27.2）验 `#available(iOS 27)`；iPhone Duo（27.2）验折叠。
- 真机调试机：iPhone 16 Pro `00008140-001138A92E01801C`（已在团队内注册）。

### 12.3 密钥纪律

- `AuthKey_*.p8`、`license-gen/private-key.pem`、分发证书私钥：**绝不入库**（`.gitignore` 已覆盖 `.p8`）。
- BYOK 的用户密钥只存 Keychain，不进 JSON / 日志 / 诊断包。

### 12.4 接手路线（建议）

**第 1 天**
1. 读完 `AGENTS.md` → 本文 → `.workbuddy/memory/MEMORY.md`（三份，顺序别反）。
2. 跑通模拟器构建（记得移出 `.mlmodel`）+ 装到 iPhone 16 Pro 模拟器 + `SCREEN=pending` 截一张图。
3. 跑 `tools/parser-regression`、`tools/station-check`、`tools/dedupe-check`，确认基线仍有 175/274。
4. **登录 ASC 看 Resolution Center**，把拒信原文与条款记下来（这是唯一 P0）。

**第 1 周**
5. 按拒信修，重新绑 321+ 构建提交审核；内购一并提交。
6. 真机跑一遍 §11.2 第 2 项清单，把结果补进本文。
7. 处理 §11.3 备案，同步 §11.2 第 6/7 项的发版 checklist。

**之后**
8. 补测试（先把三组自检脚本接到 pre-commit）。
9. 性能基线真机化，再谈优化。

---

## 13. 文档索引

| 文件 | 内容 |
|---|---|
| `AGENTS.md` | **项目硬规则**：构建参数、不可改的标识、权益枚举、图标流程、界面口径。第一优先 |
| `.workbuddy/memory/MEMORY.md` | 长期笔记（路径 / 构建 / 发版 / 踩坑浓缩版） |
| `.workbuddy/memory/2026-11-*.md` | 逐日踩坑日志，**改哪个模块先翻对应日期** |
| `交接说明_workbuddy.md` | 上一版交接（312），部分过时，仅作历史参考 |
| `产品与商业模式规格_v1.md` | 定位、定价、免费/Pro 边界的产品侧说明 |
| `快递短信解析规格_V803.md` | 六套正则与优先级链的完整规格 |
| `短信语料库_v1.md` | 449 段语料 + 覆盖基线 |
| `iPhone Duo 适配规范_v1.md` / `iPhone Duo 官方设计规范笔记_v1.md` | 折叠屏适配约定与官方依据 |
| `App备案准备清单_v1.md` | 备案流程与材料 |
| `竞品拆解与重构方案_v1.md` | 竞品分析与取舍依据 |
| `tools/testflight-notes/1.0.0-*.md` | 每版测试内容（写新版的模板） |
| `tools/appstore-review/1.0.0-notes.md` | 给 Apple 的审核说明稿 |

---

## 14. 一句话总结

代码与发版链路都是通的（321 已在 TestFlight 正常分发），**卡住上架的只有三件外部事情**：App Review 的拒信要读、内购要提交、备案号要拿到。技术债集中在「没有单测、真机验证不系统、驿站与解析两个子系统逻辑密度高」。接手时先按 §12.4 走，不要一上来改代码。

---

## 15. dsh 接手复核记录（2026-11-20）

只写**实测**结论，替代本文档里对不上的数字。跑法与命令见 §9 / §10。

### 15.1 与旧结论不符的四处

| 项 | 本文档原口径 | 2026-11-20 实测 |
|---|---|---|
| 免费存储上限 | 60 条（`PickupLimits.freeStorage`） | **50 条**。那个 60 从来没人读过，真正生效的是 `PickupStore.freeStorageLimit`（硬编码 50），订阅页/设置页显示的也是 50。已在本日合成一处：`PickupLimits.freeStorage = 50`，`PickupStore.freeStorageLimit` 引用它，**行为不变**。 |
| 解析回归基线 | 精选库「175 命中 / 274 拒绝」 | 口径对不上。实测：全量库 `短信语料库_v1.md` **识别 193/514、地址 192/514**（旧基线 192/189，均高 1，**无回归**）。 |
| `tools/station-check` | §11.2 第 9 项：跑不起来 | **已修**。真因不是 UIKit 混编，而是 `Allude/AlludeShared/CourierBrand.swift:720` 调 `.widgetAccentedFullColor()`（定义在 `GlassCompat.swift`，又会拉进 PickupStorage 整条链）。在 `tools/swift-cli-shim.swift` 的 `extension Image` 里补一个原样返回的同名方法即可，**匹配逻辑一行没动**。修完 63/63 精选 + 14/14 对抗样本全过。 |
| `tools/dedupe-check` | 未提 | 同样跑不起来：断言写的是 2026-09-21 那套旧口径，且用例索引越界崩溃。已按 `PickupModels.swift` 里 2026-10-30 的现有口径重写（同 id+同码+同驿站 才算重复；同码不同驿站 / 不同码同驿站 / 已取与待取 都不合并），28 条断言全过。 |

另：`tools/ocr-pipeline-check` 也不能只编 `PickupParser.swift` 了 —— 解析器现在会调
`PickupRecord.addressIsShelfOnly(_:shelf:)`，必须把 `PickupModels` 与它依赖的
（CourierBrand / PickupStorage / StationGroups / Localization / AppTheme / FontScale /
OfflineLicense / LicenseDevice + shim）一起编，且**本地不能再自定义 `PickupKind`**（会
`ambiguous for type lookup`）。完整命令已写进 `tools/ocr-pipeline-check/main.swift` 文件头。
`tools/brand-check` 仍是文档写明的 2 项既有业务差异，非回归，别去「修」。

### 15.2 构建与运行（可照抄）

```
cd Allude && xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```
- **clean build 实测 0 warning / BUILD SUCCEEDED**（2026-11-20，日志 `/tmp/allude-clean.build.log`）。
- ⚠️ agent 会话里跑构建前必须把 `Allude/Allude/Resources/AlludePickup.mlmodel` 临时移走
  （CoreML 编译会被 sandbox-exec 卡住），**跑完记得移回来**。
- 装机核对：iPhone 16 Pro 模拟器 `0211F7EF-0339-4BAF-B0D9-37521A0537AF`，
  `SCREEN=pending / add / pickedUp / stats / settings / license / appicon` 全部出图正常；
  订阅页在模拟器里两档都显示 `$0.99`（local StoreKit 配置，不是真实价）。

### 15.3 上架真实卡点（ASC API 实测，不是推测）

- 版本 `0d47d7bf-888e-4589-8a03-838658d34a4d`：1.0.0、`REJECTED`、`SCHEDULED`、
  最早放行 `2026-11-30T09:00:00-08:00`、挂的是 **build 309**。
- reviewSubmission `1c1857ec-d1da-4d33-bd70-80c44f2787f6`：`UNRESOLVED_ISSUES`（2026-11-15 提交）。
- `appStoreReviewDetail` `2de42837-aba8-4918-8973-f495a7e1a166` 的 notes **只有 128 字符**
  —— 苹果 2026-11-16 要求的 **2.1 Information Needed 六项一条都没写**。
- 两个内购 `pro.annual`(6833105878) / `pro.lifetime`(6833100079) 仍是 `READY_TO_SUBMIT`，
  **从未随版本提交过**（3.1.1 点名过）。
- 🔴 **§12.4 的「先按 checklist 走」有更新**：2.1 是信息不足，**不用打新包**。
  收口包（Notes 正文 3108 字符含预算核算 + 真机录屏脚本 + 待执行的 ASC 操作清单）在
  `tools/appstore-review/1.0.0-resubmit-2.1.md`，照它走即可。

### 15.4 顺带纠正的小口径

- App 图标是 **17 套**（`AppIconChoice` 有 icon01…icon17）。
  ⚠️ 2026-11-20 起主图标换成 **`icon07`「黑盒立体」**（详见 §16.1），
  `Allude/Info.plist` 声明 16 个 alternate（去掉 `Icon07`）。`AGENTS.md` 的「十六套」是旧数。

---

## 16. 2026-11-20 第二轮改动（主人当天新指令）

主人当场给的两件事：**默认图标换成第 7 个**、**第三方模型全部删掉，App 绝不使用任何互联网行为和服务**。
ASC 那边他说「先优化 App」，重提授权有，但要等他给录屏链接。

### 16.1 默认 App 图标 = 第 7 套「黑盒立体」

换默认必须**同时动三处**，少一处就会出现「设置里选了、系统图标没变」或反过来：

| 位置 | 改动 |
|---|---|
| `Allude/Allude/Assets.xcassets/AppIcon.appiconset/` | 三张 1024（Any / Dark / Tinted）换成黑盒立体 |
| 工程根 `Allude/Info.plist` | 旧默认（`Icon04`）插回 alternate 列表，新默认（`Icon07`）删掉声明 → 仍是 16 条 |
| `Allude/AlludeShared/AppIconChoice.swift` | `static let fallback: AppIconChoice = .icon07`（原 `.icon04`） |

- ⚠️ **没有 1024 原稿**：`tools/appicon-source/` 里只有 C 标源图与 icon13–19，
  `git log --diff-filter=D` 也查不到被删的 1024。所以从 `AppIcons/Icon07@3x.png`（180px）
  LANCZOS 升采样到 1024 + `UnsharpMask(2, 80, 2)`。**笔画略软，App Store 图标可用但不锐**；
  主人若能找到 1024 原稿，直接替换同名三张即可，代码不用动。
- 验证：装 `0211F7EF-0339-4BAF-B0D9-37521A0537AF` 后 `SCREEN=appicon` 勾已落在第 7 格，
  bundle 内 `AppIcon60x60@2x.png` 就是黑盒立体。
  🔴 光装机看不见主屏变化，必须 `xcrun simctl spawn <udid> killall SpringBoard`，
  否则看到的是旧的 icon 缓存（本次第一张截图就被缓存骗过）。
- 老用户不受影响：`AppIconStore` 的 `migrateLegacyNumberingIfNeeded()` 只管 01–16 那次重排，
  这次只换默认值，已选过图的用户仍是自己那张。

### 16.2 第三方模型通道整条删除

删掉的 5 个文件（都在 Xcode 同步组里，pbxproj 无引用，`rm` 即可）：

```
Allude/Allude/Views/AIExtensionsView.swift      653 行
Allude/Allude/Views/AIUsageView.swift           162 行
Allude/Allude/Models/AIProviderStore.swift      257 行
Allude/Allude/Models/AIExtensionEnhancer.swift  268 行
Allude/Allude/Models/AIUsageStore.swift         124 行
```

连带改的：

- `Allude/Allude/Views/ProfileView.swift`：`SettingsPane` 去掉 `.aiAppleIntelligence` /
  `.aiExtensions` / `.aiUsage` 三个 case；`.aiCapability` 标题改「Apple 智能」，
  `paneContent` 直达 `appleIntelligencePane`（不再经「扩展」总览）。
- `Allude/Allude/AlludeApp.swift`：删 `aiExtensions` / `aiUsage` / `aiHub` / `aiProvider`
  四个截图脚手架分支与 `AIHubScaffold`；`aiCapability` 保留。
- `Allude/Allude/Views/AICapabilityView.swift`：`qwenCard`（「可选：千问扩展」）换成
  `enableHintCard`（「怎么打开」＋跳系统设置），触发条件不变。
- `Allude/Allude/Views/DesignSystem.swift` + `AddPickupSheet.swift` + `ScanPickupSheet.swift`：
  删 `AIEnhanceHint`（读 `AIProviderSettings.anyReadyProvider`）及三处调用。
- `Allude/Allude/Models/Models.swift`：`ingest()` 里删 `AIExtensionEnhancer.schedule(merged.added)`；
  `PickupAIEnhancer.schedule`（纯 Apple 端侧）保留。
- 文案：`BetaBuildLog.swift` 删 47 行第三方相关更新（剩 60 条），
  `VersionHistoryView.swift` 1.0.0 主题改「…· iCloud 同步」、删 3 条第三方 highlights。
- 法务（App 内）：`Legal/privacy.html` 删第 12 节改写「12. 不使用第三方服务」、
  「运行方式」段改「没有第三方模型、没有 API Key、没有外部接口」；
  `Legal/terms.html` 删「4B. 第三方模型扩展」整节。
- `AGENTS.md`：图标段改十七套/默认第 7 套；端侧 AI 段补「第三方通道整条删除，别再加回来」。
- 审核 Notes（`tools/appstore-review/1.0.0-resubmit-2.1.md`）第 4 项改写成
  **「No AI or model service of any kind … Apart from StoreKit and the user's own optional
  iCloud container, the app contains no networking code and contacts no server.」**
  正文重新计数 **3170 字符**（+录屏长链 691 = 3861，仍在 4000 以内）。

🔴 **代码侧确认无联网**：全仓 `grep -rn "URLSession\|URLRequest\|NSURLConnection"` 在 app /
shared / widget 三个目录**零命中**，`https://` 只出现在 `LegalLinks.swift`（法务网址）、
`SmsLibrary.swift`（Debug 语料里的短信原文）、快捷指令签包链接。
`SmsLibrary` 整个包在 `#if DEBUG` 里，Release 不带。

### 16.3 自检与构建（改完重跑，全绿）

| 项 | 结果 |
|---|---|
| clean build | **BUILD SUCCEEDED，0 warning 0 error**（`/tmp/clean3.log`） |
| `tools/parser-regression 短信语料库_v1.md` | 识别 193/514、地址 192/514，与基线无回退 |
| `tools/station-check` | 63/63 精选 + 14/14 对抗样本 |
| `tools/dedupe-check` | 28 条断言全过（编译要 11 份文件，见 §15） |
| `tools/ocr-pipeline-check` | 端到端通过：C-4082 / 免喜生活 / 地址全对，银行短信已拦 |
| `tools/multi-parse-check` | 全部通过 |
| `tools/notify-check` | 全部通过 |
| `tools/brand-check` | 仍是既有 2 项业务差异（非回归） |

### 16.4 仍未做 / 需要主人

1. ~~法务远程副本未同步~~ → GitHub 已推（§17.2）；Gitee 因 token 过期待主人换令牌。
2. ~~1024 图标原稿~~ → 主人 2026-11-20 给了 1536×1536 原稿，已全部重出（§17.1）。
3. **ASC 重提**：等录屏链接；操作清单在 `tools/appstore-review/1.0.0-resubmit-2.1.md`。
4. **App 备案进度**：仍未知，中国区能不能上取决于它。
5. **全仓未提交**（22 个 M + 5 个 D + 1 个 ??），等主人过一眼再落 commit。

---

## 17. 2026-11-20 第二轮：图标换原稿 / 法务推送 / 取件码管理页重做

### 17.1 图标换成主人给的原稿（1536×1536）

`20261120-223431.png` 的 art bbox 占幅 0.608×0.641、中心 (0.501,0.500)，
与旧 180px 版（0.617×0.650）帧位一致，**不裁切**直接 LANCZOS 出各档：

| 目标 | 文件 |
|---|---|
| App 图标 | `Allude/Allude/Assets.xcassets/AppIcon.appiconset/AppIcon-1024{,-Dark,-Tinted}.png` |
| 内嵌 imageset | `AlludeShared/Assets.xcassets/AppIcon07.imageset/AppIcon07@{1x,2x,3x}.png` |
| alternate 包内图 | `Allude/AppIcons/Icon07@{2x,3x}.png` |

全部 RGB 无 alpha（App Store 会拒带 alpha 的 1024）。§16.1 里「180 放大笔画软」的遗留已消。

### 17.2 法务三副本

- GitHub Pages `Zhangwangning/allude-legal`：**已推**，commit `1ad10c7`（删第 12 节第三方模型 →
  「12. 不使用第三方服务」；条款删 4B 与尾部两段；support 页改只讲 iCloud）。
- Gitee 镜像：本地已提交 `67305c4`（用 GitHub 权威版整体覆盖，顺带补齐落后两版的
  「到达提醒」「驿站组排序」），**推送被拒**：`Oauth: Access token is expired`（403）。
  修法：在 Gitee 重新生成私人令牌，或主人用客户端推 `/tmp/legal-gitee`。
- App 内 `Allude/Allude/Legal/*.html` 见 §16.2。

### 17.3 取件码管理页（`Allude/Allude/Views/CodeManagementView.swift` 重做）

主人反馈：「开关开着，为啥上面的预览是一个颜色……开关点击后预览要及时响应……
提示文字能少则少」。三个根因、三处改动：

1. **预览慢一拍**：原来预览读的是存储里的 `CodeAppearanceStyle.current`，而 SwiftUI 先按
   新的 `@State` 重画、`onChange` 之后才写 UserDefaults —— 拨开关看到的永远是上一档。
   现在预览用 `@State` 现拼一份 `style` 传给 `PickupCodeEmphasis.text(_:isDone:tint:headOpacity:style:)`
   （新增可选 `style` 参数，默认仍读存储，真实渲染面一个都没动）。
2. **颜色对不上**：预览原来拿 `AppTheme.accent` 冒充品牌色，现在走
   `CourierBrand.color(for: "圆通速递")` + `CourierLogo`，与列表卡片同源，圆通就是紫的。
3. **文案收口**：删掉三段说明（色板说明、「关掉末四位强调…」长句、「示例数据…」脚注）
   与「当前 · xxx」那一行；只留分组标题 + 行标题，靠预览本身自证。

模拟器实测（`SCREEN=codeManagement`）：`/tmp/cm-new.png` —— 圆通紫码、
「8-4-」浅 /「3019」实、色板 7 档、三行显示方式（关掉强调时「前段透明度」行自动收起）、
卡片分组一行。列表真卡同源：`/tmp/list-final-crop.png`（申通 D31- 浅 / 2532 实）。

---

## 18. 2026-11-20 第三轮：桌面小组件页去文案 / Gitee 推送完成

### 18.1 Gitee 镜像已推（§17.2 的遗留）

用主人给的私人令牌推成功：`0565b31..67305c4  main`。已重新匿名 clone 复核：
`privacy.html` 是「12. 不使用第三方服务」，四份文件里 `第三方模型扩展` / `API Key 接入` 零命中。
（令牌只在本轮命令里用过，没写进任何脚本或配置文件。）

### 18.2 桌面小组件页（`Allude/Allude/Views/WidgetSettingsView.swift`）

主人口径：「提示文字能少则少，非必要不提示，用户压根不看」。改动：

| 原来 | 现在 |
|---|---|
| 六行开关一张卡 | **两张卡**：「完整信息」单独一张，其余五项一张 |
| 三行「显示xxx」 | 去掉「显示」前缀：取件地址 / 快递公司 / 驿站 / 快递柜 / 货架 / 占位符 |
| 卡下两段说明（「取件码永远显示…」「关掉占位符后…」） | **全删** |
| 预览下「示例数据 · 桌面小组件会按这套显示设置渲染…」 | **删** |
| 行内 `.system(size: 16)` | 统一 `AppTheme.TypeScale.rowTitle`（17） |
| 图标底 38pt / 图标 16pt | 34pt / 15pt，行高略收 |

`Allude/Allude/Views/WidgetPreviewGallery.swift` 同一轮收口：
删「以上为示例数据…」；免费档那句缩成「小、中尺寸可直接添加，最多 4 条。」

`Allude/Allude/zh-Hant.lproj/Localizable.strings` 补四条新键（取件地址 / 驿站 / 快递柜 / 货架 / 占位符）。

模拟器实测：`SCREEN=widgetSettings` → `/tmp/w-final.png`（对比旧版 `/tmp/w-before.png`）。

### 18.3 验证

clean build **BUILD SUCCEEDED，0 warning 0 error**（`/tmp/clean3.log`）。

---

## §19 驿站运行逻辑重做（2026-11-21，按主人四项决定落地）

### 19.1 主人的四项决定（原话：「1、A　2、加　3、不参与　4、按照你的建议」）

| # | 问题 | 决定 | 代码落点 |
|---|---|---|---|
| 1 | 组是「地点」还是「品牌集合」 | **A：地点** → 同一品牌可在多个组 | `StationGroupStore.create/update` 不再 `detach`；`groupsByMember()` 一对多 |
| 2 | 记录能不能手工改驿站 / 组 | **加** | `PickupRecord.stationGroupOverride` + 详情页编辑态选择器 |
| 3 | 组名 / 别名参不参与识别 | **不参与** | 识别仍只用内置词表 `name`/`aliases` + 自定义驿站名 |
| 4 | 围栏与排序口径 | 按建议 | 围栏「组 → 最近用过的位置」；组间「件数多在前」 |

### 19.2 新增：单一解析入口（`Allude/AlludeShared/StationGroups.swift`）

```swift
StationCatalog            // 自定义驿站名单的跨进程副本（App Group: allude.station.customNames）
StationResolution         // stationName / groupID / groupName / candidateGroups / source
StationResolver.resolve(_:)  // ① 记录指定组 ② 记录指定驿站 ③ 内置词表 ④ 自定义 ⑤ 唯一归属
```

优先级 **记录指定 > 自动识别**；驿站出现在多个组时 `candidateGroups` 非空、`isAmbiguous == true`，
分组键回落成驿站原名（不猜），详情页提示「这个驿站在 A、B，请选一个」。

消费端全部改走它：`PickupSortLogic.stationName`、`PickupNaming(resolution:)` / `record.namingResolved`、
`PickupListView` / `HistoryView` / `RecordDetailView` / `PickupShareCard` /
`PickupActivityController.stationResolver`（灵动岛）/ `StationLocationService.matches`（围栏）。

### 19.3 修掉的四个真实缺陷

1. **小组件认不出自定义驿站**：扩展进程读不到 `UserDefaults.standard`，
   自定义驿站建的组在桌面掉进「未标注驿站」→ `StationDirectory.persist()` 顺手写
   `StationCatalog`（App Group），启动时再 `syncCatalog()` 补一次。
2. **组间排序三处不一致**：待取/已取按件数、小组件按名字升序 → 统一「件数多在前 → 同数按名字 →
   未标注置底」，组内仍按「驿站内排序」。
3. **`StationGroupStore.save()` 缓存顺序反了**（本轮新发现）：原来先 `cachedGroups = groups`
   再 `invalidateCache()`，等于把刚存的组从缓存里抹掉，磁盘写失败时组会凭空消失。
   现在「先清派生索引 → 再落新缓存」，并补 `createDirectory`。
4. **跨组成员在两个列表里同时出现**：`ungroupedNames` / `groupedNames` 用 `memberIndex()`
   （多组时给 nil）→ 改走 `groupsByMember()`；「已归入驿站组」段按 (驿站, 组) 展开，
   格子标题写成「菜鸟驿站 · 恒大御府」。

### 19.4 围栏（到达提醒）

- `StationLocation` 新增 `updatedAt`（Optional，旧数据解码为 nil）；
- `StationLocationService.plannedTargets()` 抽成单一口径：组 → 未归组驿站（**最近改动位置的在前**）→ 上限 20；
- 设置 › 通知 › 到达提醒 的驿站列表里，超出 20 个的会标一枚「未在监控」——
  以前界面照旧一个开关，用户以为在监控，其实系统里没有这个围栏。

### 19.5 自检

新增 `tools/station-resolver-check/main.swift`（9 条断言，退出码 0/1）：

```bash
swiftc -O -o /tmp/station-resolver-check \
  "$PWD/Allude/AlludeShared/PickupModels.swift" "$PWD/Allude/AlludeShared/CourierBrand.swift" \
  "$PWD/Allude/AlludeShared/BrandPalette.swift" "$PWD/Allude/AlludeShared/PickupStorage.swift" \
  "$PWD/Allude/AlludeShared/StationGroups.swift" "$PWD/Allude/AlludeShared/Localization.swift" \
  "$PWD/Allude/AlludeShared/AppTheme.swift" "$PWD/Allude/AlludeShared/FontScale.swift" \
  "$PWD/Allude/AlludeShared/OfflineLicense.swift" "$PWD/Allude/AlludeShared/LicenseDevice.swift" \
  "$PWD/tools/swift-cli-shim.swift" "$PWD/tools/station-resolver-check/main.swift" && /tmp/station-resolver-check
```

本轮全绿：resolver 9/9、station-check 63/63 + 14/14、dedupe 28/28、
parser 识别 193/514（基线 192）+ 地址 192/514（基线 189）；clean build **0 warning 0 error**。

### 19.6 仍未做

- 组间排序里「件数多在前」只在待取页验证过；已取页与小组件是同一函数，未单独截图；
- 详情页驿站选择器只拍了编辑态外观（模拟器无法脚本化点击菜单），逻辑由 resolver 断言覆盖。

### 19.7 口径修订（2026-11-21 深夜，主人推翻 19.1 的第 1 条）

主人原话：「一个驿站只能属于一个组，我觉得没问题，你想想，App 是一个人在用的，取件的地址基本上在范围内是固定的几个地方，如果短信中有菜鸟驿站，按照你的有多个组都包含菜鸟驿站，那么这条信息的驿站就没法归到一个具体的驿站组中啊」

**定案：一个驿站只属于一个组**（`create` / `update` 都把成员从其它组摘掉）。理由就是上面那句 ——
「多组共享」会把「短信里只有一个品牌名」的记录变成永久歧义，而一个人常去的取件点就那么几个，
真正需要区分的是**地点**，不是让品牌同时挂多处。

保留 19.1 的另外三条：手工指定照旧（`stationGroupOverride` 优先级最高）、组名不参与识别、围栏口径不变。

配套新增（避免移组把历史改判）：

- **移组时钉住历史**：`StationGroupStore.displacedMembers(_:excluding:)` 先算出「这次保存会把谁从哪个组拿走」，
  `StationGroupEditView.save()` 拿到结果后对每个被移走的驿站调
  `PickupStore.pinRecords(station:toGroup:)` —— 给**没有手工指定过**的旧记录写上原组 ID。
  效果：把菜鸟驿站从「恒大御府」挪到「蓝山公馆」后，以前那批件仍然算恒大御府的。
- 文案回退：成员行 `在「X」里，勾选会移过来`；成员卡 `选中的驿站会从待取 / 已取页收进这个组。一个驿站只在一个组里。`；
  驿站组说明 `组是一个取件地点：…一个驿站只在一个组里；个别记录不在这组取的，详情页里可以单独指定。`；
  「已归入驿站组」格子去掉「· 组名」后缀（一个组一个归属后，后缀纯属噪音，还会折成三行）。
- `StationResolution.isAmbiguous` 与 `candidateGroups` **保留**：只服务旧数据 / 手改文件里重复归属的情况，
  正常路径下恒为 false / 空。

自检同步改写：`tools/station-resolver-check` 现在断言「移组后归属新组、候选为空、原组成员被摘掉」，
外加「移组前能算出原组」；9 条断言全过。

---

## §20 驿站管理三页改版 + 快速分组（2026-11-21）

主人原话：「把驿站管理的页面再优化一下，还有新建/编辑驿站组的页面也重新优化设计，还有点击驿站可以后不仅可以设置定位和到达提醒，还增加一个快速分组的功能，点击可以快速选择不同的驿站组或添加到新创建驿站组中」。

### 20.1 驿站管理页（`Allude/Allude/Views/DesignSystem.swift` · `CourierGalleryView`）

| 改前 | 改后 |
|---|---|
| 顶部一张「内置 34 个取件地点图标 + 两句说明」的大卡 | **删掉，换成搜索框**（34 个内置 + 自定义 + 组，滑两屏才找得到才是真问题） |
| 组格子只有图标 + 名字 | 图标左下角加**成员数徽章**（一眼知道这组装了几家） |
| 组段下面一段长说明 | 一行：「组＝一个取件地点。一个驿站只在一个组里，个别件可在详情页单独指定。」 |
| 页面底部一句「点『新建驿站组』可把…最长命中」 | **删掉**（快递公司页保留版权那一句） |

搜索同时过滤：内置驿站格、自定义驿站格、驿站组格、「已归入驿站组」段。

### 20.2 新建 / 编辑驿站组页（`Allude/Allude/Views/StationGroupEditView.swift`）

| 改前 | 改后 |
|---|---|
| 组名一张卡（含「不能与内置驿站…」说明） | 与图标合并成**顶部一张卡**：左图标（点一下切到相册来源）、右名字输入 |
| 图标一张卡 + 三格大缩略图 | 三枚小胶囊：**首字 / 相册 / 继承**，选中紫底；继承模式的成员横条仍在 |
| 位置卡：一句「或直接沿用成员的位置」+ 一排成员图 | 收成一行 **「位置来源」Menu**：自己的位置 / 沿用「X」 |
| 成员卡：一段说明 + 长列表 | 删说明，加**搜索框**（34 个内置 + 自定义，滑一半就找不到） |
| 页尾一段「组是独立的一个驿站…」 | **删掉**；重名等错误仍走页脚红字 |

### 20.3 快速分组（`Allude/Allude/Views/StationEditView.swift`）

- 「编辑驿站」页（内置驿站走 `StationLocationEditor`，自定义走这里）新增 **驿站组 › 所属** 一行：
  `Menu` 里是「不归组 / 各组名（当前组带勾）/ 新建驿站组…」。
- 选组＝`StationGroupStore.addMember(stationName:toGroup:)`：把该驿站从原组摘掉、加进新组，并**返回原组 ID**；
  调用方据此 `PickupStore.pinRecords(station:toGroup:)` 把旧记录钉在原组（移组不改判历史）。
- 「新建驿站组…」→ 弹 `StationGroupEditView(mode: .create, preselectedMemberIDs: [该驿站])`，建完自动带上它。
- 该页同时把「图标卡 + 名称卡」合并成一张头部卡，删掉「改名后…」「点按图标从相册选择」两句说明。

### 20.4 新增脚手架

`SCREEN=stationEdit` 支持 `STATION=菜鸟驿站` 直接进**编辑态**（原来只能进添加态，验证不了「驿站组」行）。

### 20.5 自检

- `tools/station-resolver-check` 增 3 条：快速分组返回原组 / 分组后归新组 / 不归组回落原名 → 共 12 条全过。
- station-check 63/63 + 14/14、dedupe 28/28、parser 193 与 192（无回退）。
- clean build **0 warning 0 error**。

### 20.6 内置驿站也能直接分组（2026-11-21 补）

- 新增组件 `Allude/Allude/Views/StationGroupMembershipRow.swift`：一行「驿站组 › 所属」Menu
  （不归组 / 各组名带勾 / 新建驿站组…），内部走 `StationGroupStore.addMember` →
  `PickupStore.pinRecords` → `WidgetCenter.reloadAllTimelines()`，建组回来自动刷新。
- 挂载点两处：
  - `Allude/Allude/Views/StationLocationEditor.swift`（内置 / 自定义共用的定位页）：
    `settingsCard` 之后、`disclaimer` 之前 —— 内置驿站点进来就能改归属。
  - `Allude/Allude/Views/StationEditView.swift`：`groupCard` 改成复用同一组件，
    原 `showCreateGroup` / `stationIDForGrouping` / `moveToGroup` / `currentGroupID` /
    `currentGroupName` 全部删除（同一份逻辑只留一处）。
- 验证：clean build 0 warning 0 error；resolver 12/12、station-check、dedupe 全过；
  截图 `/tmp/r-loc-crop.png`（菜鸟驿站定位页底部出现「驿站组 › 所属 恒大御府」）。

## 21. 对外文案：不表述收费（2026-11-21）

主人指令：更新隐私政策、使用条款、版本历史等，**去除关于收费、订阅、iPadOS 适配**的内容。

### 21.1 法务两页（三副本已同步）

- `Allude/Allude/Legal/privacy.html` 整篇重写（13 节）：运行方式 / 1 数据 / 2 权限 /
  3 小组件与实时活动 / 4 端侧智能 / 5 iCloud 同步 / 6 TestFlight / 7 反馈 /
  8 数据保留与删除 / 9 儿童 / 10 安全 / 11 变更 / 12 不使用第三方服务 / 13 联系方式。
  原文件有两个「9.」编号重复、一节「内购」、一处「Allude Pro 的实验功能」、日志口径写「权益档位」。
- `Allude/Allude/Legal/terms.html` 整篇重写（11 节）：0 运行方式 / 1 许可范围 /
  2 功能边界 / 3 iCloud 同步 / 4 内测版 / 5 得到什么不会得到什么 / 6 责任 /
  7 免责声明 / 8 责任限制 / 9 变更 / 10 适用法律 / 11 联系方式。
  原文件的价格表、「订阅、扣款与取消」、「内购走 StoreKit 沙盒」、「责任不超过实际支付金额」全部删除。
- `support.html`（仅远程副本）删掉英文「Subscription and purchase」整节与中文「恢复购买 / 取消订阅」两条。
- 远程同步：GitHub Pages `09ad47b`、Gitee 镜像 `33967d9`（`grep` 复核 `订阅|内购|买断|Allude Pro|Restore Purchases` 全为 0）。
- ⚠️ 如果以后仍然售卖内购，Apple 3.1.2 要求在**购买页内**显示自动续期与取消方式 ——
  那时在 `SubscriptionView` 里补最小一版即可，不要依赖法务页承担这件事。

### 21.2 版本历史

- `Allude/Allude/Views/VersionHistoryView.swift`：entries 26 条（1.0.0 → 0.1.0）。
  **整条删掉 0.3.0 / 0.3.1**（原文全是「免费下载 + 订阅解锁」「订阅页三档」）；
  1.0.0 去掉「Allude Pro 订阅版」「购买页价格」「iPad 与折叠屏分栏下线」；
  0.3.7 / 0.3.3 / 0.2.8 / 0.2.4 / 0.2.1 各删若干条 Pro / Duo / 凭证 / 会员体系表述。
- `Allude/Allude/Views/BetaBuildLog.swift`：按 `Duo|iPad|折叠|分栏|订阅|买断|价格|内购|免费|Pro|恢复购买|沙盒|凭证`
  过滤，删 64 条要点、5 个构建清空后整条移除（318 / 316 / 314 / 303 / 248），现存 **55 条**构建。
- 内测区标题下那句「前期做过 iPad 与折叠屏的分栏适配尝试…」改成「以下是 TestFlight 的逐次构建记录。」
- 截图验收：`SCREEN=versionHistory`（含 `BETA_EXPAND=1` + `SCROLL_TO=beta` 看内测区）。

### 21.3 项目指令

- `AGENTS.md` 顶部加「对外不表述收费」红框，商品信息标注为**内部备查**（App Store Connect 两条商品仍在，是否继续售卖待定）。

## 22. 端侧智能定位 + 排序同源（2026-11-21）

### 22.1 端侧智能是「辅助」，不是与正则二选一

主人原话：「Apple 端侧智能能力只用于正则表达式解析时辅助以获取更完美的结果，不是 Apple 端侧智能与正则表达式是二选一」。

- 代码本来就这个分工（`PickupAI` 注释写明：正则主力、模型只填空不覆盖），**逻辑没改**；
  改的是所有**对外口径**，以前写成「能用端侧智能就用，不能用就退回正则」，读起来像二选一。
- 改的文案：`Allude/Allude/Legal/privacy.html`（运行方式 / 第 4 节 / 第 12 节三处）、
  `Allude/Allude/Views/AICapabilityView.swift` 的说明卡、`AGENTS.md` 的端侧 AI 段。
  现在的说法：**正则负责主解析，端侧智能在旁边辅助补齐与校对，结果更完整；不可用时只是少了这层辅助**。
- 远程副本已同步：GitHub `3a7fa69`、Gitee `46ef1a3`。

### 22.2 小组件排序＝待取页排序（同一门函数）

主人原话：「小组件的排序就和待取页面的分组排序保持一致就行」。

三处以前各写一套，现在收敛到 `Allude/AlludeShared/PickupStorage.swift` 的 `PickupSortLogic`：

| 位置 | 改前 | 改后 |
|---|---|---|
| `PickupSortLogic.sort(.station)` | 组内按 `receivedAt` | 组内按 `lastNotifiedAt`（= 待取页同一时刻） |
| `PickupListView.stationName(for:)` | `record.station` → 组名（不认手工指定） | `PickupSortLogic.stationName(of:)`（走单一解析入口） |
| `HistoryView`（已取） | 组间按名字升序、组内 `receivedAt` | 直接 `PickupSortLogic.sort(_:mode: .station)` |
| `HistoryView.stationName(for:)` | 同上旧实现 | 同上共享函数 |

组间口径（三页 + 小组件一致）：**件数多在前 → 同数按名字 → 「未标注驿站」置底 → 组内按「驿站内排序」**。

⚠️ 踩坑：`PickupRecord.lastNotifiedAt` 是**非可选**计算属性（`history?.last ?? receivedAt`），
写 `lastNotifiedAt ?? receivedAt` 会报 `left side of nil coalescing operator '??' has non-optional type`。

---

## §23 2026-11-21：开源页 / 特别鸣谢 / 首启同意页（主人第 13 轮）

### 23.1 关于 Allude › 开源项目

新增 `SettingsPane.openSource`（标题「开源项目」，图标 `chevron.left.forwardslash.chevron.right`，
色 `AppTheme.indigo`），排在「隐私政策（简明版）」之后、「特别鸣谢」之前。
页面在 `Allude/Allude/Views/AboutOpenSource.swift`：顶部一句「Allude 的代码是公开的」，
两张仓库卡（`OpenSourceLinks.alludeApp` / `.shortcuts`，点击跳 GitHub），
底部「仓库里有什么」写清 **完整开发过程在此仓库、不放 IPA / 构建产物 / 签名私钥**。

### 23.2 关于 Allude › 特别鸣谢

`SettingsPane.credits`（图标 `heart.text.square.fill`，色 `AppTheme.pink`）。
名单按主人给的原顺序：@我爱吃派大星 / @么么 / @很酷的Z / @无言 / @青云 / @momo /
@春山springhil / @低调肚兜 —— 页面下方只补一句「排名不分先后」。

### 23.3 首启同意页重做（`LegalConsentView.swift`）

- 版式：图标 + 「取件码，只留在你手机上」+「全程离线 · 不需要账号」徽标（三句差异点：
  不联网 / 不上传 / 不用注册）→ 一行删除提醒 → 条款两行 + 勾选 → 底部主按钮。
  删掉原来的大段说明与「删除请谨慎」重复话术。
- 🔴 行为变更：「同意并继续」**不再置灰**。未勾选时点它 → 自动勾上「我已阅读并同意」并弹
  「确认同意」框（按钮：同意 / 查看条款 / 不同意）。确认框里能直接翻条款（sheet 打开
  `LegalDocumentView`），不同意则回到原来的说明弹窗。
- 截图脚手架：`SCREEN=consent`（页面本体）、`CONSENT_CONFIRM=1`（复现确认框，
  simctl 点不了屏幕，这条路径只能这样验）。

### 23.4 仓库开源前清理

- 新增 `README.md`：定位、编译命令（含 `-disable-sandbox` 说明）、
  「仓库里有什么（开发过程）」清单、自检脚本跑法、仓库不放什么、署名与第三方标识口径。
- `Reverse/`（三个第三方 App 的逆向产物 Info.plist）已 `git rm --cached` 并写进 `.gitignore`，
  文件仍留在本机。
- 实测 `git ls-files | grep -c '\.ipa$'` = 0，仓库内无 IPA。

### 23.5 验证

- clean build：**0 warning / 0 error / BUILD SUCCEEDED**。
- 模拟器：iPhone 16 Pro `0211F7EF…`、**iPhone Duo `EEFA6F55…`（折叠态 `--display=1`）**、
  **iPhone 18 Pro Max `97B88473…`** 三台都已装最新构建，主人可直接看。
- 截图：`/tmp/about-list2-b.png`（关于页两行新入口）、`/tmp/about-openSource.png`、
  `/tmp/about-credits.png`、`/tmp/consent-new.png`、`/tmp/consent-confirm-c.png`、
  `/tmp/duo-consent.png`（Duo 外屏，右侧摄像头区安全内缩生效）。
  ⚠️ `simctl io <udid> screenshot --display=1 <path>` 的参数顺序必须是
  `screenshot --display=… 路径`，写在 screenshot 前面会报 `Invalid argument`。

### 23.6 2026-11-21 晚二轮修订（主人当场反馈）

| 项 | 改成 |
|---|---|
| 开源项目页 | **删掉所有说明**（intro 卡 + 「仓库里有什么」卡），只剩两行仓库：`Allude` / `快递取件码`，点进去看源码 |
| 特别鸣谢页 | 文案里的「被他们逼出来」删掉；**只留名字**，居中单列、无图标无首字块（主人：没有头像，硬做图反而难受）；保留一句分组标题「深度测试与反馈」与「排名不分先后」 |
| 鼓励一下页 | 只保留「在 App Store 上评分」（`requestReview`）；两段说明与「推荐给朋友」一并移出 |
| 推荐给朋友 | 挪到**关于 Allude**，紧跟「鼓励一下」下面是 `ShareLink`（不是 push，所以**不画 chevron**） |
| 首启确认框 | 原生 `.alert` 会**自动补一个多余的「取消」**，且按钮颜色不可控 → 改**自绘确认框**（`.regularMaterial` 卡片、42pt 行、分隔线、圆角 22），「同意 / 查看条款」系统蓝、「不同意」`Color(.systemRed)` |
| 勾选状态 | 点「取消」（空白处）或「不同意」时，**把「我已阅读并同意」退回未勾选**（主人 2026-11-21 要求）；「查看条款 / 同意」不回退 |

截图：`/tmp/v3-openSource.png`、`/tmp/v9-credits-c.png`、`/tmp/v3-encourage.png`、
`/tmp/chk-aboutAllude-c.png`（关于页含「推荐给朋友」且无 chevron）、`/tmp/v6-confirm-c.png`（确认框）。

---

## 24. 标签栏显隐改原生 + 首启页玻璃（2026-11-21 深夜）

### 24.1 为什么改：Duo 内屏横屏「标签栏看得见、点不动」

主人实测：Duo **内屏横屏**下只有待取页能滑能点，点标签栏换不了页；外屏与内屏竖屏正常。

定位结论（未改代码阶段）：

- 那根竖排标签栏是**系统**在 regular 宽度下自动放到右侧的浮动条，不是我们自绘的；
  实测尺寸 46×190pt、距右边 20pt，**完整可见**，所以不是被挤出屏幕。
- 全工程只有 **Duo 内屏**这一种组合让「系统标签栏」与旧 `TabBarCloak` 同时活着：
  iPad 走 `PadTabChrome(enabled: PadLayout.isPad)` 把系统栏藏了、自绘 `PadBottomBar`；
  Duo 的 idiom 仍是 phone，`PadLayout.isPad == false`，于是两套都在。
- `TabBarCloak` 收起时做三件事：`transform` 下移、`alpha = 0`、**`isUserInteractionEnabled = false`**。
  恢复只在 `reveal()`，而它要求手里那个 `bar` 引用**还是同一个 UITabBar 实例**（`RootView.swift`
  旧注释已承认 iOS 27 浮动标签栏会被系统重新布局、旧引用会被摘掉）。
  一旦实例被换掉／`isHidden` 卡在 true，就出现「画出来了、但不可交互」——
  点击穿透到下面的详情列，表现为「点了没反应」。

### 24.2 改法：不再碰任何 UIKit 视图

`RootView.swift` 删掉整块 `TabBarCloak`（计数、定位、弹簧动画）与 `NativeTabBarBridge`；
`cloaksTabBar()` 改成一行原生调用：

```swift
private struct TabBarCloakModifier: ViewModifier {
    @Environment(\.suppressTabBarCloak) private var suppressed
    func body(content: Content) -> some View {
        content.toolbar(suppressed ? .visible : .hidden, for: .tabBar)
    }
}
```

- 显隐与动画都交给系统（`.toolbar(.hidden, for: .tabBar)`，iOS 16+）；
- 5 处 `TabBarCloak.shared.reveal()` 调用（待取/已取/统计/设置根页 + 设置分栏）一并删除；
- `suppressTabBarCloak` 环境值保留：设置分栏的常驻 pane 仍然靠它不收起。

🔴 **不要再抓 `UITabBar` 改 `transform / alpha / isUserInteractionEnabled`** ——
那是「非原生」的那部分，也正是这次踩到的坑。系统标签栏只允许通过 SwiftUI 的
`.toolbar(...)` / `.tabBarMinimizeBehavior` 控制。

### 24.3 首启同意页补玻璃材质

`Allude/Allude/Views/LegalConsentView.swift` 三处换成同一条材质链（`appGlass`）：

| 位置 | 改前 | 改后 |
|---|---|---|
| 条款 + 勾选卡 | `.cardSurface()`（不透明分组卡） | `.settingsCard()` → iOS 26+ 真液态玻璃 / 低版本系统卡片 |
| 确认弹窗 | 写死 `.regularMaterial` | `.appGlass(.rect(cornerRadius: 22))` |
| 底部操作条 | `.background(.bar)` | `.appGlass(.rect(cornerRadius: 0))` |

`appGlass`（`Allude/AlludeShared/GlassCompat.swift`）的分档：≥ iOS 26 且开关开 → `glassEffect`；
其余（iOS 17–25，或用户关掉玻璃）→ `.ultraThinMaterial` + 细描边。iOS 18 上 tint 必须画在
**内容下方**（画在 `.overlay` 会盖住文字，2026-11-08 踩过）。

测试：iOS 27 模拟器 `SCREEN=consent` 截图 `/tmp/g-consent.png` 通过；19 Pro/26 以下需另机验证。

### 24.4 2026-11-21 深夜：Duo 内屏横屏「点不动」的真实原因（已修）

删掉 cloak 改成原生 `.toolbar(.hidden, for: .tabBar)` 之后主人实测**仍然不行**。
于是加了一个 Debug 探针（`Allude/Allude/Views/TabBarProbe.swift`，
`SIMCTL_CHILD_TABPROBE=1` 启动，3 秒后把窗口层级写进 `Documents/tabprobe.txt`），
在**内屏横屏的真实姿态**下取证（命令行的取证办法见下）：

```
window=951×669  safeArea=t0 l0 b34 r84
tabBars=1
  [0] frame= x882 y0 w69 h669  hidden=false alpha=1.0 interactive=true items=4
      superview=_UITouchPassthroughView
  _UITabButton[881,435,44,58] / [881,485] / [881,535] / [881,585]
```

**结论有两层**：

1. 系统把浮动标签栏摆在 **x882…951**，而窗口的**右侧安全区是 84pt**
   （`951-84=867`）—— 整条标签栏都落在右侧**摄像头 / dock 保留区**里。
   那一带收不到触摸事件，所以「看得见、点不动」。
2. 标签栏本身是好的：探针给第 2 个 `_UITabButton` 程序化发
   `sendActions(for: .touchUpInside)`，**界面当场切到「已取」**。
   所以问题不在 `TabView` / selection 绑定，而在**触摸投递**。

**改法**：Duo 内屏横屏不再用系统标签栏，改用 iPad 那条自绘底部栏
（`PadBottomBarGlassHost`，SwiftUI + 系统玻璃，in-app 已稳定跑了几个版本）：

| 位置 | 改为 |
|---|---|
| `RootView.swift` 底部栏显示条件 | `PadLayout.isPad` → `PadLayout.isPad \|\| PadLayout.isExpandedFoldable` |
| `suppressTabBarCloak` 环境值 | 同上（Duo 内屏也收起系统栏） |
| 4 处 `PadTabChrome(enabled:)` | 同上（给自绘栏让出 76pt 底部内边距） |

验证：`xcrun simctl io EEFA6F55… screenshot --display=3 /tmp/duo-fix.png`
（2853×2007，内屏横屏）→ 底部出现带文字的标签栏，整条都在安全区内。

🔴 **命令行怎么看到内屏横屏**（极有用）：`simctl` 没有转屏命令，
但**只要设备已经展开**，`xcrun simctl io <udid> screenshot --display=3 <path>`
直接给出 2853×2007 的横向画面；`screenConfig geometry 2853x2007` 会报
`No mode found`，别在那上面浪费时间。

⚠️ 同一姿态下，详情栏顶部的「编辑 / 分享」按钮也在 x884 一带（保留区内），
可能同样收不到触摸 —— 需要主人实测确认；若确实不行，下一步在分栏详情侧
补 trailing 内边距，把交互元素推出保留区。

---


### 24.5 更正（2026-11-21 13:57）：Duo 内屏横屏**继续用系统原生标签栏**

§24.4 的结论「系统把标签栏摆进右侧 84pt 摄像头保留区、那里收不到触摸」**是错的**，本机实测推翻了它：

- 用 `TABPROBE=1` 在真机上取系统 `_UITabButton` 的**真实** frame（`x881 y435/485/535/585 w44 h58`），
  再对每个按钮中心做 `window.hitTest` —— 四个点**全部命中 `_UITabButton`**；
- 对第 2 个按钮 `sendActions(for: .touchUpInside)`，界面当场切到「已取」。

即：**系统标签栏本身是可点的**。之前「看得见点不动」的真正来源是已删除的 `TabBarCloak`
（它把 `isUserInteractionEnabled` 置假、靠 `reveal()` 恢复，实例一换就再也恢复不回来）。

现在的口径（2026-11-21 主人：「能用原生组件就用原生组件，Duo 也是 iOS」）：

| 设备 / 姿态 | 标签栏 |
|---|---|
| iPhone 直板机 | 系统原生（底部） |
| Duo 外屏（compact） | 系统原生（底部） |
| **Duo 内屏横屏（regular）** | **系统原生（系统自己摆成侧边竖排，符合 HIG《针对 iPhone Duo 设计》）** |
| iPad | 自绘底部栏（2026-11-14 主人当时的决定；现在不做 iPadOS，可按需删） |

`suppressTabBarCloak` 只在 iPad 为真；`PadTabChrome` 的 76pt 底部留白也只在 iPad 生效。
**不要再给 Duo 画任何自绘标签栏**——试过底部栏与侧边胶囊两条路，都被主人否掉（遮内容、非原生）。

## §25 iPhone Duo 技能包（2026-11-21）

主人要求「把官网内容扒下来，总结成一个专业的 iPhone Duo 开发 skill，并不断强化」。
产物是 `skills/iphone-duo/`，**只从 Apple 官方原文提炼**，不是我凭经验编的：

| 文件 | 行数 | 内容 |
|---|---|---|
| `SKILL.md` | 220 | 何时用、三条铁律、**布局基线六条（HIG《布局》）**、四态表、8 步流程、快速判断表、交付 checklist |
| `references/hig-designing-for-iphone-duo.md` | 266 | HIG《Designing for iPhone Duo》**页面正文原文**（6,953 字符） |
| `references/dev-preparing-your-app.md` | 72 | 开发者文档要点 + API 对照 |
| `references/api.md` | 164 | 全部 API 签名 + 可用性 + 最小示例 |
| `references/poses.md` | 114 | 几何真值表、判据推导、simctl 取数、两套探针模板 |
| `references/pitfalls.md` | 97 | 7 条踩坑（含本次标签栏事故的完整证据） |
| `references/hig-layout.md` | 84 | HIG《布局》**页面正文原文**（3,597 字符，2026-11-21 补） |

### 25.1 原文怎么来的

主人给的 `.webarchive` 是 Apple binary plist，用 `plistlib` 取出
`WebMainResource['WebResourceData']` 就是 205,335 字节 HTML（另含 39 个 subresource）。
正则去 script/style/svg、`h1-6 → ###`、`li → -`、`td → | `、剥标签 → 6,953 字符正文。
开发者文档那篇 `web_fetch` 直接拿。

### 25.2 API 可用性全部对 SDK 核过

对照 `iPhoneOS27.2.sdk/.../SwiftUICore.swiftinterface`，三条关键结论：

```
@available(anyAppleOS 27.1, *) public struct ReservedRegion
@available(anyAppleOS 27.1, *) public func reservedRegions(kind:options:layoutDirectionBehavior:) -> [ReservedRegion]
@available(anyAppleOS 27.1, *) public struct ArrangementView<Primary, Secondary>
@available(anyAppleOS 27.1, *) public func toolbarVerticalBehavior(_: ToolbarVerticalBehavior)
```

即 **`ReservedRegion` / `ArrangementView` / `toolbarVerticalBehavior` 都是 iOS 27.1 起**，
不是 26、也不是 27.0。UIKit 侧 `UIView.reservedRegionsOfKind:options:` 同样是 27.1。

### 25.3 三条铁律（为什么写这三条）

1. **按窗口几何判据**，不用 `idiom` / 方向 / 机型名 / `UIScreen.main`
   —— 官方口径就是「按 size class 与几何适配」，而且我们实测过 `UIDevice.model` 恒为 iPhone。
2. **系统容器优先**：能交给 `TabView` / `NavigationSplitView` / `ArrangementView` 就别自绘
   —— 本次事故的根因正是「自己抓 `UITabBar` 改 transform」。
3. **折叠时只做小幅调整**：内容不因折叠而重排。

### 25.4 「不断强化」的约定

以后再在 Duo 上踩坑，**往 `references/pitfalls.md` 追加一条**（症状 / 证据 / 根因 / 处置），
不要新建文档、不要写进 SKILL.md 正文。`AGENTS.md` 已有该节指向这里。

---

## §26 Apple HIG 全量入库（skills/apple-hig，2026-11-21）

主人先给了 28 个 `.webarchive`，随后说「https://developer.apple.com/cn/design/ 这里直接自己去看吧」。
最终把 HIG 全站**167 个主题页**逐字镜像进仓库，脚本化、可增量更新。

### 26.1 首先踩到的坑：`.webarchive` 里没有正文

28 个文件的 `WebMainResource['WebResourceURL']` 全是同一页 `designing-for-iphone-duo`，
HTML 里只有 `vue-recycle-scroller` 的导航卡片，正文由 JS 运行时渲染、**保存时没落盘**。
第一次提取把壳当成了正文（28 份文件的一级标题完全相同，都是「探索"入门汇总"」这类导航文案）。
判断方法：抓完如果正文不足 2 KB 且标题雷同，就是壳。

### 26.2 正解：官方文档 JSON + 脚本 `tools/fetch-hig.py`

```bash
python3 tools/fetch-hig.py --missing        # 只补索引里还没入库的
python3 tools/fetch-hig.py --all            # 全量重抓（167 篇）
python3 tools/fetch-hig.py widgets tab-bars # 指定主题
```

端点：`https://developer.apple.com/tutorials/data/cn/design/human-interface-guidelines/<slug>.json`
（液态玻璃那篇是 `.../documentation/technologyoverviews/adopting-liquid-glass.json`）。

- 必须走 `curl` 子进程：本机 python 的 urllib 会撞代理 MITM，报
  `CERTIFICATE_VERIFY_FAILED: self-signed certificate in certificate chain`；
  偶发 `curl: (35) TLS connect error` 是抖动，重跑即可（脚本里带了 UA 与 `-sSL`）。
- 递归遍历 `heading / paragraph / codeListing / unorderedList / orderedList / table / aside / links`；
  **`links` 块是一串 `doc://` 标识，必须用同页 `references` 映射成标题 + 摘要 + 内部链接**，
  否则那些目录页（`components` / `presentation` / `patterns` / `technologies`…）会读成一堆裸标识符。
- 正文 < 350 字符的直接跳过（Apple 有些分区只有导航，没有正文）。

### 26.3 入库清单

`skills/apple-hig/references/` 共 **167 篇、1.6 MB**，覆盖：

| 分类 | 代表页面 |
|---|---|
| 基础 | 布局 / 材质 / 字体排印 / 颜色 / App 图标 / 图像 / SF 符号 / 深色模式 / 动效 / 触感 / 无障碍 / 包容性 / 编写 / 品牌 / RTL / 撤销重做 |
| 组件 | 标签页栏 / 工具栏 / 侧边栏 / 拆分视图 / 列表 / 按钮 / 滑块 / 开关 / 分段控制 / 搜索栏 / 文本框 / 表单 / 提醒 / 弹出窗口 / 进度指示 / 页面控制 / 菜单 / 上下文菜单 … |
| 模式 | 启动 / 加载 / 设置 / 搜索 / 数据输入 / 反馈 / 模态化 / 用户引导 / 全屏 / 评分与评论 / 文件管理 / 数据图表化 … |
| 输入 | 手势 / 键盘 / 虚拟键盘 / 指针设备 / 相机控制 / 操作按钮 / 聚焦与选择 |
| 技术 | 小组件 / 实时活动 / 通知 / Siri / 通过 Apple 登录 / Apple Pay / iCloud / 同播共享 / 轻 App / 快捷指令 … |
| 平台 | 针对 iOS / iPadOS / iPhone Duo / macOS / tvOS / watchOS / visionOS / 游戏设计（本项目只做 iOS，其余备查） |

### 26.4 SKILL.md 的两个要点

1. **「本项目必须守的 12 条」**：每条都写成「官方怎么说 + 我们怎么做（带文件名）」——
   尺寸分类 / 安全区 / 控制与内容分层 / 玻璃只做分层不做装饰 / 字号只用 `TypeScale` 档位 /
   少让人打字（粘贴、拍照、快捷指令三条入口）/ 加载立刻有东西看 / 启动即用 /
   设置只放不常改的 / 权限按需最小化 / 反馈多通道 / 文案说人话。
2. **「有意识的偏离」表**：官方明说不建议、但主人明确要了的，一律记在这里并注明原因——
   目前两条：App 内「外观」三档选择（`dark-mode.md`）、App 内字号滑块（`typography.md`）；
   另加一条产品选择：App 内不显示备案号。

### 26.5 与其它文档的关系

- `AGENTS.md` 新增「## 设计规范：skills/apple-hig（2026-11-21 接入）」放在 Duo 那节前面；
- `skills/iphone-duo/SKILL.md` 顶部加了交叉链接，只讲折叠设备；
- 维护约定：**只替换 `references/` 原文，不手改原文**；新主题跑 `--missing` 即可。

---

## §27 Duo 内屏横屏：竖排栏为什么点不动（2026-11-21 收口）

### 27.1 现象与排除过程

主人反馈：内屏横屏下右侧标签栏点不动，「编辑」「分享」也点不动；左侧列表与卡片正常。

排除顺序（都做过，别再重复）：

1. **不是卡顿/固件**：同一运行期外屏一点就切页；进程内对这 4 个 `_UITabButton` 发
   `sendActions(for: .touchUpInside)` 立刻切页。
2. **不是我们的代码拦的**：`TabBarCloak` 那套 UIKit 接管已整段删除（§24），
   `TabView` / selection 绑定 / 按钮 target 全部正常。
3. **不是自定义修饰引起的**：把这一姿态的四个修饰（`PushTrailingSafeArea`、
   `AdaptiveTabBarStyle`、`TabBarMinimizeNever`、`ToolbarVerticalCompat`）全关掉，
   栏位置不变，仍然点不动。
4. **不是这次改出来的**：`git worktree` 拉交接版 `27b085b` 重新构建装到同一台 Duo，
   标签栏位置/外观与当前构建**完全一致**（见 §24.4 的对照截图）。
5. **连裸系统 TabView 也一样**：`SCREEN=minimalTabs` 的最小复现页（四个 `Color.clear`
   + `.tabItem`）点右侧栏同样没反应 —— 与我们的业务视图无关。

### 27.2 决定性证据（保留区域 API）

`window.reservedRegions(kind:)`（iOS 27.1+，`UIView.ReservedRegion.Kind`）实测：

```
window=951x669  safe=t0.0 l0.0 b34.0 r84.0
occlusion.count=0
division.count=0
```

**系统自己报告展开态没有任何保留区域，但 `safeAreaInsets.right` 仍是 84。**
系统把这 84pt 当成不可交互区，又把竖排栏摆进 `x882…951` —— 栏看得见、点不到。

### 27.3 结论与主人的选择

- 这是**模拟器的幽灵安全区**（真机完全展开时右侧没有摄像头遮挡），App 侧无法打开这条带子；
- 主人 2026-11-21 选 **A：保持系统原生竖排，接受模拟器里点不动，记为环境限制**；
- 备选 B（`.toolbarVerticalBehavior(.disabled)`，iOS 27.1+）能让栏回底部横排、点得动，
  但那不是 Duo 的竖排设计；⚠️ 挂 `NavigationSplitView` 上会让分栏塌成单列，挂根视图只影响标签栏。
- 同一结论已写进 `skills/iphone-duo/references/pitfalls.md` 第 8 条。

### 27.4 代码现状（本轮收口后的净结果）

- `Allude/Allude/Views/RootView.swift` 与 `27b085b` **无差异**（`git diff 27b085b -- …/RootView.swift` 为空）；
- 探查期新增的文件全部删除：`DuoInnerShell.swift` / `TabBarProbe.swift` / `TouchLogProbe.swift` /
  `DuoRegionProbe.swift` / `ToolbarVerticalCompat.swift`，`AlludeApp.swift` 里的挂载与
  `MinimalTabFixture` 一并清掉；
- 保留与 Duo 无关的改动：驿站解析入口与驿站组、关于页（开源/鸣谢/推荐）、端侧 AI 收口、
  圆通→中通纠错、法务与版本历史、首启页材质、构建号 323。
