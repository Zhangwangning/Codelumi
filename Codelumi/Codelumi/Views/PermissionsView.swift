import SwiftUI
import UIKit

// MARK: ============================================================================
// 使用权限（2026-11-22 主人）
//
// 原话：「在关于Codelumi页面中添加一个使用权限，里面列举App使用了的权限，加个开关，
// 用户可以关闭某个权限的开关，但要提醒用户关闭时，因为我们尽量不使用权限的，
// 非必要不使用，一般使用的权限还是很重要的，但是如果是互联网服务的权限，关闭就关闭吧」
//
// 三条设计后果：
//   1. **只列真的用到的**，不为了"看起来完整"去列通讯录、健康、蓝牙这类根本没申请的权限。
//   2. **重要权限关掉要问一句**（`warning` 非空 → 弹确认）；互联网类（iCloud / 网络）
//      `warning` 为 nil，关就直接关 —— 它不影响收码，只是少一次同步。
//   3. 这些开关控制的是「Codelumi 用不用这项能力」，**撤销系统授权只能去系统设置** ——
//      页面底部给一个直跳入口，不假装 App 能替用户撤销。
// ============================================================================

/// App 用到的权限（一项一行）。
enum AppPermission: String, CaseIterable, Identifiable {
    case notifications
    case camera
    case photos
    case location
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: return "通知"
        case .camera:        return "相机"
        case .photos:        return "相册"
        case .location:      return "定位"
        case .cloud:         return "iCloud 与网络"
        }
    }

    /// 一句话说清「用在哪」—— 不写「为了给您更好的体验」这种空话。
    var scope: String {
        switch self {
        case .notifications: return "新取件、超时未取、每日固定提醒"
        case .camera:        return "拍照识别取件码"
        case .photos:        return "从相册选图识别取件码"
        case .location:      return "到驿站时提醒"
        case .cloud:         return "多设备同步、购买与反馈"
        }
    }

    var symbol: String {
        switch self {
        case .notifications: return "bell.badge.fill"
        case .camera:        return "camera.fill"
        case .photos:        return "photo.on.rectangle.angled"
        case .location:      return "location.fill"
        case .cloud:         return "icloud.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notifications: return AppTheme.pendingTint
        case .camera:        return AppTheme.sky
        case .photos:        return AppTheme.violet
        case .location:      return AppTheme.doneTint
        case .cloud:         return AppTheme.indigo
        }
    }

    /// 关闭时的后果。`nil` = 不劝（互联网类）。
    var warning: String? {
        switch self {
        case .notifications: return "关掉后，新取件、超时未取都不会提醒你。"
        case .camera:        return "关掉后不能拍照识别，只能用相册里的图。"
        case .photos:        return "关掉后不能从相册选图识别。"
        case .location:      return "关掉后走到驿站不会提醒你。"
        case .cloud:         return nil
        }
    }
}

/// 权限开关的真值（App Group）。
///
/// 2026-11-22 语音录入整块删除后，只剩 `.cloud` 要碰主线程单例，其余都读 App Group 里的键。
enum PermGate {
    private static var store: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    private static func key(_ permission: AppPermission) -> String {
        "codelumi.perm.\(permission.rawValue)"
    }

    /// 不走主线程的轻量查询：只覆盖存在 App Group 里的那几项。
    ///
    /// 给「非 UI 上下文」用（通知器在后台队列里判断、列表菜单构建时判断）。
    /// `.cloud` 要碰主线程单例，必须用 `isOn`。
    static func storedIsOn(_ permission: AppPermission) -> Bool {
        store.object(forKey: key(permission)) as? Bool ?? true
    }

    @MainActor
    static func isOn(_ permission: AppPermission) -> Bool {
        switch permission {
        case .cloud:
            return ICloudSyncController.shared.isEnabled
        default:
            return storedIsOn(permission)
        }
    }

    @MainActor
    static func set(_ permission: AppPermission, _ on: Bool) {
        switch permission {
        case .cloud:
            ICloudSyncController.shared.setEnabled(on)
        default:
            store.set(on, forKey: key(permission))
        }
        // 通知关掉要立刻清场：只写标记的话，昨天排好的提醒还会照常响
        if permission == .notifications, !on {
            PickupNotifier.suspendAll()
        }
        DiagnosticsLog.record("permission", "\(permission.rawValue)=\(on)")
    }
}

// MARK: - 页面

struct PermissionsView: View {
    @State private var values: [AppPermission: Bool] = [:]
    /// 待确认关闭的那一项（非 nil 时弹窗）
    @State private var pendingOff: AppPermission?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                intro

                VStack(spacing: 0) {
                    ForEach(Array(AppPermission.allCases.enumerated()),
                            id: \.element) { index, item in
                        if index > 0 { SettingsDivider() }
                        row(item)
                    }
                }
                .settingsCard()

                systemSettingsButton

                PageFooter()
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("使用权限")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadValues)
        .alert(alertTitle, isPresented: alertBinding) {
            Button("取消", role: .cancel) {
                if let item = pendingOff { values[item] = true }
                pendingOff = nil
            }
            Button("仍要关闭", role: .destructive) {
                if let item = pendingOff {
                    values[item] = false
                    PermGate.set(item, false)
                }
                pendingOff = nil
            }
        } message: {
            Text(pendingOff?.warning ?? "")
        }
    }

    private var intro: some View {
        Text("能不用就不用。关掉某项只少一个功能，取件码本身不受影响。")
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ item: AppPermission) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: item.symbol, tint: item.tint, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.L)
                    .font(AppTheme.TypeScale.body)
                Text(item.scope.L)
                    .font(AppTheme.TypeScale.badge)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: binding(for: item))
                .labelsHidden()
                .tint(AppTheme.accent)
                .accessibilityLabel(item.title.L)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var systemSettingsButton: some View {
        VStack(spacing: 8) {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                SettingsRow(symbol: "gearshape.fill",
                            title: "打开系统设置",
                            showsChevron: false,
                            tint: .secondary)
            }
            .buttonStyle(.plain)
            .settingsCard()

            Text("撤销系统授权只能在系统设置里做，App 不能替你做。")
                .font(AppTheme.TypeScale.badge)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 绑定与弹窗

    private func binding(for item: AppPermission) -> Binding<Bool> {
        Binding(
            get: { values[item] ?? true },
            set: { on in
                if on {
                    values[item] = true
                    PermGate.set(item, true)
                } else if item.warning != nil {
                    // 重要权限：先关视觉、再问；用户点「取消」由弹窗把视觉复原。
                    values[item] = false
                    pendingOff = item
                } else {
                    // 互联网类：关就关，不劝
                    values[item] = false
                    PermGate.set(item, false)
                }
            }
        )
    }

    private var alertTitle: String {
        guard let item = pendingOff else { return "" }
        return "关闭「\(item.title.L)」？"
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { pendingOff != nil },
                set: { if !$0 { pendingOff = nil } })
    }

    /// 进页面读一次真值。
    ///
    /// 🔴 不能直接用 `PermGate.isOn` 当 Binding 的 get：它读的是 UserDefaults，
    ///    不是可观察的 —— 开关点了不刷新。所以先灌进 `@State`，由 SwiftUI 管。
    private func loadValues() {
        for item in AppPermission.allCases {
            values[item] = PermGate.isOn(item)
        }
    }
}
