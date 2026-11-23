import AVFoundation
import SwiftUI
import UIKit

// MARK: ============================================================================
// 拍照识别（2026-11-16 主人）
//
// 主人原话：「扫码添加就不要了，软件本身不联网，扫码添加根本就无法使用，到时候
// 可以拍照识别添加，这样就和从相册选择图片是一样的原理了」。
//
// 为什么删掉扫码：二维码里那串内容通常是一个跳转链接（需要联网才能兑换成取件信息），
// 而 Codelumi 刻意不联网 —— 扫出来的东西在离线状态下没有任何价值，入口留着只会让人
// 白试一次。改成「拍一张照片 → 端侧 OCR → 同一套解析」之后，拍照与相册选图
// 走的是**完全同一条链路**（`PickupOCR` → `PickupParser.parseAll(ocrSource:)`），
// 一套逻辑两种图片来源。
//
// 相机实现用 AVFoundation 而不是 `UIImagePickerController`：后者的系统相机页
// 无法定制，快门、提示、降级界面都得跟 App 自己的视觉走；而且它一旦弹出就
// 盖住整个 sheet，取景时看不到「这张照片会识别成什么」的说明。
//
// ⚠️ 必须在 Info.plist 提供 NSCameraUsageDescription，否则进程会被系统直接终止。
// ============================================================================

/// 相机能力的可用性三态 —— 用于在模拟器 / 拒绝授权时给出正确降级界面，
/// 而不是丢给用户一块黑屏。
enum CameraAvailability {
    case ready
    case denied
    case unsupported

    static func current() -> CameraAvailability {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return .ready          // 交给系统在首次进入时弹权限
        default: return .denied
        }
    }
}

/// 实时取景 + 单张拍照。快门由 SwiftUI 侧驱动（`captureToken` 变化即拍一张），
/// 这样快门按钮能长成 App 自己的样子，而不用把整套 UI 搬进 UIKit。
struct CameraPhotoView: UIViewControllerRepresentable {
    /// 每次「按快门」父视图换一个新值，这里据此触发一次拍摄
    var captureToken: UUID
    var onCaptured: (UIImage) -> Void
    var onFailed: () -> Void

    func makeUIViewController(context: Context) -> CameraPhotoController {
        let controller = CameraPhotoController()
        controller.onCaptured = onCaptured
        controller.onFailed = onFailed
        // 🔴 首帧的 token 是「初始值」，不是用户按了快门。不预置的话
        //    `updateUIViewController` 第一次调用就会误拍一张 —— 真机上表现为
        //    刚进页面就自动跳到识别结果，用户还没来得及按快门。
        controller.handledToken = captureToken
        return controller
    }

    func updateUIViewController(_ controller: CameraPhotoController, context: Context) {
        controller.onCaptured = onCaptured
        controller.onFailed = onFailed
        controller.captureIfNeeded(token: captureToken)
    }
}

final class CameraPhotoController: UIViewController, AVCapturePhotoCaptureDelegate {

    var onCaptured: ((UIImage) -> Void)?
    var onFailed: (() -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    /// 上一次已经响应过的快门 token —— 只认变化，避免每次 body 求值都拍一张。
    /// `makeUIViewController` 会把它预置成首帧值，因此初次进页面不会自动拍。
    var handledToken: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 没有摄像头设备时**不要**去要权限：系统弹窗会盖住整个取景页，
        // 而用户点了「允许」也照样拍不了（模拟器就是这种情况）。
        guard AVCaptureDevice.default(for: .video) != nil else { return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.startSession() }
            }
        } else {
            startSession()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 预览层不参与 Auto Layout，尺寸靠这里跟随容器
        previewLayer?.frame = view.bounds
    }

    // MARK: 会话装配

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // 竖屏拍照：不设这一项，拍出来的 buffer 是横向的，
        // OCR 拿到一张躺倒的照片，识别率会明显掉（Vision 不做自动旋转）。
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        isConfigured = true
    }

    private func startSession() {
        configureIfNeeded()
        guard isConfigured, !session.isRunning else { return }
        // startRunning 是同步阻塞调用，放主线程会卡住进入动画
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    // MARK: 快门

    func captureIfNeeded(token: UUID) {
        guard token != handledToken else { return }
        handledToken = token
        capture()
    }

    private func capture() {
        guard isConfigured else { onFailed?(); return }
        // 刚进页面就按快门时 session 可能还在起，等它跑起来再拍一次
        guard session.isRunning else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.shoot() }
            }
            return
        }
        shoot()
    }

    private func shoot() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off            // 拍纸面/屏幕用闪光只会反光糊字
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.onFailed?() }
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let upright = Self.flatten(image)
        DispatchQueue.main.async { self.onCaptured?(upright) }
    }

    /// 把 `UIImage` 压平到 `.up` 方向。
    ///
    /// 为什么必须做：`PickupOCR` 走的是 `image.cgImage` + `VNImageRequestHandler`，
    /// 这条路**不读** `imageOrientation` —— 带旋转标记的图在 Vision 眼里就是躺倒的，
    /// 竖排文字会整段识别不出来，且不报错。
    private static func flatten(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
