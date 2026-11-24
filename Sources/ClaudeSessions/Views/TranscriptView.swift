import SwiftUI

struct TranscriptView: View {
    @Environment(SessionStore.self) private var store
    let session: SessionSummary

    @State private var document: TranscriptDocument?
    @State private var loaded = false
    /// 열린 세션이 tterm에서 돌고 있으면 그 tty. 입력창은 이때만 보인다.
    @State private var ttermTTY: String?

    private struct LoadKey: Hashable {
        let path: String?
        let modifiedAt: Date
        let size: Int64
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document, !document.isEmpty {
                TranscriptTextView(document: document)
            } else {
                ContentUnavailableView("대화 내용이 없습니다", systemImage: "text.bubble")
            }
            if let ttermTTY {
                Divider()
                MessageComposer(tty: ttermTTY)
                    .id(ttermTTY)
            }
        }
        .task(id: store.live[session.sessionId]?.pid) {
            guard let pid = store.live[session.sessionId]?.pid else {
                ttermTTY = nil
                return
            }
            ttermTTY = await Task.detached { TerminalLauncher.ttermTTY(of: pid) }.value
        }
        // 파일이 바뀌면(열린 세션이 진행되면) 다시 읽는다.
        .task(id: LoadKey(path: session.fileURL?.path, modifiedAt: session.modifiedAt, size: session.size)) {
            guard let url = session.fileURL else {
                document = nil
                loaded = true
                return
            }
            let source = session.source
            let icon = SourceIcon.image(for: source)
            let parsed = await Task.detached(priority: .userInitiated) {
                TranscriptDocument(messages: source.messages(url: url), source: source, icon: icon)
            }.value
            guard !Task.isCancelled else { return }
            document = parsed
            loaded = true
        }
    }

    private var header: some View {
        let live = store.live[session.sessionId]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let live { StatusBadge(live: live) }
                SourceBadge(source: session.source)
                Text(session.displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                SessionActions(session: session, live: live)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
            }
            // 버튼 사이의 세로 구분선이 헤더 높이를 끝없이 늘리지 않게 한다.
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Label(abbreviateHome(session.projectPath), systemImage: "folder")
                if let branch = session.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                }
                if let started = session.startedAt {
                    Label(started.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                }
                Label(ByteCountFormatter.string(fromByteCount: session.size, countStyle: .file), systemImage: "doc")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Text(session.sessionId)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
