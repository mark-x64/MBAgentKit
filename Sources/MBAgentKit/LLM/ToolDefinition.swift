//
//  ToolDefinition.swift
//  MBAgentKit
//

import Foundation

// MARK: - Function Calling Tool Definition

/// Tool definition compatible with OpenAI-style Function Calling APIs.
public struct Tool: Codable, Sendable {
    public let type: String
    public let function: FunctionDefinition

    public init(function: FunctionDefinition) {
        self.type = "function"
        self.function = function
    }
}

/// Function definition within a tool.
public struct FunctionDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let parameters: ToolParameters

    public init(name: String, description: String, parameters: ToolParameters) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// JSON Schema object describing tool parameters.
public struct ToolParameters: Codable, Sendable {
    public let type: String
    public let properties: [String: ToolProperty]
    public let required: [String]

    public init(properties: [String: ToolProperty], required: [String]) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
}

/// Description of a single parameter property.
public struct ToolProperty: Codable, Sendable {
    public let type: String
    public let description: String

    public init(type: String, description: String) {
        self.type = type
        self.description = description
    }
}

// MARK: - LLM Tool Call Response

/// A single tool call returned by the LLM.
public struct ToolCall: Codable, Sendable {
    public let id: String
    public let type: String
    public let function: ToolCallFunction

    public init(id: String, type: String = "function", function: ToolCallFunction) {
        self.id = id
        self.type = type
        self.function = function
    }

    public struct ToolCallFunction: Codable, Sendable {
        public let name: String
        /// Tool arguments as a JSON-serialized string.
        public let arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }
}

// MARK: - chatCompletionWithTools Return Value

/// Response from a Function Calling LLM request.
public enum ToolCallResponse: Sendable {
    /// LLM returned a final text answer (finish_reason == "stop").
    case text(String)
    /// LLM requested tool execution (finish_reason == "tool_calls"),
    /// along with the assistant message to append to the conversation.
    case toolCalls([ToolCall], assistantMessage: ChatMessage)
}
