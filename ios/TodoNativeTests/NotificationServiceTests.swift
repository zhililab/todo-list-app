import XCTest
import UserNotifications
@testable import TodoNative

@MainActor
private final class FakeNotificationCenterClient: NotificationCenterClient {
    var status: UNAuthorizationStatus
    var authorizationResult = true
    var statusAfterAuthorization: UNAuthorizationStatus?
    var requests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var pauseAdds = false
    var pauseAuthorizationRequests = false
    var onAdd: ((UNNotificationRequest) -> Void)?
    var onRemove: (([String]) -> Void)?
    private var addStarted = false
    private var addStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var addedIdentifiers: Set<String> = []
    private var addedWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var pendingAdd: (UNNotificationRequest, CheckedContinuation<Void, Never>)?
    private var authorizationRequestStarted = false
    private var authorizationRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingAuthorizationRequest: CheckedContinuation<Void, Never>?

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequestStarted = true
        authorizationRequestWaiters.forEach { $0.resume() }
        authorizationRequestWaiters.removeAll()
        if pauseAuthorizationRequests {
            await withCheckedContinuation { continuation in
                pendingAuthorizationRequest = continuation
            }
        }
        if authorizationResult, let statusAfterAuthorization {
            status = statusAfterAuthorization
        }
        return authorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        if pauseAdds {
            pauseAdds = false
            addStarted = true
            addStartedWaiters.forEach { $0.resume() }
            addStartedWaiters.removeAll()
            await withCheckedContinuation { continuation in
                pendingAdd = (request, continuation)
            }
        }
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
        addedIdentifiers.insert(request.identifier)
        addedWaiters.removeValue(forKey: request.identifier)?.forEach { $0.resume() }
        onAdd?(request)
    }

    func pendingRequestIdentifiers() async -> [String] {
        requests.map(\.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        requests.removeAll { identifiers.contains($0.identifier) }
        onRemove?(identifiers)
    }

    func waitForAddToStart() async {
        if addStarted { return }
        await withCheckedContinuation { continuation in
            addStartedWaiters.append(continuation)
        }
    }

    func waitForAdded(identifier: String) async {
        if addedIdentifiers.contains(identifier) { return }
        await withCheckedContinuation { continuation in
            addedWaiters[identifier, default: []].append(continuation)
        }
    }

    func waitForAuthorizationRequestToStart() async {
        if authorizationRequestStarted { return }
        await withCheckedContinuation { continuation in
            authorizationRequestWaiters.append(continuation)
        }
    }

    func finishPendingAdd() {
        let continuation = pendingAdd?.1
        pendingAdd = nil
        continuation?.resume()
    }

    func finishPendingAuthorizationRequest() {
        let continuation = pendingAuthorizationRequest
        pendingAuthorizationRequest = nil
        continuation?.resume()
    }
}

