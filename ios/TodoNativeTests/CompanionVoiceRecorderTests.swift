import Foundation
import XCTest
@testable import TodoNative

@MainActor
final class CompanionVoiceRecorderTests: XCTestCase {
    func testStartRequestsSpeechThenMicrophoneBeforeRecording() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime, locale: Locale(identifier: "zh-CN"))

        await recorder.start()

        XCTAssertEqual(runtime.calls, ["speechPermission", "microphonePermission", "available", "start"])
        XCTAssertEqual(recorder.state, .recording)
    }

    func testSpeechPermissionDenialDoesNotRequestMicrophone() async {
        let runtime = FakeVoiceRuntime(speechPermission: .denied)
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()

        await recorder.start(onError: { output.errors.append($0) })

        XCTAssertEqual(output.errors, [.speechPermissionDenied])
        XCTAssertEqual(runtime.calls, ["speechPermission", "cancel"])
        XCTAssertEqual(recorder.state, .idle)
    }

    func testMicrophonePermissionDenialFollowsSpeechPermission() async {
        let runtime = FakeVoiceRuntime(microphonePermission: .denied)
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()

        await recorder.start(onError: { output.errors.append($0) })

        XCTAssertEqual(output.errors, [.microphonePermissionDenied])
        XCTAssertEqual(runtime.calls, ["speechPermission", "microphonePermission", "cancel"])
        XCTAssertEqual(recorder.state, .idle)
    }

    func testUnavailableRecognizerReportsTypedError() async {
        let runtime = FakeVoiceRuntime(recognizerAvailable: false)
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()

        await recorder.start(onError: { output.errors.append($0) })

        XCTAssertEqual(output.errors, [.recognizerUnavailable])
        XCTAssertEqual(runtime.calls, ["speechPermission", "microphonePermission", "available", "cancel"])
    }

    func testSecondStartWhileRecordingIsIgnored() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)

        await recorder.start()
        await recorder.start()

        XCTAssertEqual(runtime.calls, ["speechPermission", "microphonePermission", "available", "start"])
    }

    func testCancelWhilePermissionAwaitsPreventsLateStart() async {
        let runtime = FakeVoiceRuntime(suspendSpeechPermission: true)
        let recorder = CompanionVoiceRecorder(runtime: runtime)

        let start = Task { @MainActor in
            await recorder.start()
        }
        await runtime.waitForSpeechPermissionRequestToStart()
        recorder.cancel()
        runtime.resumeSpeechPermission(with: .authorized)
        await start.value

        XCTAssertEqual(runtime.calls, ["speechPermission", "cancel"])
        XCTAssertEqual(recorder.state, .idle)
    }

    func testCancelledPermissionResultCannotCancelImmediateRestart() async {
        let runtime = FakeVoiceRuntime(suspendSpeechPermission: true)
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()

        let firstStart = Task { @MainActor in
            await recorder.start(onError: { output.errors.append($0) })
        }
        await runtime.waitForSpeechPermissionRequestToStart()
        recorder.cancel()

        await recorder.start(onError: { output.errors.append($0) })
        XCTAssertEqual(recorder.state, .recording)

        runtime.resumeSpeechPermission(with: .denied)
        await firstStart.value

        XCTAssertEqual(recorder.state, .recording)
        XCTAssertTrue(output.errors.isEmpty)
        XCTAssertEqual(runtime.cancelCount, 1)
    }

    func testQueuedEventFromCancelledSessionCannotReachRestart() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()

        await recorder.start(onError: { output.errors.append($0) })
        recorder.cancel()
        await recorder.start(onError: { output.errors.append($0) })

        runtime.emit(.failure(.recognitionFailed), session: 0)

        XCTAssertEqual(recorder.state, .recording)
        XCTAssertTrue(output.errors.isEmpty)
        XCTAssertEqual(runtime.cancelCount, 1)
    }

    func testCompatibilityStartCleansUpBeforeThrowing() async {
        let runtime = FakeVoiceRuntime(speechPermission: .denied)
        let recorder = CompanionVoiceRecorder(runtime: runtime)

        do {
            try await recorder.start(onTranscript: { _ in })
            XCTFail("Expected permission error")
        } catch {
            XCTAssertEqual(error as? CompanionVoiceError, .speechPermissionDenied)
        }

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(runtime.cancelCount, 1)
    }

    func testPartialIsPublishedWithoutFinishing() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()
        await recorder.start(onPartial: { output.partials.append($0) })

        runtime.emit(.partial("临时识别"))

        XCTAssertEqual(output.partials, ["临时识别"])
        XCTAssertTrue(output.finals.isEmpty)
        XCTAssertEqual(recorder.state, .recording)
    }

    func testStopFinalizesAndFinalEventFinishesExactlyOnce() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()
        await recorder.start(onFinal: { output.finals.append($0) })

        recorder.stop()
        runtime.emit(.final("最终结果"))
        runtime.emit(.final("重复结果"))

        XCTAssertEqual(output.finals, ["最终结果"])
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(runtime.stopCount, 1)
    }

    func testFinalizingTimesOutAndReleasesRuntime() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime, finalizationTimeoutNanoseconds: 5_000_000)
        let output = VoiceOutput()
        await recorder.start(onError: { output.errors.append($0) })

        recorder.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(output.errors, [.noSpeechDetected])
        XCTAssertEqual(runtime.cancelCount, 1)
    }

    func testFinalEventCancelsFinalizationTimeout() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime, finalizationTimeoutNanoseconds: 5_000_000)
        let output = VoiceOutput()
        await recorder.start(onFinal: { output.finals.append($0) }, onError: { output.errors.append($0) })

        recorder.stop()
        runtime.emit(.final("完成"))
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(output.finals, ["完成"])
        XCTAssertTrue(output.errors.isEmpty)
        XCTAssertEqual(runtime.cancelCount, 0)
    }

    func testEmptyFinalIsReportedAsNoSpeech() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()
        await recorder.start(
            onFinal: { output.finals.append($0) },
            onError: { output.errors.append($0) }
        )

        runtime.emit(.final(" \n "))

        XCTAssertTrue(output.finals.isEmpty)
        XCTAssertEqual(output.errors, [.noSpeechDetected])
        XCTAssertEqual(recorder.state, .idle)
    }

    func testNoSpeechErrorReturnsToIdle() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()
        await recorder.start(onError: { output.errors.append($0) })

        runtime.emit(.failure(.noSpeechDetected))

        XCTAssertEqual(output.errors, [.noSpeechDetected])
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(runtime.cancelCount, 1)
    }

    func testCancelDoesNotPublishFinalAndIsIdempotent() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()
        await recorder.start(onFinal: { output.finals.append($0) })

        recorder.cancel()
        recorder.cancel()
        runtime.emit(.final("不应交付"))

        XCTAssertTrue(output.finals.isEmpty)
        XCTAssertEqual(runtime.cancelCount, 1)
        XCTAssertEqual(recorder.state, .idle)
    }

    func testRecognitionFailureClearsCallbacks() async {
        let runtime = FakeVoiceRuntime()
        let recorder = CompanionVoiceRecorder(runtime: runtime)
        let output = VoiceOutput()
        await recorder.start(onPartial: { output.partials.append($0) }, onError: { output.errors.append($0) })

        runtime.emit(.failure(.recognitionFailed))
        runtime.emit(.partial("不应交付"))

        XCTAssertEqual(output.errors, [.recognitionFailed])
        XCTAssertTrue(output.partials.isEmpty)
        XCTAssertEqual(recorder.state, .idle)
    }

}

