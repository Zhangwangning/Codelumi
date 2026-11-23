import SwiftUI
import UserNotifications
import CoreLocation

// MARK: ============================================================================
// 通知提醒（我的 › 设置 › 二级页）
//
// 回答两个问题：
//   1. **东西来了要说一声** —— 入库通知，开关一拨立即生效；
//   2. **东西放久了要催一下** —— 取件提醒，分两类：
//      · **定期**：每天固定时间看一眼还有几件没取（与单条记录无关）；
//      · **不定期**：某条入库 N 小时还没取，单独催一次（与单条记录绑定）。
//
// ⚠️ 全页沿用工程口径：`ObservableObject` + `@StateObject`，不用 `@State` 宏。
// ============================================================================

final class ReminderSettingsModel: ObservableObject {
    /// 入库通知开关（App 内）
    @Published var isEnabled = PickupNotifier.isEnabled
    /// 系统通知权限。与 App 内开关可能不一致，分开显示（静默失效的经典坑）。
    @Published var authStatus: UNAuthorizationStatus = .notDetermined

    @Published var dailyEnabled = PickupNotifier.isDailyReminderEnabled
    /// DatePicker 只吃 `Date` —— 用「今天」垫底、只取时分的桥接值。
    @Published var dailyTime: Date
    @Published var pendingEnabled = PickupNotifier.isPendingReminderEnabled
    @Published var pendingHours = PickupNotifier.pendingReminderHours
    /// 重复提醒（2026-11-16 新增）：全局一条按间隔催，全部取完自动停
    @Published var repeatEnabled = PickupNotifier.isRepeatReminderEnabled
    @Published var repeatHours = PickupNotifier.repeatReminderHours
    /// 到达提醒（实验室 + Codelumi Pro）
    @Published var arrivalEnabled = StationLocationService.isArrivalReminderEnabled
    /// 系统定位权限：界面要如实显示，避免「开关开着但系统没给权限」静默失效
    @Published var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    init() {
        dailyTime = Self.bridge(hour: PickupNotifier.dailyReminderHour,
                                minute: PickupNotifier.dailyReminderMinute)
    }

    private static func bridge(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    func refresh() {
        isEnabled = PickupNotifier.isEnabled
        dailyEnabled = PickupNotifier.isDailyReminderEnabled
        pendingEnabled = PickupNotifier.isPendingReminderEnabled
        // 权益降级后界面必须落回关闭态，否则会出现「开关是关的、展开项还挂着」
        repeatEnabled = PickupNotifier.isRepeatReminderEnabled && EntitlementSnapshot.licensedPro
        repeatHours = PickupNotifier.repeatReminderHours
        arrivalEnabled = StationLocationService.isArrivalReminderEnabled && EntitlementSnapshot.licensedPro
        locationStatus = CLLocationManager().authorizationStatus
        PickupNotifier.queryAuthorizationStatus { [weak self] status in
            self?.authStatus = status
        }
    }

    func refreshLocationStatus() {
        locationStatus = CLLocationManager().authorizationStatus
    }

    func setEnabled(_ value: Bool) {
        PickupNotifier.isEnabled = value
        if value { PickupNotifier.requestAuthorizationIfNeeded() }
        refresh()
    }

    func setDailyEnabled(_ value: Bool) {
        PickupNotifier.isDailyReminderEnabled = value
        dailyEnabled = value
        PickupNotifier.rescheduleDailyReminder()
    }

    func setDailyTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        PickupNotifier.dailyReminderHour = components.hour ?? 20
        PickupNotifier.dailyReminderMinute = components.minute ?? 0
        dailyTime = date
        PickupNotifier.rescheduleDailyReminder()
    }

    func setPendingEnabled(_ value: Bool) {
        // 超时未取提醒属于Codelumi Pro：非 Pro 一律落回关闭态
        let allowed = value && EntitlementSnapshot.licensedPro
        PickupNotifier.isPendingReminderEnabled = allowed
        pendingEnabled = allowed
        PickupNotifier.rescheduleAllPendingReminders()
    }

