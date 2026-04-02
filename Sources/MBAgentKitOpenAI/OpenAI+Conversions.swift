//
//  OpenAI+Conversions.swift
//  MBAgentKitOpenAI
//
//  SDK conversion extensions for ChatMessage and Tool → MacPaw/OpenAI types.
//

import Foundation
import MBAgentKit
import OpenAI

// MARK: - ChatMessage → SDK

extension ChatMessage {
    /// Convert to MacPaw/OpenAI SDK `ChatCompletionMessageParam`.
    public func toSDK() -> ChatQuery.ChatCompletionMessageParam? {
        switch role {
        case .system:
            return .system(.init(content: .textContent(content ?? "")))
        case .user:
            return .user(.init(content: .string(content ?? "")))
        case .assistant:
            if let toolCalls, !toolCalls.isEmpty {
                let sdkCalls = toolCalls.map { tc in
                    ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
                        id: tc.id,
                        function: .init(arguments: tc.function.arguments, name: tc.function.name)
                    )
                }
                return .assistant(.init(content: content.map { .textContent($0) }, toolCalls: sdkCalls))
            }
            return .assistant(.init(content: .textContent(content ?? "")))
        case .tool:
            guard let toolCallId else { return nil }
            return .tool(.init(content: .textContent(content ?? ""), toolCallId: toolCallId))
        }
    }
}

extension Array where Element == ChatMessage {
    /// Batch-convert to SDK messages, filtering out conversion failures.
    public func toSDK() -> [ChatQuery.ChatCompletionMessageParam] {
        compactMap { $0.toSDK() }
    }
}

// MARK: - Tool → SDK

extension MBAgentKit.Tool {
    /// Convert to MacPaw/OpenAI SDK `ChatCompletionToolParam`.
    public func toSDK() -> ChatQuery.ChatCompletionToolParam {
        let sdkParams: JSONSchema = .init(fields: [
            .type(.object),
            .properties(
                function.parameters.properties.mapValues { prop in
                    let sdkType: JSONSchemaInstanceType
                    switch prop.type {
                    case "integer": sdkType = .integer
                    case "string": sdkType = .string
                    case "boolean": sdkType = .boolean
                    case "array": sdkType = .array
                    case "object": sdkType = .object
                    case "number": sdkType = .number
                    case "null": sdkType = .null
                    default: sdkType = .string
                    }

                    return JSONSchema(fields: [
                        .type(sdkType),
                        .description(prop.description)
                    ])
                }
            ),
            .required(function.parameters.required),
            .additionalProperties(.boolean(false))
        ])
        return ChatQuery.ChatCompletionToolParam(
            function: .init(
                name: function.name,
                description: function.description,
                parameters: sdkParams
            )
        )
    }
}

extension Array where Element == MBAgentKit.Tool {
    /// Batch-convert to SDK tool definitions.
    public func toSDK() -> [ChatQuery.ChatCompletionToolParam] {
        map { $0.toSDK() }
    }
}
