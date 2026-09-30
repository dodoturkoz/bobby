import XCTest
@testable import BobbyCore

final class CurrencyInputRecognitionTests: XCTestCase {
    func testUserCurrencyPairsMeanOneUnitRateQueries() {
        for input in ["USD TL", "usd Turkish lira", "USD to TRY", "USD/TRY", "USD → tl"] {
            XCTAssertEqual(CurrencyInputRecognizer.recognize(input),
                           .conversion(amountExpression: "1", pair: CurrencyPair(base: "USD", quote: "TRY"), isRateQuery: true), input)
        }
        XCTAssertEqual(CurrencyInputRecognizer.recognize("TL euro"),
                       .conversion(amountExpression: "1", pair: CurrencyPair(base: "TRY", quote: "EUR"), isRateQuery: true))
    }

    func testExplicitNamesAndPluralFormsConvertWithoutGuessing() {
        for input in ["3 USD to Turkish lira", "3 US dollars in Turkish liras",
                      "3 U.S. dollars into Turkish lira", "3 United States dollars -> TL"] {
            XCTAssertEqual(CurrencyInputRecognizer.recognize(input),
                           .conversion(amountExpression: "3", pair: CurrencyPair(base: "USD", quote: "TRY"), isRateQuery: false), input)
        }
        XCTAssertEqual(CurrencyInputRecognizer.recognize("50 euros to Canadian dollars"),
                       .conversion(amountExpression: "50", pair: CurrencyPair(base: "EUR", quote: "CAD"), isRateQuery: false))
    }

    func testAmbiguousLiraAsksForConfirmationWithAnExactReplacement() {
        for input in ["3 USD to lira", "3 USD to liras"] {
            XCTAssertEqual(CurrencyInputRecognizer.recognize(input),
                           .suggestion(canonicalExpression: "3 USD to TL", question: "Do you mean Turkish lira?"), input)
        }
        XCTAssertEqual(CurrencyInputRecognizer.recognize("USD liras"),
                       .suggestion(canonicalExpression: "USD to TL", question: "Do you mean Turkish lira?"))
        XCTAssertEqual(CurrencyInputRecognizer.recognize("3 liras to euros"),
                       .suggestion(canonicalExpression: "3 TL to EUR", question: "Do you mean Turkish lira?"))
    }

    func testAmbiguousDollarDoesNotSilentlyAssumeUSD() {
        XCTAssertEqual(CurrencyInputRecognizer.recognize("20 dollars to TL"),
                       .suggestion(canonicalExpression: "20 USD to TL", question: "Do you mean U.S. dollars?"))
        XCTAssertEqual(CurrencyInputRecognizer.recognize("$20 to TL"),
                       .suggestion(canonicalExpression: "20 USD to TL", question: "Do you mean U.S. dollars?"))
        XCTAssertEqual(CurrencyInputRecognizer.recognize("dollars to liras"),
                       .suggestion(canonicalExpression: "USD to TL", question: "Do you mean Turkish lira and U.S. dollars?"))
    }

    func testConfirmedAmbiguousRateQueryRetainsItsRatePrecisionSemantics() throws {
        guard case .suggestion(let canonical, _) = CurrencyInputRecognizer.recognize("liras to euro") else {
            return XCTFail("Expected a lira confirmation")
        }
        XCTAssertEqual(canonical, "TL to EUR")
        let request = try XCTUnwrap(CalculationEngine().evaluate(canonical).first?.conversion)
        XCTAssertTrue(request.isRateQuery)
        XCTAssertEqual(request.amount, 1)

        guard case .suggestion(let amountCanonical, _) = CurrencyInputRecognizer.recognize("1 lira to euro") else {
            return XCTFail("Expected an explicit-amount confirmation")
        }
        let amountRequest = try XCTUnwrap(CalculationEngine().evaluate(amountCanonical).first?.conversion)
        XCTAssertFalse(amountRequest.isRateQuery)
        XCTAssertEqual(amountRequest.amount, 1)
    }

