import XCTest

@testable import opaq

final class ContactNormalizationTests: XCTestCase {
    func testNormalizePhoneExactAndLast10() {
        let normalized = ContactManager.normalizePhone("+1 (555) 123-4567")
        XCTAssertEqual(normalized.exact, "+15551234567")
        XCTAssertEqual(normalized.last10, "5551234567")
    }

    func testDottedPhoneLast10Matches() {
        let dotted = ContactManager.normalizePhone("555.123.4567")
        let international = ContactManager.normalizePhone("+1 (555) 123-4567")
        XCTAssertEqual(dotted.last10, "5551234567")
        XCTAssertEqual(dotted.last10, international.last10)
    }

    func testNormalizeEmailTrimsAndLowercases() {
        XCTAssertEqual(
            ContactManager.normalizeEmail("  Alice@Example.COM \n"),
            "alice@example.com"
        )
    }

    func testIsEmailAcceptsAddressAndRejectsPhone() {
        XCTAssertTrue(ContactManager.isEmail("a@b.co"))
        XCTAssertFalse(ContactManager.isEmail("+1 (555) 123-4567"))
    }
}
