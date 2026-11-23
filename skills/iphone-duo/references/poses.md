# 几何真值与取证方法

## 1. 本项目实测的几何表（2026-11，Duo 模拟器）

| 姿态 | window bounds (pt) | safeAreaInsets | size class | 备注 |
|---|---|---|---|---|
| 外屏（折叠） | 466 × 678 | `t0 l0 r84 b34` | compact / regular | 右侧 84pt 是前置相机 + dock 区；底部 34pt 是 Home 条 |
| 内屏 · 竖屏 | 669 × 951 | 同上量级 | regular / regular | 本项目**不分栏**（两栏各 330pt 太窄） |
| 内屏 · 横屏 | 951 × 669 | `t0 l0 r84 b34` | regular / regular | 分栏；**系统标签栏会被摆进右侧 84pt 里**（见 pitfalls） |

内屏横屏 `safeArea` 实测输出（探针原文）：

```
window=x0 y0 w951 h669  safeArea=t0.0 l0.0 b34.0 r84.0
sizeClass h=2 v=2 idiom=0
```

- 屏的**物理像素**：外屏 1398×2034；内屏横屏 2853×2007、内屏竖屏 2007×2853（`--display=3` 的返回值随姿态变）。
- `UIScreen.main` 在 Duo 上**报的是外屏**（466×678），内屏也这么报 —— **永远不要用它做布局判断**。

## 2. 判据推导（为什么是「最短边 > 600 且 宽 > 高」）

| 设备/姿态 | 尺寸 | 最短边 | 宽 > 高 | 命中 |
|---|---|---|---|---|
| 直板机竖 | 402 × 874 | 402 | ✗ | — |
| 直板机横 | 874 × 402 | 402 | ✓ | ✗（最短边不够） |
| Duo 外屏 | 466 × 678 | 466 | ✗ | — |
| Duo 内屏竖 | 669 × 951 | 669 | ✗ | — |
| **Duo 内屏横** | **951 × 669** | **669** | **✓** | ✅ |

补充：iPhone 18 Pro Max 竖 440×956、横 956×440 —— 横屏最短边 440，仍不命中。
即使将来出现更大直板机，只要「最短边 > 600」这条在，就同时要求「它是宽的」，
直板机横屏的短边永远受 440 级别约束，不会误判。

## 3. 模拟器：能看到什么、不能做什么

```bash
# 设备清单
xcrun simctl list devices | grep -i duo

# 截图（--display 必须跟在 screenshot 后面！）
xcrun simctl io <UDID> screenshot --display=1 /tmp/duo-outer.png   # 外屏 1398×2034
xcrun simctl io <UDID> screenshot --display=3 /tmp/duo-inner.png   # 内屏，随姿态给 2853×2007 或 2007×2853

# 启动到某个脚手架页面（本项目约定）
SIMCTL_CHILD_SCREEN=pending SIMCTL_CHILD_SKIP_PERM=1 SIMCTL_CHILD_SKIP_ONBOARDING=1 \
  xcrun simctl launch --terminate-running-process <UDID> com.jikezhang.codelumi
```

- ❌ `simctl` **没有** fold / unfold / rotate；`io ... screenConfig --display=3 geometry 2853x2007`
  报 `No mode found that supports size`（这条命令只用于查询，不支持改）。
- ✅ **只要设备已经展开**，`screenshot --display=3` 就给内屏画面，且**已经是横屏比例** ——
  这是命令行侧唯一能取到「内屏横屏」证据的入口。
- ⚠️ Duo 冷启动要 **14–20 秒**才出画面；7 秒截到的是白屏，别误判成崩溃。
- ⚠️ 反复出现 `CoreSimulatorService: Connection interrupted`（code=53）时，
  `xcrun simctl bootstatus <UDID> -b` 再 `install` 即可恢复。

## 4. 探针模板 A：几何与 size class

放进 `#if DEBUG`，用环境变量触发，避免影响正常路径：

```swift
#if DEBUG
enum DuoGeometryProbe {
    static func log() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for (i, scene) in scenes.enumerated() {
            for (j, w) in scene.windows.enumerated() {
                print("[duo] scene\(i).window\(j) frame=\(w.bounds) "
                      + "safe=\(w.safeAreaInsets) "
                      + "h=\(scene.traitCollection.horizontalSizeClass.rawValue) "
                      + "v=\(scene.traitCollection.verticalSizeClass.rawValue)")
            }
        }
    }
}
#endif
```

## 5. 探针模板 B：命中测试（判断「看得见但点不动」的唯一可靠办法）

```swift
#if DEBUG
enum HitTestProbe {
    static func dump(_ points: [CGPoint]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
                ?? scenes.first?.windows.first else { return }
        for p in points {
            var chain: [String] = []
            var v: UIView? = window.hitTest(p, with: nil)
            while let cur = v, chain.count < 6 {
                chain.append("\(type(of: cur))\(Int(cur.frame.minX)),\(Int(cur.frame.minY)),"
                             + "\(Int(cur.frame.width)),\(Int(cur.frame.height))")
                v = cur.superview
            }
            print("[hit] \(Int(p.x)),\(Int(p.y)) -> " + chain.joined(separator: " < "))
        }
    }
}
#endif
```

判读：如果链头是**你预期的控件**，可点性 OK；如果链头是 `HostingScrollView` / `PlatformGroupContainer`
这类内容容器，说明那个点**落在别人的可点区域里** —— 视觉上看得到，事件却给了别人。

⚠️ 探针只回答「窗口内部谁接管这个点」。系统外壳（俯视、分屏、保留区）层面的拦截它**看不到**，
所以命中链正常仍可能点不动（本项目真实事故就是这样，见 `pitfalls.md` 第 1 条）。

## 6. 相机/折痕区域的取值习惯

- **不要写死 84pt**。它来自 `safeAreaInsets` / `ReservedRegion`，随姿态和机型变。
- 需要「面板贴在安全区内」时，从**窗口**取 `safeAreaInsets`（`ignoresSafeArea` 之后
  `GeometryReader` 报的可能是安全区内的尺寸，会把面板算小一圈）。
