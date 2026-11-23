import AppKit

// ============================================================================
// 入口：菜单栏常驻 + 独立主窗口（两者都要）
//
// 菜单栏面板 = 随手签一张；主窗口 = 批量 / 验签 / 台账
// 编译：xcrun swiftc -swift-version 5 Src/*.swift -o build/发码.app/Contents/MacOS/发码
// 注意：手动 main.swift 入口下不要标 @MainActor（Swift 5 模式会报跨 actor 调用）
// ============================================================================

// MARK: - 诊断日志
// `open` 启动路径不继承终端环境变量，所以开关同时支持「环境变量」与「落盘开关文件」：
//   touch /tmp/cc-issuer-debug.on   → 打开日志（写到 /tmp/cc-issuer-debug.log）
//   rm    /tmp/cc-issuer-debug.on   → 关闭
let ccDebugON: Bool = {
    if ProcessInfo.processInfo.environment["CC_ISSUER_DEBUG"] == "1" { return true }
    return FileManager.default.fileExists(atPath: "/tmp/cc-issuer-debug.on")
}()

func ccLog(_ message: String) {
    guard ccDebugON else { return }
    let line = "[codelumi-issuer] \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    let file = "/tmp/cc-issuer-debug.log"
    if let handle = FileHandle(forWritingAtPath: file) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(toFile: file, atomically: true, encoding: .utf8)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panelController: SignPanelController!
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ccLog("didFinishLaunching 进入 · policy=\(NSApp.activationPolicy().rawValue) "
              + "bundle=\(Bundle.main.bundlePath)")
        setupStatusItem()
        setupPopover()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(openMainWindow),
                                               name: .codelumiOpenMainWindow,
                                               object: nil)
        // 延后到 run loop 下一轮再建窗：`open` 启动路径下，此刻立即 showWindow
        // 会因前台权限尚未就绪而窗口不上屏（实测直接执行二进制却正常）
        DispatchQueue.main.async { [weak self] in
            ccLog("async 回调触发，准备建窗")
            self?.openMainWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ccLog("didBecomeActive · windows=\(NSApp.windows.count) "
              + "visible=\(NSApp.windows.filter { $0.isVisible }.count)")
        // 兜底：若因前台激活时序问题窗口没上屏，这里补救一次
        if let window = mainWindowController?.window, !window.isVisible {
            ccLog("兜底补救：窗口存在但不可见，重新 orderFront")
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ccLog("shouldHandleReopen · hasVisibleWindows=\(flag)")
        openMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false        // 关掉窗口后仍留在菜单栏
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "signature", accessibilityDescription: "Codelumi 发码")
            image?.isTemplate = true
            button.image = image
            button.image?.size = NSSize(width: 17, height: 17)
            button.toolTip = "Codelumi · 发码工具"
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusButtonClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: "o")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil          // 用完即摘，避免左键也弹菜单
    }

    // MARK: 弹出面板

    private func setupPopover() {
        panelController = SignPanelController()
        popover.contentViewController = panelController
        popover.behavior = .transient
        popover.animates = false
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: 主窗口

    @objc func openMainWindow() {
        if mainWindowController == nil {
            ccLog("openMainWindow：首次创建 MainWindowController")
            mainWindowController = MainWindowController()
        }
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)

        // 诊断脚手架（见文件头 ccDebugON）：打印窗口真实状态，用于排查"进程活着但没窗口"
        if let window = mainWindowController?.window {
            ccLog("openMainWindow 返回 · frame=\(window.frame) visible=\(window.isVisible) "
                  + "isMini=\(window.isMiniaturized) alpha=\(window.alphaValue) "
                  + "screen=\(String(describing: window.screen?.frame)) "
                  + "windows=\(NSApp.windows.count) onscreen=\(NSApp.windows.filter { $0.isVisible }.count)")
        } else {
            ccLog("openMainWindow 返回 · mainWindowController.window 为 nil")
        }
    }
}

// MARK: - 启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)       // 有 Dock 图标 + 菜单栏图标

// 主菜单：必须在 run() 之前装好。
// 缺了它，AppKit 只给一个「应用名」顶级菜单 —— 没有「编辑」菜单，
// 于是 ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z 全部无人响应（快捷键靠主菜单分发），
// 且 NSTextView 的右键菜单会退回英文。详见 Src/MainMenu.swift。
MainMenu.install()
ccLog("主菜单已安装：\n\(MainMenu.describe())")

// 外观覆盖（截图验证脚手架，用于在两种外观下核对 UI）：
//   echo light > /tmp/cc-issuer-appearance   → 强制浅色
//   echo dark  > /tmp/cc-issuer-appearance   → 强制深色
//   rm          /tmp/cc-issuer-appearance    → 跟随系统
if let raw = try? String(contentsOfFile: "/tmp/cc-issuer-appearance", encoding: .utf8) {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "light": app.appearance = NSAppearance(named: .aqua)
    case "dark":  app.appearance = NSAppearance(named: .darkAqua)
    default: break
    }
}

ccLog("即将进入 run loop · policy=\(app.activationPolicy().rawValue) "
      + "pid=\(ProcessInfo.processInfo.processIdentifier)")
app.run()
