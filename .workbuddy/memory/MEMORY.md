# Allude 长期笔记 · 核心（2026-11-22 v4 精简）

> 发版链路 / 真机安装重签 / 模拟器取证 / 内购实测 → 同目录 **`OPS.md`**。
> **踩过的坑 / 判断原则 / 协作红线 → `PITFALLS.md`（接手先读它）。**

## 路径与构建
- 仓库根 `/Volumes/ZWN/Downloads/Project/Allude/`（GitHub `Zhangwangning/Allude` 私有）；
  工程根 `Allude/`（内含 `Allude.xcodeproj`、`AlludeShared/`、`AlludeWidget/`），App 源码 `Allude/Allude/`。
- Bundle `com.jikezhang.allude`、Widget `…AlludeWidget`、App Group `group.com.jikezhang.allude`、
  iCloud `iCloud.com.jikezhang.allude`。纯 iPhone，部署目标 iOS 17.0，`GENERATE_INFOPLIST_FILE=NO`
  → 增删 Info.plist 键必须改真实文件（`INFOPLIST_KEY_*` 不生效）。
- 版本号 4 处 `CURRENT_PROJECT_VERSION`；pbxproj 改版本号必须「先读进变量再写回」，内联读写会截成 0 字节。
- 🔴 Xcode 16 同步文件夹（`PBXFileSystemSynchronizedRootGroup`）：`Allude/Allude/` 下新增 Swift/PNG **不用改 pbxproj**；
  但 **`AlludeShared/`、`AlludeWidget/` 不是同步组** —— 新增文件必须手工登记（2 处 `PBXBuildFile`
  + 1 处 `PBXFileReference` + group children + 两个 target 的 Sources，共 6 处），漏了就是「cannot find X in scope」。
```
cd Allude && xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```
- 缺 `-disable-sandbox` → 宏插件起不来，报假错（`'self' is immutable`、`StateMacro could not be found`）。
- 🔴 agent 会话内构建必卡 CoreML（`sandbox_apply: Operation not permitted`），`ENABLE_USER_SCRIPT_SANDBOXING=NO` 无效。
  绕过：**同卷**改名 `mv Allude/Resources/AlludePickup.mlmodel{,_hold.bak}` → 构建 → 还原。
  🔴 不能 `mv` 到 `/tmp`（跨卷 EXDEV，静默失败，CoreML 照跑构建照挂 —— 踩过）。

## 卡面命名与图标（唯一真源 · 2026-11-22 定规）
- `PickupNaming`（`AlludeShared/PickupModels.swift`）是**全 App 唯一取名规则**：
  `primary` = 快递公司(courier) → 短信平台(company) → 快递驿站(station)；第二段 = 驿站 → 平台且不重复；
  `secondaryLabel` 归组后为「组名/原名」。`iconSource` **恒等于 `primary`**。
- 🔴 图标规矩（老大原话）：「图标就是当前显示在最前面的那一个」——
  待取卡 / 已取卡 / 详情 / 分享卡 / 添加页 / 锁屏灵动岛 / 小组件**全部**遵守。
  **别用 `record.company`**（那是短信平台，会把「圆通发的、兔喜取的」画成拼多多）。
- App 内画图标唯一实现 `PickupIcon(naming:size:)`（`Views/DesignSystem.swift`）：
  第一段是驿站 → `StationLogo`（用户上传图 / 组继承），否则 `CourierLogo`。新代码只许调它。
- 跨进程（小组件 / 锁屏）读不到 `StationDirectory`（`.standard` + App 沙盒图）→
  `CourierLogo(primary, usesStaticAsset: true)`；取名同源，仅「自定义驿站图」退兜底。
- 🔴 品牌色只有 `CourierBrand.color(for:)` 一个入口：`Color.adaptive(light: ink, dark: inkOnDark)`。
  浅色 `ink` = 亮品牌压暗；深色 `inkOnDark` = 向白逐档混合到 BT.601 亮度 ≥ 0.55。
  别再拿 `resolvedFrom` 当文字色，也别自己写 `Color(hex: info.ink)`。锁屏/灵动岛 `tint` 传 `inkOnDark`。
