import Foundation

/// Extracts concrete `Host` aliases from `~/.ssh/config` to populate the editor's
/// host picker. Wildcard / pattern entries (`*`, `?`, `!`) are skipped — they are
/// rules, not connectable hosts.
enum SSHConfigParser {
    /// Default location of the user's SSH config.
    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config", isDirectory: false)
    }

    /// Read and parse aliases from a config file. Returns `[]` if unreadable.
    static func aliases(at url: URL = SSHConfigParser.defaultConfigURL) -> [String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return aliases(fromContents: contents)
    }

    /// Parse aliases from raw config text. Preserves first-seen order, de-duplicates.
    static func aliases(fromContents contents: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = tokens.first, keyword.lowercased() == "host" else { continue }

            for token in tokens.dropFirst() {
                let host = String(token)
                // Skip patterns: globs, single-char wildcards, and negations.
                guard !host.contains("*"), !host.contains("?"), !host.hasPrefix("!") else { continue }
                if seen.insert(host).inserted {
                    result.append(host)
                }
            }
        }
        return result
    }
}
