import AppKit
import BobbyCore
import QuartzCore
import XCTest
@testable import Bobby

@MainActor
final class ScratchPagerViewTests: XCTestCase {
    @MainActor
    private final class UndoDelegate: NSObject, NSTextViewDelegate {
        let manager = UndoManager()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    @MainActor
    private final class UndoTarget: NSObject {
        var value = 0
    }

    private struct Fixture {
        let pager: ScratchPagerView
        let editor: ResultTextView
        let currentID: UUID
        let previous: ScratchPagePreview
        let next: ScratchPagePreview
        let undoDelegate: UndoDelegate
        let undoTarget: UndoTarget
    }

    private func makeFixture(onNavigate: @escaping (ScratchNavigationDirection) -> Void = { _ in }) -> Fixture {
        _ = NSApplication.shared
        let pager = ScratchPagerView(frame: NSRect(x: 0, y: 0, width: 760, height: 450))
        pager.appearance = NSAppearance(named: .aqua)
        pager.reduceMotion = { false }
        let editor = ResultTextView(frame: pager.bounds)
        editor.configureScratchAppearance()
        editor.appearance = pager.effectiveAppearance
        editor.string = "Current scratch\n12 + 30\nprincipal = 500k"
        editor.displayResults = [result(line: 1, value: "42"), result(line: 2, value: "500,000")]
        let undoDelegate = UndoDelegate()
        editor.delegate = undoDelegate
        let undoTarget = UndoTarget()
        undoDelegate.manager.groupsByEvent = false
        undoDelegate.manager.beginUndoGrouping()
        undoDelegate.manager.registerUndo(withTarget: undoTarget) { $0.value += 1 }
        undoDelegate.manager.setActionName("Existing edit")
        undoDelegate.manager.endUndoGrouping()
        pager.scrollView.hasVerticalScroller = true
        pager.scrollView.autohidesScrollers = true
        pager.scrollView.drawsBackground = false
        pager.scrollView.documentView = editor
        pager.scrollView.tile()
        editor.layoutResults()
        editor.setSelectedRange(NSRange(location: 3, length: 4))
        let currentID = UUID()
        let previous = ScratchPagePreview(id: UUID(), text: "Previous scratch\n10 * 10\n25 + 15",
                                          results: [result(line: 1, value: "100"), result(line: 2, value: "40")])
        let next = ScratchPagePreview(id: UUID(), text: "Next scratch\n250 / 5\n1,000 * 40%",
                                      results: [result(line: 1, value: "50"), result(line: 2, value: "400")])
        pager.onNavigate = { direction in
            onNavigate(direction)
            return direction == .next ? next.id : previous.id
        }
        pager.updatePages(currentID: currentID, text: editor.string, previous: previous, next: next)
        return Fixture(pager: pager, editor: editor, currentID: currentID, previous: previous,
                       next: next, undoDelegate: undoDelegate, undoTarget: undoTarget)
    }

    private func result(line: Int, value: String) -> DisplayResult {
        DisplayResult(lineIndex: line, text: value, detail: "Immediate result", tooltip: value,
                      isError: false, copyText: value)
    }

    private func drag(_ pager: ScratchPagerView, offset: Double, ended: Bool = false,
                      navigation: ScratchNavigationDirection? = nil, cancelled: Bool = false) {
        pager.handleSwipe(ScratchSwipeResponse(consumesEvent: true, navigation: navigation,
                                               dragOffset: offset, gestureEnded: ended, cancelled: cancelled))
    }

    private func overlay(in pager: ScratchPagerView) -> NSView? {
        pager.subviews.first { $0 !== pager.scrollView }
    }

    private func layers(in pager: ScratchPagerView) throws -> (current: CALayer, neighbor: CALayer) {
        let overlay = try XCTUnwrap(overlay(in: pager))
        let layers = try XCTUnwrap(overlay.layer?.sublayers)
        XCTAssertEqual(layers.count, 2)
        return (try XCTUnwrap(layers.last), try XCTUnwrap(layers.first))
    }

