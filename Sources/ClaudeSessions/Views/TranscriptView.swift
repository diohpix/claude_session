import SwiftUI

struct TranscriptView: View {
    @Environment(SessionStore.self) private var store
    let session: SessionSummary

    @State private var messages: [ChatMessage] = []
    @State private var loaded = false

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
            } else if messages.isEmpty {
                ContentUnavailableView("대화 내용이 없습니다", systemImage: "text.bubble")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, source: session.source)
                        }
                    }
                    .padding(16)
                }
                .defaultScrollAnchor(.bottom)
            }
        }
        // 파일이 바뀌면(열린 세션이 진행되면) 다시 읽는다.
        .task(id: LoadKey(path: session.fileURL?.path, modifiedAt: session.modifiedAt, size: session.size)) {
            guard let url = session.fileURL else {
                messages = []
                loaded = true
                return
            }
            let source = session.source
            let parsed = await Task.detached(priority: .userInitiated) {
                source.messages(url: url)
            }.value
            guard !Task.isCancelled else { return }
            messages = parsed
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

private struct MessageBubble: View {
    let message: ChatMessage
    let source: SessionSource

    /// 아주 긴 붙여넣기 때문에 화면이 멈추지 않도록 표시 길이를 제한한다.
    private static let displayLimit = 20_000

    private var rendered: AttributedString {
        var text = message.text
        if text.count > Self.displayLimit {
            text = String(text.prefix(Self.displayLimit)) + "\n\n…(이하 생략)"
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var toolSummary: String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for t in message.tools {
            if counts[t] == nil { order.append(t) }
            counts[t, default: 0] += 1
        }
        return order.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }.joined(separator: ", ")
    }

    var body: some View {
        let isUser = message.role == .user
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if !isUser { SourceIcon(source: source, size: 14) }
                    Text(isUser ? "나" : source.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isUser ? Color.accentColor : .secondary)
                    if let ts = message.timestamp {
                        Text(ts.formatted(date: .numeric, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !message.text.isEmpty {
                    Text(rendered)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !message.tools.isEmpty {
                    Label(toolSummary, systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                isUser ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .frame(maxWidth: isUser ? 640 : .infinity, alignment: .leading)
            if !isUser { Spacer(minLength: 0) }
        }
    }
}