    func testExpressionsAndVariablesArePreservedForEngineValidation() {
        XCTAssertEqual(CurrencyInputRecognizer.recognize("(250 + 250) usd -> TL"),
                       .conversion(amountExpression: "(250 + 250)", pair: CurrencyPair(base: "USD", quote: "TRY"), isRateQuery: false))
        XCTAssertEqual(CurrencyInputRecognizer.recognize("budget * .75 USD to euros"),
                       .conversion(amountExpression: "budget * .75", pair: CurrencyPair(base: "USD", quote: "EUR"), isRateQuery: false))
    }

    func testUnicodeMathOperatorsRemainValidInConversionAmounts() {
        for expression in ["budget × .75", "100 ÷ 4", "100 − 25", "−.75"] {
            XCTAssertEqual(CurrencyInputRecognizer.recognize("\(expression) USD to TL"),
                           .conversion(amountExpression: expression, pair: CurrencyPair(base: "USD", quote: "TRY"), isRateQuery: false), expression)
        }
        XCTAssertEqual(CurrencyInputRecognizer.recognize("−3USD to TL"),
                       .conversion(amountExpression: "−3", pair: CurrencyPair(base: "USD", quote: "TRY"), isRateQuery: false))
    }

    func testCompactNumericAmountsAndUnambiguousSymbols() {
        for input in ["3USD to TL", "3 US$ to TL", "US$3 to ₺"] {
            XCTAssertEqual(CurrencyInputRecognizer.recognize(input),
                           .conversion(amountExpression: "3", pair: CurrencyPair(base: "USD", quote: "TRY"), isRateQuery: false), input)
        }
        for input in ["€500k to TL", "500k € to ₺", "500kEUR TL"] {
            XCTAssertEqual(CurrencyInputRecognizer.recognize(input),
                           .conversion(amountExpression: "500k", pair: CurrencyPair(base: "EUR", quote: "TRY"), isRateQuery: false), input)
        }
        XCTAssertEqual(CurrencyInputRecognizer.recognize(".75 TL euros"),
                       .conversion(amountExpression: ".75", pair: CurrencyPair(base: "TRY", quote: "EUR"), isRateQuery: false))
    }

    func testCaseAndRepeatedWhitespaceDoNotMatter() {
        XCTAssertEqual(CurrencyInputRecognizer.recognize("  3   uS DoLlArS   to  tUrKiSh   LiRaS  "),
                       .conversion(amountExpression: "3", pair: CurrencyPair(base: "USD", quote: "TRY"), isRateQuery: false))
        XCTAssertEqual(CurrencyInputRecognizer.canonicalCode(for: "  Turkish   Liras "), "TRY")
    }

    func testIncompleteCurrencyPhrasesRemainQuiet() {
        for input in ["", "USD", "euro", "USD to", "3 USD", "3 USD to", "USD Turkish", "3 USD to Turkish"] {
            XCTAssertNil(CurrencyInputRecognizer.recognize(input), input)
        }
    }

    func testProseAndCurrencyArithmeticAreNotNewConversionRequests() {
        for input in ["The exchange rate is USD to TL", "Please convert 3 USD to TL",
                      "USD TL tomorrow", "Travel from USD to Turkish lira",
                      "500 USD + 10 EUR", "principal * .75", "USD + TL", "500 USD / 10 EUR",
                      "budgetUSD to TL", "3 apples to TL", "3 USD to French lira", "3 USD to xyz"] {
            XCTAssertNil(CurrencyInputRecognizer.recognize(input), input)
        }
    }

    func testCanonicalNamesAreExplicitAndSupportedOnly() {
        let aliases = ["TL": "TRY", "tRy": "TRY", "euro": "EUR", "Euros": "EUR",
                       "Turkish lira": "TRY", "Turkish liras": "TRY", "₺": "TRY", "€": "EUR",
                       "US dollars": "USD", "U.S. dollar": "USD", "US$": "USD", "British pounds": "GBP",
                       "Swiss francs": "CHF", "Japanese yen": "JPY", "Canadian dollars": "CAD"]
        for (input, code) in aliases {
            XCTAssertEqual(CurrencyInputRecognizer.canonicalCode(for: input), code, input)
        }
        for input in ["lira", "liras", "dollar", "dollars", "$", "XYZ", "French lira", "pounds"] {
            XCTAssertNil(CurrencyInputRecognizer.canonicalCode(for: input), input)
        }
    }
}
