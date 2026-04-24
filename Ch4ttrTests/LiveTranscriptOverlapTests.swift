import XCTest
@testable import Ch4ttr

final class LiveTranscriptOverlapTests: XCTestCase {
    func testLongestSuffixPrefixOverlap() {
        let tail = "one two three four five six"
        let previous = "prefix words " + tail
        let next = tail + " seven eight nine"
        XCTAssertEqual(LiveTranscriptOverlap.longestSuffixPrefixOverlapWordCount(previous: previous, next: next), 6)
    }

    func testSplitRemovesSharedClause() {
        let tail = "my voice into any type of text field in any application"
        let previous = "I am trying to build a replacement " + tail
        let next = tail + " but one that is built natively"
        let split = LiveTranscriptOverlap.splitNonRefinementUpdate(previous: previous, next: next)
        XCTAssertFalse(split.head.contains(tail), "Shared tail should move out of committed head.")
        XCTAssertTrue(split.tail.hasPrefix("but"), "Unstable tail should continue after the overlap.")
        XCTAssertFalse((split.head + " " + split.tail).contains(tail + " " + tail))
    }

    func testSplitNoOverlapReturnsOriginalParts() {
        let previous = "first clause here"
        let next = "totally different beginning"
        let split = LiveTranscriptOverlap.splitNonRefinementUpdate(previous: previous, next: next)
        XCTAssertEqual(split.head, previous)
        XCTAssertEqual(split.tail, next)
    }
}
