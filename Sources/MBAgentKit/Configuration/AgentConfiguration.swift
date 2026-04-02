//
//  AgentConfiguration.swift
//  MBAgentKit
//

import Foundation

/// Runtime configuration for the Agent execution engine.
///
/// Provides sensible defaults that can be overridden per-executor.
public struct AgentConfiguration: Sendable {

    /// Maximum ReAct loop iterations before the executor stops.
    public let maxIterations: Int

    /// Maximum number of messages retained in an ``AgentSession`` before
    /// older (non-system) messages are discarded.
    public let sessionMaxMessages: Int

    /// LLM sampling temperature used during agent execution.
    public let temperature: Double

    /// Optional context compression strategy applied between iterations.
    ///
    /// When set, the executor calls this strategy after each tool-call cycle
    /// to intelligently compress the conversation history. When `nil`,
    /// the session's built-in sliding window is used as a fallback.
    public let contextStrategy: (any ContextStrategy)?

    /// Sensible defaults matching common LLM usage patterns.
    public static let `default` = AgentConfiguration()

    public init(
        maxIterations: Int = 50,
        sessionMaxMessages: Int = 20,
        temperature: Double = 0.7,
        contextStrategy: (any ContextStrategy)? = nil
    ) {
        self.maxIterations = maxIterations
        self.sessionMaxMessages = sessionMaxMessages
        self.temperature = temperature
        self.contextStrategy = contextStrategy
    }
}
