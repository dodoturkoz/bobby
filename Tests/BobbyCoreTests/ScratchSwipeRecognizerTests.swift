import XCTest
@testable import BobbyCore

final class ScratchSwipeRecognizerTests: XCTestCase {
    func testPhysicalDirectionDoesNotDependOnNaturalScrollingPreference() {
        XCTAssertEqual(ScratchSwipeRecognizer.physicalMotion(scrollingDelta: -90, invertedFromDevice: true), -90)
        XCTAssertEqual(ScratchSwipeRecognizer.physicalMotion(scrollingDelta: 90, invertedFromDevice: false), -90)
        XCTAssertEqual(ScratchSwipeRecognizer.physicalMotion(scrollingDelta: 90, invertedFromDevice: true), 90)
        XCTAssertEqual(ScratchSwipeRecognizer.physicalMotion(scrollingDelta: -90, invertedFromDevice: false), 90)
    }

    func testLeftSwipeNavigatesNextOnlyWhenTheGestureEnds() {
        var recognizer = ScratchSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(horizontal: -12, vertical: 0, phase: .began),
                       ScratchSwipeResponse(consumesEvent: true))
        XCTAssertNil(recognizer.handle(horizontal: -90, vertical: 2, phase: .changed).navigation)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, navigation: .next))
    }

    func testRightSwipeNavigatesPrevious() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: 5, vertical: 0, phase: .began)
        _ = recognizer.handle(horizontal: 90, vertical: 1, phase: .changed)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation, .previous)
    }

    func testVerticalScrollIsNeverConsumedEvenWithHorizontalDrift() {
        var recognizer = ScratchSwipeRecognizer()
        let samples: [(Double, Double, ScratchSwipePhase)] = [(3, -15, .began), (-8, -55, .changed), (-5, -40, .changed), (0, 0, .ended)]
        for (horizontal, vertical, phase) in samples {
            XCTAssertEqual(recognizer.handle(horizontal: horizontal, vertical: vertical, phase: phase), ScratchSwipeResponse())
        }
    }

    func testVerticalIntentCannotTurnIntoNavigationMidGesture() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: 1, vertical: 15, phase: .began)
        _ = recognizer.handle(horizontal: -200, vertical: 0, phase: .changed)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended), ScratchSwipeResponse())
    }

    func testDiagonalMotionDoesNotNavigate() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -9, vertical: 8, phase: .began)
        _ = recognizer.handle(horizontal: -90, vertical: 80, phase: .changed)
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
    }

    func testHorizontalIntentWithLaterVerticalMovementDoesNotNavigate() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -12, vertical: 1, phase: .began)
        _ = recognizer.handle(horizontal: -90, vertical: 90, phase: .changed)
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
    }

    func testSmallHorizontalJitterDoesNotNavigateOrConsumeEvents() {
        var recognizer = ScratchSwipeRecognizer()
        for phase in [ScratchSwipePhase.began, .changed, .changed, .ended] {
            XCTAssertEqual(recognizer.handle(horizontal: -1, vertical: 0.5, phase: phase), ScratchSwipeResponse())
        }
    }

    func testShortHorizontalGestureDoesNotNavigate() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -20, vertical: 0, phase: .began)
        XCTAssertNil(recognizer.handle(horizontal: -20, vertical: 0, phase: .ended).navigation)
    }

    func testReversingToTheStartingPointDoesNotNavigate() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        _ = recognizer.handle(horizontal: 100, vertical: 0, phase: .changed)
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
    }

    func testCancelledSwipeNeverNavigates() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .cancelled),
                       ScratchSwipeResponse(consumesEvent: true))
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
    }

    func testMomentumCannotFinishAnInsufficientGestureOrStartANewOne() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -20, vertical: 0, phase: .began)
        _ = recognizer.handle(horizontal: 0, vertical: 0, phase: .ended)
        XCTAssertEqual(recognizer.handle(horizontal: -200, vertical: 0, phase: .none, isMomentum: true),
                       ScratchSwipeResponse(consumesEvent: true))
        recognizer.reset()
        XCTAssertEqual(recognizer.handle(horizontal: -200, vertical: 0, phase: .none, isMomentum: true), ScratchSwipeResponse())
    }

    func testCompletedGestureAndItsMomentumNavigateOnlyOnce() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation, .next)
        for _ in 0..<5 {
            XCTAssertNil(recognizer.handle(horizontal: -100, vertical: 0, phase: .none, isMomentum: true).navigation)
        }
        XCTAssertNil(recognizer.handle(horizontal: -100, vertical: 0, phase: .ended).navigation)
    }

    func testANewGestureStartsCleanAfterThePreviousOne() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        _ = recognizer.handle(horizontal: 0, vertical: 0, phase: .ended)
        _ = recognizer.handle(horizontal: 100, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation, .previous)
    }

    func testMayBeginAndExplicitResetDiscardIncompleteGestures() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        _ = recognizer.handle(horizontal: 0, vertical: 0, phase: .mayBegin)
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        recognizer.reset()
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
    }

    func testUnphasedWheelAndChangedWithoutBeganDoNotNavigate() {
        var recognizer = ScratchSwipeRecognizer()
        XCTAssertEqual(recognizer.handle(horizontal: -300, vertical: 0, phase: .none), ScratchSwipeResponse())
        XCTAssertEqual(recognizer.handle(horizontal: -300, vertical: 0, phase: .changed), ScratchSwipeResponse())
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended), ScratchSwipeResponse())
    }

    func testInvalidMotionCancelsRecognition() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: .nan, vertical: 0, phase: .changed), ScratchSwipeResponse())
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
    }
}
