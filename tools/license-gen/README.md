# Codelumi · 离线凭证签发工具

这是**卖家侧**（也就是你）用的工具，不是给用户的。用户侧只有一个入口：
App 的「我的 › VIP 模式 › 导入凭证」。

整条链路不联网：私钥在你这台机器上，公钥硬编码在 App 里，
买家把凭证粘进 App，验签在本机完成。

---

## 私钥

`private-key.pem` 已经在本目录生成好了。它**只存在于这台机器上**：

- 不进任何仓库（`.gitignore` 已挡）
- 不进 App 包
- 换机器时手工拷过去；**丢了就再也签不出能被 App 接受的码**

对应的公钥硬编码在 App 的 `CodelumiShared/OfflineLicense.swift`
（`LicenseVerifier.publicKeysBase64`）。

> 🔴 私钥泄露 = 任何人都能自造永久会员，且没有补救手段。
> 🔴 换密钥 = **已发出的所有凭证当场作废**。要平滑轮换，必须让 App
>    同时接受新旧两把公钥（那个字段本来就是数组），不能直接替换。

---

## 完整流程（先收设备码，再发凭证）

```
① 买家装 App →「我的 › VIP 模式 › 导入凭证」→ 看到「本机设备码」（32 位十六进制）
② 买家把这串码发给你（截图或文字都行，带连字符/空格会自动归一化）
③ 你跑 issue.mjs --device <那串码> 签出凭证，整段发回给买家
④ 买家粘进 App → 解锁
```

🔴 **凭证与设备码绑定，这是唯一能挡「一码多卖」的机制。**
买家把凭证转发给别人，别人导进去也解锁不了 —— 因为凭证里签的是原来那台
设备的码。所以 `--device` 是**必填**：忘了传就是发出去一张全网通用券，
而凭证一旦发出就收不回来。

---

## 发码

拿到买家的设备码后，按他买的档位跑一条命令，把输出**整段**复制发给他：

```bash
DEV=3F2A1C8D4E5B7A901234ABCDEF567890        # 买家发来的那串码

node issue.mjs --service lifetime --device $DEV          # 永久
node issue.mjs --service yearly   --device $DEV          # 年费，365 天
node issue.mjs --service monthly  --device $DEV          # 月付，30 天

node issue.mjs --service yearly --device $DEV --days 400 # 自定义天数（补发、补偿）
node issue.mjs --service yearly --device $DEV --note "订单尾号1234"   # 备注，仅供你对账

# 一次给多个买家签（设备码与买家顺序一一对应）
node issue.mjs --service yearly --batch 3 --device "3F2A…,1111…,ABCD…"
```

输出形如（约 200 字符，一整串、没有空格）：

```
CLIP1.eyJzIjoibGlmZXRpbWUiLCJkIjoiM0YyQTFDOEQ0RTVCN0E5MDEyMzRBQkNERUY1Njc4OTAiLCJpIjoiMjAyNi0wOS0yM1QwNTowMTo0MloifQ.ZAAeqIwEacgPZ4brDu9BO5TX_qu72x21EjFVRb5YwiQjNwc53FDDZK-rtHeP2GroDenHp_KrwE5Vrf4s8xLYGQ
```

发给买家时**别加换行、别加空格**——那是「校验未通过」的第一大来源。

---

## 发出前自检

```bash
node issue.mjs --check "CLIP1.xxx.yyy"
```

会回签名是否有效、载荷内容、**绑定的设备码**、到期时间。只验签、不消耗任何东西，
建议**每张发出去之前都跑一次** —— 尤其用来确认绑的是对的那台设备。

---

## 用户侧常见反馈对照

| 用户说 | 真实原因 | 你怎么做 |
|---|---|---|
| 「凭证格式不对」 | 复制时漏了尾部，或粘进了换行/空格 | 让他整段重新复制一次 |
| 「凭证校验未通过」 | 少复制了一段；或这码不是本店发的 | 核对订单，必要时补发 |
| 「凭证已过期」 | 到期了 | 发新码 |
| **「这张凭证不属于这台设备」** | ① 把别人的凭证转给他用了；② 他换了手机；③ 他重装了 App 以外的原因导致设备码变了 | 让他把**当前**设备码重新发来，按新码补签一张（见下） |
| 「凭证没有绑定设备」 | 你这张码是旧脚本（无 `--device`）签的 | 用当前脚本重签一张 |
| 「换手机要重新买吗」 | 设备码变了，老凭证在新机上无效 | 不一定要重买。让他发新设备码，按原档位补签一张即可 |
| 「卸载重装后没了」 | 重装会清掉 App 内的凭证文件（设备码在 Keychain 里，**不会变**） | 让他把原来那张凭证重新导入一次即可，**不用**重签 |
| 「导入成功但功能没解锁」 | 不应出现 | 导入成功即已写权益；若真出现，让他重启 App 后回报 |

