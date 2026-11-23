import AppIntents
import Foundation
import os
import UIKit
import UniformTypeIdentifiers

// MARK: - 快捷指令调用入口
//
// 产品数据流：短信 → 快捷指令自动化（触发：信息 · 信息内容 · 包含【）
//   → **本 Intent**（后台运行，不切前台）→ PickupParser 解析
//   → PickupStore 落盘 → 列表 / 桌面小组件展示。
//
// 关键设计：
//  · 静默后台执行 —— 自动化触发时不打断用户当前操作，直接写库。
//    ⚠️ `IntentModes`（含 `.background`）是 iOS 26 新增；部署目标是 iOS 17，
//       所以两个动作都用等价的 `openAppWhenRun = false`（iOS 16 起可用）。
//       语义一致：后台跑、不把 App 拉到前台。
//  · 🔴 **绝不返回 dialog / 视图**（不声明 ProvidesDialog、不返回 value）。见下节。
//  · 参数 `inputConnectionBehavior = .connectToPreviousIntentResult` —— 在快捷指令里
//    拖入本动作时会**自动接上一环的输出**（自动化中即「快捷指令输入」= 刚收到的短信），
//    省掉让用户手动去变量面板里挑「快捷指令输入」这一步。
//  · 去重由 PickupStore.ingest 负责：同「类别+凭证+地址」不重复入库。

// MARK: - 为什么这两个动作不留对话框（2026-09-21 定案）
//
// 快捷指令里每个动作卡片底部都有一个「运行时显示」开关（内部键 `ShowWhenRun`，
// 与 `OpenInApp` / `InProcess` 同属 intent 动作的参数族）。实测结论：
//
//  · App Intents **没有任何 API 能预设这个开关的默认值** —— `AppIntent` 协议的全部属性
//    （title / supportedModes / authenticationPolicy / isDiscoverable /
//     allowedExecutionTargets / parameterSummary / description）里没有对应项。
//  · 它由 Shortcuts 侧按「动作」持久化在 `WFWorkflowActionParameters.ShowWhenRun`；
//    实测新建动作时该键**根本不落盘**（重启 Shortcuts、跑一遍都不会补写），
//    也就是说没有可被 App 影响的"默认值"来源。
//  · 它控制的是"运行动作时要不要把动作的**结果**显示出来"，
//    而 Shortcuts 只在**意图有可展示结果**时才提供这个能力 ——
//    所以让动作不产出结果（不返回 dialog、不返回 value），它就没有东西可显示。
//
// 权衡：动作不再在快捷指令里回一句「已记录 XX，当前待取 N 件」。
//  · 成功反馈改由 `PickupNotifier` 的**本地通知**承担（含取件码 + 平台｜地址，
//    多条时按取件码逐条发）—— 比快捷指令的弹窗更及时、更重要。
//  · 「没识别到取件信息」这类中性提示本来也不该打扰用户：自动化触发条件是
//    「信息内容包含【」，银行/验证码短信同样命中，逐条弹窗会是纯噪音。
//  · 需要排查时看日志：`log stream --predicate 'subsystem == "com.jikezhang.codelumi"'`。

struct ParsePickupTextIntent: AppIntent {
    static var title: LocalizedStringResource { "添加到Codelumi" }

    static var description: IntentDescription {
        IntentDescription("从短信文本中提取取件码、运单号或尾号，连同取件地址写入「Codelumi」的待取件列表。配合「信息 · 信息内容 · 包含【」自动化即可自动收纳取件短信。")
    }

    /// 只支持后台执行：自动化触发时不把 App 拉到前台，快捷指令里「运行时显示」默认关闭。
    /// 🔴 部署目标 iOS 17：`IntentModes`（含 `.background`）是 iOS 26 新增，用不了；
    ///    改用等价的 `openAppWhenRun = false`（iOS 16 起可用）：后台执行、不拉起 App。
    static var openAppWhenRun: Bool { false }

