import SwiftUI
import OSLog

// MARK: ============================================================================
// App 图标（2026-11-01 主人）
//
// 版式照**快递公司页**那一套：白色卡片里自适应网格，格子 = 54pt 圆角方块。
// 2026-11-12 主人：图标下面**不要名字**，只留图形（名字移到无障碍标签里）。
// 换图标是系统级动作（`UIApplication.setAlternateIconName`），选中后桌面、设置、
// 多任务、通知里的图标会一起变；灵动岛与关于页读同一份选择。
// ============================================================================

struct AppIconSettingsView: View {
    @State private var selected = AppIconStore.current
    @State private var showError = false

    /// 与快递公司页同口径：自适应列，最小 72pt（54 方块 + 左右留白）
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppIconChoice.allCases) { choice in
                        cell(choice)
                    }
                }
                .padding(14)
                .settingsCard()

                // 当前选中（2026-11-21 主人要的「目录号」）：显示 DZYTB 编号 + 名称。
                // 12/13/15 都是深色底，光看格子分不清；有这么一行，"选的是哪一张"可直接核对。
                HStack(spacing: 5) {
                    Text(selected.catalogID)
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(selected.title)
                        .font(AppTheme.TypeScale.note)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                // 🔴 2026-11-22 主人：删掉「更换后，桌面、App 资源库、多任务和通知里的
                //    图标会一起改变。」—— 换图标当然是全局换，这行是废话。
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("自定义 App 图标")
        .navigationBarTitleDisplayMode(.inline)
        // 截图/验收脚手架：命令行点不了格子，`APP_ICON=icon05` 强制切换。
        .onAppear {
            guard let raw = ProcessInfo.processInfo.environment["APP_ICON"],
                  let choice = AppIconChoice(rawValue: raw) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                AppIconStore.store(choice)
                UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
                    Logger(subsystem: "com.jikezhang.allude", category: "appIcon")
                        .notice("scaffold=\(choice.rawValue, privacy: .public) error=\(error.map { "\($0)" } ?? "none", privacy: .public)")
                    DispatchQueue.main.async {
                        if error == nil {
                            selected = choice
                            Task { await PickupActivityController.refreshForAppIconChange() }
                        } else {
                            // 🔴 与 apply() 一致：失败必须回滚已经写进共享状态的偏好，
                            //    否则存储里留着「用户其实没换成的那个图标」，
                            //    下次冷启动 selected 会读回它、界面显示一个假选中态
                            //    （2026-11-21 在模拟器上撞到：明明报错，格子却是蓝框）。
                            AppIconStore.store(selected)
                        }
                    }
                }
            }
        }
        .alert("更换图标失败", isPresented: $showError) {
            Button("好", role: .cancel) {}
        } message: {
            // 🔴 2026-11-21：模拟器**永远**换不了图标，不是"稍后再试"能等到的。
            // 系统要靠 CoreServicesUI 的 upcall bundle 弹「正在更改图标」确认，
            // 而模拟器里这个 bundle 加载失败（日志：NSPOSIXErrorDomain Code=5
            // "couldn't load upcall bundle principal class"），重启模拟器也不会好；
            // 真机则正常（同日实测 iPhone 16 Pro 换成第 14 套并生效）。
            // 所以这里按环境分开说，别让开发者对着「稍后再试」白等。
            #if targetEnvironment(simulator)
            Text("模拟器不支持更换主屏幕图标，请在真机上试。这是模拟器的限制，与 App 本身无关。")
            #else
            Text("系统暂时不能更换图标，请稍后再试。")
            #endif
        }
    }

    /// 与快递公司页一致：分类图标 + 标题 + 数量 + 说明
    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "app.badge.fill")
                .font(AppTheme.TypeScale.badge)
                .foregroundStyle(AppTheme.accent)
            Text("可选图标")
                .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
            Text("\(AppIconChoice.allCases.count)")
                .font(AppTheme.TypeScale.note)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private func cell(_ choice: AppIconChoice) -> some View {
        let isOn = choice == selected

        return Button {
            apply(choice)
        } label: {
            VStack(spacing: 0) {
                Image(choice.assetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 54, height: 54)
                    .clipShape(.rect(cornerRadius: 54 * 0.29, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 54 * 0.29, style: .continuous)
                            .strokeBorder(AppTheme.accent, lineWidth: isOn ? 2 : 0)
                            .padding(-3)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.accent)
                                .background(Circle().fill(.white).padding(1.5))
                                .offset(x: 4, y: 4)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.catalogID) \(choice.title)图标")
    }

    private func apply(_ choice: AppIconChoice) {
        guard choice != selected else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            showError = true
            return
        }

        // 先写共享状态：灵动岛/关于页立刻跟着变；系统图标随后换。
        AppIconStore.store(choice)
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            DispatchQueue.main.async {
                if error != nil {
                    showError = true
                    AppIconStore.store(selected)
                } else {
                    Logger(subsystem: "com.jikezhang.allude", category: "appIcon")
                        .notice("changed to \(choice.rawValue, privacy: .public)")
                    withAnimation(.snappy(duration: 0.2)) { selected = choice }
                    // 灵动岛 / 锁屏是扩展进程画的，只有 ContentState 变了才会重绘 ——
                    // 把新选择推进现有活动，岛内图标当场就跟着换（2026-11-15）。
                    Task { await PickupActivityController.refreshForAppIconChange() }
                }
            }
        }
    }
}