### 关于「换机补签」

凭证里的到期时间是**写死的**，补签不会凭空续期。给换机的用户补签时：

- 剩多少天就发多少天（`--days`），别直接发满期 —— 否则换一次机就白送一年；
- 或者干脆当作一次续费处理，按你的实际承诺发。

---

## 采买建议（避免售后）

- **永久档**：不设到期，`--note` 写上订单号，便于日后对账。
- **月付/年费**：`--days` 与你的承诺保持一致；淘宝写「一年」就发 365 天，
  别为了留余量发 360 天——到期日不对是最容易被投诉的细节。
- **补发/续期**：老码没有「叠加」能力（凭证里只有一个到期时间），
  直接按新的到期日发一张新码，让用户重新导入即可覆盖。
- **每单存一份设备码 + 签发记录**（订单号、档位、到期日、设备码）。
  售后全靠它 —— 用户说「码不能用」时，先 `--check` 他手上那张，
  再和记录比对设备码，基本一眼定位。

---

## Mac 端图形工具（发码.app）

不想敲命令行时用这个。状态栏随手签一张，主窗口做批量 / 验签 / 台账。

```bash
cd macapp && ./install.sh        # 构建 + 安装到 /Applications/发码.app（推荐）
cd macapp && ./build.sh          # 仅构建，产物：macapp/build/发码.app
```

### 安装到「应用程序」（推荐）

```bash
./install.sh                      # release 构建并安装
./install.sh debug                # debug 构建并安装
./install.sh --no-build           # 跳过构建，只同步现有产物
```

装到 `/Applications` 后，Spotlight / 启动台都能搜到，也可以直接拖进 Dock 常驻。
**这一步不只是图方便** —— 仓库在外挂卷上，而 `open` 启动的 App 读该卷文件会被
内核门禁永久挂起（详见下节）。装到本机卷后，这个风险从根上消失。

App 的数据（私钥、台账）本来就落在 `~/Library/Application Support/CodelumiIssuer/`，
仓库只作一次性导入来源，所以安装副本是**自包含**的，不需要仓库在场也能跑。

> 装到 `/Applications` 后，「导入来源目录」的默认推算会失效（`build/发码.app`
> 上溯三级是 `tools/license-gen`，而 `/Applications/发码.app` 上溯三级是 `/`）。
> `install.sh` 只负责复制文件，不会改配置；如需重新导入，在界面上手动选一次
> 仓库目录即可，之后会记进 `UserDefaults`（键 `LicenseGenSourceDir`）。

### 界面

遵循 macOS 26 的液态玻璃语言，浅色 / 深色两套外观都做了实拍验证（见 `macapp/截图/`）：

- **卡片**用 `NSGlassEffectView`（macOS 26 引入）。玻璃会自己跟随系统外观与背后内容，
  天然免疫下面的「颜色固化」问题。所以 `Info.plist` 的最低系统版本是 **26.0**。
- **按钮**自绘胶囊：背景走 `draw(_:)` 画在标题**之下**（用 sublayer 会盖住系统绘制的
  标题）。主按钮是强调色渐变 + 顶部掠射高光 + 轻投影，次按钮是玻璃质感底 + 细描边。
- 顶栏 / 底栏高度在 `T.headerHeight` / `T.footerHeight` 钉死，不靠 Auto Layout 分配。
- **结果行一律单行**：主信息（设备码）与明细（档位 / 到期 / 备注）横向排成一行，
  行高由 `T.rowHeightInline = 42` 兜底。窗口宽度本就富余，堆成上下两行只会显得挤。
  （实测坑：横向 `NSStackView` 的拟合高度**只按文字算**，26pt 的按钮不参与 ——
  不显式给下限的话行高只有 31，按钮上下各剩 2pt，视觉上"顶格"。）