    // 🔴 2026-11-11 复核：`inputOptions` / `inputConnectionBehavior` 属于
    //    `IntentParameter where Value.ValueType == String` 的初始化器，
    //    iOS 16.0 起就有（iPhoneOS27.2.sdk 的 swiftinterface 里明写
    //    `@available(macOS 13.0, iOS 16.0, …)`），部署目标 iOS 17 可以直接用。
    //    之前误以为「iOS 18 才有」—— 那是 AppEntity / FileEntity 的 iOS 18 重载。
    //    `inputConnectionBehavior = .connectToPreviousIntentResult` 让快捷指令里
    //    拖入本动作时自动接上一环输出，也允许用户点开字段从变量面板改选
    //    「输入快捷指令的信息 / 信息 / 剪贴板」；`multiline` 让长短信能换行读。
    @Parameter(title: "短信内容",
               description: "接上一环的输出，或点开字段选「快捷指令输入」/「信息」/剪贴板；自动化触发时就是刚收到的那条短信",
               inputOptions: String.IntentInputOptions(multiline: true),
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var text: String

    /// 🔴 2026-11-11 主人要求：动作卡片第二行要像系统动作那样 —— **左边是标题「输入」，
    ///    右边是可点开选择变量的槽位**（输入快捷指令的信息 / 信息 / 剪贴板）。
    ///    只靠 `@Parameter` 时 Shortcuts 会把参数渲染成一行纯文本输入框，
    ///    变量面板要用户自己摸到；`parameterSummary` 把参数变成摘要里的 token，
    ///    卡片就显示成「输入 [变量槽]」，点槽位即弹出变量面板。
    static var parameterSummary: some ParameterSummary {
        Summary("输入 \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            PickupIntentLog.note("短信内容为空，已忽略")
            return .result()
        }

        // 结果只写日志 + 走本地通知，不返回 dialog（理由见文件头）
        PickupIntentLog.report(PickupStore.shared.ingest(trimmed), source: "短信")
        return .result()
    }
}

// MARK: - 截图识别（配合快捷指令的「截屏」动作）

/// 接收一张图片，做文字识别后解析写入。
///
/// **为什么要单独一个动作**：短信进来时自动收纳已有「信息 · 包含【」那条自动化覆盖；
/// 但取件信息还散落在别处 —— 微信群里转发的取件通知、快递 App 的推送、驿站发来的
/// 聊天截图。这些都没有可监听的系统事件，用户能做的动作只有「截屏」。
/// 于是这个动作衔接快捷指令自带的「截屏」：截屏 → 本动作 → 有取件信息才写入。
///
/// 识别不出取件信息时**不写入**，只回一句中性提示 —— 用户截错图（截了个聊天记录、
/// 截了个网页）不会污染待取件列表。
struct ParsePickupImageIntent: AppIntent {
    static var title: LocalizedStringResource { "识别取件截图" }

    static var description: IntentDescription {
        IntentDescription("对传入的截图做文字识别，识别到取件码 / 运单号 / 尾号就存进「Codelumi」。配合快捷指令自带的「截屏」动作，可一键把截图里的取件信息收进待取件列表；识别不到则不写入。")
    }

    /// 只支持后台执行：截屏后静默入库，不把 App 拉到前台打断当前操作
    /// 🔴 部署目标 iOS 17：`IntentModes`（含 `.background`）是 iOS 26 新增，用不了；
    ///    改用等价的 `openAppWhenRun = false`（iOS 16 起可用）：后台执行、不拉起 App。
    static var openAppWhenRun: Bool { false }

    // ⚠️ 2026-11-11：`supportedContentTypes` 只出现在 `FileEntity` 的 iOS 18 重载上，
    //    `IntentFile` 参数没有这个初始化参数；截图动作的输出本来就是 IntentFile，
    //    类型本身已经把内容限定成文件。这里只补 `inputConnectionBehavior`，
    //    效果和文本动作一致：接上一环「截屏」的输出，用户也能改选别的图片变量。
    @Parameter(title: "截图",
               description: "选「截屏」动作的输出，或任意含取件信息的图片",
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$image)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // IntentFile.data 是非可选 Data：传进来必定有字节，不成立才是异常情况
        guard let picture = UIImage(data: image.data) else {
            PickupIntentLog.note("截图没解码成图片，已忽略")
            return .result()
        }

        // Vision 是同步 API，放到后台线程跑，避免卡住手势/自动化流程
        let text = await Task.detached(priority: .userInitiated) {
            PickupOCR.recognize(picture)
        }.value

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            PickupIntentLog.note("截图里没识别到文字，已忽略")
            return .result()
        }

        // 走 OCR 入口：截图里的换行是视觉折行，且一张图里可能有好几条
        PickupIntentLog.report(PickupStore.shared.ingestOCR(text), source: "截图")
        return .result()
    }
}

// MARK: - 动作诊断日志（不面向用户）
//
// 动作不再返回对话框，写入结果改由本地通知呈现；解析失败 / 重复这类
// 「不需要打扰用户」的情况只写系统日志，方便排查时回看：
//   log stream --predicate 'subsystem == "com.jikezhang.codelumi"'

enum PickupIntentLog {
    private static let logger = Logger(subsystem: "com.jikezhang.codelumi", category: "intent")

    static func note(_ message: String) {
        logger.log("\(message, privacy: .public)")
    }

    static func report(_ outcome: IngestOutcome, source: String) {
        guard !outcome.isEmpty else {
            note("[\(source)] 没识别到取件信息，未写入")
            return
        }
        note("[\(source)] 新增 \(outcome.added.count) 条（同码旧件自动完成 \(outcome.completed.count) 条），待取 \(outcome.pendingCount) 件")
    }
}

// MARK: - 让动作出现在快捷指令 App 的动作库里

struct CodelumiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ParsePickupTextIntent(),
            phrases: [
                "用 \(.applicationName) 添加取件信息",
                "把短信存到 \(.applicationName)",
                "让 \(.applicationName) 记下这个取件码",
            ],
            shortTitle: "添加到Codelumi",
            systemImageName: "shippingbox.fill"
        )
    }
}