- 卡面：主名 `titlePrimary = naming.primary`，副名 `secondaryLabel`；取件码恒用 `iconBrand`；
  卡面 `brand = company.isEmpty ? iconBrand : brandColor`。图标 26pt 与取件码 `.center` 对齐
  （`.lastTextBaseline` 沉 4pt），多选圈 44。待取 `PickupListView` 与已取 `HistoryView` 卡同构，改一处必须同步。
- 字号只用 `AppTheme.TypeScale`（rowTitle 17 / rowSubtitle 13 / body 15 / section 13 / note 12 / badge 11）；
  强调只加 weight（例外：chevron 12–13、等宽码）。通知里字段空就整段不出现，不拿占位句凑行。
- 灵动岛：展开必须用满 `.leading/.trailing/.bottom`，尺寸只在 `IslandExpandedMetrics` 改，改完强制 update
  （有「内容一致跳过」分支，靠 `needsForcedRender`）；图片 `Contents.json` 要
  `template-rendering-intent: original` + 1x/2x/3x，否则折叠态纯色方块。
- Section header 里 `listRowInsets` 不生效 → 分组标题当普通行塞进 Section 首行。
- 版本历史页 `Entry.id` **不能用 `UUID()`**（视图重建换 ID，与 `@State` 旧 ID 对不上，折叠弹回）。
  版本历史/内测记录是给用户看的：只写能感知的变化，不写「页头 34pt」这类开发者口径，不留 `*…**` 星号。
- 付费页 `FullVersionView` **必须一屏放得下**（form sheet 上限 890pt）；解锁清单固定 5 行。

## 桌面小组件（2026-11-22 六次改版定稿 · 18 kind）
- 每个款式一个 kind，真源 `AlludeShared/WidgetPresets.swift`；现状 **18 kind**：
  · 清单款 3 条都叫「待取清单」，都声明小+中+大：`AlludeCode`（精简，只露驿站/公司）/
    `AlludeList`（主中）/ `AlludeBoard`（主大）；
  · 5 个版式按尺寸各占一条：Progress / FocusCode / Stations / Oldest × 小·中·大（中 `M`、大 `L`）= 15；
  · 取件码卡片 `AlludeCodeCard`（小）+ `AlludeCodeCardM`（中）——**大尺寸不做**（画布浪费）；
  · 超大 `AlludeAll` 1 条。
  🔴 `@WidgetBundleBuilder` 不支持 ForEach，每款逐个写；`Widget` 协议要求**无参 `init()`**
  （缺了只报「does not conform」并指向 bundle，看不出真凶）。
- 两轴分离：`WidgetPreset.layout`（`WidgetLayout`：list / todayProgress / focusCode / stationBars /
  oldestPending / codeCard）决定画面组织，`WidgetDisplayOptions` 决定列表每行露到哪层。
  **分发只有一个视图 `WidgetLayoutContent`**（桌面 entry 与 App 内预览都走它）。
- 同一版式画三种画布：带 `metrics: WidgetHeroMetrics`（小 1 / 中 1.2 / 大 1.75），
  **放大字号本身而不是 `scaleEffect`**（后者大尺寸发虚）。
