import XCTest
@testable import TodoNative

@MainActor
final class CompanionComposerStateTests: XCTestCase {
    func testDefaultsToKeyboardMode() {
        let composer = CompanionComposerState()

        XCTAssertEqual(composer.mode, .keyboard)
    }

    func testSwitchingToVoicePreservesDraftForCancellation() {
        var composer = CompanionComposerState()

        composer.switchToVoice()
        composer.beginRecording(currentDraft: "已有草稿")

        XCTAssertEqual(composer.mode, .voice)
        XCTAssertEqual(composer.cancelRecording(), "已有草稿")
        XCTAssertEqual(composer.mode, .keyboard)
    }

    func testFinishRecordingUsesTrimmedTranscriptForEmptyDraft() {
        var composer = CompanionComposerState()
        composer.switchToVoice()
        composer.beginRecording(currentDraft: "")

        XCTAssertEqual(composer.finishRecording(transcript: "  记录明天的会议  "), "记录明天的会议")
        XCTAssertEqual(composer.mode, .keyboard)
    }

    func testFinishRecordingAppendsTranscriptToExistingDraft() {
        var composer = CompanionComposerState()
        composer.switchToVoice()
        composer.beginRecording(currentDraft: "提醒我")

        XCTAssertEqual(composer.finishRecording(transcript: "  联系客户  "), "提醒我 联系客户")
    }

    func testFinishRecordingWithEmptyTranscriptKeepsExistingDraft() {
        var composer = CompanionComposerState()
        composer.switchToVoice()
        composer.beginRecording(currentDraft: "保留这段")

        XCTAssertEqual(composer.finishRecording(transcript: " \n "), "保留这段")
        XCTAssertEqual(composer.mode, .keyboard)
    }

    func testSwitchBackBeforeRecordingReturnsToKeyboard() {
        var composer = CompanionComposerState()

        composer.switchToVoice()
        composer.switchToKeyboard()

        XCTAssertEqual(composer.mode, .keyboard)
        XCTAssertNil(composer.cancelRecording())
    }
}
