import AppKit
import XCTest
@testable import Ch4ttr

final class LongHoldModifierMonitorTests: XCTestCase {
    func testExclusiveShiftRequiresNoOtherModifiers() {
        XCTAssertTrue(
            LongHoldModifierMonitor.exclusiveTargetDown([.shift], key: .shift)
        )
        XCTAssertFalse(
            LongHoldModifierMonitor.exclusiveTargetDown([.shift, .command], key: .shift)
        )
        XCTAssertFalse(
            LongHoldModifierMonitor.exclusiveTargetDown([.command], key: .shift)
        )
    }

    func testExclusiveCommand() {
        XCTAssertTrue(
            LongHoldModifierMonitor.exclusiveTargetDown([.command], key: .command)
        )
        XCTAssertFalse(
            LongHoldModifierMonitor.exclusiveTargetDown([.command, .shift], key: .command)
        )
    }
}
