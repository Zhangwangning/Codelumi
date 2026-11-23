import AppKit

// ============================================================================
// 主菜单（Application Main Menu）
//
// 🔴 为什么必须有这个文件
//
// 纯代码（无 nib）的 AppKit 程序如果不设 `NSApp.mainMenu`，系统只会给一个
// 「应用名」顶级菜单 —— **没有「编辑」菜单**（./verify 里可复跑实测）。
// 而 AppKit 的键盘快捷键**是由主菜单的 keyEquivalent 分发的**：
//   ⌘V / ⌘C / ⌘X / ⌘A / ⌘Z 这些并没有写死在 NSTextView 里，
//   它们靠「编辑」菜单里对应的 NSMenuItem 进入响应链。
// 没有菜单项 ⇒ 快捷键一律失效。表现就是主人遇到的：
//   「从短信里复制了 UUID，在软件里按 ⌘V 没反应」。
//
// 🔴 同时它也解决「拷贝是英文的」
//
// 无 nib 时系统给的默认菜单标题是**英文硬编码**，不随系统语言本地化；
// 而 NSTextView 的**右键上下文菜单**由 AppKit 提供，按 App 的本地化资源解析 ——
// 本工程 Info.plist 原先既没有 `CFBundleDevelopmentRegion`，
// bundle 里也没有任何 `.lproj`（`Bundle.main.localizations == []`），
// 于是右键菜单一直显示 Cut / Copy / Paste / Paste and Match Style。
// 修法分两处：① 本文件硬编码中文菜单标题；② build.sh 补本地化声明
// 与 `zh-Hans.lproj`，让**系统提供**的那部分 UI 也走中文。
//
// 约定（很重要）：所有菜单项的 **target 一律留 nil** —— 走响应链，谁在焦点上谁处理。
//   NSTextView / field editor 自己实现了 cut: / copy: / paste: / selectAll: ...
//   一旦把 target 钉到某个控制器，焦点在输入框时菜单项就会被错误地指向别处。
//   唯一例外是「应用菜单」里那几个 NSApplication 自己的动作（关于/隐藏/退出），
//   它们不依赖焦点，直接 target = NSApp 更稳。
// ============================================================================

enum MainMenu {

    /// 安装主菜单。必须在 `app.run()` 之前调用
    /// （`finishLaunching` 会把第一个菜单项的标题替换成 CFBundleName）。
    static func install() {
        let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "发码"

        let main = NSMenu(title: "主菜单")
        main.addItem(makeAppMenu(appName: appName))
        main.addItem(makeEditMenu())
        main.addItem(makeWindowMenu())
        NSApp.mainMenu = main
    }

