import XCTest
@testable import Ch4ttr

final class VoiceCommandServiceTests: XCTestCase {
    func testRestartClearsPreviousTextAndKeepsFollowingDictation() {
        let result = VoiceCommandService().apply(
            to: "Keep the bad version chatter restart keep the better version"
        )

        XCTAssertEqual(result.text, "keep the better version")
        XCTAssertTrue(result.handledCommand)
        XCTAssertFalse(result.shouldStopRecording)
    }

    func testRestartParagraphKeepsPreviousSentence() {
        let result = VoiceCommandService().apply(
            to: "Keep this sentence. Remove this sentence chatter restart paragraph write this instead"
        )

        XCTAssertEqual(result.text, "Keep this sentence. write this instead")
        XCTAssertTrue(result.handledCommand)
        XCTAssertFalse(result.shouldStopRecording)
    }

    func testStartBeginsKeptTranscriptAfterCommand() {
        let result = VoiceCommandService().apply(
            to: "noise before the command chatter start this is the keeper"
        )

        XCTAssertEqual(result.text, "this is the keeper")
        XCTAssertTrue(result.handledCommand)
        XCTAssertFalse(result.shouldStopRecording)
    }

    func testEndStopsAndDropsCommandAndFollowingWords() {
        let result = VoiceCommandService().apply(
            to: "this should remain chatter end this should be ignored"
        )

        XCTAssertEqual(result.text, "this should remain")
        XCTAssertTrue(result.handledCommand)
        XCTAssertTrue(result.shouldStopRecording)
    }

    func testUnknownChatterMentionIsPreserved() {
        let result = VoiceCommandService().apply(
            to: "I am talking about the Chatter app"
        )

        XCTAssertEqual(result.text, "I am talking about the Chatter app")
        XCTAssertFalse(result.handledCommand)
        XCTAssertFalse(result.shouldStopRecording)
    }
}
