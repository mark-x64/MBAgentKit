//
//  AgentEvent.swift
//  MBAgentKit
//

import Foundation

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

    public init(raw: String, parsed: [String: String]) {
        self.raw = raw
        self.parsed = parsed
    }

    /// Convenience initializer that parses a JSON string into key-value pairs.
    public init(jsonString: String) {
        self.raw = jsonString
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            self.parsed = [:]
            return
        }
        var result: [String: String] = [:]
        for (key, value) in json {
            result[key] = String(describing: value)
        }
        self.parsed = result
    }

    /// The empty arguments instance.
    public static let empty = ToolArguments(raw: "{}", parsed: [:])
}

/// Events emitted by ``AgentExecutor`` during a ReAct loop, driving reactive UI.
public enum AgentEvent: Sendable {
    /// A new iteration of the ReAct loop has started.
    case iterationStarted(Int)

    /// The LLM produced reasoning/thought content.
    case thought(String)

    /// The LLM is invoking a tool (pre-execution).
    case toolCalling(id: String, name: String, arguments: ToolArguments)

    /// A sensitive tool requires human confirmation before execution.
    case awaitingConfirmation(id: String, toolName: String, arguments: ToolArguments)

    /// A tool has returned its result.
    case toolResult(id: String, name: String, result: String)

    /// The LLM produced final answer text.
    case answer(String)

    /// The agent run completed successfully.
    case completed(finalMessage: ChatMessage)

    /// An error occurred during execution.
    case error(any Error)
}
