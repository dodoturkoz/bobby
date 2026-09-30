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
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: -12))
        XCTAssertNil(recognizer.handle(horizontal: -90, vertical: 2, phase: .changed).navigation)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, navigation: .next,
                                            dragOffset: -102, gestureEnded: true))
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
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: -100,
                                            gestureEnded: true, cancelled: true))
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
        XCTAssertEqual(recognizer.handle(horizontal: .nan, vertical: 0, phase: .changed),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: -100,
                                            gestureEnded: true, cancelled: true))
        XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
    }

    func testHorizontalProgressIncludesMovementBeforeIntentIsEstablished() {
        var recognizer = ScratchSwipeRecognizer()
        XCTAssertNil(recognizer.handle(horizontal: -4, vertical: 1, phase: .began).dragOffset)
        XCTAssertNil(recognizer.handle(horizontal: -4, vertical: 1, phase: .changed).dragOffset)
        XCTAssertEqual(recognizer.handle(horizontal: -4, vertical: 1, phase: .changed),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: -12))
        XCTAssertEqual(recognizer.handle(horizontal: -18, vertical: 0, phase: .changed).dragOffset, -30)
    }

    func testProgressFollowsReversalWithoutCommittingBeforeRelease() {
        var recognizer = ScratchSwipeRecognizer()
        let initial = recognizer.handle(horizontal: -120, vertical: 0, phase: .began)
        XCTAssertEqual(initial.dragOffset, -120)
        XCTAssertNil(initial.navigation)
        XCTAssertFalse(initial.gestureEnded)
        XCTAssertEqual(recognizer.handle(horizontal: 90, vertical: 0, phase: .changed).dragOffset, -30)
        XCTAssertEqual(recognizer.handle(horizontal: 50, vertical: 0, phase: .changed).dragOffset, 20)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: 20, gestureEnded: true))
    }

    func testReversalCanCommitInTheOppositeDirectionOnRelease() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        _ = recognizer.handle(horizontal: 190, vertical: 0, phase: .changed)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, navigation: .previous,
                                            dragOffset: 90, gestureEnded: true))
    }

    func testShortHorizontalReleaseSignalsSnapBackWithoutNavigation() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -20, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: -20, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: -40, gestureEnded: true))
    }

    func testFinalReleaseMotionCountsTowardProgressAndThreshold() {
        var recognizer = ScratchSwipeRecognizer(navigationThreshold: 120)
        _ = recognizer.handle(horizontal: -100, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: -20, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, navigation: .next,
                                            dragOffset: -120, gestureEnded: true))
    }

    func testConfiguredThresholdControlsCommitWithoutChangingLiveProgress() {
        var recognizer = ScratchSwipeRecognizer(navigationThreshold: 200)
        _ = recognizer.handle(horizontal: -150, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: -150, gestureEnded: true))
        _ = recognizer.handle(horizontal: -200, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation, .next)
    }

    func testInvalidConfiguredThresholdsUseTheDefault() {
        for threshold in [0.0, -1.0, Double.nan, .infinity] {
            var recognizer = ScratchSwipeRecognizer(navigationThreshold: threshold)
            _ = recognizer.handle(horizontal: -79, vertical: 0, phase: .began)
            XCTAssertNil(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation)
            _ = recognizer.handle(horizontal: -80, vertical: 0, phase: .began)
            XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended).navigation, .next)
        }
    }

    func testCancelledGestureSignalsSnapBackAndMomentumCannotMoveIt() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: 150, vertical: 0, phase: .began)
        let cancelled = recognizer.handle(horizontal: 50, vertical: 0, phase: .cancelled)
        XCTAssertEqual(cancelled.dragOffset, 150)
        XCTAssertTrue(cancelled.gestureEnded)
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertNil(cancelled.navigation)
        let momentum = recognizer.handle(horizontal: 200, vertical: 0, phase: .none, isMomentum: true)
        XCTAssertTrue(momentum.consumesEvent)
        XCTAssertNil(momentum.dragOffset)
        XCTAssertFalse(momentum.gestureEnded)
        XCTAssertFalse(momentum.cancelled)
    }

    func testVerticalCancellationDoesNotAnimateThePage() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: 1, vertical: 20, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .cancelled), ScratchSwipeResponse())
    }

    func testNewBeginStartsOffsetAtTheNewGestureMotion() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -150, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 15, vertical: 0, phase: .began),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: 15))
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: 15, gestureEnded: true))
    }

    func testMayBeginCancelsVisibleProgressBeforeStartingANewGesture() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -150, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .mayBegin),
                       ScratchSwipeResponse(dragOffset: -150, gestureEnded: true, cancelled: true))
        XCTAssertEqual(recognizer.handle(horizontal: -3, vertical: 1, phase: .began), ScratchSwipeResponse())
    }

    func testAccumulatedOverflowCancelsTheLastFiniteVisiblePosition() {
        var recognizer = ScratchSwipeRecognizer()
        _ = recognizer.handle(horizontal: -Double.greatestFiniteMagnitude, vertical: 0, phase: .began)
        XCTAssertEqual(recognizer.handle(horizontal: -Double.greatestFiniteMagnitude, vertical: 0, phase: .changed),
                       ScratchSwipeResponse(consumesEvent: true, dragOffset: -Double.greatestFiniteMagnitude,
                                            gestureEnded: true, cancelled: true))
        XCTAssertEqual(recognizer.handle(horizontal: 0, vertical: 0, phase: .ended), ScratchSwipeResponse())
    }
}