    func testDraggingMovesBothRenderedPagesAndClipsToEditorPane() throws {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -140)
        let layers = try layers(in: fixture.pager)
        XCTAssertEqual(layers.current.transform.m41, -140, accuracy: 0.001)
        XCTAssertEqual(layers.neighbor.transform.m41, 620, accuracy: 0.001)
        XCTAssertEqual(layers.current.frame.size, fixture.pager.bounds.size)
        XCTAssertEqual(layers.neighbor.frame.size, fixture.pager.bounds.size)
        XCTAssertTrue(fixture.pager.layer?.masksToBounds == true)
        XCTAssertTrue(overlay(in: fixture.pager)?.layer?.masksToBounds == true)
        XCTAssertEqual(overlay(in: fixture.pager)?.frame, fixture.pager.bounds)
        let currentImage = try layerImage(layers.current)
        let nextImage = try layerImage(layers.neighbor)
        XCTAssertEqual(currentImage.width, 1_520)
        XCTAssertEqual(currentImage.height, 900)
        XCTAssertEqual(nextImage.width, currentImage.width)
        XCTAssertEqual(nextImage.height, currentImage.height)
        XCTAssertNotEqual(imageData(currentImage), imageData(nextImage))
        XCTAssertTrue(hasDrawnContent(nextImage, xRange: 20..<900, yRange: 20..<330), "Neighbor text must be rendered")
        XCTAssertTrue(hasDrawnContent(nextImage, xRange: 1_020..<1_460, yRange: 70..<290), "Neighbor results must be rendered")
        try exportPreview(current: currentImage, neighbor: nextImage, currentOffset: -140, neighborOffset: 620)
    }

    func testDragPreservesEditorTextSelectionAndUndo() throws {
        let fixture = makeFixture()
        let originalText = fixture.editor.string
        let originalSelection = fixture.editor.selectedRange()
        let originalDocument = fixture.pager.scrollView.documentView
        drag(fixture.pager, offset: -180)
        XCTAssertEqual(fixture.editor.string, originalText)
        XCTAssertEqual(fixture.editor.selectedRange(), originalSelection)
        XCTAssertTrue(fixture.pager.scrollView.documentView === originalDocument)
        XCTAssertTrue(fixture.editor.undoManager === fixture.undoDelegate.manager)
        XCTAssertEqual(fixture.undoDelegate.manager.undoActionName, "Existing edit")
        XCTAssertTrue(fixture.undoDelegate.manager.canUndo)
        fixture.pager.cancelTransition()
        fixture.undoDelegate.manager.undo()
        XCTAssertEqual(fixture.undoTarget.value, 1)
        XCTAssertEqual(fixture.editor.string, originalText)
    }

