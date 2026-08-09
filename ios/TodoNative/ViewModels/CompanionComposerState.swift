import Foundation

struct CompanionComposerState: Equatable {
    enum Mode: Equatable {
        case keyboard
        case voice
    }

    private(set) var mode: Mode = .keyboard
    private var draftBeforeRecording: String?

    mutating func switchToVoice() {
        mode = .voice
    }

    mutating func switchToKeyboard() {
        mode = .keyboard
    }

    mutating func beginRecording(currentDraft: String) {
        draftBeforeRecording = currentDraft
    }

    mutating func finishRecording(transcript: String) -> String {
        let finalDraft = Self.mergedDraft(existing: draftBeforeRecording ?? "", transcript: transcript)
        draftBeforeRecording = nil
        mode = .keyboard
        return finalDraft
    }

    mutating func cancelRecording() -> String? {
        let draft = draftBeforeRecording
        draftBeforeRecording = nil
        mode = .keyboard
        return draft
    }

    static func mergedDraft(existing: String, transcript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return existing }
        guard !existing.isEmpty else { return trimmedTranscript }
        return "\(existing) \(trimmedTranscript)"
    }
}
