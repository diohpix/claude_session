import Foundation
import Observation

/// 디스크를 읽는 순수 함수 모음 (백그라운드에서 호출).
enum Scanner {
    static let claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    static let projectsDir = claudeDir.appendingPathComponent("projects")
    static let sessionsDir = claudeDir.appendingPathComponent("sessions")

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
                projectDir: l.cwd.replacingOccurrences(of: "/", with: "-"),
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
    /// 삭제 확인을 기다리는 세션 (확인 창은 ContentView가 띄운다).
    var pendingDelete: SessionSummary?
    var errorMessage: String?

    @ObservationIgnored private var cache: [String: SessionSummary] = [:]
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var pending = false

    var projects: [ProjectGroup] {
        var groups: [String: (name: String, path: String, count: Int, latest: Date)] = [:]
        for s in sessions {
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
        watcher = DirectoryWatcher(paths: [Scanner.projectsDir.path, Scanner.sessionsDir.path]) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        // 비정상 종료된 세션은 파일 변경 없이 사라지므로 주기적으로도 확인한다.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// 세션 기록 파일과 같은 이름의 부속 폴더를 휴지통으로 옮긴다. 실행 중인 세션은 거부한다.
    func delete(_ session: SessionSummary) {
        guard let url = session.fileURL else { return }
        guard Scanner.liveSessions()[session.sessionId] == nil else {
            errorMessage = "실행 중인 세션은 삭제할 수 없습니다. 먼저 세션을 종료해 주세요."
            return
        }
        let fm = FileManager.default
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            let sidecar = url.deletingPathExtension()
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: sidecar.path, isDirectory: &isDir), isDir.boolValue {
                try fm.trashItem(at: sidecar, resultingItemURL: nil)
            }
        } catch {
            errorMessage = "삭제하지 못했습니다.\n\(error.localizedDescription)"
        }
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
            let summaries = Scanner.scanProjects(cache: cache)
            let live = Scanner.liveSessions()
            let merged = Scanner.merge(summaries, live: live)
            await MainActor.run {
                self.apply(cache: summaries, live: live, merged: merged)
            }
        }
    }

    private func apply(cache: [String: SessionSummary], live: [String: LiveSession], merged: [SessionSummary]) {
        self.cache = cache
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
