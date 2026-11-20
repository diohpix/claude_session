import AppKit
import Foundation

enum TerminalApp: String, CaseIterable, Identifiable {
    case tterm
    case terminal
    case alacritty

    static let defaultApp = TerminalApp.tterm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tterm: return "tterm"
        case .terminal: return "터미널 (Terminal.app)"
        case .alacritty: return "Alacritty"
        }
    }
}

enum TerminalLauncher {
    struct LaunchError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 세션의 작업 폴더에서 `claude --resume <id>` (Codex는 `codex resume <id>`) 를 새 터미널 창으로 실행한다.
    static func resume(_ session: SessionSummary, in app: TerminalApp) throws {
        guard let cwd = session.cwd else {
            throw LaunchError(message: "이 세션의 작업 폴더를 알 수 없습니다.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else {
            throw LaunchError(message: "작업 폴더가 더 이상 존재하지 않습니다.\n\(cwd)")
        }
        let command = session.source.resumeInvocation(sessionId: session.sessionId)

        switch app {
        case .tterm, .terminal:
            // 두 앱 모두 `.command` 스크립트를 열면 새 창에서 실행한다.
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeSessions", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let script = dir.appendingPathComponent("resume-\(projectKey(forPath: session.sessionId)).command")
            // 로그인+대화형 셸로 실행해 사용자의 PATH 설정(.zshrc 등)이 적용되게 한다.
            let body = "#!/bin/zsh\ncd \(shellQuote(cwd)) || exit 1\nexec /bin/zsh -ilc \(shellQuote(command))\n"
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            try run("/usr/bin/open", ["-a", app == .tterm ? "tterm" : "Terminal", script.path])

        case .alacritty:
            try run("/usr/bin/open", [
                "-na", "Alacritty", "--args",
                "--working-directory", cwd,
                "-e", "/bin/zsh", "-ilc", command,
            ])
        }
    }

    /// 실행 중인 세션을 띄운 터미널 앱을 앞으로 가져온다.
    /// 세션 프로세스의 부모를 거슬러 올라가 Dock에 보이는 첫 앱을 찾는다.
    /// tterm이면 세션의 tty에 포커스 요청 시퀀스를 써서 해당 창·탭까지 선택하게 한다.
    static func focusTerminal(of pid: Int32) throws {
        var current = pid
        for _ in 0..<32 {
            guard let parent = processInfo(of: current)?.kp_eproc.e_ppid, parent > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                if app.bundleIdentifier == "com.xiphoid.tterm" {
                    requestTtermFocus(sessionPID: pid)
                }
                app.activate(options: [])
                return
            }
            current = parent
        }
        throw LaunchError(message: "이 세션을 띄운 터미널 앱을 찾지 못했습니다. (PID \(pid))")
    }

    /// tterm 전용 제어 시퀀스 `ESC _ T focus ESC \` 를 세션의 tty에 쓴다.
    /// tterm은 이 출력을 받은 터미널의 창과 탭을 앞으로 가져온다 (화면에는 아무것도 찍히지 않는다).
    private static func requestTtermFocus(sessionPID pid: Int32) {
        guard let dev = processInfo(of: pid)?.kp_eproc.e_tdev, dev != -1,
              let name = devname(dev, S_IFCHR) else { return }
        let fd = open("/dev/" + String(cString: name), O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let sequence: [UInt8] = [0x1B, 0x5F] + Array("Tfocus".utf8) + [0x1B, 0x5C]
        _ = sequence.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    private static func processInfo(of pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LaunchError(message: "터미널을 열지 못했습니다.\n\(msg)")
        }
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}
