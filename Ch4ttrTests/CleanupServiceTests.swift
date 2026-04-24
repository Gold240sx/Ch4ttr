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

    func testCollapsesTripleLongDuplicateClause() {
        let phrase = "So I'm interested in building an app to replace whisper to be able to provide live voice transcription"
        let joined = "\(phrase) \(phrase) \(phrase)"
        let cleaned = CleanupService().cleanupText(joined, language: .english, dictionary: [])
        XCTAssertFalse(cleaned.contains("\(phrase) \(phrase)"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("replace whisper"))
    }

    func testCollapsesLongRunsWithSingleWordNearMiss() {
        let a = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo"
        let b = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilos"
        let joined = "\(a) \(b) \(a)"
        let polished = CleanupService().postProcessJoinedLiveDisplay(joined, language: .english, dictionary: [])
        XCTAssertFalse(polished.contains("\(a) \(b)"))
        XCTAssertTrue(polished.localizedCaseInsensitiveContains("juliet"))
    }

    func testCollapsesNearDuplicateClauseWithExtraTailWords() {
        let core = "If I had play then I can basically have it type and write whatever I am trying to have transcribed"
        let longer = "\(core) again there is hot keys and secondary passes"
        let joined = "\(core) \(longer)"
        let polished = CleanupService().postProcessJoinedLiveDisplay(joined, language: .english, dictionary: [])
        let wcJoined = joined.split { $0.isWhitespace }.count
        let wcPolished = polished.split { $0.isWhitespace }.count
        XCTAssertLessThan(wcPolished, wcJoined - 6, "Should drop most of the repeated clause, not stack both.")
        XCTAssertTrue(polished.localizedCaseInsensitiveContains("transcribed"))
    }

    func testCollapsesEqualLengthClauseWithSeveralSmallWordRewrites() {
        let a = "one two three four five six seven eight nine ten eleven twelve"
        let b = "one two three four fiev six seven eight nine ten eleven twelve"
        let joined = "\(a) \(b)"
        let polished = CleanupService().postProcessJoinedLiveDisplay(joined, language: .english, dictionary: [])
        XCTAssertFalse(polished.lowercased().contains("five") && polished.lowercased().contains("fiev"))
    }
}
