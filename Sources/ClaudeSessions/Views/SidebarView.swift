import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Binding var selection: SidebarItem?

    var body: some View {
        let activeSource = selection?.activeSource
        List(selection: $selection) {
            Section {
                Label("전체 세션", systemImage: "tray.full")
                    .badge(store.sessions.count)
                    .tag(SidebarItem.all)
                Label("열린 세션", systemImage: "bolt.fill")
                    .badge(store.live.count)
                    .tag(SidebarItem.live)
            }
            Section("도구") {
                ForEach(SessionSource.allCases, id: \.self) { source in
                    Label { Text(source.title) } icon: { SourceIcon(source: source, size: 18) }
                        .badge(store.sessions.count { $0.source == source })
                        .tag(SidebarItem.source(source))
                }
            }
            Section(activeSource.map { "프로젝트 · \($0.title)" } ?? "프로젝트") {
                ForEach(store.projects(for: activeSource)) { project in
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
                    .tag(SidebarItem.project(project.id, activeSource))
                    .help(project.path)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
