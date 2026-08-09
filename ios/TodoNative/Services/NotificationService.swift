import Foundation
import UserNotifications
import UIKit

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

enum NotificationService {
    static func setup() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion?(granted)
        }
    }

    static func authorizationStatus(completion: @escaping (UNAuthorizationStatus?) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    static func pendingCount(completion: @escaping (Int) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            completion(requests.count)
        }
    }

    static func scheduleDueReminder(taskID: UUID, title: String, dueDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = Localization.t("notification.dueTitle")
        content.body = Localization.t("notification.dueBody", title)
        content.sound = .default
        let fireDate = triggerDate(for: dueDate)
        let interval = max(60, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let idString = taskID.uuidString
        let request = UNNotificationRequest(identifier: idString, content: content, trigger: trigger)
        print("[NotificationService] scheduling \(idString) at \(fireDate)")
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] schedule failed \(idString): \(error)")
            } else {
                print("[NotificationService] scheduled OK \(idString)")
            }
        }
    }

    static func cancelReminder(taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [taskID.uuidString])
    }

    static func triggerDate(for dueDate: Date, now: Date = Date()) -> Date {
        if dueDate > now { return dueDate }
        let interval = max(60, now.timeIntervalSince(dueDate))
        return now.addingTimeInterval(interval)
    }
}