@MainActor
private final class VoiceOutput {
    var partials: [String] = []
    var finals: [String] = []
    var errors: [CompanionVoiceError] = []
}

@MainActor
private final class FakeVoiceRuntime: CompanionVoiceRuntime {
    private let speechPermission: CompanionVoicePermission
    private let microphonePermission: CompanionVoicePermission
    private let recognizerAvailable: Bool
    private var suspendedSpeechPermissionRequests: Int
    private var pendingSpeechPermissions: [CheckedContinuation<CompanionVoicePermission, Never>] = []
    private var speechPermissionRequestStarted = false
    private var speechPermissionRequestStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var eventHandlers: [(@MainActor @Sendable (CompanionVoiceRuntimeEvent) -> Void)] = []

    private(set) var calls: [String] = []
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    init(
        speechPermission: CompanionVoicePermission = .authorized,
        microphonePermission: CompanionVoicePermission = .authorized,
        recognizerAvailable: Bool = true,
        suspendSpeechPermission: Bool = false
    ) {
        self.speechPermission = speechPermission
        self.microphonePermission = microphonePermission
        self.recognizerAvailable = recognizerAvailable
        suspendedSpeechPermissionRequests = suspendSpeechPermission ? 1 : 0
    }

    func requestSpeechPermission() async -> CompanionVoicePermission {
        calls.append("speechPermission")
        speechPermissionRequestStarted = true
        speechPermissionRequestStartWaiters.forEach { $0.resume() }
        speechPermissionRequestStartWaiters.removeAll()
        guard suspendedSpeechPermissionRequests > 0 else { return speechPermission }
        suspendedSpeechPermissionRequests -= 1
        return await withCheckedContinuation { pendingSpeechPermissions.append($0) }
    }

    func waitForSpeechPermissionRequestToStart() async {
        if speechPermissionRequestStarted { return }
        await withCheckedContinuation { continuation in
            speechPermissionRequestStartWaiters.append(continuation)
        }
    }

    func requestMicrophonePermission() async -> CompanionVoicePermission {
        calls.append("microphonePermission")
        return microphonePermission
    }

    func isRecognizerAvailable(locale: Locale) -> Bool {
        calls.append("available")
        return recognizerAvailable
    }

    func start(locale: Locale, onEvent: @escaping @MainActor @Sendable (CompanionVoiceRuntimeEvent) -> Void) throws {
        calls.append("start")
        eventHandlers.append(onEvent)
    }

    func stop() {
        stopCount += 1
        calls.append("stop")
    }

    func cancel() {
        cancelCount += 1
        calls.append("cancel")
    }

    func resumeSpeechPermission(with permission: CompanionVoicePermission) {
        guard !pendingSpeechPermissions.isEmpty else { return }
        pendingSpeechPermissions.removeFirst().resume(returning: permission)
    }

    func emit(_ event: CompanionVoiceRuntimeEvent, session: Int? = nil) {
        guard let index = session ?? eventHandlers.indices.last else { return }
        eventHandlers[index](event)
    }
}