- **「取件进度」`WidgetTodayProgressContent`**（合并原「今日到件」+「取件进度」，2026-11-22 夜定稿）：
  · 分母 = `待取 + 今日已取`（只拿待取当分母永远 0%，拿总数当分母跨天会算进上周的件）。
  · 小（1.0）：标题「取件进度」+ 右侧「今日 N」→ 环 60（中心 % + 已取）→ 待取/已取两格。
  · 中（1.2）：**左**「今日到件」34pt 大数字 + 图例，**右**环 78。
  · 大（1.75）：**横线进度条**（`GeometryReader` 取宽，0% 保底 `sc(7)`）→ **全年连续热力网格** → 三格数字。
    网格 = 从 1 月 1 日连续排到 12 月 31 日，**每行固定 25 个**、排满折行（365 / 25 = 15 行，
    末行 15 个）；点径与行高由可用空间**反算**（`min(格宽×0.78, 行高×0.72)`，约 10.8pt），
    所以能自动把中间区域铺满。今天那格套一圈 `accent` 描边。
    🔴 别退回「一周一列 × 7 行」那种：列数被画布宽度锁死，点只能 5pt、整块又扁又空，
    老大当场否掉（「中间区域也大着呢啊，每行的个数要一致，超过的放在下一行」）。
    🔴 **只要圆点，没有任何文字标注**（老大 2026-11-22 定）：不要月份刻度、不要星期标签、不要标题。
    🔴 这块一共改了五版（本月日历 → 月折线 → 本年按月 12 行 → 本年连续 → 去掉全部标注），
    别擅自往回加标题/刻度，他明确嫌过「不要标月份等」。
    🔴 大画布高度预算 ~326pt：进度区 46 + 网格 91 + 三格 86 = 223，余量给三处 Spacer 均分；
    末尾必须留一个 `Spacer(minLength: 0)`，否则最后一格贴内容区下缘、数字看着像被切一半（截图实测）。
- 热力圆点配色 `AppTheme.undoneHeat(_:)`：4 档（1 / 2 / 3 / ≥4 件）。绿色直接用 `doneTint`
  （与进度条同色，同一件事不该有两种绿）。没件用 `AppTheme.emptyDayDot`（实色 `DDDCE0`/`3C3C41`，
  **不能用 `secondary.opacity(0.18)`** —— 浅色卡上几乎看不见，365 个点断成残渣）。
  🔴 **不能用「一个红 + 不同 opacity」**：深底上 opacity 低 = 混背景 = 更暗，于是「未取 1」比「未取 4」还暗，
  与「深 = 多」反了。浅/深各给硬色值。🔴 色相选**低饱和陶土红**（`E8B4A9→A34734` / `F6C7BD→DA5741`），
  别用纯红或玫红 —— 同屏已有蓝（待取）、青绿（已取）、橙（今日到件），粉红是第四种"喊话"色，
  老大原话「一点都不协调，太丑了」。
- 取件码卡片版式：中画布 = 首行「公司 ｜ 驿站」（同名只画一次）→ 图标 `sc(26)` + 大码 → 地址 →
  底部「◀ 第几/共几 ▶」；**右上角**复制，其**正下方**勾选圈。小画布 = 图标 `sc(17)` 左上 + 名字 +
  复制（右上 `sc(22)`）+ 勾选在其右（`sc(20)`，热区 `hitSize: sc(28)`）。
  宽度预算 126pt：固定 99pt，名字只剩 ~27pt → 10.5pt + `minimumScaleFactor(0.7)`。
  游标 `WidgetSingleCursor` 夹紧不环形，到头画置灰 `Image` 而非 `Button`。
- 动作型靠 `WidgetActionBridge`（App Group 信箱）+ AppIntent：拷贝写 `UIPasteboard` + 3 秒「已复制」。
  **平台边界**：WidgetKit 不支持文本选择 → 只能「轻点复制」。
- 非列表版式的口径必须在 `WidgetSnapshot.load()` 里算好，**不能拿裁过的 `items` 现数**：
  `pendingTodayCount` / `stationCounts`（前 3 + 其他，无驿站退公司）/ `oldestPending` /
  `yearDays / yearFirstWeekday / yearDayCount / todayMonth / todayDay`
  （`WidgetDayStat{month,day,total,pending,key}`，统计**全量记录含已取**，只保留有件的天；
  网格按 `month*100+day` 查表，缺的补空格）。
- 🔴 显示内容 = 用户开关：`WidgetDisplayField`（address/company/station/complete）+
  `allude.widget.showAddress / showCompany / showStation / showComplete`。
  中大清单款露 4 个、精简款露 2 个；`complete` 是总开关。默认驿站+地址开、公司关、完整关。
  `isCustomizable = layout == .list`；改完 `reloadAllTimelines()`。
  🔴 档位按**当前实际 family**（`WidgetPageSize.isFreeFamily`），不能按 `preset.needsPro`。
