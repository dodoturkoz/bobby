import Foundation
import XCTest
@testable import BobbyCore

final class GoldInputRecognitionTests: XCTestCase {
    func testTurkishASCIIAndCaseVariantsRecognizeQuarterGold() {
        for input in ["çeyrek altın", "ceyrek altin", "ÇEYREK ALTIN", "Çeyrek Altın", "ceyrek altını", "  çeyrek   altın  "] {
            XCTAssertEqual(GoldInputRecognizer.recognize(input), .gold(product: .quarterCoin, quantityExpression: "1", side: nil), input)
        }
    }

    func testNamedProductsKeepDistinctProviderIdentifiers() {
        let inputs: [(String, GoldProduct)] = [
            ("eski çeyrek altın", .oldQuarterCoin), ("yarım altın", .halfCoin),
            ("eski yarim altin", .oldHalfCoin), ("tam altın", .fullCoin),
            ("teklik altin", .fullCoin), ("eski tam altın", .oldFullCoin),
            ("eski teklik altin", .oldFullCoin), ("ata altını", .ataCoin),
            ("cumhuriyet altını", .ataCoin), ("ata cumhuriyet altın", .ataCoin),
            ("gram altın", .gram)
        ]
        for (input, product) in inputs {
            XCTAssertEqual(GoldInputRecognizer.recognize(input), .gold(product: product, quantityExpression: "1", side: nil), input)
        }
        XCTAssertEqual(GoldProduct.allCases.map(\.rawValue), ["PC", "EC", "PY", "EY", "PT", "ET", "PA", "PGA"])
        XCTAssertEqual(GoldProduct.quarterCoin.providerName, "Çeyrek")
        XCTAssertEqual(GoldProduct.oldQuarterCoin.providerName, "Eski Çeyrek")
        XCTAssertEqual(GoldProduct.gram.unitDescription, "gram")
        XCTAssertEqual(GoldProduct.quarterCoin.unitDescription, "coin")
    }

    func testEnglishAliasesRecognizeTheSameNamedProducts() {
        let inputs: [(String, GoldProduct)] = [
            ("quarter gold", .quarterCoin), ("old quarter gold coin", .oldQuarterCoin),
            ("half gold coin", .halfCoin), ("old half gold", .oldHalfCoin),
            ("full gold", .fullCoin), ("old full gold coin", .oldFullCoin),
            ("ata gold", .ataCoin), ("ata coin", .ataCoin), ("republic gold coin", .ataCoin), ("gram gold", .gram)
        ]
        for (input, product) in inputs {
            XCTAssertEqual(GoldInputRecognizer.recognize(input), .gold(product: product, quantityExpression: "1", side: nil), input)
        }
    }

    func testSideAliasesHaveAnExplicitDealerPerspective() {
        for side in ["alış", "alis", "ALIS", "buy", "dealer buy"] {
            XCTAssertEqual(GoldInputRecognizer.recognize("çeyrek altın \(side)"),
                           .gold(product: .quarterCoin, quantityExpression: "1", side: .dealerBuy), side)
        }
        for side in ["satış", "satis", "SATIS", "sell", "dealer sell"] {
            XCTAssertEqual(GoldInputRecognizer.recognize("çeyrek altın \(side)"),
                           .gold(product: .quarterCoin, quantityExpression: "1", side: .dealerSell), side)
        }
    }

    func testQuantityExpressionPreservesVariableSpellingAndSourcePunctuation() {
        XCTAssertEqual(GoldInputRecognizer.recognize("(miktarı + 1) * .75 GRAM ALTINI SATIŞ"),
                       .gold(product: .gram, quantityExpression: "(miktarı + 1) * .75", side: .dealerSell))
        XCTAssertEqual(GoldInputRecognizer.recognize("1,234.5 gram altin"),
                       .gold(product: .gram, quantityExpression: "1,234.5", side: nil))
        XCTAssertEqual(GoldInputRecognizer.recognize("2 eski ceyrek altin buy"),
                       .gold(product: .oldQuarterCoin, quantityExpression: "2", side: .dealerBuy))
    }

    func testGenericGoldOrdinaryNotesAndUnsupportedSuffixesAreNotQueries() {
        for input in ["altın", "altin", "gold", "ceyrek", "çeyrek alt", "Buy gold tomorrow", "I have 2 ceyrek altin",
                      "2026 plan gram altin", "today's ceyrek altin", "ceyrek altin tomorrow", "ceyrek altin buy extra",
                      "ceyrek altin / USD", "2 coins ceyrek altin", "ceyrek altin buy sell"] {
            XCTAssertNil(GoldInputRecognizer.recognize(input), input)
        }
    }

    func testMoneyQuantityRemainsRecognizableForTheEngineToExplain() {
        XCTAssertEqual(GoldInputRecognizer.recognize("500 TL çeyrek altın buy"),
                       .gold(product: .quarterCoin, quantityExpression: "500 TL", side: .dealerBuy))
    }

    func testCoinPhrasesWithoutGoldRemainOrdinaryNotes() {
        for input in ["quarter coin", "half coin", "full coin", "old quarter coin", "old half coin", "old full coin",
                      "republic coin", "2 quarter coin", "quarter coin buy", "old half coin sell"] {
            XCTAssertNil(GoldInputRecognizer.recognize(input), input)
            XCTAssertTrue(CalculationEngine().evaluate(input).isEmpty, input)
        }
    }
}
