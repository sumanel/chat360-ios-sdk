import XCTest
@testable import Chat360SDK

final class FormFieldValidatorTests: XCTestCase {
    private func field(type: BotContent.Form.FieldType, validation: BotContent.Form.FieldValidation? = nil) -> BotContent.Form.Field {
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
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        let f = field(type: .text, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: ""), "This field is required")
    }

    func testRequiredFieldBlankUsesCustomErrorMessageWhenPresent() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.errorMessage = "Please tell us your name"
        let f = field(type: .text, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: ""), "Please tell us your name")
    }

    func testOptionalBlankFieldAlwaysPasses() {
        var validation = BotContent.Form.FieldValidation()
        validation.email = true
        let f = field(type: .email, validation: validation)
        XCTAssertNil(FormFieldValidator.validate(f, value: ""))
    }

    func testEmailFieldBlocksTheWordTestBeforeAnythingElse() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.email = true
        let f = field(type: .email, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: "test@example.com"), "Email cannot contain the word 'Test'")
    }

    func testEmailFieldWithValidNonTestAddressPasses() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.email = true
        let f = field(type: .email, validation: validation)
        XCTAssertNil(FormFieldValidator.validate(f, value: "user@example.com"))
    }

    func testPhoneFieldBlocksTheFixedBlocklist() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.phone = true
        let f = field(type: .phone, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: "1231231231"), "This phone number is blocked")
    }

    func testPhoneFieldWithRealNumberPasses() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.phone = true
        let f = field(type: .phone, validation: validation)
        XCTAssertNil(FormFieldValidator.validate(f, value: "9876543210"))
    }

    func testTextFieldBlocksTheWordTestAsAName() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        let f = field(type: .text, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: "John test Doe"), "Name cannot contain the word 'Test'")
    }

    func testTextFieldWithAlphaUserInputTypeRejectsDigits() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.userInputType = "alpha"
        let f = field(type: .text, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: "John123"), "Only characters and space are allowed'")
    }

    func testMaxAndMinCharactersBoundTextLength() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.maxCharacters = 5
        validation.minCharacters = 2
        let f = field(type: .text, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: "toolongvalue"), "Invalid input")
        XCTAssertEqual(FormFieldValidator.validate(f, value: "a"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(f, value: "abc"))
    }

    func testNumberFieldRejectsNonNumericValues() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        let f = field(type: .number, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: "abc"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(f, value: "42"))
    }

    func testMaxAndMinCountIgnoreNonNumericValuesRatherThanFailingOnThem() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.maxCount = 10.0
        let f = field(type: .text, validation: validation)
        XCTAssertNil(FormFieldValidator.validate(f, value: "not-a-number"))
    }

    func testMaxAndMinCountBoundNumericValues() {
        var validation = BotContent.Form.FieldValidation()
        validation.isRequired = true
        validation.maxCount = 100.0
        validation.minCount = 10.0
        let f = field(type: .number, validation: validation)
        XCTAssertEqual(FormFieldValidator.validate(f, value: "5"), "Invalid input")
        XCTAssertEqual(FormFieldValidator.validate(f, value: "500"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(f, value: "50"))
    }

    func testMediaFieldSkipsFormatChecksButStillEnforcesRequired() {
        var requiredValidation = BotContent.Form.FieldValidation()
        requiredValidation.isRequired = true
        let required = field(type: .media, validation: requiredValidation)
        XCTAssertEqual(FormFieldValidator.validate(required, value: ""), "This field is required")
        XCTAssertNil(FormFieldValidator.validate(required, value: "https://example.com/uploaded.png"))

        let optional = field(type: .media)
        XCTAssertNil(FormFieldValidator.validate(optional, value: ""))
    }

    func testNumberFormatDecimalRequiresADecimalPointNumberForbidsOne() {
        var decimalValidation = BotContent.Form.FieldValidation()
        decimalValidation.numberFormat = "DECIMAL"
        let decimalField = field(type: .number, validation: decimalValidation)
        XCTAssertEqual(FormFieldValidator.validate(decimalField, value: "42"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(decimalField, value: "42.0"))

        var numberValidation = BotContent.Form.FieldValidation()
        numberValidation.numberFormat = "NUMBER"
        let numberField = field(type: .number, validation: numberValidation)
        XCTAssertEqual(FormFieldValidator.validate(numberField, value: "42.0"), "Invalid input")
        XCTAssertNil(FormFieldValidator.validate(numberField, value: "42"))
    }
}
