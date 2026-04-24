import XCTest
@testable import Ch4ttr

final class CleanupServiceTests: XCTestCase {
    func testCollapsesAdjacentRepeatedWordsAcrossPunctuation() {
        let cleaned = CleanupService().cleanupText(
            "as. as. you see. see in this repo",
            language: .english,
            dictionary: []
        )

        XCTAssertEqual(cleaned, "As you see in this repo.")
    }

    func testCollapsesAdjacentRepeatedShortPhrases() {
        let cleaned = CleanupService().cleanupText(
            "I have a QMK layout. layout which has a hot. has a hot key key",
            language: .english,
            dictionary: []
        )

        XCTAssertEqual(cleaned, "I have a QMK layout which has a hot key.")
    }

    func testNormalizesMissingSpaceAfterPunctuation() {
        let cleaned = CleanupService().cleanupText(
            "I have a P36K.Layout AndHas a hotkey",
            language: .english,
            dictionary: []
        )

        XCTAssertEqual(cleaned, "I have a P36K. Layout And Has a hotkey.")
    }

    func testDictionaryExactReplacementIgnoresLowStrength() {
        let cleaned = CleanupService().cleanupText(
            "piano layout",
            language: .english,
            dictionary: [
                DictionaryEntry(
                    phrase: "piano",
                    replacement: "P36K",
                    replacementStrength: 0
                )
            ]
        )

        XCTAssertEqual(cleaned, "P36K layout.")
    }

    func testDictionaryHighStrengthAllowsFuzzyReplacement() {
        let cleaned = CleanupService().cleanupText(
            "I have a pianist layout",
            language: .english,
            dictionary: [
                DictionaryEntry(
                    phrase: "piano",
                    replacement: "P36K",
                    replacementStrength: 1
                )
            ]
        )

        XCTAssertEqual(cleaned, "I have a P36K layout.")
    }

    func testDictionaryLowStrengthRejectsFuzzyReplacement() {
        let cleaned = CleanupService().cleanupText(
            "I have a pianist layout",
            language: .english,
            dictionary: [
                DictionaryEntry(
                    phrase: "piano",
                    replacement: "P36K",
                    replacementStrength: 0
                )
            ]
        )

        XCTAssertEqual(cleaned, "I have a pianist layout.")
    }

    func testDictionaryChoosesStrongerFuzzyReplacement() {
        let cleaned = CleanupService().cleanupText(
            "I have a piantor layout",
            language: .english,
            dictionary: [
                DictionaryEntry(
                    phrase: "painter",
                    replacement: "Painter",
                    replacementStrength: 0.2
                ),
                DictionaryEntry(
                    phrase: "piano",
                    replacement: "P36K",
                    replacementStrength: 1
                )
            ]
        )

        XCTAssertEqual(cleaned, "I have a P36K layout.")
    }

    func testStreamingPartialSkipsForcedPeriodUntilFinal() {
        let svc = CleanupService()
        let partial = svc.cleanupStreamingPartial(
            "there is plenty",
            language: .english,
            dictionary: [],
            isUtteranceFinal: false
        )
        XCTAssertFalse(partial.hasSuffix("."))

        let final = svc.cleanupStreamingPartial(
            "there is plenty",
            language: .english,
            dictionary: [],
            isUtteranceFinal: true
        )
        XCTAssertTrue(final.hasSuffix("."))
    }

    func testPostProcessJoinedLiveDisplayCollapsesStreamingEcho() {
        let joined = "There's plenty of. There's plenty of space to be"
        let polished = CleanupService().postProcessJoinedLiveDisplay(
            joined,
            language: .english,
            dictionary: []
        )
        XCTAssertFalse(polished.contains("There's plenty of. There's plenty"))
        XCTAssertTrue(polished.localizedCaseInsensitiveContains("plenty of space"))
    }
}
