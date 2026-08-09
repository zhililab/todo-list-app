import Combine
import Foundation

@MainActor
final class CompanionVoiceRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case finalizing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""

    private let runtime: any CompanionVoiceRuntime
    private let locale: Locale
    private let finalizationTimeoutNanoseconds: UInt64
    private var onPartial: (@MainActor @Sendable (String) -> Void)?
    private var onFinal: (@MainActor @Sendable (String) -> Void)?
    private var onError: (@MainActor @Sendable (CompanionVoiceError) -> Void)?
    private var generation: UInt64 = 0
    private var activeGeneration: UInt64?
    private var finalizationTask: Task<Void, Never>?

    var isRecording: Bool { state == .recording }

    static var speechLocale: Locale {
        Locale(identifier: Localization.currentLanguage == "en" ? "en-US" : "zh-CN")
    }

    init(
        runtime: any CompanionVoiceRuntime = SystemCompanionVoiceRuntime(),
        locale: Locale = CompanionVoiceRecorder.speechLocale,
        finalizationTimeoutNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.runtime = runtime
        self.locale = locale
        self.finalizationTimeoutNanoseconds = finalizationTimeoutNanoseconds
    }

    func start(
        onPartial: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        onFinal: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        onError: @escaping @MainActor @Sendable (CompanionVoiceError) -> Void = { _ in }
    ) async {
        do {
            try await begin(onPartial: onPartial, onFinal: onFinal, onError: onError)
        } catch {
            // `begin` has already cleaned up and delivered the typed error.
        }
    }

    // Compatibility bridge for the existing composer. New callers should keep
    // partial and final transcription handlers separate.
    func start(onTranscript: @escaping @MainActor @Sendable (String) -> Void) async throws {
        try await begin(onPartial: onTranscript, onFinal: onTranscript, onError: { _ in })
    }

    func stop() {
        guard state == .recording, let currentGeneration = activeGeneration else { return }
        state = .finalizing
        runtime.stop()
        scheduleFinalizationTimeout(for: currentGeneration)
    }

    func cancel() {
        guard state != .idle, let currentGeneration = activeGeneration else { return }
        runtime.cancel()
        reset(generation: currentGeneration)
    }

    private func begin(
        onPartial: @escaping @MainActor @Sendable (String) -> Void,
        onFinal: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (CompanionVoiceError) -> Void
    ) async throws {
        guard state == .idle else { return }

        generation &+= 1
        let currentGeneration = generation
        activeGeneration = currentGeneration

        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onError = onError
        transcript = ""
        state = .requestingPermission

        do {
            let speechPermission = await runtime.requestSpeechPermission()
            guard isActive(currentGeneration, state: .requestingPermission) else { return }
            guard speechPermission == .authorized else {
                throw CompanionVoiceError.speechPermissionDenied
            }

            let microphonePermission = await runtime.requestMicrophonePermission()
            guard isActive(currentGeneration, state: .requestingPermission) else { return }
            guard microphonePermission == .authorized else {
                throw CompanionVoiceError.microphonePermissionDenied
            }

            guard runtime.isRecognizerAvailable(locale: locale) else {
                throw CompanionVoiceError.recognizerUnavailable
            }
            guard isActive(currentGeneration, state: .requestingPermission) else { return }

            state = .recording
            try runtime.start(locale: locale) { [weak self] event in
                self?.handle(event, generation: currentGeneration)
            }
        } catch let error as CompanionVoiceError {
            deliver(error, generation: currentGeneration)
            throw error
        } catch {
            let voiceError = CompanionVoiceError.recognitionFailed
            deliver(voiceError, generation: currentGeneration)
            throw voiceError
        }
    }

    private func handle(_ event: CompanionVoiceRuntimeEvent, generation currentGeneration: UInt64) {
        guard activeGeneration == currentGeneration else { return }
        switch event {
        case .partial(let partial):
            guard state == .recording else { return }
            transcript = partial
            onPartial?(partial)

        case .final(let final):
            guard state == .recording || state == .finalizing else { return }
            guard !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                deliver(.noSpeechDetected, generation: currentGeneration)
                return
            }
            let callback = onFinal
            reset(generation: currentGeneration)
            callback?(final)

        case .failure(let error):
            guard state != .idle else { return }
            deliver(error, generation: currentGeneration)
        }
    }

    private func deliver(_ error: CompanionVoiceError, generation currentGeneration: UInt64) {
        guard activeGeneration == currentGeneration else { return }
        let callback = onError
        runtime.cancel()
        reset(generation: currentGeneration)
        callback?(error)
    }

    private func scheduleFinalizationTimeout(for currentGeneration: UInt64) {
        finalizationTask?.cancel()
        let timeout = finalizationTimeoutNanoseconds
        finalizationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, let self else { return }
            guard self.isActive(currentGeneration, state: .finalizing) else { return }
            let error: CompanionVoiceError = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .noSpeechDetected
                : .recognitionFailed
            self.deliver(error, generation: currentGeneration)
        }
    }

    private func isActive(_ currentGeneration: UInt64, state expectedState: State) -> Bool {
        activeGeneration == currentGeneration && state == expectedState
    }

    private func reset(generation currentGeneration: UInt64) {
        guard activeGeneration == currentGeneration else { return }
        activeGeneration = nil
        finalizationTask?.cancel()
        finalizationTask = nil
        state = .idle
        transcript = ""
        onPartial = nil
        onFinal = nil
        onError = nil
    }
}
