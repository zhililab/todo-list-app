import AVFoundation
import Speech

// 伙伴语音输入：SFSpeechRecognizer（zh-CN / en-US 跟随语言设置）+ AVAudioEngine 实时辨识。
@MainActor
final class CompanionVoiceRecorder: ObservableObject {
    enum MicState {
        case idle
        case recording
    }

    enum VoiceError: LocalizedError {
        case speechUnavailable
        case permissionDenied
        case sessionFailed(message: String)
        case engineFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .speechUnavailable:
                return Localization.t("voice.speechUnavailable")
            case .permissionDenied:
                return Localization.t("voice.micPermissionDenied")
            case .sessionFailed(let message):
                return Localization.t("voice.sessionFailed", message)
            case .engineFailed(let message):
                return Localization.t("voice.engineFailed", message)
            }
        }
    }

    @Published var state: MicState = .idle
    @Published var transcript = ""

    private let engine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var onTranscript: ((String) -> Void)?

    var isRecording: Bool { state == .recording }

    static var speechLocale: Locale {
        Locale(identifier: Localization.currentLanguage == "en" ? "en-US" : "zh-CN")
    }

    // 请求/检查语音识别权限；被拒返回 false（由视图弹提示）
    func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor in
                        continuation.resume(returning: status == .authorized)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    func start(onTranscript: @escaping (String) -> Void) async throws {
        guard await ensureMicrophonePermission() else {
            throw VoiceError.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: Self.speechLocale),
              recognizer.isAvailable else {
            throw VoiceError.speechUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceError.sessionFailed(message: error.localizedDescription)
        }

        self.recognizer = recognizer
        self.onTranscript = onTranscript

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw VoiceError.engineFailed(message: error.localizedDescription)
        }

        transcript = ""
        state = .recording

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.onTranscript?(self.transcript)
                }
                if error != nil || result?.isFinal == true {
                    self.stop(callingTranscript: false)
                }
            }
        }
    }

    func stop() {
        stop(callingTranscript: true)
    }

    private func stop(callingTranscript: Bool) {
        guard state == .recording else { return }
        let final = transcript
        cleanup()
        state = .idle
        if callingTranscript && !final.isEmpty {
            onTranscript?(final)
        }
        onTranscript = nil
        transcript = ""
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }

    private func cleanup() {
        if engine.isRunning {
            engine.stop()
        }
        if engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
    }
}