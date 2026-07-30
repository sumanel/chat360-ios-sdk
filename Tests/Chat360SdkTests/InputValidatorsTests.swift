import XCTest
@testable import Chat360SDK

final class InputValidatorsTests: XCTestCase {

    func testValidateEmailAcceptsWellFormedAddressesAndRejectsMalformedOnes() {
        XCTAssertTrue(InputValidators.validateEmail("user@example.com"))
        XCTAssertTrue(InputValidators.validateEmail("first.last+tag@sub.example.co"))
        XCTAssertFalse(InputValidators.validateEmail("not-an-email"))
        XCTAssertFalse(InputValidators.validateEmail("missing@domain"))
        XCTAssertFalse(InputValidators.validateEmail("@example.com"))
    }

    func testValidateTestFlagsTheLiteralWordTestInEmailLocalPartOrDomain() {
        XCTAssertTrue(InputValidators.validateTest("test@example.com"))
        XCTAssertTrue(InputValidators.validateTest("user@test.com"))
        XCTAssertFalse(InputValidators.validateTest("attestation@example.com"))
        XCTAssertFalse(InputValidators.validateTest("real.user@example.com"))
    }

    func testValidateTestNameFlagsStandaloneWordTestAnywhereInAName() {
        XCTAssertTrue(InputValidators.validateTestName("test"))
        XCTAssertTrue(InputValidators.validateTestName("John test Doe"))
        XCTAssertFalse(InputValidators.validateTestName("Testimony"))
        XCTAssertFalse(InputValidators.validateTestName("John Doe"))
    }

    func testValidatePhoneNumberRejectsASingleRepeatedDigitRegardlessOfFormat() {
        XCTAssertFalse(InputValidators.validatePhoneNumber("1111111111", international: false))
        XCTAssertFalse(InputValidators.validatePhoneNumber("0000000000", international: true))
    }

    func testValidatePhoneNumberAcceptsWellFormed10DigitNumbers() {
        XCTAssertTrue(InputValidators.validatePhoneNumber("9876543210", international: false))
        XCTAssertTrue(InputValidators.validatePhoneNumber("+919876543210", international: true))
        XCTAssertFalse(InputValidators.validatePhoneNumber("12345", international: false))
    }

    func testHasOnlyCharacterAcceptsLettersAndSpacesOnly() {
        XCTAssertTrue(InputValidators.hasOnlyCharacter("John Doe"))
        XCTAssertFalse(InputValidators.hasOnlyCharacter("John123"))
        XCTAssertFalse(InputValidators.hasOnlyCharacter("John_Doe"))
    }

    func testSanitizeInputEscapesHtmlSignificantCharacters() {
        XCTAssertEqual(InputValidators.sanitizeInput("<script>alert(\"x\")</script>"), "&lt;script&gt;alert(&quot;x&quot;)&lt;&#x2F;script&gt;")
        XCTAssertEqual(InputValidators.sanitizeInput("Tom & Jerry"), "Tom &amp; Jerry")
    }
}
