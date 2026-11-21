import Foundation
import UserNotifications

@available(iOS 26.0, *)
final class PairingNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PairingNotifications()
    private let center = UNUserNotificationCenter.current()
    private let identifier = "jit-pairing-code"
    private var active = false

    private override init() {
        super.init()
        center.delegate = self
        clear()
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async { completion(true) }
            } else if settings.authorizationStatus == .denied {
                DispatchQueue.main.async { completion(false) }
            } else {
                self.center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
                    DispatchQueue.main.async { completion(allowed) }
                }
            }
        }
    }

    func show(code: String, name: String) {
        guard code.utf8.count == 6, code.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return }
        active = true
        let content = UNMutableNotificationContent()
        content.title = "Pairing code for " + name
        content.body = code + " — Enter this code in Settings to finish pairing."
        content.sound = .default
        content.threadIdentifier = identifier
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.active else { return }
                self.clear()
            }
        }
    }

    func clear() {
        active = false
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion(notification.request.identifier == identifier ? [.banner, .list, .sound] : [])
    }
}
