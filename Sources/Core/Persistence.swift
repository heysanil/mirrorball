import Foundation

/// Loads and saves the list of forwards as pretty-printed JSON.
///
/// Writes are atomic. A missing or malformed file degrades gracefully to an
/// empty list rather than throwing on load, so a corrupted config never wedges
/// the app — matching the original's "graceful defaults" behavior.
struct Persistence: Sendable {
    let fileURL: URL

    init(configDirectory: URL) {
        fileURL = configDirectory.appendingPathComponent("forwards.json", isDirectory: false)
    }

    /// Best-effort load. Returns `[]` if the file is absent or unreadable.
    func load() -> [Forward] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? Self.decoder.decode([Forward].self, from: data)) ?? []
    }

    /// Atomically persist the full list, creating the directory if needed.
    func save(_ forwards: [Forward]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(forwards)
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()
}