    func testReversalBringsOppositeNeighborIntoView() throws {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -120)
        let first = try layerImage(try layers(in: fixture.pager).neighbor)
        drag(fixture.pager, offset: 75)
        let layers = try layers(in: fixture.pager)
        let reversed = try layerImage(layers.neighbor)
        XCTAssertEqual(layers.current.transform.m41, 75, accuracy: 0.001)
        XCTAssertEqual(layers.neighbor.transform.m41, -685, accuracy: 0.001)
        XCTAssertNotEqual(imageData(first), imageData(reversed))
    }

    func testNativeTextEditStillUndoesAfterCancelledSwipe() {
        let fixture = makeFixture()
        let originalText = fixture.editor.string
        fixture.undoDelegate.manager.removeAllActions()
        fixture.undoDelegate.manager.beginUndoGrouping()
        fixture.editor.insertText("\n99 + 1", replacementRange: NSRange(location: (originalText as NSString).length, length: 0))
        fixture.undoDelegate.manager.endUndoGrouping()
        XCTAssertTrue(fixture.undoDelegate.manager.canUndo)
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        drag(fixture.pager, offset: -120)
        fixture.pager.cancelTransition()
        fixture.undoDelegate.manager.undo()
        XCTAssertEqual(fixture.editor.string, originalText)
    }

    func testNeighborResultsAreCalculatedOnlyOncePerDirectionDuringGesture() {
        let fixture = makeFixture()
        var previews: [String] = []
        fixture.pager.onPreviewResults = { text in
            previews.append(text)
            return []
        }
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertTrue(previews.isEmpty)
        drag(fixture.pager, offset: -40)
        drag(fixture.pager, offset: -80)
        drag(fixture.pager, offset: -140)
        XCTAssertEqual(previews, [fixture.next.text])
        drag(fixture.pager, offset: 40)
        drag(fixture.pager, offset: 80)
        XCTAssertEqual(previews, [fixture.next.text, fixture.previous.text])
        fixture.pager.cancelTransition()
        drag(fixture.pager, offset: -40)
        XCTAssertEqual(previews, [fixture.next.text, fixture.previous.text, fixture.next.text])
    }

    func testMissingNeighborResistsAndNeverNavigates() throws {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: nil)
        drag(fixture.pager, offset: -200)
        let layers = try layers(in: fixture.pager)
        XCTAssertLessThan(abs(layers.current.transform.m41), 40)
        XCTAssertLessThan(layers.current.transform.m41, 0)
        XCTAssertNil(layers.neighbor.contents)
        drag(fixture.pager, offset: -200, ended: true, navigation: .next)
        fixture.pager.finishNavigation(direction: .next, target: nil)
        XCTAssertTrue(navigations.isEmpty)
        XCTAssertNil(overlay(in: fixture.pager))
    }

    func testResizeCancelsAndPreservesLiveEditor() {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -100)
        fixture.pager.setFrameSize(NSSize(width: 900, height: 500))
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
        XCTAssertTrue(fixture.pager.scrollView.documentView === fixture.editor)
        XCTAssertEqual(fixture.editor.string, "Current scratch\n12 + 30\nprincipal = 500k")
    }

    func testSourceChangeCancelsFrozenPreview() {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -100)
        fixture.editor.string += "\nEdited while dragging"
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertTrue(fixture.editor.string.hasSuffix("Edited while dragging"))
    }

    func testScratchIdentityChangeCancelsFrozenPreview() {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -100)
        fixture.pager.updatePages(currentID: UUID(), text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
    }

    func testRateResultRefreshDoesNotInterruptDrag() throws {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -100)
        fixture.editor.displayResults = [result(line: 1, value: "42.00")]
        fixture.editor.layoutResults()
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertEqual(try layers(in: fixture.pager).current.transform.m41, -100, accuracy: 0.001)
    }

    func testDestinationOverlayWaitsForEditorAndNavigationCompletesOnce() throws {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        XCTAssertTrue(navigations.isEmpty, "Navigation waits for settling")
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        XCTAssertEqual(navigations, [.next])
        XCTAssertTrue(fixture.pager.isAwaitingEditor)
        XCTAssertNotNil(overlay(in: fixture.pager))
        XCTAssertEqual(try layers(in: fixture.pager).neighbor.transform.m41, 0, accuracy: 0.001)
        XCTAssertFalse(fixture.pager.prepareForInteraction(), "The outgoing editor cannot be edited during handoff")
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        XCTAssertEqual(navigations, [.next], "Duplicate completion cannot navigate twice")
        fixture.editor.string = fixture.next.text
        fixture.editor.displayResults = fixture.next.results
        fixture.editor.layoutResults()
        fixture.pager.updatePages(currentID: fixture.next.id, text: fixture.next.text,
                                  previous: ScratchPagePreview(id: fixture.currentID, text: "Current", results: []), next: nil)
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
        XCTAssertEqual(fixture.editor.string, fixture.next.text)
        XCTAssertTrue(fixture.pager.prepareForInteraction())
    }

    func testVisualCancellationKeepsCommittedEditorHandoffLocked() {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        fixture.pager.cancelTransition()
        XCTAssertEqual(navigations, [.next])
        XCTAssertNil(overlay(in: fixture.pager), "Visual cancellation removes the snapshot")
        XCTAssertTrue(fixture.pager.isAwaitingEditor, "Committed navigation still awaits its destination editor")
        XCTAssertFalse(fixture.pager.prepareForInteraction(), "The outgoing scratch cannot receive edits")
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertTrue(fixture.pager.isAwaitingEditor, "An outgoing scratch update cannot unlock the handoff")
        loadNextEditor(fixture)
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
        XCTAssertTrue(fixture.pager.prepareForInteraction())
    }

    func testResizeKeepsCommittedEditorHandoffLocked() {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        fixture.pager.setFrameSize(NSSize(width: 900, height: 500))
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertTrue(fixture.pager.isAwaitingEditor)
        XCTAssertFalse(fixture.pager.prepareForInteraction())
        loadNextEditor(fixture)
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
        XCTAssertTrue(fixture.pager.prepareForInteraction())
    }

    func testNoOpNavigationReleasesEditorImmediately() {
        let fixture = makeFixture()
        let originID = fixture.currentID
        var navigationCount = 0
        fixture.pager.onNavigate = { _ in
            navigationCount += 1
            return originID
        }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        XCTAssertEqual(navigationCount, 1)
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertTrue(fixture.pager.prepareForInteraction())
    }

    func testAnotherSynchronizedScratchSupersedesPendingDestination() {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        fixture.pager.cancelTransition()
        let otherID = UUID()
        fixture.pager.selectedScratchID = { otherID }
        fixture.editor.string = "A different selected scratch"
        fixture.editor.representedScratchID = otherID
        fixture.pager.updatePages(currentID: otherID, text: fixture.editor.string, previous: nil, next: nil)
        XCTAssertFalse(fixture.pager.isAwaitingEditor, "A synchronized new document safely supersedes the pending target")
        XCTAssertTrue(fixture.pager.prepareForInteraction())
        XCTAssertEqual(fixture.editor.string, "A different selected scratch")
    }

    func testAuthoritativeReturnToOriginReleasesPendingEditorLock() {
        let fixture = makeFixture()
        let originID = fixture.currentID
        let destinationID = fixture.next.id
        var selectedID = originID
        fixture.pager.selectedScratchID = { selectedID }
        fixture.pager.onNavigate = { _ in
            selectedID = destinationID
            return selectedID
        }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        fixture.pager.updatePages(currentID: originID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertTrue(fixture.pager.isAwaitingEditor, "A stale outgoing update cannot unlock a different selected scratch")
        XCTAssertFalse(fixture.pager.prepareForInteraction())
        selectedID = originID
        fixture.pager.updatePages(currentID: originID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertFalse(fixture.pager.isAwaitingEditor, "Returning model selection to the loaded origin safely unlocks it")
        XCTAssertTrue(fixture.pager.prepareForInteraction())
    }

    func testCancelledGestureReturnsWithoutNavigation() {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        drag(fixture.pager, offset: -220, ended: true, navigation: .next, cancelled: true)
        fixture.pager.finishNavigation(direction: .next, target: nil)
        XCTAssertTrue(navigations.isEmpty)
        XCTAssertNil(overlay(in: fixture.pager))
    }

    func testChangedNeighborInvalidatesPendingCommit() {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        let replacement = ScratchPagePreview(id: UUID(), text: "Changed neighbor", results: [])
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: replacement)
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        XCTAssertTrue(navigations.isEmpty)
        XCTAssertNil(overlay(in: fixture.pager))
    }

    func testCancelledTransitionIgnoresLateCompletion() {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        fixture.pager.cancelTransition()
        fixture.pager.finishNavigation(direction: .next, target: fixture.next)
        XCTAssertTrue(navigations.isEmpty)
        XCTAssertNil(overlay(in: fixture.pager))
    }

    func testInteractionCancelsDragBeforeEditing() {
        let fixture = makeFixture()
        drag(fixture.pager, offset: -100)
        XCTAssertTrue(fixture.pager.prepareForInteraction())
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertTrue(fixture.pager.scrollView.documentView === fixture.editor)
    }

    func testReducedMotionUsesThresholdWithoutAnimatedOverlay() {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        fixture.pager.reduceMotion = { true }
        drag(fixture.pager, offset: -100)
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertTrue(navigations.isEmpty)
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        XCTAssertEqual(navigations, [.next])
        XCTAssertNil(overlay(in: fixture.pager))
    }

    func testReducedMotionCommitLocksOutgoingEditorUntilDestinationLoads() {
        var navigations: [ScratchNavigationDirection] = []
        let fixture = makeFixture { navigations.append($0) }
        fixture.pager.reduceMotion = { true }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        XCTAssertEqual(navigations, [.next])
        XCTAssertNil(overlay(in: fixture.pager))
        XCTAssertTrue(fixture.pager.isAwaitingEditor)
        XCTAssertFalse(fixture.pager.prepareForInteraction())
        fixture.pager.cancelTransition()
        XCTAssertTrue(fixture.pager.isAwaitingEditor, "Focus or sheet changes cannot unlock the outgoing editor")
        fixture.pager.updatePages(currentID: fixture.currentID, text: fixture.editor.string,
                                  previous: fixture.previous, next: fixture.next)
        XCTAssertTrue(fixture.pager.isAwaitingEditor)
        loadNextEditor(fixture)
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
        XCTAssertTrue(fixture.pager.prepareForInteraction())
    }

    func testReducedMotionNoOpNavigationKeepsCurrentEditorUsable() {
        let fixture = makeFixture()
        let originID = fixture.currentID
        fixture.pager.reduceMotion = { true }
        fixture.pager.onNavigate = { _ in originID }
        drag(fixture.pager, offset: -180, ended: true, navigation: .next)
        XCTAssertFalse(fixture.pager.isAwaitingEditor)
        XCTAssertTrue(fixture.pager.prepareForInteraction())
        XCTAssertNil(overlay(in: fixture.pager))
    }

    private func loadNextEditor(_ fixture: Fixture) {
        fixture.editor.string = fixture.next.text
        fixture.editor.representedScratchID = fixture.next.id
        fixture.editor.displayResults = fixture.next.results
        fixture.editor.layoutResults()
        fixture.pager.updatePages(currentID: fixture.next.id, text: fixture.next.text,
                                  previous: ScratchPagePreview(id: fixture.currentID, text: "Current", results: []), next: nil)
    }

    private func imageData(_ image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    private func layerImage(_ layer: CALayer) throws -> CGImage {
        let contents = try XCTUnwrap(layer.contents)
        XCTAssertEqual(CFGetTypeID(contents as CFTypeRef), CGImage.typeID)
        return contents as! CGImage
    }

    private func hasDrawnContent(_ image: CGImage, xRange: Range<Int>, yRange: Range<Int>) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var darkPixels = 0
        for y in stride(from: yRange.lowerBound, to: min(yRange.upperBound, bitmap.pixelsHigh), by: 2) {
            for x in stride(from: xRange.lowerBound, to: min(xRange.upperBound, bitmap.pixelsWide), by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.8,
                   min(color.redComponent, color.greenComponent, color.blueComponent) < 0.7 { darkPixels += 1 }
            }
        }
        return darkPixels > 20
    }

    private func exportPreview(current: CGImage, neighbor: CGImage, currentOffset: CGFloat, neighborOffset: CGFloat) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1_520, pixelsHigh: 900,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1_520, height: 900))
        context.draw(neighbor, in: CGRect(x: neighborOffset * 2, y: 0, width: 1_520, height: 900))
        context.draw(current, in: CGRect(x: currentOffset * 2, y: 0, width: 1_520, height: 900))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/bobby-swipe-preview.png"))
    }
}
