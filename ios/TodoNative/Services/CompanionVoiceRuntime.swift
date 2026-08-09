import AVFoundation
import Foundation
import Speech

enum CompanionVoicePermission: Equatable, Sendable {
    case authorized
    case denied
}

enum CompanionVoiceError: Error, Equatable, Sendable {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case noSpeechDetected
    case recognitionFailed
    case sessionFailed(String)
    case engineFailed(String)
}

extension CompanionVoiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return Localization.t("voice.speechPermissionDenied")
        case .microphonePermissionDenied:
            return Localization.t("voice.microphonePermissionDenied")
        case .recognizerUnavailable:
            return Localization.t("voice.speechUnavailable")
        case .noSpeechDetected:
            return Localization.t("voice.noSpeechDetected")
        case .recognitionFailed:
            return Localization.t("voice.recognitionFailed")
        case .sessionFailed(let message):
            return Localization.t("voice.sessionFailed", message)
        case .engineFailed(let message):
            return Localization.t("voice.engineFailed", message)
        }
    }
}

enum CompanionVoiceRuntimeEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
    case failure(CompanionVoiceError)
}

@MainActor
protocol CompanionVoiceRuntime: AnyObject {
    func requestSpeechPermission() async -> CompanionVoicePermission
    func requestMicrophonePermission() async -> CompanionVoicePermission
    func isRecognizerAvailable(locale: Locale) -> Bool
    func start(locale: Locale, onEvent: @escaping @MainActor @Sendable (CompanionVoiceRuntimeEvent) -> Void) throws
    func stop()
    func cancel()
}

@MainActor
final class SystemCompanionVoiceRuntime: CompanionVoiceRuntime {
    private let engine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var eventHandler: (@MainActor @Sendable (CompanionVoiceRuntimeEvent) -> Void)?
    private var sessionCounter: UInt64 = 0
    private var activeSessionToken: UInt64?
    private var isInputTapInstalled = false

    func requestSpeechPermission() async -> CompanionVoicePermission {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized ? .authorized : .denied)
                }
            }
        @unknown default:
            return .denied
        }
    }

    func requestMicrophonePermission() async -> CompanionVoicePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        default:
            return await AVAudioApplication.requestRecordPermission() ? .authorized : .denied
        }
    }

    func isRecognizerAvailable(locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }

    func start(locale: Locale, onEvent: @escaping @MainActor @Sendable (CompanionVoiceRuntimeEvent) -> Void) throws {
        cancel()
        sessionCounter &+= 1
        let sessionToken = sessionCounter
        activeSessionToken = sessionToken

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            cleanup(cancelRecognition: true, sessionToken: sessionToken)
            throw CompanionVoiceError.recognizerUnavailable
        }

        self.recognizer = recognizer
        eventHandler = onEvent

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            cleanup(cancelRecognition: true, sessionToken: sessionToken)
            throw CompanionVoiceError.sessionFailed(error.localizedDescription)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        isInputTapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanup(cancelRecognition: true, sessionToken: sessionToken)
            throw CompanionVoiceError.engineFailed(error.localizedDescription)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let event: CompanionVoiceRuntimeEvent?
            if let result {
                let transcript = result.bestTranscription.formattedString
                event = result.isFinal ? .final(transcript) : .partial(transcript)
            } else if error != nil {
                event = .failure(.recognitionFailed)
            } else {
                event = nil
            }
            guard let event else { return }
            Task { @MainActor [weak self] in
                self?.handleRecognitionEvent(event, sessionToken: sessionToken)
            }
        }
    }

    func stop() {
        guard activeSessionToken != nil else { return }
        recognitionRequest?.endAudio()
        if engine.isRunning {
            engine.stop()
        }
        removeInputTap()
        deactivateAudioSession()
    }

    func cancel() {
        cleanup(cancelRecognition: true, sessionToken: activeSessionToken)
    }

    private func handleRecognitionEvent(_ event: CompanionVoiceRuntimeEvent, sessionToken: UInt64) {
        guard activeSessionToken == sessionToken else { return }
        switch event {
        case .partial:
            eventHandler?(event)
        case .final(let transcript):
            let callback = eventHandler
            cleanup(cancelRecognition: false, sessionToken: sessionToken)
            if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                callback?(.failure(.noSpeechDetected))
            } else {
                callback?(event)
            }
        case .failure:
            let callback = eventHandler
            cleanup(cancelRecognition: true, sessionToken: sessionToken)
            callback?(event)
        }
    }

    private func cleanup(cancelRecognition: Bool, sessionToken: UInt64?) {
        guard sessionToken == nil || activeSessionToken == sessionToken else { return }
        if engine.isRunning {
            engine.stop()
        }
        removeInputTap()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if cancelRecognition {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        recognizer = nil
        eventHandler = nil
        activeSessionToken = nil
        deactivateAudioSession()
    }

    private func removeInputTap() {
        guard isInputTapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        isInputTapInstalled = false
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
