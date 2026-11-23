import Foundation
import NaturalLanguage

// MARK: ============================================================================
// 快递短信分类器（Create ML 训练，端侧 Core ML 推理）2026-11-05
//
// 目的：**守门员**，不是主力。现在入库靠「包含【 + 关键词」两道闸门，
// 银行/验证码短信含【也会触发一次解析；分类器用来判断"这条到底像不像快递短信"。
//
// 训练：Create ML（Xcode 自带框架，无需装软件）训的 `MLTextClassifier`，
// 语料用仓库的 514 段：能被现有解析器解析的当正样本，其余当负样本。
// 留出 20% 测试集的结果：真快递保留 39/40，非快递挡掉 67/67。
//
// 🔴 **当前只记日志、不拦截**。快递短信代价极高（漏一条就少一个码），
//    模型在测试集里仍误杀 1 条；先观察真实短信上的表现，再决定是否启用过滤。
//
// 🔴 纯本地推理：模型随 App 打包，不联网、不上传任何文本。
// ============================================================================

enum PickupClassifier {
    enum Verdict: String {
        case pickup
        case other
        case unavailable
    }

    /// 懒加载：`NLModel` 首次加载有成本，别在启动路径上做
    private static let model: NLModel? = {
        guard let url = Bundle.main.url(forResource: "CodelumiPickup", withExtension: "mlmodelc") else {
            return nil
        }
        return try? NLModel(contentsOf: url)
    }()

    static var isAvailable: Bool { model != nil }

    /// 判定文本像不像快递短信；模型缺失时返回 `.unavailable`
    static func classify(_ text: String) -> (verdict: Verdict, confidence: Double) {
        guard let model else { return (.unavailable, 0) }
        let label = model.predictedLabel(for: text) ?? "other"
        let confidence = model.predictedLabelHypotheses(for: text, maximumCount: 1)
            .first?.value ?? 0
        return (Verdict(rawValue: label) ?? .other, confidence)
    }
}
