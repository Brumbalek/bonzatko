import Foundation

/// Reads and writes one JSON file per class in Application Support.
/// Every write is atomic: the file is written next to the old one and swapped in only when complete.
struct ClassRepository: Sendable {
    let directory: URL

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "Bonzatko", directoryHint: .isDirectory)
            .appending(path: "Classes", directoryHint: .isDirectory)
    }

    init(directory: URL = ClassRepository.defaultDirectory) {
        self.directory = directory
    }

    struct LoadResult: Sendable {
        var classes: [SchoolClass]
        /// Files that could not be decoded. They are left untouched on disk.
        var unreadableFiles: [URL]
    }

    func loadAll() throws -> LoadResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var result = LoadResult(classes: [], unreadableFiles: [])
        for file in files {
            do {
                result.classes.append(try Self.decoder.decode(SchoolClass.self, from: Data(contentsOf: file)))
            } catch {
                result.unreadableFiles.append(file)
            }
        }
        return result
    }

    func save(_ schoolClass: SchoolClass) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(schoolClass)
        try data.write(to: fileURL(for: schoolClass.id), options: [.atomic])
    }

    func fileURL(for classID: UUID) -> URL {
        directory.appending(path: "\(classID.uuidString).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
