# Codelumi 操作手册（发版 / 真机 / 取证 / 内购）

## 真机安装（Debug，唯一能验灵动岛的路）
```
DEST='platform=iOS,id=00008140-001138A92E01801C'   # iPhone 16 Pro（桌面名被改成「Huawei Mate XT」）
xcodebuild -project Codelumi.xcodeproj -scheme Codelumi -destination "$DEST" \
  -derivedDataPath /tmp/codelumi-device -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration OTHER_SWIFT_FLAGS="-disable-sandbox" build
```
- 团队 `8499X3S9X8` automatic signing。模拟器 `CODE_SIGNING_ALLOWED=NO` 的包**没有 App Group**。
- 移开模型构建出的包**缺 `.mlmodelc` 且残留 `.bak`**：
  `xcrun coremlc compile <in> <outdir>`（**位置参数**，没有 `--output-dir`）→ `rm` 掉 `.bak`
  → `cp -R` 进 `Codelumi.app/` → **必须重签**，先 appex 后 App：
  ```
  codesign -d --entitlements :- Codelumi.app 2>&1 | sed -n '/<?xml/,$p' > /tmp/ent.plist
  ID="2728A60C4902F4F2EF87F8A9B02564C87172B59E"   # Apple Development: zhang_wangning@126.com (K2FQFHU46Z)
  codesign -f -s "$ID" --entitlements /tmp/ent_widget.plist --timestamp=none Codelumi.app/PlugIns/CodelumiWidget.appex
  codesign -f -s "$ID" --entitlements /tmp/ent_app.plist    --timestamp=none Codelumi.app
  ```
  **必须用导出的** entitlements：裸 `Config/*.entitlements` 缺 `application-identifier` /
  `team-identifier` / `get-task-allow`，装了起不来。
- `devicectl device install app --device <id> <path>`；
  `devicectl device process launch --terminate-existing -e '{"SCREEN":"…"}'`；
  `--console` 可抓 stdout（`[codelumi-iap]` 等日志）；`process terminate --pid <pid>`（**只吃 pid**）；
  `devicectl device capture screenshot --device <id> --destination p.png`。
- 真机读写：`devicectl device info files|copy from|copy to --domain-type appGroupDataContainer
  --domain-identifier group.com.jikezhang.codelumi`。真机启动会从 iCloud 同步，种子数据可能被覆盖。
- ⚠️ 装 Debug 包会**覆盖 TestFlight 正式版**（同 bundle id），要回正式版得从 TestFlight 重装。

## 模拟器取证
- 无 idb/applesimutils，AppleScript 被拒（-10004）→ 面板靠
  `SIMCTL_CHILD_SCREEN=xxx xcrun simctl launch <dev> com.jikezhang.codelumi`
  （**前缀形式**；写在 bundle id 后面会被当 argv 丢弃）。
- `simctl launch` 必须 `--terminate-running-process`；装完先核对 `CFBundleVersion` 再截图。
- 常用直达入口（`BuildFlags.scaffoldsEnabled`，仅 Debug）：`history|stats|browse`、`settings|profile`、
  `appicon`、`license`（= `FullVersionView` 付费页）、`legal`、`stationGroups`、`share`、`aiCheck`。
  付费页另有 `PAYWALL_ANCHOR=bottom` 落到页底。
- 模拟器 ID 会变，`xcrun simctl list devices` 现查。折叠屏（iPhone Duo）截图必须 `--display=1`。
- 性能：`xctrace record --template 'Time Profiler' --attach <pid> --time-limit 18s`，
  导出 xpath `/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]`；
  XML 里 frame/thread 是 id 定义 + ref 引用，必须建表再解析。`Animation Hitches` 模拟器不支持。
  DEBUG 探针：`PERF_LOG=1`（PerfProbe，写 Documents/perf.log）、`PERF_FPS=1`（FrameMonitor）。

## 内购（2026-11-21 实测定论）
- 商品：`…pro.lifetime`（非消耗，基准地 CHN，手动价 1 档）+ `…pro.annual`（订阅组 `22565648`）。
  `displayedPlans = [.lifetime, .yearly]`，月度已下架。
