import AppKit
import SwiftUI
import UserNotifications

/// 작업이 끝난 세션을 알린다. 알림을 누르면 그 세션의 터미널로 이동한다.
///
/// macOS 알림 센터를 쓸 수 있으면 그쪽으로 보내고, 권한이 없으면(ad-hoc 서명 앱은 macOS가
/// 권한을 묻지도 않고 거부하는 경우가 있다) 화면 오른쪽 위에 직접 그린 알림 창을 띄운다.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let enabledKey = "notifyOnIdle"

    /// 알림 센터는 앱 번들 안에서 실행될 때만 쓸 수 있다 (`swift run` 으로 띄우면 번들이 없다).
    private let hasBundle = Bundle.main.bundleIdentifier != nil

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func start() {
        guard hasBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 작업 중이던 세션이 대기로 바뀌었을 때 호출한다.
    func sessionBecameIdle(_ live: LiveSession, title: String, projectName: String) {
        guard Self.isEnabled else { return }
        deliver(
            id: live.sessionId,
            title: title,
            body: "작업이 끝나 입력을 기다리고 있습니다 · \(projectName)",
            pid: live.pid
        )
    }

    private func deliver(id: String, title: String, body: String, pid: Int32?) {
        systemAuthorized { authorized in
            if authorized {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                if let pid { content.userInfo = ["pid": Int(pid)] }
                // 같은 세션의 알림은 하나만 남도록 세션 ID를 식별자로 쓴다.
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: id, content: content, trigger: nil)
                )
            } else {
                Task { @MainActor in
                    ToastCenter.shared.show(id: id, title: title, body: body, pid: pid)
                }
            }
        }
    }

    private func systemAuthorized(_ completion: @escaping (Bool) -> Void) {
        guard hasBundle else { return completion(false) }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
    }

    /// 알림 권한 상태를 출력하고 시험 알림을 하나 보낸다 (점검용, `--notify-check`).
    @MainActor
    func check() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        systemAuthorized { authorized in
            print("macOS 알림 권한: \(authorized ? "허용 → 알림 센터로 보냅니다" : "없음 → 앱이 직접 알림 창을 띄웁니다") / 설정 켜짐: \(Self.isEnabled)")
            self.deliver(id: "check", title: "AI 세션", body: "시험 알림입니다.", pid: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ToastCenter.lifetime + 1) { app.terminate(nil) }
        app.run()
    }

    // 이 앱이 맨 앞에 있을 때도 알림을 띄운다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let pid = response.notification.request.content.userInfo["pid"] as? Int {
            DispatchQueue.main.async {
                try? TerminalLauncher.focusTerminal(of: Int32(pid))
            }
        }
        completionHandler()
    }
}

// MARK: - 직접 그리는 알림 창

/// 화면 오른쪽 위에 쌓이는 알림 창. 누르면 세션의 터미널로 이동하고, 몇 초 뒤 저절로 사라진다.
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()
    nonisolated static let lifetime: TimeInterval = 8

    private var panels: [(id: String, panel: NSPanel)] = []

    func show(id: String, title: String, body: String, pid: Int32?) {
        close(id: id)  // 같은 세션의 이전 알림은 바꿔 끼운다.

        let view = ToastView(title: title, message: body) { [weak self] in
            if let pid { try? TerminalLauncher.focusTerminal(of: pid) }
            self?.close(id: id)
        }
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panels.append((id, panel))
        layout()
        panel.orderFrontRegardless()
        NSSound(named: "Glass")?.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime) { [weak self, weak panel] in
            guard let self, let panel, self.panels.contains(where: { $0.panel === panel }) else { return }
            self.close(id: id)
        }
    }

    private func close(id: String) {
        guard let i = panels.firstIndex(where: { $0.id == id }) else { return }
        panels.remove(at: i).panel.close()
        layout()
    }

    private func layout() {
        guard let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        var top = area.maxY - 12
        for (_, panel) in panels {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 12, y: top - size.height))
            top -= size.height + 8
        }
    }
}

/// 앱이 뒤에 있어도 첫 클릭을 바로 받는다.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ToastView: View {
    let title: String
    let message: String
    let onClick: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SourceIcon(source: .claude, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onClick)
    }
}