> **两个 AppKit 坑（都造成过实际故障）**
>
> 1. **`layer.backgroundColor = 动态色.cgColor` 会把颜色固化。**
>    `.cgColor` 取的是「当前绘制外观」下的值，赋给 layer 后就不再变化 ——
>    系统切到浅色时窗口背景变了、自绘部分却还是深色，表现就是
>    「浅色窗口 + 深灰卡片 + 近黑输入框」，非常难看。修法：自绘视图实现
>    `viewDidChangeEffectiveAppearance()` 重设颜色，并用
>    `effectiveAppearance.performAsCurrentDrawingAppearance { }` 包住解析。
>    （`NSTextField.textColor` 不受影响，它每次绘制都重新解析。）
> 2. **没有 `intrinsicContentSize` 的视图，设 `contentHuggingPriority` 完全无效。**
>    Auto Layout 的 hugging / compression 只在该视图有固有尺寸时才生成约束。
>    AppKit 里自定义 `NSView`（连 `NSStackView` 自身实测也是 `-1×-1`）都属此类，
>    于是「谁吃剩余高度」变成无解方程 —— 实测顶栏被分到 328pt、内容区只剩 350pt、
>    结果区被压成 10px，表现就是窗口下方一大片空白。修法：工具栏这类固定高度区域
>    直接钉死高度；行内弹性占位（`makeSpacer()`）用显式 0 高度约束锁住 ——
>    靠 hugging 拦不住，它会被 NSStackView 拉伸到填满可用高度。

改完任何 UI 跑一次验证器：它会创建真实窗口、量化测量布局、抓真实渲染出图，
并逐项审计（玻璃是否就位 / 颜色是否跟随外观 / 有无尺寸塌陷）。

```bash
./verify/run.sh                 # 结构审计 + 出图（/tmp/ccui-verify）
```

### 菜单与快捷键

主菜单在 `Src/MainMenu.swift` 里**自建**（理由见下面那条坑），顶栏三项：

| 菜单 | 内容 |
|---|---|
| 发码 | 关于「Codelumi 发码」· 服务 · 隐藏 ⌘H · 隐藏其他 ⌥⌘H · 退出 ⌘Q |
| 编辑 | 撤销 ⌘Z · 重做 ⇧⌘Z · 剪切 ⌘X · 拷贝 ⌘C · 粘贴 ⌘V · 粘贴并匹配样式 ⌥⇧⌘V · 删除 · 全选 ⌘A |
| 窗口 | 关闭窗口 ⌘W · 最小化 ⌘M · 缩放 · 前置全部窗口 |

> **为什么非有不可 —— 这就是「⌘V 按了没反应」的根因**
>
> 纯代码（无 nib）的 AppKit 程序不设 `NSApp.mainMenu` 时，系统只给一个「应用名」顶级菜单
> —— **没有「编辑」菜单**。而 AppKit 的键盘快捷键**是由主菜单的 keyEquivalent 分发**的：
> ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z 并没有写死在 `NSTextView` 里，它们靠「编辑」菜单里对应的
> `NSMenuItem` 进入响应链。没有菜单项 ⇒ 按键一律无人认领。
> 实测（`verify/menu/run.sh`）：不装菜单时 `performKeyEquivalent` 返回 `false`；
> 装上之后 ⌘V / ⌘A / ⌘C / ⌘X / ⌘Z / ⇧⌘Z 全通。
>
> **「拷贝是英文的」是另一件事**：系统在无 nib 时给的那套默认菜单标题是**英文硬编码**，
> 不跟系统语言走；`NSTextView` 的**右键菜单**也按 App 的本地化资源解析 ——
> 而本工程原先 `CFBundleDevelopmentRegion` 缺失、bundle 里没有任何 `.lproj`
> （`Bundle.main.localizations == []`），所以右键一直是 Cut / Copy / Paste。
> 现在 `build.sh` 会写 `zh-Hans.lproj/InfoPlist.strings`，右键已变中文
> （连 AppKit 自动追加的「自动填充 / 开始听写… / 表情与符号 / 全部关闭」也跟着中文化了）。
>
> 两条修法各自独立、都不能省：自建菜单解决「快捷键 + 自己菜单标题」，本地化声明解决「系统那部分 UI」。