- 🔴 **真机价格不显示 = 商品在 ASC 未过审，不是代码问题**。真机实测日志
  `[codelumi-iap] storefront=CHN products=(empty)` —— StoreKit 连上了，但一个商品都不返回。
  ASC 状态：lifetime `READY_TO_SUBMIT`、annual `CREATED`（都没进过审核）。
- 模拟器里显示 `$0.99` 是**占位价**，不能当「商品可用」的证据（本地 `Codelumi.storekit` 写的是
  9.99 / 1.99，ASC 是 CNY，都对不上 0.99）。
- 修复路径：把两个内购挂进提交单随版本一起送审 → 过审后 StoreKit 才返回商品。
  1.0.0 现为 REJECTED（2.1），得先在 Resolution Center 回复。
- API：`/v1/subscriptionGroups` 对当前 Key **403**；annual 状态从
  `/v1/apps/{aid}/inAppPurchases`（legacy）读；价格走
  `/v1/inAppPurchasePriceSchedules/{id}/manualPrices?include=territory`。
- 代码侧：`Product.displayPrice` 是系统按 storefront 格式化好的串，**不许写死金额**；
  取不到商品时 `price(for:)` 返 nil → 按钮「暂时无法购买」+「重新获取商品信息」重试入口。

## 🔴 文案口径（2026-11-23 老大发火定的）
- **TestFlight「测试内容」和 App 内版本历史都是写给用户看的**，不是给开发者看的。
  一律不写：逆向了哪个私有框架、descriptor 属性、角标读数、诊断键、build 号之外的排查细节。
  只写「用户能感知到什么变了 / 怎么试」。排查过程写在代码注释和给老大的对话里。
- 同理：临时加在界面上的排查标记（如小组件右下角红色小字）要在文案里一句话说明「临时、下版去掉」。

## TestFlight 发版（全命令行）
- 🔴 `-exportArchive` **本机不可用**（无 GUI 时 `ITunesSoftwareService` 起不来），别试。
- 分发证书 `P76B23FF7S`（2027-11-15）。🔴 **profile 别用 Xcode 本地缓存**
  （`~/Library/Developer/Xcode/UserData/Provisioning Profiles/` 里那两个是 `Apple Distribution:`
  证书签的，本机只有 `iPhone Distribution: Wangnjng Zhang (8499X3S9X8)` → altool 报 90179）。
  ✅ 用 ASC 上 2027-11-15 到期的：App `7H29P7MJ8Q`(313) / `QWXC4A3745`(322)、
  Widget `4F62FDJ8K2`(313) / `43ADL489RJ`(322)；`python3 tools/asc-profiles.py --list` 现查，
  `GET /v1/profiles/{id}` 的 `profileContent`(base64) 下载。⚠️ 别用 `bids["data"][0]`（第一个是 Widget）。
- 🔴 entitlements 不能照抄 profile：`icloud-services=*`、`icloud-container-environment`、
  `ubiquity-kvstore-identifier=团队.*` 都会被拒。手写精简版：`CloudDocuments`（数组）、
  删 environment、`keychain-access-groups` 写具体 bundle id、`get-task-allow=false`、
  `aps-environment=production`、`beta-reports-active=true`。
- 链路：`mv .mlmodel .bak` → `xcodebuild archive -destination 'generic/platform=iOS'
  -allowProvisioningUpdates` → 删包内 `.bak` + 补 `.mlmodelc` → 下载 profile 重签（先 appex 后 App）
  → `cd /tmp && ditto -c -k --norsrc --keepParent Payload /tmp/Codelumi.ipa`
  （🔴 传 **Payload 目录**；**不能加 `--sequesterRsrc`**）
  → `xcrun altool --validate-app` / `--upload-app`（apiKey `34Z43R5SGY`，
  issuer `e2936bfc-e52b-4931-a763-9f03dec868e3`；`WILL RETRY` 是常态）
  → 2–3 分钟转 VALID 后 `python3 tools/testflight-publish.py --build NNN --notes-file …`。
- 停测旧构建：`python3 tools/asc-expire-old-builds.py --below N [--apply]`（`PATCH /v1/builds/{id}`
  `{expired:true}`；Apple 语义是「停止测试」不是删除）。

