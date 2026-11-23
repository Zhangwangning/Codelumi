import SwiftUI
import MessageUI

// MARK: ============================================================================
// 反馈邮件（2026-10-31 主人：反馈时自动把日志打包发过来）
//
// 为什么要从 `mailto:` 换成 `MFMailComposeViewController`：
//   `mailto:` 只能带正文，**不能带附件**。诊断日志动辄几十 KB，塞进正文既难读
//   又可能被邮箱截断。系统邮件编辑器的 `addAttachmentData` 才是正路。
//
// 用户不装邮件 App 时（`canSendMail == false`）不硬弹，走原来的复制邮箱兜底。
// ============================================================================

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    /// 附件（文件名, 数据）。为 nil 时只发正文。
    let attachment: (name: String, data: Data)?
    /// 用户取消或发送完成
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackModel.mail])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)

        if let attachment {
            controller.addAttachmentData(attachment.data,
                                         mimeType: "text/plain",
                                         fileName: attachment.name)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            switch result {
            case .sent:        DiagnosticsLog.record("feedback", "sent")
            case .cancelled:   DiagnosticsLog.record("feedback", "cancelled")
            case .saved:       DiagnosticsLog.record("feedback", "saved")
            case .failed:      DiagnosticsLog.record("feedback", "failed")
            @unknown default:  DiagnosticsLog.record("feedback", "unknown")
            }
            controller.dismiss(animated: true) { self.onFinish() }
        }
    }
}
