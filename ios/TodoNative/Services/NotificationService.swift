import Combine
import Foundation
import UIKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

enum ReminderEnableResult: Equatable {
    case enabled
    case disabled
    case permissionDenied
    case restricted
}

@MainActor
protocol ReminderScheduling: AnyObject {
    func scheduleDueReminder(taskID: UUID, title: String, dueDate: Date)
    func cancelReminder(taskID: UUID)
}

@MainActor
final class NotificationService: ObservableObject, ReminderScheduling {
    static let enabledKey = "reminders_enabled"
    static let reminderPrefix = "task-reminder."
    static let testPrefix = "test-notification-"

    private let client: NotificationCenterClient
    private let defaults: UserDefaults
    private struct DesiredReminder {
        let schedulingGeneration: Int
        let taskGeneration: Int
        let request: UNNotificationRequest
    }

    private var schedulingGeneration = 0
    private var enablementGeneration = 0
    private var taskSchedulingGenerations: [UUID: Int] = [:]
    private var desiredReminders: [UUID: DesiredReminder] = [:]
    @Published private(set) var isRemindersEnabled: Bool
    @Published private(set) var systemAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingReminderCount = 0

    init(
        client: NotificationCenterClient = SystemNotificationCenterClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
        isRemindersEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    static func setup() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    static func reminderIdentifier(for taskID: UUID) -> String {
        "\(reminderPrefix)\(taskID.uuidString)"
    }

    static func isReminderIdentifier(
        _ identifier: String,
        legacyTaskIDs: Set<UUID> = []
    ) -> Bool {
        if identifier.hasPrefix(reminderPrefix) { return true }
        guard let legacyID = UUID(uuidString: identifier) else { return false }
        return legacyTaskIDs.contains(legacyID)
    }

    func refresh() async {
        let status = await client.authorizationStatus()
        systemAuthorizationStatus = status

        if defaults.object(forKey: Self.enabledKey) == nil {
            let enabled = Self.isAuthorized(status)
            isRemindersEnabled = enabled
            defaults.set(enabled, forKey: Self.enabledKey)
        } else {
            isRemindersEnabled = defaults.bool(forKey: Self.enabledKey)
        }

        await refreshPendingReminderCount()
    }

    func scheduleDueReminder(taskID: UUID, title: String, dueDate: Date) {
        let request = makeReminderRequest(taskID: taskID, title: title, dueDate: dueDate)
        let capturedGeneration = schedulingGeneration
        let capturedTaskGeneration = advanceTaskGeneration(for: taskID)
        desiredReminders[taskID] = DesiredReminder(
            schedulingGeneration: capturedGeneration,
            taskGeneration: capturedTaskGeneration,
            request: request
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            let beforeAddStatus = await self.client.authorizationStatus()
            guard self.isRemindersEnabled,
                  Self.isAuthorized(beforeAddStatus),
                  self.schedulingGeneration == capturedGeneration,
                  self.taskSchedulingGenerations[taskID] == capturedTaskGeneration
            else { return }

            do {
                try await self.client.add(request)
                let afterAddStatus = await self.client.authorizationStatus()
                guard self.isRemindersEnabled,
                      Self.isAuthorized(afterAddStatus),
                      self.schedulingGeneration == capturedGeneration,
                      self.taskSchedulingGenerations[taskID] == capturedTaskGeneration
                else {
                    await self.reconcileLatestReminder(
                        for: taskID,
                        identifier: request.identifier
                    )
                    return
                }
                await self.refreshPendingReminderCount()
            } catch {
                await self.refreshPendingReminderCount()
            }
        }
    }

    func cancelReminder(taskID: UUID) {
        _ = advanceTaskGeneration(for: taskID)
        desiredReminders.removeValue(forKey: taskID)
        client.removePendingRequests(withIdentifiers: [
            Self.reminderIdentifier(for: taskID),
            taskID.uuidString
        ])
        Task { @MainActor [weak self] in
            await self?.refreshPendingReminderCount()
        }
    }

    func setRemindersEnabled(
        _ enabled: Bool,
        legacyTaskIDs: Set<UUID> = []
    ) async -> ReminderEnableResult {
        enablementGeneration += 1
        let capturedEnablementGeneration = enablementGeneration

        guard enabled else {
            isRemindersEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            schedulingGeneration += 1
            await cancelAllReminders(
                incrementingGeneration: false,
                legacyTaskIDs: legacyTaskIDs
            )
            return .disabled
        }

        var status = await client.authorizationStatus()
        guard enablementGeneration == capturedEnablementGeneration else {
            return currentEnablementResult
        }
        if status == .notDetermined {
            do {
                guard try await client.requestAuthorization(options: [.alert, .sound, .badge]) else {
                    guard enablementGeneration == capturedEnablementGeneration else {
                        return currentEnablementResult
                    }
                    let deniedStatus = await client.authorizationStatus()
                    guard enablementGeneration == capturedEnablementGeneration else {
                        return currentEnablementResult
                    }
                    systemAuthorizationStatus = deniedStatus
                    return .permissionDenied
                }
                guard enablementGeneration == capturedEnablementGeneration else {
                    return currentEnablementResult
                }
                status = await client.authorizationStatus()
            } catch {
                guard enablementGeneration == capturedEnablementGeneration else {
                    return currentEnablementResult
                }
                let deniedStatus = await client.authorizationStatus()
                guard enablementGeneration == capturedEnablementGeneration else {
                    return currentEnablementResult
                }
                systemAuthorizationStatus = deniedStatus
                return .permissionDenied
            }
        }

        guard enablementGeneration == capturedEnablementGeneration else {
            return currentEnablementResult
        }
        systemAuthorizationStatus = status
        guard Self.isAuthorized(status) else {
            return Self.deniedResult(for: status)
        }

        isRemindersEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        await refreshPendingReminderCount()
        return enablementGeneration == capturedEnablementGeneration ? .enabled : currentEnablementResult
    }

    func cancelAllReminders(legacyTaskIDs: Set<UUID> = []) async {
        await cancelAllReminders(
            incrementingGeneration: true,
            legacyTaskIDs: legacyTaskIDs
        )
    }

    static func triggerDate(for dueDate: Date, now: Date = Date()) -> Date {
        if dueDate > now { return dueDate }
        let interval = max(60, now.timeIntervalSince(dueDate))
        return now.addingTimeInterval(interval)
    }

    private func refreshPendingReminderCount(legacyTaskIDs: Set<UUID> = []) async {
        pendingReminderCount = await client.pendingRequestIdentifiers()
            .filter { Self.isReminderIdentifier($0, legacyTaskIDs: legacyTaskIDs) }
            .count
    }

    private func cancelAllReminders(
        incrementingGeneration: Bool,
        legacyTaskIDs: Set<UUID>
    ) async {
        if incrementingGeneration { schedulingGeneration += 1 }
        desiredReminders.removeAll()
        let identifiers = await client.pendingRequestIdentifiers()
            .filter { Self.isReminderIdentifier($0, legacyTaskIDs: legacyTaskIDs) }
        if !identifiers.isEmpty {
            client.removePendingRequests(withIdentifiers: identifiers)
        }
        await refreshPendingReminderCount(legacyTaskIDs: legacyTaskIDs)
    }

    private func makeReminderRequest(taskID: UUID, title: String, dueDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = Localization.t("notification.dueTitle")
        content.body = Localization.t("notification.dueBody", title)
        content.sound = .default
        let fireDate = Self.triggerDate(for: dueDate)
        let interval = max(60, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(
            identifier: Self.reminderIdentifier(for: taskID),
            content: content,
            trigger: trigger
        )
    }

    private var currentEnablementResult: ReminderEnableResult {
        isRemindersEnabled ? .enabled : .disabled
    }

    private func advanceTaskGeneration(for taskID: UUID) -> Int {
        let nextGeneration = taskSchedulingGenerations[taskID, default: 0] + 1
        taskSchedulingGenerations[taskID] = nextGeneration
        return nextGeneration
    }

    private func reconcileLatestReminder(for taskID: UUID, identifier: String) async {
        while true {
            guard isRemindersEnabled,
                  let desired = desiredReminders[taskID],
                  desired.schedulingGeneration == schedulingGeneration,
                  taskSchedulingGenerations[taskID] == desired.taskGeneration
            else {
                client.removePendingRequests(withIdentifiers: [identifier])
                await refreshPendingReminderCount()
                return
            }

            let beforeAddStatus = await client.authorizationStatus()
            guard isRemindersEnabled, Self.isAuthorized(beforeAddStatus) else {
                client.removePendingRequests(withIdentifiers: [identifier])
                await refreshPendingReminderCount()
                return
            }

            guard let latestBeforeAdd = desiredReminders[taskID],
                  latestBeforeAdd.schedulingGeneration == desired.schedulingGeneration,
                  latestBeforeAdd.taskGeneration == desired.taskGeneration,
                  taskSchedulingGenerations[taskID] == desired.taskGeneration
            else { continue }

            do {
                try await client.add(desired.request)
            } catch {
                await refreshPendingReminderCount()
                return
            }

            let afterAddStatus = await client.authorizationStatus()
            guard isRemindersEnabled, Self.isAuthorized(afterAddStatus) else {
                client.removePendingRequests(withIdentifiers: [identifier])
                await refreshPendingReminderCount()
                return
            }

            if let latestAfterAdd = desiredReminders[taskID],
               latestAfterAdd.schedulingGeneration == desired.schedulingGeneration,
               latestAfterAdd.taskGeneration == desired.taskGeneration,
               taskSchedulingGenerations[taskID] == desired.taskGeneration {
                await refreshPendingReminderCount()
                return
            }
        }
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func deniedResult(for status: UNAuthorizationStatus) -> ReminderEnableResult {
        switch status {
        case .notDetermined, .denied:
            return .permissionDenied
        case .authorized, .provisional, .ephemeral:
            return .enabled
        @unknown default:
            return .restricted
        }
    }
}