## 提交单 / ICP（2026-11-21 21:50）
- 内购已挂进**草稿提交单** `543c618e-8ca5-4b3b-a506-aefec5752bbf`（`READY_FOR_REVIEW`，未提交）：
  条目 3 = 1.0.0 版本 + `inAppPurchaseVersions d0a4b8bd…` + `subscriptionVersions 25ba11be…`。
- 🔴 `reviewSubmissionItems` 的关系名是 **`inAppPurchaseVersion` / `subscriptionVersion`**，
  不是 `inAppPurchase` / `subscription`（会报 ENTITY_ERROR.RELATIONSHIP.UNKNOWN）。
  版本 id 取自 `/v2/inAppPurchases/{id}/versions`、`/v1/subscriptions/{id}/versions`。
  权威字段表：官方 OpenAPI zip → `components.schemas.ReviewSubmissionItemCreateRequest`。
- ASC「App 合规 › 中国大陆 ICP 备案号 › 设置」弹窗**只有输入框 + 取消/保存**，
  **没有豁免开关**；没备案号只能留空（Apple 文案是「如果有…请在此处提供」）。

## 小组件真透明（2026-11-23 定位到根因 + 已实现）
- 🔴 **公开 API 做不到是事实**，但 Widgy / Top Widgets 用的是**私有接口**，路线已摸清：
  小组件由 SpringBoard 贴图，贴图前按 widget descriptor 垫底色，那是宿主进程的决定。
  改法（源自 `pookjw/ClearAndBlurredWidgets`）：在**扩展进程**里 swizzle WidgetKit 的
  `_TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject`
  `getAllCurrentDescriptorsWithCompletion:`，把返回的 descriptor `mutableCopy` 后调
  `setBackgroundRemovable:YES` / `setTransparent:YES` / `setPreferredBackgroundStyle:`
  （0x1 透明、0x2 模糊），重新编码后交回宿主。
- 本工程实现：`CodelumiWidget/WidgetTransparency.mm`（**必须 -fno-objc-arc**，pbxproj 里挂了
  `COMPILER_FLAGS`；同时登记 fileRef/buildFile/group/widget Sources 四处）。
  只在 `codelumi.widget.clear` 打开时才改，其余原样放过；方法找不到/参数个数不对就完全不挂。
- 风险：私有接口，系统改名字就静默失效（已做判空保护）；全运行时字符串派发，二进制里没有
  私有符号，所以静态扫描看不出来 —— 这也是那些 App 能上架的原因。仍属审核灰区。
- 参考：`https://github.com/pookjw/ClearAndBlurredWidgets`、方君宇那篇中文复盘
  （`fangjunyu.com/2025/10/08/...`）。有说法称 iOS 26 起该 hack 会退化成液态玻璃，需真机验。

## ASC 现状（2026-11-22 23:35 更新）
- 构建 **334** 已上传 VALID（2026-11-23 00:36，`183c7a74`，含真透明私有接口 + 完整信息联动）；333 亦可测。
- 构建 **333** 已上传 VALID（23:35，`cd0a7120`），已挂「Codelumi公测」、测试内容 1366 字、Beta 审核 submitted。
  这是 2026-11-22 那轮（18 款小组件 / 取件进度 / 背景两开关 / 外部入库通知）的发版构建，
  文案 `tools/testflight-notes/333.md`，App 内版本历史已同步（1.0.0 卡片 + `330–333` 内测记录）。
- 🔴 entitlements 的 `keychain-access-groups` 必须写**团队前缀的具体 bundle id**
  （`8499X3S9X8.com.jikezhang.codelumi`），写裸 `com.jikezhang.codelumi` → altool 90164
  「contains a key value that is not allowed」（profile 里是 `8499X3S9X8.*`）。
- 332 / 331 / 330 / 329 … 全部保留可用（未停测）。

## ASC 历史（2026-11-21 21:52）
- 构建 **329** 已上传 VALID（21:52，`019d0ed6`），挂「Codelumi公测」（组
  `c90099fc-1862-4b2a-8f48-a7537111fe45`），测试内容 693 字，Beta 审核 submitted。
  328（`b49a57ce`）/ 327 / 326 / 325 保留可用。
