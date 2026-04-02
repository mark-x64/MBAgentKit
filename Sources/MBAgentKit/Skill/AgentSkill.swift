//
//  AgentSkill.swift
//  MBAgentKit
//

import Foundation

/// A composable bundle of system prompt, tools, and configuration
/// that defines a specialized agent capability.
///
/// Skills are reusable "modes" that can be activated on demand.
/// Each skill encapsulates everything needed to run a focused agent:
///
/// ```swift
/// let codeReview = AgentSkill(
///     name: "code_review",
///     description: "Reviews code for bugs and best practices",
///     systemPrompt: "You are an expert code reviewer...",
///     tools: [readFileTool, searchTool]
/// )
///
/// // Run directly
/// let stream = codeReview.run(llm: service, userMessage: "Review this PR")
///
/// // Or create an executor for manual control
/// let executor = codeReview.makeExecutor(llm: service)
/// ```
public struct AgentSkill: Sendable {
    public let name: String
    public let description: String
    public let systemPrompt: String
    public let tools: [any AgentTool]
    public let configuration: AgentConfiguration

    public init(
        name: String,
        description: String,
        systemPrompt: String,
        tools: [any AgentTool],
        configuration: AgentConfiguration = .default
    ) {
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.configuration = configuration
    }

    /// Create an ``AgentExecutor`` configured with this skill's tools and settings.
    public func makeExecutor(llm: any LLMServiceProtocol) -> AgentExecutor {
        AgentExecutor(llm: llm, tools: tools, configuration: configuration)
    }

    /// Convenience: run this skill with a single user message.
    public func run(
        llm: any LLMServiceProtocol,
        userMessage: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let executor = makeExecutor(llm: llm)
        return executor.run(messages: [
            .system(systemPrompt),
            .user(userMessage)
        ])
    }

    /// Convert this skill into a ``SubAgentTool`` so a parent agent can invoke it.
    public func asSubAgentTool(llm: any LLMServiceProtocol) -> SubAgentTool {
        SubAgentTool(
            name: name,
            description: description,
            llm: llm,
            tools: tools,
            systemPrompt: systemPrompt,
            maxIterations: configuration.maxIterations
        )
    }
}
