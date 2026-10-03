import AppKit
import BobbyCore
import XCTest
@testable import Bobby

@MainActor
final class GoldResultUITests: XCTestCase {
    private let observation = Date(timeIntervalSince1970: 1_791_018_000)

    func testBothDealerPricesAndProvenanceFitNormalResultGutter() throws {
        let display = try presentation()
        let editor = makeEditor(results: [result(display, line: 0)])
        let button = try resultButton(in: editor, line: 0)
        XCTAssertTrue(button.attributedTitle.string.hasPrefix("Dealer buy 10,516.94 TL\nDealer sell 11,140.23 TL"))
        XCTAssertTrue(button.attributedTitle.string.contains("Altınkaynak"))
        XCTAssertEqual(button.accessibilityLabel(), display.valueText)
        XCTAssertEqual(button.accessibilityHelp(), display.tooltip)
        try assertVisibleLinesFit(button)
    }

    func testLargerQuantityWrapsExactBuyAndSellTotalsWithoutOverlappingNextRow() throws {
        let display = try presentation(quantity: 101)
        let next = try presentation(side: .dealerSell)
        let editor = makeEditor(results: [result(display, line: 0), result(next, line: 1)])
        let button = try resultButton(in: editor, line: 0)
        let nextButton = try resultButton(in: editor, line: 1)
        let lines = button.attributedTitle.string.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Dealer buy 1,062,210.94 TL")
        XCTAssertEqual(lines[1], "Dealer sell 1,125,163.23 TL")
        XCTAssertTrue(lines[2].contains("Altınkaynak"))
        XCTAssertLessThanOrEqual(button.frame.maxY, nextButton.frame.minY + 0.001)
        XCTAssertEqual(button.accessibilityLabel(), display.valueText, "Accessibility retains the unsplit exact prices")
        try assertVisibleLinesFit(button)
    }

    func testOfflineOlderRefreshingQuoteRetainsCompleteCopyAndAccessibleProvenance() throws {
        let display = try presentation(quantity: 101, offline: true, refreshing: true,
                                       now: observation.addingTimeInterval(3_600))
        let editor = makeEditor(results: [result(display, line: 0)])
        let originalText = editor.string
        let button = try resultButton(in: editor, line: 0)
        var copied: String?
        editor.onCopy = { copied = $0 }
        button.performClick(nil)
        XCTAssertEqual(copied, display.copyText)
        XCTAssertTrue(copied?.contains("Dealer buy (you receive): 1,062,210.94 TL") == true)
        XCTAssertTrue(copied?.contains("Dealer sell (you pay): 1,125,163.23 TL") == true)
        XCTAssertTrue(copied?.contains("Altınkaynak") == true)
        XCTAssertTrue(copied?.contains("Europe/Istanbul") == true)
        XCTAssertTrue(copied?.contains(GoldPriceStore.sourceURL.absoluteString) == true)
        XCTAssertTrue(copied?.contains("offline cache") == true)
        XCTAssertTrue(copied?.contains("older quote") == true)
        XCTAssertTrue(copied?.contains("refreshing") == true)
        XCTAssertTrue(button.accessibilityHelp()?.contains("Using a saved quote") == true)
        XCTAssertTrue(button.accessibilityHelp()?.contains("Refreshing") == true)
        XCTAssertTrue(button.attributedTitle.string.contains("saved"), "The visible row identifies the saved quote")
        XCTAssertEqual(editor.string, originalText)
        try assertVisibleLinesFit(button)
    }

    func testFreshRefreshingQuoteKeepsSourceAndTimestampWithinGutter() throws {
        let display = try presentation(quantity: 101, refreshing: true)
        let editor = makeEditor(results: [result(display, line: 0)])
        let button = try resultButton(in: editor, line: 0)
        XCTAssertTrue(button.attributedTitle.string.contains("Altınkaynak"))
        XCTAssertTrue(button.attributedTitle.string.contains("2026-"))
        try assertVisibleLinesFit(button)
    }

    func testSingleSideQuoteKeepsFullPriceAndArithmeticCopy() throws {
        let display = try presentation(side: .dealerSell)
        let editor = makeEditor(results: [result(display, line: 0)])
        let button = try resultButton(in: editor, line: 0)
        var copied: String?
        editor.onCopy = { copied = $0 }
        button.performClick(nil)
        XCTAssertEqual(display.valueText, "Dealer sell: 11,140.23 TL")
        XCTAssertEqual(copied, "11,140.23 TL")
        XCTAssertFalse(display.showsBothSides)
        XCTAssertEqual((button.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 15)
        try assertVisibleLinesFit(button)
    }

    private func presentation(quantity: Decimal = 1, side: GoldSide? = nil,
                              offline: Bool = false, refreshing: Bool = false, now: Date? = nil) throws -> GoldPricePresentation {
        let quote = GoldQuote(product: .quarterCoin, dealerBuy: Decimal(string: "10516.94")!,
                              dealerSell: Decimal(string: "11140.23")!, observedAt: observation,
                              fetchedAt: observation, productLabel: "Çeyrek")
        return try GoldPricePresentation.make(request: GoldRequest(product: .quarterCoin, quantity: quantity, side: side),
                                              lookup: GoldLookup(quote: quote, usedOfflineCache: offline,
                                                                 failureDescription: offline ? "Test connection unavailable" : nil),
                                              isRefreshing: refreshing, now: now ?? observation)
    }

    private func result(_ presentation: GoldPricePresentation, line: Int) -> DisplayResult {
        DisplayResult(lineIndex: line, text: presentation.valueText, detail: presentation.detail,
                      tooltip: presentation.tooltip, isError: false, copyText: presentation.copyText,
                      usesCompactValue: presentation.showsBothSides)
    }

    private func makeEditor(results: [DisplayResult]) -> ResultTextView {
        _ = NSApplication.shared
        let editor = ResultTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 450))
        editor.configureScratchAppearance()
        editor.string = "101 çeyrek altın\nçeyrek altın sell"
        editor.displayResults = results
        editor.layoutResults()
        return editor
    }

    private func resultButton(in editor: ResultTextView, line: Int) throws -> NSButton {
        try XCTUnwrap(editor.subviews.compactMap { $0 as? NSButton }.first {
            $0.accessibilityIdentifier() == "result-line-\(line)"
        })
    }

    private func assertVisibleLinesFit(_ button: NSButton, file: StaticString = #filePath, line: UInt = #line) throws {
        let titleRect = try XCTUnwrap(button.cell?.titleRect(forBounds: button.bounds), file: file, line: line)
        let text = button.attributedTitle.string as NSString
        var offset = 0
        for visualLine in button.attributedTitle.string.components(separatedBy: "\n") {
            let range = NSRange(location: offset, length: (visualLine as NSString).length)
            let attributedLine = button.attributedTitle.attributedSubstring(from: range)
            XCTAssertLessThanOrEqual(attributedLine.size().width, titleRect.width + 0.01,
                                     "Result line would truncate: \(text.substring(with: range))", file: file, line: line)
            offset += range.length + 1
        }
        let textHeight = button.attributedTitle.boundingRect(with: NSSize(width: titleRect.width, height: 1_000),
                                                             options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        XCTAssertLessThanOrEqual(textHeight, button.bounds.height + 0.01,
                                 "Source/date must not be clipped vertically", file: file, line: line)
        XCTAssertLessThanOrEqual(button.cell?.cellSize.height ?? 0, button.bounds.height + 0.01,
                                 "The native button title must fit its frame", file: file, line: line)
    }
}
