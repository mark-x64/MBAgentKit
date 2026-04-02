//
//  AgentTool.swift
//  MBAgentKit
//

import Foundation

/// Protocol for tools that an ``AgentExecutor`` can invoke during a ReAct loop.
///
/// Each tool declares its LLM-facing definition and whether it requires
/// human confirmation (HITL) before execution.
public protocol AgentTool: Sendable {
    /// The tool's LLM schema (name, description, parameters).
    var definition: Tool { get }

    /// Whether this tool requires user confirmation before execution.
    /// Mutation tools should typically set this to `true`.
    var requiresConfirmation: Bool { get }

    /// Execute the tool with the given arguments.
    ///
    /// - Parameter arguments: Parsed argument dictionary from the LLM response.
    /// - Returns: A string result consumed by the LLM in the next iteration.
    func execute(arguments: [String: Any]) async throws -> String
}

/// Closure-based lightweight tool implementation.
///
/// Convenient for wrapping simple logic without declaring a dedicated type.
public struct BlockTool: AgentTool {
    public let definition: Tool
    public let requiresConfirmation: Bool
    public let block: @Sendable ([String: Any]) async throws -> String

    public init(
        name: String,
        description: String,
        parameters: ToolParameters,
        requiresConfirmation: Bool = false,
        block: @escaping @Sendable ([String: Any]) async throws -> String
    ) {
        self.definition = Tool(function: FunctionDefinition(
            name: name,
            description: description,
            parameters: parameters
        ))
        self.requiresConfirmation = requiresConfirmation
        self.block = block
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        try await block(arguments)
    }
}
