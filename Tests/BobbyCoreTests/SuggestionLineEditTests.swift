import Foundation
import XCTest
@testable import BobbyCore

final class SuggestionLineEditTests: XCTestCase {
    func testChangesOnlyTheAnchoredMiddleLine() throws {
        let source = "first note\n3 years interest at 42%\nlast note\n"
        let edit = try XCTUnwrap(SuggestionLineEdit.make(in: source, lineIndex: 1,
            expectedLine: "3 years interest at 42%", expression: "1000 TL at 42% for 1095 days basis 365"))
        XCTAssertEqual(edit.range, NSRange(location: 11, length: 23))
        XCTAssertEqual(applying(edit, to: source), "first note\n1000 TL at 42% for 1095 days basis 365\nlast note\n")
    }

    func testRangeUsesUTF16ForEmojiAndUnicodeBeforeTheLine() throws {
        let source = "🏦 İstanbul\nfaiz 💰\nclosing"
        let expectedLocation = "🏦 İstanbul\n".utf16.count
        let edit = try XCTUnwrap(SuggestionLineEdit.make(in: source, lineIndex: 1,
            expectedLine: "faiz 💰", expression: "500 TL at 42% for 32 days"))
        XCTAssertEqual(edit.range, NSRange(location: expectedLocation, length: "faiz 💰".utf16.count))
        XCTAssertEqual(applying(edit, to: source), "🏦 İstanbul\n500 TL at 42% for 32 days\nclosing")
    }

    func testChangedSourceDoesNotUseAnOutdatedProposal() {
        XCTAssertNil(SuggestionLineEdit.make(in: "note\n4 years interest at 42%", lineIndex: 1,
            expectedLine: "3 years interest at 42%", expression: "replacement"))
        XCTAssertNil(SuggestionLineEdit.make(in: "  original", lineIndex: 0,
            expectedLine: "original", expression: "replacement"))
        XCTAssertNil(SuggestionLineEdit.make(in: "original ", lineIndex: 0,
            expectedLine: "original", expression: "replacement"))
    }

    func testAssignmentPrefixAndItsSpacingArePreserved() throws {
        let cases = [
            ("budget = 3 years interest at 42%", "budget = replacement"),
            ("budget=original", "budget=replacement"),
            ("  budget\t =\t original  ", "  budget\t =\t replacement"),
            ("_principal42 = original", "_principal42 = replacement"),
            ("faiz_ödeme2  =   original", "faiz_ödeme2  =   replacement")
        ]
        for (source, expected) in cases {
            let edit = try XCTUnwrap(SuggestionLineEdit.make(in: source, lineIndex: 0,
                expectedLine: source, expression: "replacement"), source)
            XCTAssertEqual(applying(edit, to: source), expected, source)
        }
    }

    func testEqualsInsideMathAndProseDoNotBecomeAssignmentPrefixes() throws {
        let cases = ["1 = 2", "amount + 2 = 4", "call the bank = tomorrow", "loan-cost = original", "42budget = original"]
        for source in cases {
            let edit = try XCTUnwrap(SuggestionLineEdit.make(in: source, lineIndex: 0,
                expectedLine: source, expression: "replacement"), source)
            XCTAssertEqual(applying(edit, to: source), "replacement", source)
        }
    }

    func testCRLFSuffixAndOtherLinesArePreserved() throws {
        let source = "first\r\n  principal = original\r\nlast\r\n"
        let edit = try XCTUnwrap(SuggestionLineEdit.make(in: source, lineIndex: 1,
            expectedLine: "  principal = original\r", expression: "100 TL at 42% for 32 days"))
        XCTAssertEqual(applying(edit, to: source), "first\r\n  principal = 100 TL at 42% for 32 days\r\nlast\r\n")
        XCTAssertNil(SuggestionLineEdit.make(in: source, lineIndex: 1,
            expectedLine: "  principal = original", expression: "replacement"))
    }

    func testNonAssignmentReplacementPreservesCRLFSuffix() throws {
        let source = "first\r\noriginal\r\nlast"
        let edit = try XCTUnwrap(SuggestionLineEdit.make(in: source, lineIndex: 1,
            expectedLine: "original\r", expression: "replacement"))
        XCTAssertEqual(edit.replacement, "replacement\r")
        XCTAssertEqual(applying(edit, to: source), "first\r\nreplacement\r\nlast")
    }

    func testInvalidIndicesAndEmbeddedNewlinesAreRejected() {
        for index in [-1, 2, Int.max] {
            XCTAssertNil(SuggestionLineEdit.make(in: "first\nlast", lineIndex: index,
                expectedLine: "last", expression: "replacement"))
        }
        for expression in ["a\nb", "a\rb", "a\r\nb", "a\u{2028}b", "a\u{2029}b", "a\u{85}b"] {
            XCTAssertNil(SuggestionLineEdit.make(in: "original", lineIndex: 0,
                expectedLine: "original", expression: expression))
        }
    }

    func testFirstLastAndEmptyLinesHaveCorrectRanges() throws {
        let first = try XCTUnwrap(SuggestionLineEdit.make(in: "first\nlast", lineIndex: 0,
            expectedLine: "first", expression: "replacement"))
        XCTAssertEqual(first.range, NSRange(location: 0, length: 5))
        XCTAssertEqual(applying(first, to: "first\nlast"), "replacement\nlast")

        let last = try XCTUnwrap(SuggestionLineEdit.make(in: "first\nlast", lineIndex: 1,
            expectedLine: "last", expression: "replacement"))
        XCTAssertEqual(last.range, NSRange(location: 6, length: 4))
        XCTAssertEqual(applying(last, to: "first\nlast"), "first\nreplacement")

        let trailingEmpty = try XCTUnwrap(SuggestionLineEdit.make(in: "first\n", lineIndex: 1,
            expectedLine: "", expression: "replacement"))
        XCTAssertEqual(trailingEmpty.range, NSRange(location: 6, length: 0))
        XCTAssertEqual(applying(trailingEmpty, to: "first\n"), "first\nreplacement")

        let emptyDocument = try XCTUnwrap(SuggestionLineEdit.make(in: "", lineIndex: 0,
            expectedLine: "", expression: "replacement"))
        XCTAssertEqual(emptyDocument.range, NSRange(location: 0, length: 0))
        XCTAssertEqual(applying(emptyDocument, to: ""), "replacement")
    }

    func testEmptyReplacementCanClearTheLineWithoutRemovingItsSeparator() throws {
        let source = "first\noriginal\nlast"
        let edit = try XCTUnwrap(SuggestionLineEdit.make(in: source, lineIndex: 1,
            expectedLine: "original", expression: ""))
        XCTAssertEqual(applying(edit, to: source), "first\n\nlast")
    }

    private func applying(_ edit: SuggestionLineEdit, to source: String) -> String {
        (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
}
