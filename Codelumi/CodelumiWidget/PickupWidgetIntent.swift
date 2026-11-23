import WidgetKit
import AppIntents

// MARK: - 小组件配置意图
//
// 形态说明（规格 v1.3 §技术架构：小组件用 AppIntentConfiguration）：
//   首发（TestFlight）阶段**不提供任何可配置项** —— 中尺寸固定展示「最近 3 条待取件」，
//   不引入额外分支可以把验收面压到最小。
//
//   之所以仍用 AppIntentConfiguration 而非 StaticConfiguration：
//   两者在「无可配置项」时行为一致，但前者已经是配置型注册 —— 将来加入
//   「选择展示的快递公司 / 排序方式」等参数时，**只需给这个 intent 加 @Parameter**，
//   不必更换注册方式。这样已装用户桌面上已有的小组件实例不会被系统重置。
//
// ⚠️ 勾选动作的意图（TogglePickupIntent）放在 `CodelumiShared/WidgetVisuals.swift` ——
//    它需要被 App target 一起编译，才能在 App 内预览页里渲染出真实的勾选框。

struct PickupWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "取件信息" }
    static var description: IntentDescription { "在桌面查看最近待取的快递" }
}