@MainActor
final class NotificationServiceTests: XCTestCase {
    private var calendar: Calendar { Calendar.current }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NotificationServiceTests.\(UUID().uuidString)")!
    }

    private func makeRequest(_ identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
    }

    private func date(_ daysFromNow: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let base = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testFutureDateTriggersAtUserChosenTime() {
        let now = date(0, hour: 10)
        let due = date(3, hour: 18, minute: 30)

        XCTAssertEqual(
            NotificationService.triggerDate(for: due, now: now).timeIntervalSinceReferenceDate,
            due.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testTodayChosenTimeStillInFutureTriggersAtThatTime() {
        let now = date(0, hour: 10)
        let due = date(0, hour: 15)

        XCTAssertEqual(NotificationService.triggerDate(for: due, now: now), due)
    }

    func testTodayChosenTimeAlreadyPassedTriggersWithMinimumInterval() {
        let now = date(0, hour: 10)
        let due = date(0, hour: 9)

        let fired = NotificationService.triggerDate(for: due, now: now)
        XCTAssertGreaterThanOrEqual(fired.timeIntervalSince(now), 60)
    }

    func testPastDateTriggersWithMinimumInterval() {
        let now = date(0, hour: 10)
        let due = date(-2, hour: 15)

        let fired = NotificationService.triggerDate(for: due, now: now)
        XCTAssertGreaterThanOrEqual(fired.timeIntervalSince(now), 60)
    }

    func testFarPastDateUsesAtLeastOneMinuteInterval() {
        let now = date(0, hour: 10)
        let due = date(-10)

        let fired = NotificationService.triggerDate(for: due, now: now)
        XCTAssertGreaterThanOrEqual(fired.timeIntervalSince(now), 60)
    }

    func testReminderIdentifierUsesTaskPrefix() {
        let id = UUID()

        XCTAssertEqual(NotificationService.reminderIdentifier(for: id), "task-reminder.\(id.uuidString)")
    }

    func testDebugIdentifierIsNotCountedAsReminder() {
        XCTAssertFalse(NotificationService.isReminderIdentifier("test-notification-123"))
    }

    func testRefreshMigratesAuthorizedUsersWithoutStoredPreferenceToEnabled() async {
        let defaults = makeDefaults()
        let client = FakeNotificationCenterClient(status: .authorized)
        let service = NotificationService(client: client, defaults: defaults)

        await service.refresh()

        XCTAssertTrue(service.isRemindersEnabled)
        XCTAssertEqual(defaults.object(forKey: NotificationService.enabledKey) as? Bool, true)
    }

    func testEnablingWithAuthorizedSystemStatusPersistsPreference() async {
        let defaults = makeDefaults()
        let service = NotificationService(
            client: FakeNotificationCenterClient(status: .authorized),
            defaults: defaults
        )

        let result = await service.setRemindersEnabled(true)

        XCTAssertEqual(result, .enabled)
        XCTAssertTrue(service.isRemindersEnabled)
        XCTAssertEqual(defaults.object(forKey: NotificationService.enabledKey) as? Bool, true)
    }

    func testEnablingWithProvisionalSystemStatusSucceeds() async {
        let service = NotificationService(
            client: FakeNotificationCenterClient(status: .provisional),
            defaults: makeDefaults()
        )

        let result = await service.setRemindersEnabled(true)
        XCTAssertEqual(result, .enabled)
    }

    func testEnablingRequestsUndeterminedPermissionAndSavesGrantedResult() async {
        let client = FakeNotificationCenterClient(status: .notDetermined)
        client.statusAfterAuthorization = .authorized
        let service = NotificationService(client: client, defaults: makeDefaults())

        let result = await service.setRemindersEnabled(true)
        XCTAssertEqual(result, .enabled)
        XCTAssertTrue(service.isRemindersEnabled)
    }

    func testLateAuthorizationGrantCannotOverrideNewerDisable() async {
        let defaults = makeDefaults()
        let client = FakeNotificationCenterClient(status: .notDetermined)
        client.statusAfterAuthorization = .authorized
        client.pauseAuthorizationRequests = true
        let service = NotificationService(client: client, defaults: defaults)

        let enabling = Task { await service.setRemindersEnabled(true) }
        await client.waitForAuthorizationRequestToStart()
        let disableResult = await service.setRemindersEnabled(false)
        client.finishPendingAuthorizationRequest()
        let enableResult = await enabling.value

        XCTAssertEqual(disableResult, .disabled)
        XCTAssertEqual(enableResult, .disabled)
        XCTAssertFalse(service.isRemindersEnabled)
        XCTAssertEqual(defaults.object(forKey: NotificationService.enabledKey) as? Bool, false)
    }

    func testEnablingReturnsPermissionDeniedWhenUndeterminedPermissionIsRejected() async {
        let client = FakeNotificationCenterClient(status: .notDetermined)
        client.authorizationResult = false
        client.statusAfterAuthorization = .denied
        let service = NotificationService(client: client, defaults: makeDefaults())

        let result = await service.setRemindersEnabled(true)

        XCTAssertEqual(result, .permissionDenied)
        XCTAssertFalse(service.isRemindersEnabled)
    }

    func testEnablingReturnsPermissionDeniedWhenSystemIsDenied() async {
        let service = NotificationService(
            client: FakeNotificationCenterClient(status: .denied),
            defaults: makeDefaults()
        )

        let result = await service.setRemindersEnabled(true)
        XCTAssertEqual(result, .permissionDenied)
        XCTAssertFalse(service.isRemindersEnabled)
    }

    func testEnablingReturnsRestrictedWhenSystemIsRestricted() async {
        let service = NotificationService(
            client: FakeNotificationCenterClient(status: UNAuthorizationStatus(rawValue: 99)!),
            defaults: makeDefaults()
        )

        let result = await service.setRemindersEnabled(true)
        XCTAssertEqual(result, .restricted)
    }

    func testRefreshReflectsRevokedSystemAuthorizationWithoutChangingPreference() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: NotificationService.enabledKey)
        let client = FakeNotificationCenterClient(status: .authorized)
        let service = NotificationService(client: client, defaults: defaults)

        await service.refresh()
        client.status = .denied
        await service.refresh()

        XCTAssertTrue(service.isRemindersEnabled)
        XCTAssertEqual(service.systemAuthorizationStatus, .denied)
    }

    func testEnabledServiceSchedulesTaskReminder() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let service = NotificationService(client: client, defaults: makeDefaults())
        await service.refresh()
        let taskID = UUID()
        let identifier = NotificationService.reminderIdentifier(for: taskID)

        service.scheduleDueReminder(taskID: taskID, title: "未来任务", dueDate: Date().addingTimeInterval(3600))
        await client.waitForAdded(identifier: identifier)

        XCTAssertEqual(client.requests.map(\.identifier), [identifier])
    }

    func testDisabledServiceDoesNotScheduleTaskReminder() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let service = NotificationService(client: client, defaults: makeDefaults())
        await service.refresh()
        _ = await service.setRemindersEnabled(false)

        service.scheduleDueReminder(taskID: UUID(), title: "不会调度", dueDate: Date().addingTimeInterval(3600))

        XCTAssertTrue(client.requests.isEmpty)
    }

    func testCancelReminderRemovesNamespacedAndLegacyIdentifiers() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let service = NotificationService(client: client, defaults: makeDefaults())
        let taskID = UUID()
        client.requests = [
            makeRequest(NotificationService.reminderIdentifier(for: taskID)),
            makeRequest(taskID.uuidString),
            makeRequest("test-notification-unrelated")
        ]

        service.cancelReminder(taskID: taskID)

        XCTAssertEqual(Set(client.removedIdentifiers), Set([
            NotificationService.reminderIdentifier(for: taskID),
            taskID.uuidString
        ]))
        XCTAssertEqual(client.requests.map(\.identifier), ["test-notification-unrelated"])
    }

    func testDisablingCancelsOnlyTaskReminderIdentifiers() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let service = NotificationService(client: client, defaults: makeDefaults())
        let taskID = UUID()
        client.requests = [
            makeRequest(NotificationService.reminderIdentifier(for: taskID)),
            makeRequest(taskID.uuidString),
            makeRequest("test-notification-unrelated")
        ]
        await service.refresh()

        let result = await service.setRemindersEnabled(false, legacyTaskIDs: [taskID])
        XCTAssertEqual(result, .disabled)

        XCTAssertEqual(client.requests.map(\.identifier), ["test-notification-unrelated"])
        XCTAssertEqual(service.pendingReminderCount, 0)
    }

    func testCancelAllPreservesUnrelatedBareUUIDNotification() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let service = NotificationService(client: client, defaults: makeDefaults())
        let taskID = UUID()
        let unrelatedID = UUID()
        client.requests = [
            makeRequest(NotificationService.reminderIdentifier(for: taskID)),
            makeRequest(taskID.uuidString),
            makeRequest(unrelatedID.uuidString)
        ]

        await service.cancelAllReminders(legacyTaskIDs: [taskID])

        XCTAssertEqual(client.requests.map(\.identifier), [unrelatedID.uuidString])
    }

    func testDisableWinsAgainstAnInFlightSchedule() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        client.pauseAdds = true
        let service = NotificationService(client: client, defaults: makeDefaults())
        await service.refresh()
        let taskID = UUID()
        let identifier = NotificationService.reminderIdentifier(for: taskID)
        let lateRemoval = expectation(description: "late reminder is removed")
        client.onRemove = { identifiers in
            if identifiers.contains(identifier) { lateRemoval.fulfill() }
        }

        service.scheduleDueReminder(taskID: taskID, title: "竞态任务", dueDate: Date().addingTimeInterval(3600))
        await client.waitForAddToStart()
        _ = await service.setRemindersEnabled(false)
        client.finishPendingAdd()
        await fulfillment(of: [lateRemoval], timeout: 1)

        XCTAssertFalse(client.requests.contains { $0.identifier == identifier })
    }

    func testCancelWinsAgainstAnInFlightScheduleForSameTask() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        client.pauseAdds = true
        let service = NotificationService(client: client, defaults: makeDefaults())
        await service.refresh()
        let taskID = UUID()
        let identifier = NotificationService.reminderIdentifier(for: taskID)
        let lateRemoval = expectation(description: "cancelled late reminder is removed")
        var namespacedRemovalCount = 0
        client.onRemove = { identifiers in
            guard identifiers.contains(identifier) else { return }
            namespacedRemovalCount += 1
            if namespacedRemovalCount == 2 { lateRemoval.fulfill() }
        }

        service.scheduleDueReminder(taskID: taskID, title: "稍后取消", dueDate: Date().addingTimeInterval(3600))
        await client.waitForAddToStart()
        service.cancelReminder(taskID: taskID)
        client.finishPendingAdd()
        await fulfillment(of: [lateRemoval], timeout: 1)

        XCTAssertFalse(client.requests.contains { $0.identifier == identifier })
    }

    func testLateOlderScheduleCannotDeleteNewerReminderForSameTask() async throws {
        let client = FakeNotificationCenterClient(status: .authorized)
        client.pauseAdds = true
        let service = NotificationService(client: client, defaults: makeDefaults())
        await service.refresh()
        let taskID = UUID()
        let identifier = NotificationService.reminderIdentifier(for: taskID)
        let latestReminderRestored = expectation(description: "latest reminder is restored after stale add")
        var olderScheduleHasResumed = false
        client.onAdd = { request in
            if olderScheduleHasResumed, request.content.body.contains("最新任务") {
                latestReminderRestored.fulfill()
            }
        }

        service.scheduleDueReminder(
            taskID: taskID,
            title: "旧任务",
            dueDate: Date().addingTimeInterval(3_600)
        )
        await client.waitForAddToStart()

        service.scheduleDueReminder(
            taskID: taskID,
            title: "最新任务",
            dueDate: Date().addingTimeInterval(7_200)
        )
        await client.waitForAdded(identifier: identifier)

        olderScheduleHasResumed = true
        client.finishPendingAdd()
        await fulfillment(of: [latestReminderRestored], timeout: 1)

        let finalRequest = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(finalRequest.content.body.contains("最新任务"))
        let trigger = try XCTUnwrap(finalRequest.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertGreaterThan(trigger.timeInterval, 7_000)
    }
}