    func setPendingHours(_ value: Int) {
        PickupNotifier.pendingReminderHours = value
        pendingHours = value
        PickupNotifier.rescheduleAllPendingReminders()
    }

    func setRepeatEnabled(_ value: Bool) {
        // 重复提醒与超时提醒同属 Codelumi Pro：非 Pro 一律落回关闭态
        let allowed = value && EntitlementSnapshot.licensedPro
        PickupNotifier.isRepeatReminderEnabled = allowed
        repeatEnabled = allowed
        PickupNotifier.rescheduleRepeatReminder()
    }

    func setRepeatHours(_ value: Int) {
        PickupNotifier.repeatReminderHours = value
        repeatHours = value
        PickupNotifier.rescheduleRepeatReminder()
    }

    func setArrivalEnabled(_ value: Bool) {
        // 🔴 老大 2026-11-16 补充：到达提醒也是 Codelumi Pro 功能。
        //    非 Pro 一律落回关闭态，并把围栏全撤（service 内部按权益校验）。
        let allowed = value && EntitlementSnapshot.licensedPro
        StationLocationService.shared.setArrivalEnabled(allowed)
        arrivalEnabled = allowed
        refreshLocationStatus()
    }
}

// MARK: - 页面

struct NotificationSettingsView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = ReminderSettingsModel()
    /// 已设位置的驿站清单（含内置）要跟着驿站管理页的改动即时刷新
    @ObservedObject private var locationStore = StationLocationStore.shared
    /// 非 Pro 点「超时未取提醒」时直接弹订阅页（不显示任何加锁标志）
    @State private var showPaywall = false

    /// 不定期提醒的可选等待时长（小时）。
    private let hourOptions = [3, 6, 12, 24, 48]
    /// 重复提醒的间隔档位（小时）。最小 1 小时：`UNTimeIntervalNotificationTrigger`
    /// 的 `repeats: true` 要求 ≥ 60 秒，且更密的间隔对用户就是骚扰。
    private let repeatHourOptions = [1, 2, 4, 6, 12, 24]

    var body: some View {
        ScrollView {
            // 组间距 24：iOS 设置页的分组留白比卡内行距大得多，
            // 分组标题 + 卡 + 卡外说明构成一个"块"，块与块之间必须能一眼断开。
            VStack(spacing: 24) {
                toggleSection
                dailySection
                pendingSection
                labSection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 14)
            .padding(.bottom, 60)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("通知")
        .sheet(isPresented: $showPaywall) {
            NavigationStack { FullVersionView() }
                .modifier(PaywallSheetSizing())
        }
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.refresh()
            // 截图脚手架 `ARRIVAL_LAB=1`：展开全部提醒项（含实验室分组）。
            // 需配合 `FORCE_PRO=1` —— 超时 / 重复 / 到达三项都是 Codelumi Pro。
            if ProcessInfo.processInfo.environment["ARRIVAL_LAB"] == "1" {
                model.setPendingEnabled(true)
                model.setRepeatEnabled(true)
                model.setArrivalEnabled(true)
            }
            // 截图脚手架 `HOURS_MENU=1`：把「等待时长」选单直接打开。
            // 命令行点不出 popover，没有这个入口就只能靠肉眼在真机上验。
            guard ProcessInfo.processInfo.environment["HOURS_MENU"] == "1" else { return }
            model.setPendingEnabled(true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                showHoursMenu = true
            }
        }
        // 从系统设置改完权限回来 / 系统授权弹窗被点掉，都要把状态刷新到脸上
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.refreshLocationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stationLocationAuthDidChange)) { _ in
            model.refreshLocationStatus()
        }
    }

    // MARK: 入库通知

    private var toggleSection: some View {
        // 第一组也带组标题：三组（入库通知 / 定期 / 不定期）节奏一致，
        // 否则顶上一块无标题的卡会像是从上一页漏下来的。
        //
        // 🔴 2026-11-22 主人：「标题清晰的就不要提示了」—— 「添加后发送通知」已经把
        //    「什么时候发、发什么」说完了，原提示「入库后弹一条：标题是取件码。」删除。
        SettingsGroup(title: "入库通知") {
            SettingsPlainRow(title: "添加后发送通知") {
                Toggle("", isOn: Binding(get: { model.isEnabled },
                                         set: { model.setEnabled($0) }))
                    .labelsHidden()
                    .tint(AppTheme.accent)
            }

            // 🔴 App 内开关开着、系统权限却是关的 —— 静默失效要摆在脸上。
            if model.isEnabled && model.authStatus == .denied {
                SettingsDivider(style: .plain)
                systemDeniedHint
            }
        }
    }

    private var systemDeniedHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.pendingTint)

            VStack(alignment: .leading, spacing: 3) {
                Text("系统的「通知」权限被关掉了")
                    .font(.caption.weight(.medium))
                Text("上面这个开关开着也不会弹。需要到系统设置里把「Codelumi」的通知打开。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("去开启") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 定期提醒

    private var dailySection: some View {
        // 🔴 2026-11-22 主人：删掉「到点数一遍待取件，没取的才响。」
        //    开关名字已经把「每天定时」说清楚，后半句只是把实现讲了一遍。
        SettingsGroup(title: "提醒 · 每天固定") {
            SettingsPlainRow(title: "每天定时提醒") {
                Toggle("", isOn: Binding(get: { model.dailyEnabled },
                                         set: { model.setDailyEnabled($0) }))
                    .labelsHidden()
                    .tint(AppTheme.accent)
            }

            if model.dailyEnabled {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "提醒时间") {
                    DatePicker("",
                               selection: Binding(get: { model.dailyTime },
                                                  set: { model.setDailyTime($0) }),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }
        }
    }

    /// 等待时长 / 重复间隔的自绘菜单是否展开
    @State private var showHoursMenu = false
    @State private var showRepeatMenu = false

    /// 小时数选单（自绘，替代系统 `Menu`）。
    ///
    /// 布局刻意与系统菜单区分开：**勾号贴最右端**、颜色用系统蓝
    /// （`Color(.systemBlue)` = Apple 蓝 #007AFF，不是 App 主色那个偏深的蓝）。
    /// 未选中行不放占位图形 —— `Spacer` 已经把文字顶到左边，勾的有无不影响对齐。
    private func hourMenu(options: [Int], current: Int,
                          onSelect: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { hours in
                Button {
                    onSelect(hours)
                } label: {
                    HStack(spacing: 10) {
                        // 🔴 2026-11-22 主人（对照小组件尺寸菜单）：「这个是不是也可以改成这样」。
                        //    改成**对号占固定左槽、文字左对齐**：没选中的行也留同样一段空槽，
                        //    所以每一行「n 小时」的起点一致，选不选中都不会左右挪。
                        //
                        //    ⚠️ 这条覆盖 2026-10-27 的旧口径（当时要把对号推到最右、还要 Apple 蓝）。
                        //    颜色保留 Apple 蓝（系统语义色 systemBlue），只改位置与占位方式。
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(.systemBlue))
                            .opacity(hours == current ? 1 : 0)
                            .frame(width: 18, alignment: .center)

                        Text("\(hours) 小时")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 168, height: 42)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var hoursMenu: some View {
        hourMenu(options: hourOptions, current: model.pendingHours) { value in
            model.setPendingHours(value)
            showHoursMenu = false
        }
    }

    private var repeatHoursMenu: some View {
        hourMenu(options: repeatHourOptions, current: model.repeatHours) { value in
            model.setRepeatHours(value)
            showRepeatMenu = false
        }
    }

    /// 带 Codelumi Pro 门禁的开关（2026-11-16 到达提醒也用这一套）。
    ///
    /// 🔴 主人 2026-11-08 定：**界面上不显示任何加锁标志**；
    ///    非 Pro 点一下开关 = 直接弹订阅页（不先翻转开关再回弹）。
    ///    overlay 里用 `Color.clear` 而不是 ZStack 撑宽，否则开关会被挤到行中间。
    @ViewBuilder
    private func gatedToggle(isOn: Bool, label: String,
                             onChange: @escaping (Bool) -> Void) -> some View {
        if EntitlementSnapshot.licensedPro {
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .tint(AppTheme.accent)
        } else {
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .tint(AppTheme.accent)
                .allowsHitTesting(false)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showPaywall = true }
                        .accessibilityLabel(label)
                        .accessibilityHint("需要Codelumi Pro")
                }
        }
    }

    // MARK: 不定期提醒

    private var pendingSection: some View {
        // 🔴 2026-11-22 主人：长句压成一句。「超过设定时长催一次；开启重复后按间隔继续催，
        //    所有件取完自动停。」里只有「取完自动停」是用户猜不到的，其余都是标题的复述。
        SettingsGroup(title: "提醒 · 超时未取",
                      note: "取完自动停。") {
            SettingsPlainRow(title: "超时未取提醒") {
                gatedToggle(isOn: model.pendingEnabled, label: "超时未取提醒") {
                    model.setPendingEnabled($0)
                }
            }

            if model.pendingEnabled {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "等待时长") {
                    // 5 档固定时长：自由输入会把「37 小时」这类值排进
                    // UNTimeIntervalNotificationTrigger，数字对用户毫无意义。
                    //
                    // 🔴 **不再用系统 `Menu`**（2026-10-27 主人：「把这个对号继续做成 Apple 蓝，
                    // 位置再向右侧移动一些」）。系统 Menu 的行由 UIKit 渲染：
                    //   · 行内文字颜色被强制成 label 色，`foregroundStyle` 一律无效；
                    //   · `Label(_, systemImage:)` 的图标恒排**最左**，既不能右对齐也不能改色。
                    // 上一版用字符 "✓" 拼在时间后面，只是绕开了"图标跑最左"，
                    // 颜色与位置仍然动不了。所以这里换成自绘 popover：
                    // 行 = 文字 + Spacer + SF Symbol 勾，勾在最右端且可指定颜色。
                    // `.presentationCompactAdaptation(.popover)` 让它在小屏也保持气泡形态，
                    // 而不是被降级成底部 sheet。
                    Button {
                        showHoursMenu = true
                    } label: {
                        SettingsValueLabel(text: "\(model.pendingHours) 小时")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHoursMenu, arrowEdge: .top) {
                        hoursMenu
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }

            SettingsDivider(style: .plain)

            // 重复提醒（2026-11-16 主人新增）：与超时开关相互独立，
            // 逻辑上是「全局一条按间隔催」，放在同组只是位置上的从属。
            SettingsPlainRow(title: "重复提醒") {
                gatedToggle(isOn: model.repeatEnabled, label: "重复提醒") {
                    model.setRepeatEnabled($0)
                }
            }

            if model.repeatEnabled {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "提醒间隔") {
                    Button {
                        showRepeatMenu = true
                    } label: {
                        SettingsValueLabel(text: "\(model.repeatHours) 小时")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showRepeatMenu, arrowEdge: .top) {
                        repeatHoursMenu
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }

    // MARK: 实验室 · 到达提醒

    /// 到达提醒是**实验性 + Codelumi Pro** 功能（老大 2026-11-16 定）：
    ///   · 系统地理围栏有延迟，离线 / 低电量 / 定位精度差时可能不触发；
    ///   · 只有该驿站还存在待取件时才推通知，没件不打扰；
    ///   · 位置只存本机，不上传、不记录轨迹。
    private var labSection: some View {
        // 🔴 2026-11-22 主人：三段长说明压成一句。留下的三件都是标题说不出来的：
        //    实验性（预期管理）、位置只在本机（隐私承诺）、20 个上限（硬限制）。
        //    「需始终允许定位」删了 —— 打开开关时系统自己的权限弹窗会讲，
        //    写在这里既不准确（用户可以选「使用期间」）也不及时。
        SettingsGroup(
            // 2026-11-22 主人：「把所有实验室功能的都改成一样的标签来标记」——
            // 标题里的「实验室 · 」前缀退役，改挂统一的 `LabBadge`（见 SectionHeader.isLab）。
            title: "到达提醒",
            // 徽章已经说了"实验室"，note 里不再重复「实验性，」三个字
            note: "可能延迟几分钟；位置只存本机，最多 20 个驿站。",
            isLab: true
        ) {
            SettingsPlainRow(title: "开启提醒") {
                // 🔴 老大 2026-11-16 补充：到达提醒也是 Codelumi Pro；
                //    非 Pro 点开关直接弹订阅页，不显示加锁标志（同一套 gatedToggle）。
                // 2026-11-22：分组标题已经是「到达提醒」，行内再写一遍就是重复，改叫「开启提醒」。
                gatedToggle(isOn: model.arrivalEnabled, label: "开启提醒") {
                    model.setArrivalEnabled($0)
                }
            }

            if model.arrivalEnabled {
                SettingsDivider(style: .plain)
                locationPermissionRow

                SettingsDivider(style: .plain)

                NavigationLink {
                    CourierGalleryView(scope: .station)
                } label: {
                    SettingsPlainRow(title: "驿站位置") {
                        // NavigationLink 用自定义 label 不会自动补箭头，
                        // 这里保留 chevron，否则整行看不出能点进去管理。
                        SettingsValueLabel(text: "\(locationStore.configuredNames.count) 个已设置")
                    }
                }
                .buttonStyle(.plain)

                // 2026-11-21：系统只给 20 个围栏，超出部分**不会**被监控。
                // 以前界面照旧一个开关，用户以为在监控、其实没有 —— 这里如实标出来。
                let monitored = Set(StationLocationService.plannedTargets()
                    .prefix(StationLocationService.regionLimit)
                    .map(\.name))

                ForEach(locationStore.configuredNames, id: \.self) { name in
                    SettingsDivider(style: .plain)
                    SettingsPlainRow(title: name) {
                        HStack(spacing: 8) {
                            if locationStore.location(for: name)?.enabled == true,
                               !monitored.contains(name) {
                                Text("未在监控")
                                    .font(AppTheme.TypeScale.badge)
                                    .foregroundStyle(.secondary)
                            }
                            Toggle("", isOn: Binding(
                                get: { locationStore.location(for: name)?.enabled ?? false },
                                set: { locationStore.setEnabled($0, for: name) }
                            ))
                            .labelsHidden()
                            .tint(AppTheme.accent)
                        }
                    }
                }

                if locationStore.configuredNames.isEmpty {
                    SettingsDivider(style: .plain)
                    emptyStationHint
                }
            }
        }
    }

    @ViewBuilder
    private var locationPermissionRow: some View {
        switch model.locationStatus {
        case .authorizedAlways:
            SettingsPlainRow(title: "定位权限") {
                SettingsValueLabel(text: "始终允许", showsChevron: false)
            }
        case .authorizedWhenInUse:
            SettingsPlainRow(title: "定位权限") {
                permissionButton("改为始终") {
                    StationLocationService.shared.requestAlwaysAuthorization()
                }
            }
        case .denied, .restricted:
            SettingsPlainRow(title: "定位权限") {
                permissionButton("去开启") { openSystemSettings() }
            }
        default:
            SettingsPlainRow(title: "定位权限") {
                permissionButton("开启") {
                    StationLocationService.shared.requestAlwaysAuthorization()
                }
            }
        }
    }

    private func permissionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(AppTheme.TypeScale.bodyMedium)
            .foregroundStyle(AppTheme.accent)
            .buttonStyle(.plain)
    }

    private var emptyStationHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "mappin.slash.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Text("还没有驿站设置位置。到「驿站管理」标记位置后即可启用。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
