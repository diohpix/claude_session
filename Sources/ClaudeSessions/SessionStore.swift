import Foundation
import Observation

/// 디스크를 읽는 순수 함수 모음 (백그라운드에서 호출).
enum Scanner {
    static let claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    static let projectsDir = claudeDir.appendingPathComponent("projects")
    static let sessionsDir = claudeDir.appendingPathComponent("sessions")
    static let codexDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    static let codexSessionsDir = codexDir.appendingPathComponent("sessions")
    static let codexIndexFile = codexDir.appendingPathComponent("session_index.jsonl")

    /// Claude와 Codex의 세션 기록을 모두 요약한다 (키는 기록 파일 경로).
    static func scanAll(cache: [String: SessionSummary]) -> [String: SessionSummary] {
        scanProjects(cache: cache).merging(scanCodex(cache: cache)) { a, _ in a }
    }

    /// `~/.codex/sessions/<년>/<월>/<일>/rollout-*.jsonl` 을 요약한다.
    static func scanCodex(cache: [String: SessionSummary]) -> [String: SessionSummary] {
        var result: [String: SessionSummary] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: codexSessionsDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return result }

        let titles = codexTitles()
        for case let file as URL in walker where file.pathExtension == "jsonl" {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let mtime = values.contentModificationDate ?? .distantPast
            let size = Int64(values.fileSize ?? 0)
            var s: SessionSummary
            if let cached = cache[file.path], cached.modifiedAt == mtime, cached.size == size {
                s = cached
            } else {
                s = CodexTranscriptParser.summary(url: file, modifiedAt: mtime, size: size)
            }
            // 제목은 기록 파일이 아니라 색인에 있어 따로 바뀔 수 있으므로 매번 다시 붙인다.
            s.title = titles[s.sessionId]
            result[file.path] = s
        }
        return result
    }

    /// `session_index.jsonl` 의 세션 ID → 제목. 같은 ID가 여러 번 나오면 마지막 줄이 이긴다.
    private static func codexTitles() -> [String: String] {
        guard let data = try? Data(contentsOf: codexIndexFile, options: .mappedIfSafe) else { return [:] }
        var titles: [String: String] = [:]
        for line in data.split(separator: 0x0A) {
            guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let id = obj["id"] as? String,
                  let name = obj["thread_name"] as? String, !name.isEmpty else { continue }
            titles[id] = name
        }
        return titles
    }

    /// 모든 프로젝트의 세션 기록을 요약한다. 크기와 수정 시각이 그대로인 파일은 캐시를 재사용한다.
    static func scanProjects(cache: [String: SessionSummary]) -> [String: SessionSummary] {
        let fm = FileManager.default
        var result: [String: SessionSummary] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]

        guard let projects = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return result }

        for dir in projects {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)
            else { continue }

            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                let mtime = values.contentModificationDate ?? .distantPast
                let size = Int64(values.fileSize ?? 0)
                if let cached = cache[file.path], cached.modifiedAt == mtime, cached.size == size {
                    result[file.path] = cached
                } else {
                    result[file.path] = TranscriptParser.summary(
                        url: file, projectDir: dir.lastPathComponent, modifiedAt: mtime, size: size
                    )
                }
            }
        }
        return result
    }

    /// 실행 중인 세션. `<pid>.json` 만 읽고(같은 폴더의 키 파일은 건드리지 않는다) 죽은 프로세스는 제외한다.
    static func liveSessions() -> [String: LiveSession] {
        var result: [String: LiveSession] = [:]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        ) else { return result }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pid = (obj["pid"] as? NSNumber)?.int32Value,
                  let sessionId = obj["sessionId"] as? String,
                  isAlive(pid) else { continue }
            let started = (obj["startedAt"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1000)
            }
            result[sessionId] = LiveSession(
                pid: pid,
                sessionId: sessionId,
                cwd: obj["cwd"] as? String ?? "",
                name: obj["name"] as? String ?? "",
                status: obj["status"] as? String ?? "",
                kind: obj["kind"] as? String ?? "",
                startedAt: started
            )
        }
        return result
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// 요약과 열린 세션을 합쳐 화면에 보일 목록을 만든다 (열린 세션 먼저, 그다음 최근순).
    static func merge(_ summaries: [String: SessionSummary], live: [String: LiveSession]) -> [SessionSummary] {
        var list = Array(summaries.values)
        let known = Set(list.map(\.sessionId))
        for (sid, l) in live where !known.contains(sid) {
            // 아직 한 번도 대화하지 않아 기록 파일이 없는 열린 세션.
            list.append(SessionSummary(
                id: "live:\(sid)",
                sessionId: sid,
                fileURL: nil,
                projectDir: projectKey(forPath: l.cwd),
                cwd: l.cwd.isEmpty ? nil : l.cwd,
                title: l.name.isEmpty ? nil : l.name,
                startedAt: l.startedAt,
                modifiedAt: l.startedAt ?? Date(),
                size: 0
            ))
        }
        list.sort { a, b in
            let la = live[a.sessionId] != nil, lb = live[b.sessionId] != nil
            if la != lb { return la }
            if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
            return a.id < b.id
        }
        return list
    }
}

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SessionSummary] = []
    private(set) var live: [String: LiveSession] = [:]
    private(set) var isLoading = true
    /// 삭제 확인을 기다리는 세션들 (확인 창은 ContentView가 띄운다).
    var pendingDelete: [SessionSummary] = []
    var errorMessage: String?

    @ObservationIgnored private var cache: [String: SessionSummary] = [:]
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var pending = false

    /// 프로젝트 목록. `source` 를 주면 그 도구의 세션이 있는 프로젝트만, 그 도구의 세션 수로 센다.
    func projects(for source: SessionSource? = nil) -> [ProjectGroup] {
        var groups: [String: (name: String, path: String, count: Int, latest: Date)] = [:]
        for s in sessions where source == nil || s.source == source {
            if var g = groups[s.projectDir] {
                g.count += 1
                if s.modifiedAt > g.latest {
                    g.latest = s.modifiedAt
                    if s.cwd != nil { g.name = s.projectName; g.path = s.projectPath }
                }
                groups[s.projectDir] = g
            } else {
                groups[s.projectDir] = (s.projectName, s.projectPath, 1, s.modifiedAt)
            }
        }
        return groups
            .map { ProjectGroup(id: $0.key, name: $0.value.name, path: $0.value.path, count: $0.value.count, latest: $0.value.latest) }
            .sorted { $0.latest > $1.latest }
    }

    func start() {
        guard watcher == nil else { return }
        Notifier.shared.start()
        watcher = DirectoryWatcher(paths: [
            Scanner.projectsDir.path, Scanner.sessionsDir.path, Scanner.codexSessionsDir.path,
        ]) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        // 비정상 종료된 세션은 파일 변경 없이 사라지므로 주기적으로도 확인한다.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// 휴지통으로 옮길 수 있는 세션만 고른다 (실행 중이거나 기록 파일이 없는 세션 제외).
    func deletable(_ sessions: [SessionSummary]) -> [SessionSummary] {
        sessions.filter { live[$0.sessionId] == nil && $0.fileURL != nil }
    }

    /// 세션 기록 파일과 같은 이름의 부속 폴더를 휴지통으로 옮긴다. 실행 중인 세션은 건너뛴다.
    func delete(_ sessions: [SessionSummary]) {
        let live = Scanner.liveSessions()
        let fm = FileManager.default
        var skipped: [String] = []
        var failures: [String] = []
        for session in sessions {
            guard let url = session.fileURL else { continue }
            guard live[session.sessionId] == nil else {
                skipped.append(session.displayTitle)
                continue
            }
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                let sidecar = url.deletingPathExtension()
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: sidecar.path, isDirectory: &isDir), isDir.boolValue {
                    try fm.trashItem(at: sidecar, resultingItemURL: nil)
                }
            } catch {
                failures.append("\(session.displayTitle): \(error.localizedDescription)")
            }
        }
        var messages: [String] = []
        if !skipped.isEmpty {
            messages.append("실행 중인 세션은 삭제하지 않았습니다. 먼저 세션을 종료해 주세요.\n" + skipped.joined(separator: "\n"))
        }
        if !failures.isEmpty {
            messages.append("삭제하지 못했습니다.\n" + failures.joined(separator: "\n"))
        }
        if !messages.isEmpty { errorMessage = messages.joined(separator: "\n\n") }
        refresh()
    }

    func refresh() {
        if scanning {
            pending = true
            return
        }
        scanning = true
        let cache = self.cache
        Task.detached(priority: .userInitiated) {
            let summaries = Scanner.scanAll(cache: cache)
            let live = Scanner.liveSessions()
            let merged = Scanner.merge(summaries, live: live)
            await MainActor.run {
                self.apply(cache: summaries, live: live, merged: merged)
            }
        }
    }

    private func apply(cache: [String: SessionSummary], live: [String: LiveSession], merged: [SessionSummary]) {
        self.cache = cache
        // 작업 중 → 대기로 바뀐 세션을 알린다.
        for (sid, now) in live where now.status == "idle" && self.live[sid]?.status == "busy" {
            let session = merged.first { $0.sessionId == sid }
            Notifier.shared.sessionBecameIdle(
                now,
                title: session?.displayTitle ?? (now.name.isEmpty ? "Claude 세션" : now.name),
                projectName: session?.projectName ?? (now.cwd as NSString).lastPathComponent
            )
        }
        if self.live != live { self.live = live }
        if self.sessions != merged { self.sessions = merged }
        if isLoading { isLoading = false }
        scanning = false
        if pending {
            pending = false
            refresh()
        }
    }
}
