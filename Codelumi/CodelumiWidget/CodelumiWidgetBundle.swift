import WidgetKit
import SwiftUI

// MARK: - 小组件扩展入口
//
// 单一 @main 入口。实时活动（锁屏卡片 + 灵动岛）也注册在这里 ——
// Live Activity 的 UI 必须由 widget extension 提供，不能放在宿主 App 内。
//
// 🔴 **每条桌面小组件必须在这里逐个写出来，不能用 `ForEach(WidgetPreset.all)`。**
//    `@WidgetBundleBuilder` 没有 `ForEach` 支持（它只接受 `Widget` 表达式），
//    而且系统是在**编译期**扫描这个 body 来登记所有 kind 的：写成运行时循环，
//    图库里一条都不会出现。款式清单的真源仍是 `WidgetPreset.all`，
//    这里只是把它的每条映射成一个注册项。

@main
struct CodelumiWidgetBundle: WidgetBundle {
    var body: some Widget {
        // ── 小尺寸（免费）：6 款 ───────────────────────────────────
        // 1 款清单（小中大通用）+ 4 款「一块画布只回答一个问题」+ 1 款动作型。
        // 🔴 2026-11-22：「今日到件」与「取件进度」合并成一款「取件进度」（当晚改名）。
        // 清单（精简版）：小中大通用，只有驿站 / 公司两个开关
        PickupWidget(preset: Self.preset("CodelumiCode"))
        PickupWidget(preset: Self.preset("CodelumiProgress"))
        PickupWidget(preset: Self.preset("CodelumiFocusCode"))
        PickupWidget(preset: Self.preset("CodelumiStations"))
        PickupWidget(preset: Self.preset("CodelumiOldest"))
        PickupWidget(preset: Self.preset("CodelumiCodeCard"))

        // ── 中尺寸（免费）：5 款版式（清单款已合并到上面的 CodelumiCode，三尺寸通用）──
        PickupWidget(preset: Self.preset("CodelumiProgressM"))
        PickupWidget(preset: Self.preset("CodelumiFocusCodeM"))
        PickupWidget(preset: Self.preset("CodelumiStationsM"))
        PickupWidget(preset: Self.preset("CodelumiOldestM"))
        PickupWidget(preset: Self.preset("CodelumiCodeCardM"))

        // ── 大尺寸（Pro）：4 款版式（清单款同上）──────────────
        PickupWidget(preset: Self.preset("CodelumiProgressL"))
        PickupWidget(preset: Self.preset("CodelumiFocusCodeL"))
        PickupWidget(preset: Self.preset("CodelumiStationsL"))
        PickupWidget(preset: Self.preset("CodelumiOldestL"))

        // ── 超大尺寸（Pro）───────────────────────────────────────
        PickupWidget(preset: Self.preset("CodelumiAll"))

        // ── 实时活动（锁屏 + 灵动岛）──────────────────────────────
        PickupLiveActivity()
    }

    /// 按 id 取款式。
    ///
    /// 🔴 写错 id 时**必须炸出来**：静默回落到别的款式，会让系统图库里出现两个
    ///    同名条目、或者某个款式根本不存在 —— 这两种错在截图上都极难看出来
    ///    （八个缩略图长得都差不多）。Debug 断言、Release 兜底第一款。
    private static func preset(_ id: String) -> WidgetPreset {
        guard let preset = WidgetPreset.preset(id: id) else {
            assertionFailure("小组件款式 id 写错：\(id)")
            return WidgetPreset.all[0]
        }
        return preset
    }
}
