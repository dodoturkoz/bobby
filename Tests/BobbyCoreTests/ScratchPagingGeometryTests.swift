import XCTest
@testable import BobbyCore

final class ScratchPagingGeometryTests: XCTestCase {
    func testCommitThresholdAdaptsToWidthWithinUsefulBounds() {
        XCTAssertEqual(ScratchPagingGeometry.commitThreshold(viewportWidth: 400), 120)
        XCTAssertEqual(ScratchPagingGeometry.commitThreshold(viewportWidth: 1_000), 180)
        XCTAssertEqual(ScratchPagingGeometry.commitThreshold(viewportWidth: 1_600), 220)
        XCTAssertEqual(ScratchPagingGeometry.commitThreshold(viewportWidth: .greatestFiniteMagnitude), 220)
    }

    func testInvalidWidthsUseAStableFallbackThreshold() {
        for width in [0, -800, Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(ScratchPagingGeometry.commitThreshold(viewportWidth: width), 80)
        }
    }

    func testAvailableNeighborTracksFingerMotionInBothDirections() {
        for motion in [-240.0, -20, 0, 20, 240] {
            XCTAssertEqual(ScratchPagingGeometry.dragOffset(motion, viewportWidth: 800,
                                                            hasNeighbor: true), motion)
        }
    }

    func testAvailableNeighborCannotDragMoreThanOnePage() {
        XCTAssertEqual(ScratchPagingGeometry.dragOffset(-1_600, viewportWidth: 800, hasNeighbor: true), -800)
        XCTAssertEqual(ScratchPagingGeometry.dragOffset(1_600, viewportWidth: 800, hasNeighbor: true), 800)
        XCTAssertEqual(ScratchPagingGeometry.dragOffset(.greatestFiniteMagnitude,
                                                        viewportWidth: 800, hasNeighbor: true), 800)
    }

    func testBoundaryResistanceMatchesTheDefinedCurve() {
        for motion in [-600.0, -150, -20, 0, 20, 150, 600] {
            let expected = motion * 0.24 / (1 + abs(motion) / (800 * 0.18))
            XCTAssertEqual(ScratchPagingGeometry.dragOffset(motion, viewportWidth: 800,
                                                            hasNeighbor: false), expected, accuracy: 0.000_001)
        }
    }

    func testBoundaryResistanceIsSymmetricMonotoneAndBounded() {
        let width = 800.0
        let maximum = width * 0.18 * 0.24
        var previous = 0.0
        for motion in [1.0, 10, 50, 150, 600, 10_000, Double.greatestFiniteMagnitude] {
            let positive = ScratchPagingGeometry.dragOffset(motion, viewportWidth: width, hasNeighbor: false)
            let negative = ScratchPagingGeometry.dragOffset(-motion, viewportWidth: width, hasNeighbor: false)
            XCTAssertEqual(negative, -positive)
            XCTAssertGreaterThanOrEqual(positive, previous)
            XCTAssertLessThanOrEqual(positive, maximum)
            XCTAssertLessThan(positive, motion)
            previous = positive
        }
    }

    func testNextPageArrivesAtZeroWhenTheCurrentPageSlidesLeft() {
        let width = 800.0
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: 0, viewportWidth: width, direction: .next), width)
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: -160, viewportWidth: width, direction: .next), 640)
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: -width, viewportWidth: width, direction: .next), 0)
    }

    func testPreviousPageArrivesAtZeroWhenTheCurrentPageSlidesRight() {
        let width = 800.0
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: 0, viewportWidth: width, direction: .previous), -width)
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: 160, viewportWidth: width, direction: .previous), -640)
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: width, viewportWidth: width, direction: .previous), 0)
    }

    func testReversalReturnsBothPagesToTheirStartingPositions() {
        let width = 800.0
        for motion in [-160.0, -40, 0] {
            let pageOffset = ScratchPagingGeometry.dragOffset(motion, viewportWidth: width, hasNeighbor: true)
            let nextOffset = ScratchPagingGeometry.neighborOffset(pageOffset: pageOffset,
                                                                  viewportWidth: width, direction: .next)
            XCTAssertEqual(nextOffset - pageOffset, width)
        }
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: 0, viewportWidth: width, direction: .next), width)
    }

    func testInvalidGeometryNeverProducesAnOffset() {
        for width in [0.0, -800, .nan, .infinity, -.infinity] {
            for hasNeighbor in [true, false] {
                XCTAssertEqual(ScratchPagingGeometry.dragOffset(100, viewportWidth: width,
                                                                hasNeighbor: hasNeighbor), 0)
            }
            XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: 100, viewportWidth: width,
                                                                direction: .next), 0)
        }
        for motion in [Double.nan, .infinity, -.infinity] {
            for hasNeighbor in [true, false] {
                XCTAssertEqual(ScratchPagingGeometry.dragOffset(motion, viewportWidth: 800,
                                                                hasNeighbor: hasNeighbor), 0)
            }
            XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: motion, viewportWidth: 800,
                                                                direction: .previous), 0)
        }
    }

    func testOverflowingNeighborPositionFallsBackToZero() {
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: .greatestFiniteMagnitude,
                                                            viewportWidth: .greatestFiniteMagnitude,
                                                            direction: .next), 0)
        XCTAssertEqual(ScratchPagingGeometry.neighborOffset(pageOffset: -.greatestFiniteMagnitude,
                                                            viewportWidth: .greatestFiniteMagnitude,
                                                            direction: .previous), 0)
    }
}
