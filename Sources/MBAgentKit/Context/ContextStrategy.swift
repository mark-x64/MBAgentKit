//
//  ContextStrategy.swift
//  MBAgentKit
//

import Foundation

/// Strategy for compressing conversation history when it exceeds limits.
///
/// Implement this protocol to provide custom compression behaviors
/// such as summarization, selective pruning, or hybrid approaches.
public protocol ContextStrategy: Sendable {
    /// Compress the given messages to fit within the target limit.
    ///
    /// - Parameters:
    ///   - messages: Full message history including system prompt.
    ///   - limit: Maximum number of messages to retain.
    /// - Returns: Compressed message array that fits within the limit.
    func compress(messages: [ChatMessage], limit: Int) async throws -> [ChatMessage]
}

// MARK: - Sliding Window (default)

/// Drops the oldest non-system messages to fit within the limit.
///
/// This is the simplest strategy and matches the original behavior
/// of ``AgentSession``. No LLM call is needed.
public struct SlidingWindowStrategy: ContextStrategy {
    public init() {}

    public func compress(messages: [ChatMessage], limit: Int) async throws -> [ChatMessage] {
        guard messages.count > limit else { return messages }

        let systemPrompt = messages.first { $0.role == .system }
        let keepCount = limit - (systemPrompt != nil ? 1 : 0)

        var result: [ChatMessage] = []
        if let systemPrompt { result.append(systemPrompt) }
        result.append(contentsOf: messages.suffix(keepCount))
        return result
    }
}
