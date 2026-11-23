import SwiftUI
import WidgetKit

// MARK: - 「驿站组 › 所属」一行（2026-11-21 主人）
//
// 原来只有「编辑自定义驿站」这一页能改归属，内置驿站点进去只有位置和到达提醒，
// 想分组得绕到驿站管理页点组的格子再勾回来。这个组件把同一份 Menu 抽出来，
// 自定义驿站页与内置驿站定位页共用：
//   · 不归组 / 各组名（当前组带勾）/ 新建驿站组…（新建时本驿站已预先勾好）
//   · 移组会把旧记录钉在原组（`PickupStore.pinRecords`），历史归属不跟着变。

struct StationGroupMembershipRow: View {

    /// 驿站名（内置 / 自定义都用这个名字做标识）
    let stationName: String
    /// 是否自带「驿站组」分组标题（嵌在别处时传 false）
    var showsHeader: Bool = true

    @State private var groups: [StationGroup] = []
    @State private var currentGroupID: String?
    @State private var showCreate = false

    private var currentGroupName: String? {
        groups.first { $0.id == currentGroupID }?.name
    }

    var body: some View {
        Group {
            if showsHeader {
                SettingsGroup(title: "驿站组") { row }
            } else {
                row
            }
        }
        .task(id: stationName) { reload() }
        // 建完组回来要刷新（新建时这个驿站已经被勾进去了）
        .onChange(of: showCreate) { _, isPresented in
            if !isPresented { reload() }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                StationGroupEditView(
                    mode: .create,
                    preselectedMemberIDs: StationIdentity.id(for: stationName).map { [$0] } ?? []
                )
            }
        }
    }

    private var row: some View {
        SettingsPlainRow(title: "所属") {
            Menu {
                Button {
                    assign(nil)
                } label: {
                    Label("不归组", systemImage: currentGroupID == nil ? "checkmark" : "")
                }
                if !groups.isEmpty {
                    Divider()
                    ForEach(groups) { group in
                        Button {
                            assign(group.id)
                        } label: {
                            Label(group.name, systemImage: currentGroupID == group.id ? "checkmark" : "")
                        }
                    }
                }
                Divider()
                Button {
                    showCreate = true
                } label: {
                    Label("新建驿站组…", systemImage: "plus")
                }
            } label: {
                SettingsValueLabel(text: currentGroupName ?? "不归组")
            }
        }
    }

    // MARK: 动作

    private func reload() {
        groups = StationGroupStore.all()
        currentGroupID = StationGroupStore.groupsByMember()[stationName]?.first?.id
    }

    private func assign(_ groupID: String?) {
        if let groupID {
            if let previous = StationGroupStore.addMember(stationName: stationName, toGroup: groupID),
               previous != groupID {
                PickupStore.shared.pinRecords(station: stationName, toGroup: previous)
            }
        } else {
            StationGroupStore.removeMember(stationName: stationName)
        }
        WidgetCenter.shared.reloadAllTimelines()
        reload()
    }
}
