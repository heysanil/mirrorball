import Foundation

/// Loads and saves the list of forwards as pretty-printed JSON.
///
/// Writes are atomic. A missing or malformed file degrades gracefully to an
/// empty list rather than throwing on load, so a corrupted config never wedges
/// the app — matching the original's "graceful defaults" behavior.
///
/// Loading never silently loses data: entries are decoded one at a time (a bad
/// entry is skipped, the rest still load), and whenever anything is dropped the
/// original file is first copied to `forwards.corrupt-<timestamp>.json`. Without
/// that copy, the next `save` would overwrite the only record of what was lost.
struct Persistence: Sendable {
    let fileURL: URL

    init(configDirectory: URL) {
        fileURL = configDirectory.appendingPathComponent("forwards.json", isDirectory: false)
    }

    /// Best-effort load. Returns `[]` if the file is absent; skips entries that
    /// fail to decode, backing the file up first if any were dropped.
    func load() -> [Forward] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let entries = try? Self.decoder.decode([FailableForward].self, from: data) else {
            backUpUnreadableFile()
            return []
        }
        let forwards = entries.compactMap(\.forward)
        if forwards.count != entries.count {
            backUpUnreadableFile()
        }
        return forwards
    }

    /// Copies the current file aside so a failed or partial load stays recoverable.
    private func backUpUnreadableFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("forwards.corrupt-\(formatter.string(from: Date())).json")
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    /// Decodes one array element, yielding `nil` instead of failing the whole array.
    private struct FailableForward: Decodable {
        let forward: Forward?

        init(from decoder: Decoder) throws {
            forward = try? Forward(from: decoder)
        }
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