- 背景两层独立开关（正交可叠加）：`allude.widget.clear`（可用时真透明）+ `allude.widget.glass`（Liquid Glass），
  渲染态 solid / clear / glass / clearGlass，都走 `WidgetSurface`。旧键只读不写，
  `migrateLegacyIfNeeded()` 一次性回填。脚手架 `WIDGET_BG=`。
  🔴 **真透明由系统决定，不在 App 手里**（2026-11-22 晚定论，iOS 27.2 SDK 头文件核实）：
  iOS 27.2 的 WidgetKit 只有 `containerBackgroundRemovable(_:)` 与
  `showsWidgetContainerBackground` 两个相关 API，`WidgetRenderingMode` 仍只有
  fullColor/accented/vibrant —— **没有"强制透明"接口**。桌面外观选「透明」时系统把
  container background 整个移除、直接透壁纸；选「浅色/深色」时系统自己补不透明容器，
  谁都绕不过。所以 clear 态唯一正确写法是 `Color.clear`、什么都不画。
  🔴 **壁纸截图兜底方案已被老大否掉并整体删除**（`TransparentBackdrop.swift` +
  `TransparentBackdropView.swift` + pbxproj 登记 + 设置页入口行）。他拿 Widgy 三张不同壁纸
  对拍证明"换壁纸它还透"= 真透明，截的那张图跟结果无关；Widgy 页面上那张只是不支持时的兜底。
  **别再重写这套东西。**
  🔴 App 内预览 `WidgetCanvas` 必须用 `@AppStorage(store: AppGroup)` 绑同一对键 ——
  它原来把背景写死成 `secondarySystemBackground`，拨开关缩略图不动，被当成"开关没作用"。
- App 侧「设置 › 小组件」探索页：卡片底 = 玻璃（`.appGlass`，跟随外观页开关）；内边距 4pt、
  列距 8pt、行距 12pt；🔴 小尺寸一行 4 个、其余一行 2 个；卡片圆角 24 与缩略图同源
  `WidgetCanvasMetrics.cornerRadius`；同一行只能一种尺寸，分区序为 精选(中) → 小 → 中 → 大 → 超大。
  🔴 右上角「更多」别自己套玻璃（iOS 26 导航栏已给官方容器，会双圈）。
- 缩略图 = 真实视图 `scaleEffect`（宽度优先填满，不封 1.0）；`WidgetPresetContent` **不做档位判断**，
  锁只由 `PickupWidgetEntryView` 运行时画。
- ⚠️ kind 全换过（旧 `AlludePickupWidget` 退休），老用户桌面旧实例需删掉重加。

## 解析与数据
- `PickupParser` 四套正则 + 优先级链 code→waybill→tail→special；新正则必须注册进 `regexes`
  预编译表（否则静默 nil）。一码一卡：链式段须与首段同形（`codeShape`），纯数字段 ≥4 位。
- 三层误判防线：`isPendingDeliveryOnly` / `isPromotionalOnly`（营销话术 + 零取件线索**双条件**）/
  `isVersionLikeCode`（`glm-5`、`gpt-4` 不是码）。关键词闸门 `京东(?!卡)`。
- 地址 `normalizeAddressText`：括号**原样保留**，只丢说明性括注（请/超/收费/营业…）与行政地址
  （`stripAdminPrefix` 改变即丢）；结尾 `店店` 兜底折叠。
- 🔴 升级 App 不重解析存量记录：解析修好只对之后 ingest 生效，旧卡片要删掉重加。
- 权益快照新字段一律 `decodeIfPresent`；`MembershipPlan` 只增不删（删 case = 老用户掉回免费版）；
  订阅必须写 `expiresAt`。`enforceStorageLimit()` 只在 `ingest()` 触发（免费 50 条 FIFO），启动不删。
- iCloud 写 `<容器>/Documents/records.json`；BYOK Key 只在 Keychain（service `com.jikezhang.allude.ai`）。
- 回归：`swiftc -O -o /tmp/parser-reg Allude/Models/PickupParser.swift tools/parser-regression/main.swift`
  → `/tmp/parser-reg 短信语料库_v1.md`（基线 514 条：识别 193、地址 192）。

