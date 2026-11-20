import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("전체 세션", systemImage: "tray.full")
                    .badge(store.sessions.count)
                    .tag(SidebarItem.all)
                Label("열린 세션", systemImage: "bolt.fill")
                    .badge(store.live.count)
                    .tag(SidebarItem.live)
            }
            Section("프로젝트") {
                ForEach(store.projects) { project in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name)
                                .lineLimit(1)
                            Text(abbreviateHome(project.path))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .badge(project.count)
                    .tag(SidebarItem.project(project.id))
                    .help(project.path)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
