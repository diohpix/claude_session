import AppKit
import UserNotifications

/// 작업이 끝난 세션을 macOS 알림으로 알린다. 알림을 누르면 그 세션의 터미널로 이동한다.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let enabledKey = "notifyOnIdle"

    /// 알림 센터는 앱 번들 안에서 실행될 때만 쓸 수 있다 (`swift run` 으로 띄우면 번들이 없다).
    private let available = Bundle.main.bundleIdentifier != nil

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func start() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 작업 중이던 세션이 대기로 바뀌었을 때 호출한다.
    func sessionBecameIdle(_ live: LiveSession, title: String, projectName: String) {
        guard available, Self.isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "작업이 끝나 입력을 기다리고 있습니다 · \(projectName)"
        content.sound = .default
        content.userInfo = ["pid": Int(live.pid)]
        // 같은 세션의 알림은 하나만 남도록 세션 ID를 식별자로 쓴다.
        let request = UNNotificationRequest(identifier: live.sessionId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
