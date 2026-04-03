//
//  SubAgentTool.swift
//  MBAgentKit
//

import Foundation

/// A tool that spawns a child ``AgentExecutor`` to handle a focused subtask.
///
/// The parent agent delegates complex sub-problems by calling this tool
/// with a `task` argument. The child runs its own ReAct loop with a
/// separate set of tools and returns the final answer to the parent.
///
/// ```swift
/// let researcher = SubAgentTool(
///     name: "research_agent",
///     description: "Research a topic using available data sources",
///     llm: openAIService,
///     tools: [searchTool, readTool],
///     systemPrompt: "You are a thorough research assistant."
/// )
/// ```
public struct SubAgentTool: AgentTool, Sendable {
    public let definition: Tool
    public let requiresConfirmation: Bool

    private let runner: @Sendable (String) async throws -> String

    /// - Parameters:
    ///   - name: Tool name visible to the parent agent.
    ///   - description: What this sub-agent does (shown to the parent LLM).
    ///   - llm: LLM service for the child executor.
    ///   - tools: Tools available to the child executor.
    ///   - systemPrompt: System prompt for the child executor.
    ///   - maxIterations: Max ReAct iterations for the child (default 10).
    ///   - requiresConfirmation: Whether spawning needs HITL approval (default false).
    public init(
        name: String,
        description: String,
        llm: any LLMServiceProtocol,
        tools: [any AgentTool],
        systemPrompt: String,
        maxIterations: Int = 10,
        requiresConfirmation: Bool = false
    ) {
        self.definition = Tool(function: FunctionDefinition(
            name: name,
            description: description,
            parameters: ToolParameters(
                properties: [
                    "task": ToolProperty(type: "string", description: "The task to delegate to this sub-agent")
                ],
                required: ["task"]
            )
        ))
        self.requiresConfirmation = requiresConfirmation

        self.runner = { @Sendable task in
            let executor = AgentExecutor(
                llm: llm,
                tools: tools,
                configuration: AgentConfiguration(maxIterations: maxIterations)
            )

            var finalAnswer = ""
            let stream = executor.run(messages: [
                .system(systemPrompt),
                .user(task)
            ])

            for try await event in stream {
                if case .answer(let text) = event {
                    finalAnswer = text
                }
            }

            return finalAnswer.isEmpty
                ? "Sub-agent completed without producing a response."
                : finalAnswer
        }
    }

    public func execute(arguments: [String: ToolValue], context: AgentToolContext) async throws -> String {
        let task = arguments["task"]?.stringValue ?? ""
        guard !task.isEmpty else {
            return "Error: 'task' argument is required."
        }
        return try await runner(task)
    }
}
