import Foundation

/// Parses Claude Code JSONL session files into typed Swift structs.
struct JSONLParser: Sendable {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = ISO8601DateFormatter.flexible.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }()

    /// Parse a single JSONL line into a SessionRecord.
    static func parseLine(_ line: String) -> SessionRecord? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let data = line.data(using: .utf8) else { return nil }
        do {
            return try decoder.decode(SessionRecord.self, from: data)
        } catch {
            return nil
        }
    }

    /// Parse multiple JSONL lines.
    static func parseLines(_ text: String) -> [SessionRecord] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0)) }
    }

    /// Parse a complete JSONL file at a given path.
    static func parseFile(at url: URL) -> [SessionRecord] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseLines(data)
    }

    /// Parse only new content from a file starting at a byte offset.
    static func parseFileIncremental(at url: URL, fromOffset: UInt64) -> (records: [SessionRecord], newOffset: UInt64) {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return ([], fromOffset)
        }
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        guard fileSize > fromOffset else {
            return ([], fromOffset)
        }

        fileHandle.seek(toFileOffset: fromOffset)
        let newData = fileHandle.readDataToEndOfFile()
        guard let text = String(data: newData, encoding: .utf8) else {
            return ([], fileSize)
        }

        let records = parseLines(text)
        return (records, fileSize)
    }
}

// MARK: - ISO8601 Flexible Formatter

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let flexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}
