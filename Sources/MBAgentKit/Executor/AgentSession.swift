//
//  AgentSession.swift
//  MBAgentKit
//

import Foundation

/// Manages the message history for an Agent conversation.
///
/// Provides two levels of context compression:
/// 1. **Sync sliding window** — automatic on every `append`, drops oldest messages.
/// 2. **Async strategy** — call ``compress(using:)`` between iterations for
///    intelligent compression (e.g., LLM-based summarization).
public struct AgentSession: Sendable {
    public private(set) var messages: [ChatMessage] = []

    /// Maximum number of messages before compression kicks in.
    public let maxMessageCount: Int

    /// Creates a new session with the given system prompt.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system prompt that anchors the conversation.
    ///   - maxMessageCount: Upper limit on retained messages.
    public init(
        systemPrompt: String,
        maxMessageCount: Int = AgentConfiguration.default.sessionMaxMessages
    ) {
        self.messages = [.system(systemPrompt)]
        self.maxMessageCount = maxMessageCount
    }

    public mutating func append(_ message: ChatMessage) {
        messages.append(message)
        trimIfNeeded()
    }

    public mutating func append(contentsOf newMessages: [ChatMessage]) {
        messages.append(contentsOf: newMessages)
        trimIfNeeded()
    }

    /// Returns the full message history for sending to the LLM.
    public func getHistory() -> [ChatMessage] {
        messages
    }

    // MARK: - Async Strategy Compression

    /// Apply a ``ContextStrategy`` to intelligently compress the history.
    ///
    /// Call this between ReAct iterations when a strategy is configured.
    /// If the strategy throws, the session state remains unchanged.
    public mutating func compress(using strategy: any ContextStrategy) async throws {
        let compressed = try await strategy.compress(messages: messages, limit: maxMessageCount)
        messages = compressed
    }

    // MARK: - Sliding Window (sync fallback)

    /// Discards oldest non-system messages when the count exceeds the limit.
    ///
    /// Ensures the trimmed sequence never starts with an orphaned `.tool` result message
    /// (which would cause API errors because the corresponding tool-calls assistant message
    /// was dropped) or an assistant tool-calls message whose results were partially trimmed.
    private mutating func trimIfNeeded() {
        guard messages.count > maxMessageCount else { return }

        let systemMsg = messages.first { $0.role == .system }
        let keepCount = maxMessageCount - (systemMsg != nil ? 1 : 0)
        var recent = Array(messages.suffix(keepCount))

        // Drop leading orphaned tool-result messages (their tool_calls assistant was trimmed).
        while recent.first?.role == .tool {
            recent.removeFirst()
        }

        // Drop a leading assistant-with-toolCalls message if any of its results were also trimmed.
        if let first = recent.first,
           first.role == .assistant,
           let calls = first.toolCalls {
            let callIds = Set(calls.map(\.id))
            let resultIds = Set(
                recent.dropFirst()
                    .prefix(while: { $0.role == .tool })
                    .compactMap(\.toolCallId)
            )
            if !callIds.isSubset(of: resultIds) {
                recent.removeFirst()
                while recent.first?.role == .tool { recent.removeFirst() }
            }
        }

        var newMessages: [ChatMessage] = []
        if let systemMsg { newMessages.append(systemMsg) }
        newMessages.append(contentsOf: recent)
        self.messages = newMessages
    }
}
