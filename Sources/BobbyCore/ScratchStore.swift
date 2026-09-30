import Foundation

public struct Scratch: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public struct ScratchCollection: Codable, Equatable, Sendable {
    public var version: Int
    public var scratches: [Scratch]
    public var selectedID: UUID?
    public var yearBasis: Int

    public init(
        version: Int = 1,
        scratches: [Scratch] = [],
        selectedID: UUID? = nil,
        yearBasis: Int = 365
    ) {
        self.version = version
        self.scratches = scratches
        self.selectedID = selectedID
        self.yearBasis = yearBasis
    }
}

public enum ScratchStoreError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidYearBasis(Int)
    case duplicateScratchID(UUID)
    case corruptData

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "These scratches use an unsupported file version (\(version)). The existing file has been preserved."
        case .invalidYearBasis:
            return "The interest year basis must be a positive number of days."
        case .duplicateScratchID:
            return "The scratch file contains duplicate identifiers. The existing file has been preserved."
        case .corruptData:
            return "The scratch file could not be read. The existing file has been preserved."
        }
    }
}

/// A synchronous store intended to be used serially by the app's model.
/// A damaged or newer file must be moved aside explicitly before saving again.
public struct ScratchStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ScratchCollection? {
        guard let data = try existingData() else { return nil }
        return try decode(data)
    }

    public func save(_ collection: ScratchCollection) throws {
        let validCollection = try validated(collection)

        // Do not let autosave replace unreadable data after a failed load.
        if let existing = try existingData() {
            _ = try decode(existing)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Foundation's default Date coding preserves the original precision.
        let data = try encoder.encode(validCollection)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func existingData() throws -> Data? {
        do {
            return try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func decode(_ data: Data) throws -> ScratchCollection {
        let collection: ScratchCollection
        do {
            collection = try JSONDecoder().decode(ScratchCollection.self, from: data)
        } catch {
            throw ScratchStoreError.corruptData
        }
        return try validated(collection)
    }

    private func validated(_ collection: ScratchCollection) throws -> ScratchCollection {
        guard collection.version == 1 else {
            throw ScratchStoreError.unsupportedVersion(collection.version)
        }
        guard collection.yearBasis > 0 else {
            throw ScratchStoreError.invalidYearBasis(collection.yearBasis)
        }

        var ids: Set<UUID> = []
        for scratch in collection.scratches {
            guard ids.insert(scratch.id).inserted else {
                throw ScratchStoreError.duplicateScratchID(scratch.id)
            }
        }

        var validCollection = collection
        if let selectedID = collection.selectedID, ids.contains(selectedID) {
            return validCollection
        }
        validCollection.selectedID = collection.scratches.first?.id
        return validCollection
    }
}
