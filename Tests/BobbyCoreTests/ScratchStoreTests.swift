import Foundation
import XCTest
@testable import BobbyCore

final class ScratchStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private var store: ScratchStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BobbyScratchStoreTests-\(UUID().uuidString)")
        fileURL = directory.appendingPathComponent("state/scratches.json")
        store = ScratchStore(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testMissingFileReturnsNilWithoutCreatingAnything() throws {
        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRoundTripPreservesTextMetadataOrderAndSettings() throws {
        let created = Date(timeIntervalSinceReferenceDate: 123_456_789.123456)
        let updated = Date(timeIntervalSinceReferenceDate: 234_567_890.987654)
        let first = Scratch(text: "500k TL %40 yıllık 32 gün\nNotes 🐾\n", createdAt: created, updatedAt: updated)
        let second = Scratch(text: "", createdAt: updated)
        let collection = ScratchCollection(
            scratches: [first, second], selectedID: second.id, yearBasis: 360
        )

        try store.save(collection)

        XCTAssertEqual(try store.load(), collection)
        XCTAssertEqual(second.createdAt, second.updatedAt)
    }

    func testExistingValidFileCanBeReplaced() throws {
        let scratch = Scratch(text: "1 + 1")
        try store.save(ScratchCollection(scratches: [scratch], selectedID: scratch.id))
        var changed = scratch
        changed.text = "1 + 2\nPlanning a trip"
        changed.updatedAt = Date()
        let replacement = ScratchCollection(scratches: [changed], selectedID: changed.id)

        try store.save(replacement)

        XCTAssertEqual(try store.load(), replacement)
    }

    func testInvalidSelectionFallsBackToFirstScratch() throws {
        let first = Scratch(text: "first")
        let second = Scratch(text: "second")
        let collection = ScratchCollection(scratches: [first, second], selectedID: UUID())
        try writeDirectly(collection)

        let loaded = try XCTUnwrap(store.load())

        XCTAssertEqual(loaded.selectedID, first.id)
        XCTAssertEqual(loaded.scratches, collection.scratches)
    }

    func testMissingSelectionFallsBackAndEmptyCollectionIsValid() throws {
        let scratch = Scratch(text: "note")
        try store.save(ScratchCollection(scratches: [scratch]))
        XCTAssertEqual(try store.load()?.selectedID, scratch.id)

        try store.save(ScratchCollection(scratches: [], selectedID: scratch.id))
        let empty = try XCTUnwrap(store.load())
        XCTAssertTrue(empty.scratches.isEmpty)
        XCTAssertNil(empty.selectedID)
    }

    func testCorruptFileThrowsAndCannotBeOverwritten() throws {
        let original = Data("{ incomplete but important text: yıllık faiz".utf8)
        try writeDirectly(original)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ScratchStoreError, .corruptData)
        }
        XCTAssertThrowsError(try store.save(ScratchCollection())) { error in
            XCTAssertEqual(error as? ScratchStoreError, .corruptData)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testUnsupportedVersionThrowsAndCannotBeOverwritten() throws {
        let newer = ScratchCollection(version: 2, scratches: [Scratch(text: "future scratch")])
        try writeDirectly(newer)
        let original = try Data(contentsOf: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ScratchStoreError, .unsupportedVersion(2))
        }
        XCTAssertThrowsError(try store.save(ScratchCollection())) { error in
            XCTAssertEqual(error as? ScratchStoreError, .unsupportedVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testInvalidSettingsAreRejectedBeforeReplacingExistingText() throws {
        let scratch = Scratch(text: "keep this")
        let valid = ScratchCollection(scratches: [scratch], selectedID: scratch.id)
        try store.save(valid)

        XCTAssertThrowsError(try store.save(ScratchCollection(yearBasis: 0))) { error in
            XCTAssertEqual(error as? ScratchStoreError, .invalidYearBasis(0))
        }
        XCTAssertEqual(try store.load(), valid)
    }

    func testDuplicateIdentifiersAreRejected() throws {
        let scratch = Scratch(text: "keep identities unique")
        let duplicated = ScratchCollection(scratches: [scratch, scratch])

        XCTAssertThrowsError(try store.save(duplicated)) { error in
            XCTAssertEqual(error as? ScratchStoreError, .duplicateScratchID(scratch.id))
        }
        XCTAssertNil(try store.load())
    }

    private func writeDirectly(_ collection: ScratchCollection) throws {
        try writeDirectly(JSONEncoder().encode(collection))
    }

    private func writeDirectly(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
    }
}