    /// 把当前主菜单摊平成文本（含快捷键与 action），用于验证器审计与真机诊断日志。
    /// `CC_ISSUER_DEBUG=1` 启动时会被写进 /tmp/cc-issuer-debug.log。
    static func describe() -> String {
        var lines: [String] = []
        guard let main = NSApp.mainMenu else { return "(NSApp.mainMenu 为 nil —— 快捷键与中文菜单都没生效)" }
        for item in main.items {
            lines.append("· [\(item.title)]")
            guard let sub = item.submenu else { continue }
            for child in sub.items {
                if child.isSeparatorItem { lines.append("    ---"); continue }
                let key = child.keyEquivalent.isEmpty ? "" : "  ⌘\(child.keyEquivalent)"
                let action = child.action.map { NSStringFromSelector($0) } ?? "(无 action)"
                lines.append("    \(child.title)\(key) → \(action)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 应用菜单

    private static func makeAppMenu(appName: String) -> NSMenuItem {
        // ⚠️ 必须用 `NSMenuItem(title:action:keyEquivalent:)` 显式给 title。
        //    无参的 `NSMenuItem()` 构造出来的项 title 是 **"NSMenuItem"**（类名，实测），
        //    不是空串；再挂 submenu 也救不回来，菜单栏会字面显示「NSMenuItem」。
        let item = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: appName)

        menu.addItem(withTitle: "关于「Codelumi 发码」",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "").target = NSApp
        menu.addItem(.separator())

        // 「服务」子菜单：系统规定它必须挂在应用菜单下，否则 App 的右键服务菜单是空的
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let services = NSMenu(title: "服务")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services

        menu.addItem(.separator())
        menu.addItem(withTitle: "隐藏\(appName)",
                     action: #selector(NSApplication.hide(_:)),
                     keyEquivalent: "h").target = NSApp

        let hideOthers = menu.addItem(withTitle: "隐藏其他",
                                      action: #selector(NSApplication.hideOtherApplications(_:)),
                                      keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp

        menu.addItem(withTitle: "全部显示",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "").target = NSApp

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出\(appName)",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q").target = NSApp

        item.submenu = menu
        return item
    }

    // MARK: - 编辑菜单（快捷键的分发源，缺它则 ⌘C/⌘V/⌘X/⌘A/⌘Z 全失效）

    private static func makeEditMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "编辑")

        // ⚠️ action 用 `NSSelectorFromString` 而不是 `#selector`，两个都是硬需求：
        //    · `undo:` / `redo:` 定义在 NSUndoManager 上，Swift 取不到静态 selector；
        //    · `copy:` 与 NSObject 的 `copy()` 同名，`#selector` 会命歧义。
        //    这些名字是 AppKit 的公开契约，Interface Builder 的 nib 里同样以字符串存储。
        func add(_ title: String,
                 _ actionName: String,
                 _ key: String,
                 _ modifiers: NSEvent.ModifierFlags = [.command]) {
            let entry = menu.addItem(withTitle: title,
                                     action: NSSelectorFromString(actionName),
                                     keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
            // target 保持 nil：交给响应链
        }

        add("撤销", "undo:", "z")
        // 「重做」的 keyEquivalent 用**大写 Z**（Apple 约定：大写字母 = 隐含 Shift），
        // 同时显式给 mask。实测只写 "z" + mask 时，构造出来的 ⇧⌘Z 事件匹配不上这一项
        // —— 因为 `charactersIgnoringModifiers` 的定义是「忽略**除 Shift 外**的修饰键」，
        //    ⇧⌘Z 拿到的是 "Z" 而不是 "z"，用 "z" 作 keyEquivalent 就比不中。
        add("重做", "redo:", "Z", [.command, .shift])
        menu.addItem(.separator())
        add("剪切", "cut:", "x")
        add("拷贝", "copy:", "c")
        add("粘贴", "paste:", "v")
        // ⚠️ action 必须是 `pasteAsPlainText:`，不是 `pasteAndMatchStyle:` ——
        //    实测 NSTextView **不响应** `pasteAndMatchStyle:`（`responds(to:)` 为 false），
        //    挂了它那一项会永远是灰的。系统自己的右键菜单用的也是 `pasteAsPlainText:`。
        //    对 isRichText=false 的输入框，这条等于「粘成纯文本」，
        //    正好去掉从聊天记录整段复制带来的富文本样式。
        add("粘贴并匹配样式", "pasteAsPlainText:", "v", [.command, .option, .shift])
        add("删除", "delete:", "")
        menu.addItem(.separator())
        add("全选", "selectAll:", "a")

        item.submenu = menu
        return item
    }

    // MARK: - 窗口菜单

    private static func makeWindowMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "窗口")

        // 本 App 不处理文档，按 HIG 可以省略「文件」菜单；
        // 但 ⌘W 关窗是 Mac 用户的肌肉记忆，所以把它放在窗口菜单首项（而非另起「文件」菜单）。
        menu.addItem(withTitle: "关闭窗口",
                     action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")
        menu.addItem(withTitle: "最小化",
                     action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(withTitle: "缩放",
                     action: #selector(NSWindow.performZoom(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "前置全部窗口",
                     action: #selector(NSApplication.arrangeInFront(_:)),
                     keyEquivalent: "")

        // 设给 NSApp 之后，系统会自动在菜单末尾追加打开的窗口列表（可直接跳窗口）
        NSApp.windowsMenu = menu

        item.submenu = menu
        return item
    }
}
