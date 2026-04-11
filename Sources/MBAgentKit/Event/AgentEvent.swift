//
//  AgentEvent.swift
//  MBAgentKit
//

import Foundation

/// Sendable JSON value used for tool arguments.
public enum ToolValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ToolValue])
    case object([String: ToolValue])
    case null

    nonisolated public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    nonisolated public var jsonDescription: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return "[" + values.map(\.jsonDescription).joined(separator: ", ") + "]"
        case .object(let object):
            let pairs = object
                .sorted { $0.key < $1.key }
                .map { "\"\($0)\": \($1.jsonDescription)" }
            return "{" + pairs.joined(separator: ", ") + "}"
        case .null:
            return "null"
        }
    }

    nonisolated public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: ToolValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([ToolValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    nonisolated public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Sendable wrapper for tool call arguments, replacing `[String: Any]`.
///
/// Carries both the raw JSON string (for full-fidelity forwarding)
/// and a flattened key-value dictionary (for UI display).
public struct ToolArguments: Sendable {
    /// The original JSON string from the LLM response.
    public let raw: String
    /// Flattened key-value pairs for display purposes.
    /// Complex nested values are serialized to their JSON string form.
    public let parsed: [String: String]

    nonisolated public init(raw: String, parsed: [String: String]) {
        self.raw = raw
        self.parsed = parsed
    }

    /// Convenience initializer that parses a JSON string into key-value pairs.
    nonisolated public init(jsonString: String) {
        self.raw = jsonString
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: ToolValue].self, from: data) else {
            self.parsed = [:]
            return
        }
        self.parsed = json.mapValues(\.jsonDescription)
    }

    /// The empty arguments instance.
    public static let empty = ToolArguments(raw: "{}", parsed: [:])
}

public enum UserInputKind: Sendable {
    case text(placeholder: String?)
    case singleChoice(options: [String])
    case number(placeholder: String?)
    case singleChoiceWithOther(options: [String], customPlaceholder: String?)
    /// Slider with optional discrete steps.
    ///
    /// - Parameters:
    ///   - min: Lower bound (inclusive).
    ///   - max: Upper bound (inclusive). Must be greater than `min`.
    ///   - step: Discrete step size. `nil` for a continuous slider.
    ///   - defaultValue: Initial slider position. Clamped into `[min, max]`.
    ///   - unit: Optional unit label shown next to the current value (e.g. `"min"`, `"%"`).
    ///   - labels: Optional tick labels. When non-empty, one label per discrete stop
    ///     (requires `step` and `labels.count == Int((max - min) / step) + 1`).
    case slider(
        min: Double,
        max: Double,
        step: Double?,
        defaultValue: Double,
        unit: String?,
        labels: [String]?
    )
}

public struct UserInputRequest: Sendable {
    public let title: String
    public let prompt: String
    public let kind: UserInputKind

    nonisolated public init(title: String, prompt: String, kind: UserInputKind) {
        self.title = title
        self.prompt = prompt
        self.kind = kind
    }
}

public enum UserInputResponse: Sendable {
    case submitted(String)
    case cancelled
}

/// Events emitted by ``AgentExecutor`` during a ReAct loop, driving reactive UI.
///
/// NOTE: @unchecked Sendable because `case error(any Error)` carries a non-Sendable
/// associated value. Error types in practice are thread-safe.
public enum AgentEvent: @unchecked Sendable {
    /// A new iteration of the ReAct loop has started.
    case iterationStarted(Int)

    /// The LLM produced reasoning/thought content.
    case thought(String)

    /// The LLM is invoking a tool (pre-execution).
    case toolCalling(id: String, name: String, arguments: ToolArguments, iconName: String?)

    /// A sensitive tool requires human confirmation before execution.
    case awaitingConfirmation(id: String, toolName: String, arguments: ToolArguments)

    /// The tool reported the agent's current confidence estimate.
    case confidenceUpdated(Double)

    /// A tool requested free-form or choice-based user input.
    case awaitingUserInput(id: String, request: UserInputRequest)

    /// The pending user input request has been resolved.
    case userInputResolved(id: String)

    /// A tool has returned its result.
    case toolResult(id: String, name: String, result: String, iconName: String?)

    /// The LLM produced final answer text.
    case answer(String)

    /// The agent run completed successfully.
    case completed(finalMessage: ChatMessage)

    /// An error occurred during execution.
    case error(any Error)
}
