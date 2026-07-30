import XCTest
@testable import Chat360SDK

final class FormFieldValidatorTests: XCTestCase {

    private func field(_ type: BotContent.Form.FieldType, _ validation: BotContent.Form.FieldValidation? = nil) -> BotContent.Form.Field {
        BotContent.Form.Field(
            index: 0,
            type: type,
            label: "Field",
            placeholder: nil,
            isRequired: validation?.isRequired ?? false,
            options: [],
            variable: "v",
            validation: validation
        )
    }

    func testRequiredFieldBlankFailsWithDefaultMessage() {
        let f = field(.text, .init(isRequired: true))
        XCTAssertEqual(FormFieldValidator.validate(f, value: ""), "This field is required")
    }

    func testRequiredFieldBlankUsesCustomErrorMessageWhenPresent() {
        let f = field(.text, .init(isRequired: true, errorMessage: "Please tell us your name"))
        XCTAssertEqual(FormFieldValidator.validate(f, value: ""), "Please tell us your name")
    }

    func testOptionalBlankFieldAlwaysPasses() {
        let f = field(.email, .init(email: true))
        XCTAssertNil(FormFieldValidator.validate(f, value: ""))
    }

    func testEmailFieldBlocksTheWordTestBeforeAnythingElse() {
        let f = field(.email, .init(isRequired: true, email: true))
        XCTAssertEqual(FormFieldValidator.validate(f, value: "test@example.com"), "Email cannot contain the word 'Test'")
    }

    func testEmailFieldWithValidNonTestAddressPasses() {
        let f = field(.email, .init(isRequired: true, email: true))
        XCTAssertNil(FormFieldValidator.validate(f, value: "user@example.com"))
    }

    func testPhoneFieldBlocksTheFixedBlocklist() {
        let f = field(.phone, .init(isRequired: true, phone: true))
        XCTAssertEqual(FormFieldValidator.validate(f, value: "1231231231"), "This phone number is blocked")
    }

    func testPhoneFieldWithARealNumberPasses() {
        let f = field(.phone, .init(isRequired: true, phone: true))
        XCTAssertNil(FormFieldValidator.validate(f, value: "9876543210"))
    }

    func testTextFieldBlocksTheWordTestAsAName() {
        let f = field(.text, .init(isRequired: true))
        XCTAssertEqual(FormFieldValidator.validate(f, value: "John test Doe"), "Name cannot contain the word 'Test'")
    }

    func testTextFieldWithAlphaUserInputTypeRejectsDigits() {
        let f = field(.text, .init(isRequired: true, userInputType: "alpha"))
        XCTAssertEqual(FormFieldValidator.validate(f, value: "John123"), "Only characters and space are allowed'")
    }

    func testMaxCharactersAndMinCharactersBoundTextLength() {
        let f = field(.text, .init(isRequired: true, maxCharacters: 5, minCharacters: 2))
        XCTAssertEqual(FormFieldValidator.validate(f, value: "toolongvalue"), "Invalid input")
        XCTAssertEqual(FormFieldValidator.validate(f, value: "a"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(f, value: "abc"))
    }

    func testNumberFieldRejectsNonNumericValues() {
        let f = field(.number, .init(isRequired: true))
        XCTAssertEqual(FormFieldValidator.validate(f, value: "abc"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(f, value: "42"))
    }

    func testMaxCountAndMinCountIgnoreNonNumericValuesRatherThanFailingOnThem() {
        // Ports JS's `+value > maxCount` being false for NaN - a non-numeric value must not trip
        // maxCount/minCount on its own (it still fails separately via the NUMBER type-check).
        let f = field(.text, .init(isRequired: true, maxCount: 10.0))
        XCTAssertNil(FormFieldValidator.validate(f, value: "not-a-number"))
    }

    func testMaxCountAndMinCountBoundNumericValues() {
        let f = field(.number, .init(isRequired: true, maxCount: 100.0, minCount: 10.0))
        XCTAssertEqual(FormFieldValidator.validate(f, value: "5"), "Invalid input")
        XCTAssertEqual(FormFieldValidator.validate(f, value: "500"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(f, value: "50"))
    }

    func testMediaFieldSkipsFormatChecksButStillEnforcesRequired() {
        let required = field(.media, .init(isRequired: true))
        XCTAssertEqual(FormFieldValidator.validate(required, value: ""), "This field is required")
        XCTAssertNil(FormFieldValidator.validate(required, value: "https://example.com/uploaded.png"))

        let optional = field(.media)
        XCTAssertNil(FormFieldValidator.validate(optional, value: ""))
    }

    func testNumberFormatDecimalRequiresADecimalPointNumberForbidsOne() {
        let decimalField = field(.number, .init(numberFormat: "DECIMAL"))
        XCTAssertEqual(FormFieldValidator.validate(decimalField, value: "42"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(decimalField, value: "42.0"))

        let numberField = field(.number, .init(numberFormat: "NUMBER"))
        XCTAssertEqual(FormFieldValidator.validate(numberField, value: "42.0"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(numberField, value: "42"))
    }
}
