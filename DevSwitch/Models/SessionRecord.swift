import Foundation

// MARK: - JSONL Record Envelope

/// Top-level envelope for every line in a Claude Code JSONL session file.
struct SessionRecord: Codable, Sendable {
    let type: RecordType
    let uuid: String?
    let parentUuid: String?
    let timestamp: Date?
    let sessionId: String?
    let cwd: String?
    let message: MessagePayload?
    let costUSD: Double?
    let version: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case type, uuid, parentUuid, timestamp, sessionId, cwd, message
        case costUSD, version, requestId
    }
}

// MARK: - Record Type

enum RecordType: String, Codable, Sendable {
    case user
    case assistant
    case toolResult = "tool_result"
    case system
    case summary
    case result
    case fileHistorySnapshot = "file-history-snapshot"
    case progress
    case queueOperation = "queue-operation"
}

// MARK: - Message Payload

struct MessagePayload: Codable, Sendable {
    let role: String?
    let model: String?
    let content: AnyCodableContent?
    let usage: UsageData?
    let id: String?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case role, model, content, usage, id
        case isError = "is_error"
    }
}

// MARK: - Usage Data

struct UsageData: Codable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheCreation: CacheCreationData?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheCreation = "cache_creation"
    }
}

struct CacheCreationData: Codable, Sendable {
    let ephemeral5mInputTokens: Int?
    let ephemeral1hInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
    }
}

// MARK: - Flexible Content Handling

enum AnyCodableContent: Codable, Sendable {
    case string(String)
    case array([[String: AnyCodableValue]])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }
        if let arr = try? container.decode([[String: AnyCodableValue]].self) {
            self = .array(arr)
            return
        }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }
}