## 驿站组 / 排序（细节见 `OPS.md`）
- `AlludeShared/StationGroups.swift`（双 target）。ID 前缀：内置 `NZYZ`、自定义 `DZYYZ`、组 `FZYD`，
  首次发号落盘固化（`station-identity.json`），之后只追加。
- 三段优先级：组驿站 > 未归组驿站 > 组内成员（②③ 前缀相同，靠 `memberIndex()` 分辨）。
- 组名进主名位：`PickupSortLogic.stationName` → 组名；`secondaryLabel` → 「组名/原名」；
  待取卡/已取卡/详情/分享卡四处同改。图标继承：内置成员走 `CourierLogo`、自定义走 `iconFiles`。
- 取件码自然排序 `PickupCodeOrder`：数字段按**数值**比，数字段排字母段前；`ch.isASCII && ch.isNumber`。
- 🔴 并列必须走 `PickupSortLogic.tieBreak`（时间一致 → 组内按码 0-9/A-Z 恒升序）。Swift `sorted` 不稳定，
  不 tieBreak 会 App 与小组件排出两种顺序。切分组方式后 `reloadAllTimelines()`。

## 图标（15 套 · 细节见 `OPS.md`）
- 🔴 imageset 只放 `AlludeShared/Assets.xcassets`（放 App catalog → 灵动岛/锁屏灰块）；
  `AlludeWidget/Assets.xcassets` 只留 `AccentColor` + `WidgetBackground`。
- 新增一套动四处：imageset 60/120/180 + original、`Allude/AppIcons/IconNN@2x|3x.png`、
  Info.plist `CFBundleIcons › CFBundleAlternateIcons`（不在顶层）、`AppIconChoice`。
- `fallback` = `.icon06`；Info.plist 登记 14 条 alternate。🔴 换图标：iOS 17.4 模拟器正常、
  26/27 模拟器必失败、真机正常；灵动岛只能真机验。偏好三处存储，改模拟器状态要三处一起改。

## 已删除，别再加回来
- **语音录入**（2026-11-22 整块删）：`VoicePickupSheet` 全家、`VoiceSettings`、`RootTab.voice`、
  悬浮球、`WidgetLayout.voiceAdd`、`NSMicrophone`/`NSSpeechRecognition`、法务语音条款。
  `BareCodeHeuristic` 已移进 `AddPickupSheet.swift`（文本/照片共用）。
- **分享扩展**（2026-11-22 整块删）：`AlludeShare/`、`ShareInbox.swift`、`SHARE_TEXT` 脚手架、
  App 两处 drain。理由：ASC API 绑不了 App Group，卡着发不出去。
- 「使用权限」页现 5 行：通知 / 相机 / 相册 / 定位 / iCloud 与网络。

## 现状（2026-11-22 深夜）
- TestFlight：331 已发（`02c7e392`，群组「Codelumi公测」，913 字）；332 上传 VALID 未挂群；
  333 只在本地。**本次改动（删分享扩展 + 删语音 + 小组件 18 kind 重做）尚未归档发版**。
- 🔴 1.0.0 = REJECTED（2.1 Information Needed），Resolution Center 6 项草稿在
  `tools/appstore-review/1.0.0-resubmit-2.1.md`，未提交。
- 🔴 内购价格是配好的（ASC API 核实）：lifetime CHN 手动价点 `10028` + 177 地区自动价，
  annual 挂订阅组 `22565648`，两档 `READY_TO_SUBMIT`；沙盒 `storefront=USA` 均 `$0.99`。
  价格点金额查不到（403），别试。
- 免费额度：`freeVisible = 4`、`freeStorage = 50`、`widgetListCap = 60`。App 备案未完成。
- 法务线上仓 `Zhangwangning/allude-legal`（GitHub Pages），App 内 `Allude/Allude/Legal/*.html` 三副本同步。
- 性能范式：缓存放 model（`@StateObject` 的 class）不放 View 的 `@State`；键用 `hashValue`；
  `VStack` → `LazyVStack` 可消首帧冻结（代价 `proxy.scrollTo` 失效）。