两套验证器各管一段，**别混用**：

```bash
./verify/run.sh          # 结构审计：菜单标题 / 快捷键 / target 是否被钉死
./verify/menu/run.sh     # 行为验证：真按 ⌘V/⌘A/⌘C/⌘X/⌘Z/⇧⌘Z + 右键菜单语言
```

> 行为验证必须跑在**真实 .app** 里：响应链分发起点是 `keyWindow.firstResponder`，
> 命令行程序（无 bundle）拿不到 key window，测出来是假警报。
> `verify/menu/run.sh` 的做法是复制 `build/发码.app`（Info.plist + zh-Hans.lproj + 图标），
> 只把可执行文件换成验证入口 —— 所以不存在「两份 Info.plist 要同步维护」的问题。
>
> 另：验证脚本里的按键之间**必须让出主 run loop**（`DispatchQueue.main.asyncAfter`，每步约 0.25s）。
> `NSUndoManager` 的 undo 分组靠 run loop 的**事件迭代**闭合，同步连做几步会让所有编辑
> 挤进同一个 group，⌘Z 一按撤掉整段历史 —— 看起来像「撤销坏了」，其实是测试失真。

### 看历史凭证（买家说「码丢了」时重发）

签发台账页每行右侧的「查看」→ 行内展开**凭证全文**（等宽、可拖选），旁边「拷贝」
一键复制，复制后按钮短暂变「已拷贝」。

> 早期版本这里的按钮叫「凭证」，点了是**静默复制**：复制其实成功了，但界面上
> 没有任何提示，观感上就是「按钮点了没反应」。现在拆成两步 —— 先「查看」看得见，
> 再「拷贝」有反馈。
>
> 顺带一条通用纪律：**拷贝类操作必须给反馈**，否则用户无法区分「成功」与「失灵」。
> 实现见 `PillButton.flashTitle(_:)`。

### 图标

图标不依赖设计稿，由 `macapp/icon/make_icon.swift` **程序化绘制**。改色、改间距
只需改脚本顶部的常量重跑：

```bash
xcrun swift macapp/icon/make_icon.swift   # 产出 icon/AppIcon.icns
```

视觉沿用Codelumi的品牌基因（亮蓝底 + 白色卡片叠层 + 蓝色扫描框 + 青绿/橙黄点缀），
但按 macOS 规范重绘：

| 项 | 取值 | 说明 |
|---|---|---|
| 画布 / 内容体 | 1024 / 824 px | Apple HIG：内容体占画布 824，四周留白 100 |
| 图标体形状 | 超椭圆 n=5 | macOS **不会**替 App 加圆角，必须自绘 squircle |
| 底色渐变 | `#4E9EFF` → `#1361CB` | 左上亮、右下深 |
| 扫描框 | 340×310 px，线宽 32 | 完整版 |
| 小尺寸变体 | ≤ 32px | 三层叠片在 16px 下会糊成一团，改用单卡 + 加粗扫描框（线宽 50） |

`build.sh` 会自动把 `icon/AppIcon.icns` 拷进 bundle，并在 `Info.plist` 声明
`CFBundleIconFile`；构建末尾会跑一次 `lsregister -f` 刷新系统图标缓存。

> **两个易错点**
> 1. `CFBundleIconName` 是给 Asset Catalog（`Assets.car`）用的。纯 `.icns` 场景
>    只声明 `CFBundleIconFile` 即可——声明了前者却没有对应资源时，系统会回退到
>    通用底板（浅灰圆角方 + 缩小的图标内容）。
> 2. `lsregister -f` 之后图标缓存需**数十秒**才生效。这期间 `NSWorkspace` 可能
>    仍返回通用底板，属缓存过渡态，不是图标本身有问题。

### 首次使用：先双击一次「同步发码数据.command」

**这不是可选项**，原因见下一节。脚本会把私钥与台账复制到本机容器，之后
App 即可独立运行：

| | 路径 |
|---|---|
| 本机容器（App 读写此处） | `~/Library/Application Support/CodelumiIssuer/` |
| 仓库目录（同步来源） | `tools/license-gen/` |

App 每签一张，追加到的是**容器**里那份台账；跑一次同步脚本即可带回仓库
（按「已签发条数」比较，多的一方为准，不会把台账变成更少的内容）。

