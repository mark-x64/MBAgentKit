//
//  SummarizingStrategy.swift
//  MBAgentKit
//

import Foundation

/// Compresses older messages by summarizing them via an LLM call,
/// preserving key facts, decisions, and tool results.
///
/// The conversation is split into two regions:
/// - **Old region**: summarized into a single context message
/// - **Recent region**: kept intact for full-fidelity continuation
///
/// The split point is chosen to avoid breaking tool-call sequences.
///
/// ```
/// ┌─────────┐  ┌──────────────────┐  ┌───────────────────┐
/// │  System  │  │  [Summary of old  │  │  Recent messages   │
/// │  Prompt  │  │   conversation]   │  │  (kept verbatim)   │
/// └─────────┘  └──────────────────┘  └───────────────────┘
/// ```
public struct SummarizingStrategy: ContextStrategy {
    private let llm: any LLMServiceProtocol
    private let recentToKeep: Int
    private let summaryTemperature: Double

    /// - Parameters:
    ///   - llm: LLM service used to generate the summary.
    ///   - recentToKeep: Number of recent messages to preserve intact.
    ///   - summaryTemperature: Temperature for the summarization call.
    public init(
        llm: any LLMServiceProtocol,
        recentToKeep: Int = 10,
        summaryTemperature: Double = 0.2
    ) {
        self.llm = llm
        self.recentToKeep = recentToKeep
        self.summaryTemperature = summaryTemperature
    }

    public func compress(messages: [ChatMessage], limit: Int) async throws -> [ChatMessage] {
        guard messages.count > limit else { return messages }

        let systemPrompt = messages.first { $0.role == .system }
        let nonSystem = messages.filter { $0.role != .system }

        // Find a safe split point that doesn't break tool-call sequences
        let idealSplit = max(0, nonSystem.count - recentToKeep)
        let safeSplit = Self.findSafeSplitPoint(in: nonSystem, idealPoint: idealSplit)

        let oldMessages = Array(nonSystem.prefix(safeSplit))
        let recentMessages = Array(nonSystem.suffix(from: safeSplit))

        // If nothing to summarize, fall back to sliding window
        guard !oldMessages.isEmpty else {
            return try await SlidingWindowStrategy().compress(messages: messages, limit: limit)
        }

        let summary: String
        do {
            summary = try await generateSummary(of: oldMessages)
        } catch {
            // LLM summarization failed → degrade gracefully to sliding window
            return try await SlidingWindowStrategy().compress(messages: messages, limit: limit)
        }

        var result: [ChatMessage] = []
        if let systemPrompt { result.append(systemPrompt) }
        result.append(.user("[Previous conversation summary]\n\(summary)"))
        result.append(contentsOf: recentMessages)
        return result
    }

    // MARK: - Private

    private func generateSummary(of messages: [ChatMessage]) async throws -> String {
        let transcript = messages.map { Self.formatMessage($0) }.joined(separator: "\n")

        let prompt = """
        Summarize the following agent conversation concisely. \
        Preserve: key facts, user requests, decisions made, tool names called, \
        important tool results, and any unresolved items. \
        Omit: pleasantries, redundant exchanges, verbose tool arguments. \
        Output the summary directly with no preamble.

        ---
        \(transcript)
        ---
        """

        return try await llm.chatCompletion(
            messages: [
                .system("You are a precise conversation summarizer for an AI agent system."),
                .user(prompt)
            ],
            temperature: summaryTemperature,
            responseFormat: nil
        )
    }

    /// Finds a split point that doesn't break tool-call sequences.
    /// Walks forward from the ideal point until hitting a user or
    /// standalone assistant message.
    static func findSafeSplitPoint(in messages: [ChatMessage], idealPoint: Int) -> Int {
        var point = idealPoint
        while point < messages.count {
            let msg = messages[point]
            // Safe to split before a user message or an assistant message without tool calls
            if msg.role == .user || (msg.role == .assistant && msg.toolCalls == nil) {
                break
            }
            point += 1
        }
        return min(point, messages.count)
    }

    static func formatMessage(_ msg: ChatMessage) -> String {
        switch msg.role {
        case .assistant where msg.toolCalls != nil:
            let calls = msg.toolCalls!.map { tc in
                "→ \(tc.function.name)(\(tc.function.arguments))"
            }.joined(separator: "; ")
            let thought = msg.content.map { "Thought: \($0) | " } ?? ""
            return "[assistant] \(thought)\(calls)"
        case .tool:
            let content = msg.content ?? ""
            let truncated = content.count > 200
                ? String(content.prefix(200)) + "…"
                : content
            return "[tool_result] \(truncated)"
        default:
            return "[\(msg.role.rawValue)] \(msg.content ?? "")"
        }
    }
}