- 文案改名（2026-11-21 19:08 走 API 改完并回读确认）：1.0.0 版本描述 4 处
  `Codelumi` → `Codelumi`（**没动** `codelumi-legal` 两个 URL）；内购 lifetime 本地化
  「Codelumi Pro 永久 / 订阅可永久使用Codelumi Pro」→「Codelumi Pro 永久 / 一次买断，永久使用 Codelumi Pro」。
  App 级名称已是 `Codelumi`，`CFBundleDisplayName` 已是 `Codelumi`，法务 HTML 全是 Codelumi；
  版本历史 0.2.7 那条「英文名 Codelumi」是**史实保留**，别改。
- 1.0.0 目前 `PREPARE_FOR_SUBMISSION`（不是之前记的 REJECTED），已绑 build 327。
  老大 2026-11-21 19:10 决定：**先不提交审核**。
- 🔴 **API Key 权限差异（2026-11-21 定论）**：`34Z43R5SGY`（DSH）只有「App 管理」→
  `/v1/subscriptions`、`/v1/subscriptionGroups` 全 403；`T359K7F6U3`（workbuddy）是「管理」→
  订阅接口都能读能改。用法：`ASC_KEY_ID=T359K7F6U3 python3 …`（脚本 `make_token` 认这个环境变量）。
  私钥 `~/.appstoreconnect/private_keys/AuthKey_T359K7F6U3.p8`。
- 🔴 legacy `/v1/apps/{aid}/inAppPurchases` 报的 annual `state=CREATED` **是假的**；
  真状态要用 Admin Key 查 `/v1/subscriptionGroups/22565648/subscriptions` → `READY_TO_SUBMIT`。
- 两个内购的审核截图都已存在，元数据齐全，**唯一缺的就是挂进提交单送审**。
- 仍需人工在网页做的三件：Resolution Center 回 2.1 六项、App 合规页、
  「协议、税务和银行业务」里的付费应用协议（未生效会让**所有**内购返回空）。
- **324 及以下全部停测**（324/322/321/320/319/318 六个 `expired=true`）。
- **1.0.0 = REJECTED，2.1 Information Needed**（2026-11-16），`releaseType=SCHEDULED`；
  提交单 `1c1857ec…` 实测 COMPLETE，仍绑 build 309。审核备注 `reviewDetail 2de42837…` 只有
  128 字符，须补 6 项（真机录屏/用途受众/设置功能/外部服务/地区差异/受监管）。


## 图标（15 套）· 完整操作与坑（2026-11-22 迁自 MEMORY.md）
- 🔴 全部 `AppIconNN.imageset` **只放 `CodelumiShared/Assets.xcassets`**（两 target 都编）；
  放 App catalog → 灵动岛/锁屏静默渲染灰块。
- 新增一套动四处：imageset（60/120/180 + original）、`Codelumi/AppIcons/IconNN@2x|@3x.png`、
  Info.plist 的 **`CFBundleIcons › CFBundleAlternateIcons`**（⚠️ 不在顶层）、`AppIconChoice`。
  `sips -z` 只改尺寸不改格式，源是 JPEG 必须加 `-s format png`。
- 编号连续 01…15，`fallback` = **`.icon06`（黑盒立体）**，Info.plist 注册 **14 条** alternate
  （06 是主图标，不能登记）。12–15 是 2026-11-21 晚追加的四套（纯追加不改已有序号 →
  `currentScheme` 仍为 `"3"`，`legacyMap` 无需扩）。只有「已有图标序号被改动」才扩 legacyMap + 升 scheme。
- **目录号** `AppIconChoice.catalogID` = `DZYTB%04d`，按网格从上到下、从左到右发号
  （DZYTB0001…DZYTB0015），网格下方显示「DZYTB0006 · 黑盒立体」，无障碍标签也带号。
- 🔴 **岛内图标随 `ContentState.appIconRaw` 传**，扩展别自己读 `AppIconStore.current`
  （App Group 一断就回落 fallback）。换完走 `refreshForAppIconChange()`。
