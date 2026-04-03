//
//  AgentTool.swift
//  MBAgentKit
//

import Foundation

public struct AgentToolContext: Sendable {
    public let requestUserInput: @Sendable (UserInputRequest) async -> UserInputResponse
    public let reportConfidence: @Sendable (Double) -> Void

    nonisolated public init(
        requestUserInput: @escaping @Sendable (UserInputRequest) async -> UserInputResponse,
        reportConfidence: @escaping @Sendable (Double) -> Void
    ) {
        self.requestUserInput = requestUserInput
        self.reportConfidence = reportConfidence
    }

    nonisolated public func askForText(
        title: String,
        prompt: String,
        placeholder: String? = nil
    ) async -> String? {
        let response = await requestUserInput(
            UserInputRequest(
                title: title,
                prompt: prompt,
                kind: .text(placeholder: placeholder)
            )
        )
        if case .submitted(let value) = response { return value }
        return nil
    }

    nonisolated public func askForChoice(
        title: String,
        prompt: String,
        options: [String]
    ) async -> String? {
        let response = await requestUserInput(
            UserInputRequest(
                title: title,
                prompt: prompt,
                kind: .singleChoice(options: options)
            )
        )
        if case .submitted(let value) = response { return value }
        return nil
    }

    nonisolated public func askForNumber(
        title: String,
        prompt: String,
        placeholder: String? = nil
    ) async -> Double? {
        let response = await requestUserInput(
            UserInputRequest(
                title: title,
                prompt: prompt,
                kind: .number(placeholder: placeholder)
            )
        )
        guard case .submitted(let value) = response else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated public func askForChoiceWithOther(
        title: String,
        prompt: String,
        options: [String],
        customPlaceholder: String? = nil
    ) async -> String? {
        let response = await requestUserInput(
            UserInputRequest(
                title: title,
                prompt: prompt,
                kind: .singleChoiceWithOther(options: options, customPlaceholder: customPlaceholder)
            )
        )
        if case .submitted(let value) = response { return value }
        return nil
    }

    nonisolated public func updateConfidence(_ value: Double) {
        reportConfidence(value)
    }
}

/// Protocol for tools that an ``AgentExecutor`` can invoke during a ReAct loop.
///
/// Each tool declares its LLM-facing definition and whether it requires
/// human confirmation (HITL) before execution.
public protocol AgentTool: Sendable {
    /// The tool's LLM schema (name, description, parameters).
    nonisolated var definition: Tool { get }

    /// Whether this tool requires user confirmation before execution.
    /// Mutation tools should typically set this to `true`.
    nonisolated var requiresConfirmation: Bool { get }

    /// SF Symbol name used to represent this tool in the UI.
    /// Defaults to `nil` (UI will use a generic fallback icon).
    nonisolated var iconName: String? { get }

    /// Execute the tool with the given arguments and context.
    ///
    /// - Parameter arguments: Parsed argument dictionary from the LLM response.
    /// - Parameter context: Context for HITL user input and confidence reporting.
    /// - Returns: A string result consumed by the LLM in the next iteration.
    nonisolated func execute(arguments: [String: ToolValue], context: AgentToolContext) async throws -> String
}

public extension AgentTool {
    nonisolated var iconName: String? { nil }
}

/// Closure-based lightweight tool implementation.
///
/// Convenient for wrapping simple logic without declaring a dedicated type.
public struct BlockTool: AgentTool {
    nonisolated public let definition: Tool
    nonisolated public let requiresConfirmation: Bool
    nonisolated public let iconName: String?
    nonisolated public let block: @Sendable ([String: ToolValue], AgentToolContext) async throws -> String

    nonisolated public init(
        name: String,
        description: String,
        parameters: ToolParameters,
        requiresConfirmation: Bool = false,
        iconName: String? = nil,
        block: @escaping @Sendable ([String: ToolValue], AgentToolContext) async throws -> String
    ) {
        self.definition = Tool(function: FunctionDefinition(
            name: name,
            description: description,
            parameters: parameters
        ))
        self.requiresConfirmation = requiresConfirmation
        self.iconName = iconName
        self.block = block
    }

    /// Convenience initializer for tools that don't need context access.
    nonisolated public init(
        name: String,
        description: String,
        parameters: ToolParameters,
        requiresConfirmation: Bool = false,
        iconName: String? = nil,
        block: @escaping @Sendable ([String: ToolValue]) async throws -> String
    ) {
        self.init(
            name: name,
            description: description,
            parameters: parameters,
            requiresConfirmation: requiresConfirmation,
            iconName: iconName
        ) { arguments, _ in
            try await block(arguments)
        }
    }

    nonisolated public func execute(arguments: [String: ToolValue], context: AgentToolContext) async throws -> String {
        try await block(arguments, context)
    }
}
