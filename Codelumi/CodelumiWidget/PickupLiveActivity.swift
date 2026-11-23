import ActivityKit
import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 实时活动（Live Activity）注册
//
// 本文件只做「装配」：把锁屏卡片与灵动岛的四块区域接到 ActivityKit 上。
// 具体版式在 `CodelumiShared/PickupActivityAttributes.swift` —— 放共享层是为了
// 让 App 内能用同一份 View 造预览（锁屏与灵动岛都无法脚本化截图）。
//
// 版式口径（与 App 列表卡片同源）：
//   · 取件码是唯一主角，锁屏 27pt / 展开态 21pt；平台名、地址、待取数量只做上下文；
//   · 🔴 **灵动岛是纯展示，不放任何按钮**（2026-09-22 主人定调）：岛面积只有
//     十几个点、又贴在屏幕顶端，误触代价高；「标记已取」只剩两条入口 ——
//     锁屏卡片与桌面／锁屏小组件的勾选框；
//   · 灵动岛紧凑态面积以十几个点计 = **左 App 图标 / 右待取数量**（2026-11-01 去掉文字标签、>99 显示 99+），
//     最小态只剩 App 图标。🔴 这两处的图标由 `AppMarkIcon` 读
//     `AppIcon01…13` 的 imageset —— 图必须在 `CodelumiShared/Assets.xcassets`，
//     扩展进程才查得到（放在 App 的 catalog 里会渲染成灰块）；
//   · 颜色取当前这条的品牌色 —— 实时活动与 App 卡片是同一家公司的同一种色。
//
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

struct PickupLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupActivityAttributes.self) { context in

            // 🔴 2026-10-28：玻璃与内容**必须分层**。
            //    直接给「内容 + padding」套 `.glassEffect`，真机上整块玻璃会把内容吃掉
            //    （卡片只剩一块空的液态玻璃，字全没了 —— 真机实证）。
            //    正确做法：玻璃贴在一个占位的透明层上，内容用 ZStack 叠在它上面。
            ZStack {
                // 🔴 2026-11-23：卡片里不再自己铺底，深浅全由这一层玻璃决定。
                //    给它一点点暗色 tint —— 浅壁纸上前景白字才立得住，
                //    但仍然只有**一层**玻璃，不会看着像"卡里还有一张卡"。
                // 玻璃 + 背板：背板放进 `.background`，不参与尺寸计算，
                // 这样卡片大小完全由内容决定（否则模糊图会把卡撑成整块画布）。
                Color.clear
                    .appGlass(.rect(cornerRadius: 26), tint: nil)
                    .background { backdrop(for: context.state.item) }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                ActivityLockScreenCard(state: context.state)
                    // 内容块到卡片四条边等距（2026-11-23 老大要求）。
                    // 底部给 12 而不是 18：取件码是数字，行框底部自带 ~6pt 下伸空间，
                    // 补成 18 会看着比顶部多一截。
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                    .zIndex(1)          // 明确压到玻璃之上，避免被玻璃层遮掉
            }
            // 卡片按内容收紧：不写死高度，玻璃与内容同尺寸，四周留白才对得上
            .fixedSize()
            // 🔴 2026-11-23：`Glass.tint` 只是给玻璃上一层很淡的色，压不暗底色 ——
            //    亮壁纸下白字依旧发灰。改由**系统**给活动本身铺一层暗色
            //    （`activityBackgroundTint`），我们的玻璃叠在它上面取样，
            //    整体变深，但仍然是"系统底 + 一层玻璃"，没有第二张卡片。
            .activityBackgroundTint(Color.black.opacity(0.35))
            .activitySystemActionForegroundColor(islandInk(context.state.item.tint))

        } dynamicIsland: { context in

            DynamicIsland {
                // 🔴 2026-10-28 主人：「整体内容靠下显示了，空间也大着呢，为啥要往下挤」。
                // 根因：以前**只用 `.bottom` 一个区** —— 挖孔（TrueDepth）左右那两块
                // 可画区域是空的，系统又把 bottom 放在挖孔之下，于是上半截全黑、
                // 内容全堆在下半截。
                //
                // 现在按系统设计用满三个区：
                //   · leading  = 品牌图标 + 快递公司／驿站（挖孔左侧，约 120pt，4–5 字够用）
                //   · trailing = 待取数量（挖孔右侧，窄，右对齐）
                //   · bottom   = 取件码（+ 柜位）+ 取件地址，各一整行
                // 顶部那一行被利用起来后，整岛高度跟着降下来，内容不再"沉底"。
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: context.state)
                        // 与取件码左缘对齐（系统给 leading 的左边距比 bottom 少 15pt）
                        .padding(.leading, IslandExpandedMetrics.leadingInset)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: context.state)
                        // 待取计数从贴边往左收一点
                        .padding(.trailing, IslandExpandedMetrics.trailingInset)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state)
                        .padding(.horizontal, IslandExpandedMetrics.hInset)
                        .padding(.bottom, 2)
                }
            } compactLeading: {
                IslandCompactLeading(state: context.state)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(state: context.state)
            }
            // 灵动岛外圈描边走品牌色 —— 与锁屏卡片的着色口径一致。
            // 🔴 同样走 `islandTint`：顺丰纯黑主色的描边贴着任何深色壁纸都隐形，
            //    亮化后轮廓才真正可见。
            .keylineTint(islandTint(context.state.item.tint))
        }
    }

    /// 卡片背景：品牌图标放大 + 强模糊铺满整卡，再压一层暗色 ——
    /// 这样白字在任何壁纸、任何外观下都有足够对比（老大：浅色/深色都要清晰可读）。
    /// 这一层在**玻璃下面**，视觉上仍是"一张卡"，不是第二张卡片。
    @ViewBuilder
    private func backdrop(for item: PickupActivityAttributes.Item) -> some View {
        ZStack {
            CourierLogo(company: item.displayName, size: 320,
                        showsShadow: false, usesStaticAsset: true)
                .blur(radius: 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 2026-11-23 老大选 B：压暗别太狠，让玻璃折射得出颜色。
            // 上淡下深 —— 取件码那一行需要更多对比，图标行留出玻璃的通透感。
            LinearGradient(colors: [Color.black.opacity(0.18), Color.black.opacity(0.34)],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .allowsHitTesting(false)
    }
}