- `CodelumiWidget/Assets.xcassets` 只留 `AccentColor` + `WidgetBackground`。
- 模拟器截不到真实灵动岛，只能真机验。
- 🔴 **换图标模拟器差异**：iOS **17.4 模拟器完全正常**（实测切第 14 套成功）；iOS **26.1/27.2
  模拟器必失败**（宿主侧 CoreServicesUI 缺 upcall bundle：`Code=5 couldn't load upcall bundle
  principal class` / `Code=35 LSIconAlertManager`，重启/换干净模拟器/重装都无效）；**真机正常**。
  → 验切换用 iOS 17.4 runtime 那台或真机，26/27 模拟器只看网格渲染与选中态。
- ⚠️ 图标偏好**三处**存储，优先级从高到低：App Group `group.com.jikezhang.codelumi` 域
  （模拟器里也能用！）→ `<App容器>/Library/Application Support/appicon.txt` → standard 域。
  改模拟器状态必须三处一起改，只改镜像文件会被 App Group 旧值压过去；改完 `shutdown`+`boot`
  让 cfprefsd 重载。`simctl spawn defaults read` 读不到 App Group 域，要直接读 plist 文件。



## 驿站组 / 驿站 ID / 排序（2026-11-22 迁自 MEMORY.md）
- `CodelumiShared/StationGroups.swift`（App + Widget 双 target）。
- ID 前缀：内置 `NZYZ`、自定义 `DZYYZ`、组 `FZYD`，各 5 位补零；**首次发号落盘固化**
  （`station-identity.json`），之后只追加，不能按下标实时算。
- 组数据 `station-groups.json`：`id/name/memberIDs/createdAt/iconInheritMemberID/locationInheritMemberID`；
  关系挂**成员 ID**，改名走 `StationIdentity.rename`。
- 三段优先级：组驿站 > 未归组驿站 > 组内成员。⚠️ ②③ 前缀相同，靠 `memberIndex()` 分辨。
- 渲染：`PickupSortLogic.stationName` → 组名；`PickupNaming.secondaryLabel` → 「组名/原名」；
  待取卡 / 已取卡 / 详情 / 分享卡四处都改。
- 图标继承两路：内置成员 `CourierLogo`、自定义成员 `iconFiles`（只查 `iconFiles` 会把内置驿站
  按组名首字画）。
- 围栏：组优先、组内成员不单独监控；`matches` 先把记录驿站 resolve 成组名再比。
- `StationGroupStore.all()` **必须缓存** —— `StationLogo` 每画一格都问「这是不是组」。
- **取件码自然排序** `PickupCodeOrder`：切字母/数字段，数字段去前导零后先比位数再比字典序
  （等价比数值、不溢出 Int）；数字段排在字母段前；同形回落原文。自带三态 `Order` 不用
  `ComparisonResult`（单文件编译不可用）。`Character.isNumber` 对全角/罗马数字也 true →
  必须 `ch.isASCII && ch.isNumber`。
- 🔴 **并列必须走 `PickupSortLogic.tieBreak`**（2026-11-21 老大定）：短信是批量导入的，47 条待取
  只有 5 个时间戳、22 条并列在同一秒，而 Swift `sorted` 不稳定 → 同一份数据 App 与小组件排出
  两种顺序（用户看到「桌面顺序不对」）。
  **规则：时间一致 → 组内按取件码 0-9、A-Z 升序**（即 `PickupCodeOrder` 自然序；数字段按**数值**
  比，`8-4-999` 在 `8-4-1005` 前，不是逐字符），码也相同再比 id。恒升序，与当前排序方向无关。
  覆盖点：`StationInnerOrder.isOrderedBefore`、`PickupSortLogic.sort` ×3、待取页 `computedDisplayed`
  与 `searchBase`（`prefix` 截条数依赖它）、已取页 `computedOrderedList` 与公司桶、`PickupStore.pending`
  / `pickedUpRecords` / `enforceStorageLimit`、灵动岛与锁屏两处。
- 切「分组方式」后必须 `WidgetCenter.shared.reloadAllTimelines()`，只写 App Group 不会让
  桌面自己知道（能拖几小时）。