### 为什么必须装到本机卷（外挂卷门禁）

**直接从 `macapp/build/` 里双击运行是不行的** —— 那个副本在外挂卷上，受
macOS「可移除宗卷」门禁保护，表现为「一打开就永久卡死、窗口都不出」。
为避免误双击，`build/` 目录里放了 `.metadata_never_index`，Spotlight 不再索引它，
**能搜到、能正常双击的只有 `/Applications/发码.app` 这一份**。
（早期版本的本文档把结论写成「不能把 App 拖进 Dock 用」；
装到 `/Applications` 后拖进 Dock 是完全可以的，问题只在于**别从外挂卷运行**。）

实测（macOS 27.2 / 外挂 APFS 卷、`noowners` 挂载）：

1. 由 Finder 双击启动的 App 读该卷上的文件时，`stat()` **0ms 返回 true**，
   但紧接着的 `open()` 会在内核里**永久挂起** —— 因为系统要弹授权框；
2. 那个授权框在多屏布局下会弹到**副屏**（副屏位于主屏左侧、坐标为负）。
   副屏没接时根本看不见，于是表现为「App 一打开就永久卡死、窗口都不出」；
3. 终端（包括 `.command` 脚本）持有磁盘权限，所以由终端做跨卷读写即可绕开。

因此 App 的设计是：**只读写本机容器**，仓库目录仅作导入来源，且读它**只在
后台线程**做（核心层带 3 秒看门狗兜底），主线程绝不触碰外挂卷 —— 这保证
窗口永远能先上屏，不会因为 IO 卡死。若来源目录确实不可读，界面上会直接给出
「导入私钥…」按钮，用系统文件选择器手动导入一次即可。

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `issue.mjs` | 签发与自检脚本 |
| `issue-openssl.py` | 签发脚本的 Python + OpenSSL 等价实现（`issue.mjs` 的交叉验证） |
| `shortcut-shell.zsh` | 快捷指令「运行 Shell 脚本」用的自包含片段 |
| `快捷指令签发方案.md` | 用快捷指令手搓签发工具的方案与实测记录 |
| `同步发码数据.command` | 双击运行：私钥/台账在仓库与本机容器之间同步 |
| `macapp/` | Mac 端图形工具（纯 AppKit，`./install.sh` 构建并安装） |
| `macapp/install.sh` | 构建 + 安装到 `/Applications`（含签名校验与 LaunchServices 注册） |
| `macapp/Src/MainMenu.swift` | 主菜单（编辑 / 窗口 / 应用）—— **缺它 ⌘C/⌘V/⌘X/⌘A/⌘Z 全失效** |
| `macapp/icon/make_icon.swift` | 图标生成脚本（程序化绘制 → `.icns`） |
| `macapp/verify/run.sh` | 结构审计：布局量化 + 出图 + 菜单标题/快捷键（改完 UI 或菜单跑一次） |
| `macapp/verify/menu/run.sh` | 快捷键行为验证：真按 ⌘V/⌘C/⌘X/⌘A/⌘Z/⇧⌘Z + 右键菜单语言（需真实 .app） |
| `macapp/截图/` | 浅色 / 深色两套实拍图（含台账凭证展开态） |
| `private-key.pem` | 私钥（**不进仓库**） |
| `issued-ledger.md` | 签发台账（**不进仓库**） |
| `README.md` | 本文件 |

### 改脚本时必须保持的三件事

都写在 `issue.mjs` 文件头，这里再强调一次——错了只会表现为
「用户导入失败」，极难定位：

1. **签名必须是 P1363 格式**（`dsaEncoding: 'ieee-p1363'`），
   不是 Node 默认的 DER。App 侧 CryptoKit 的
   `ECDSASignature(rawRepresentation:)` 只认定长 r‖s。
2. **时间不能带毫秒**。App 侧用 `.iso8601` 解码，
   遇到 `2026-09-23T05:00:00.000Z` 会直接抛错、整张凭证被判格式错误。
3. **设备码归一化必须与 App 侧一致**：`toUpperCase()` + 只留 `0-9A-F`。
   规则不一致会变成「卖家说签了、用户说验不过」的经典售后。
   App 侧的对应实现是 `LicenseDevice.normalize`。
