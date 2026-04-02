//
//  LLMServiceProtocol.swift
//  MBAgentKit
//

import Foundation

// MARK: - Response Format

/// Response format type for LLM requests.
public enum ResponseFormatType: String, Codable, Sendable {
    case text
    case jsonObject = "json_object"
}

/// Response format configuration.
public struct ResponseFormat: Codable, Sendable {
    public let type: ResponseFormatType

    public static let text = ResponseFormat(type: .text)
    public static let jsonObject = ResponseFormat(type: .jsonObject)

    public init(type: ResponseFormatType) {
        self.type = type
    }
}

/// Errors that can occur during LLM service operations.
public enum LLMError: LocalizedError, Sendable {
    /// No API key configured.
    case noAPIKey
    /// Network request failed.
    case networkError(underlying: any Error)
    /// HTTP status code error.
    case httpError(statusCode: Int, body: String)
    /// Response body decoding failed.
    case decodingError(underlying: any Error)
    /// LLM returned empty content.
    case emptyResponse
    /// JSON output validation failed.
    case jsonValidationFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .httpError(let statusCode, let body):
            return "HTTP error (\(statusCode)): \(body)"
        case .decodingError(let underlying):
            return "Decoding error: \(underlying.localizedDescription)"
        case .emptyResponse:
            return "LLM returned an empty response"
        case .jsonValidationFailed(let detail):
            return "JSON validation failed: \(detail)"
        }
    }
}

/// Protocol for LLM service implementations.
///
/// All LLM providers (OpenAI, DeepSeek, etc.) conform to this interface.
/// Default implementations are provided for `chatCompletionWithTools`
/// (falls back to plain chat) and `streamChatCompletion`
/// (falls back to single request).
public protocol LLMServiceProtocol: Sendable {

    /// Send a chat completion request and return the assistant's text reply.
    func chatCompletion(
        messages: [ChatMessage],
        temperature: Double?,
        responseFormat: ResponseFormat?
    ) async throws -> String

    /// Send a chat completion request with Function Calling tool definitions.
    func chatCompletionWithTools(
        messages: [ChatMessage],
        tools: [Tool],
        temperature: Double?
    ) async throws -> ToolCallResponse

    /// Stream chat completion via SSE.
    ///
    /// Declared as a protocol requirement (not just an extension default)
    /// so that Swift dispatches dynamically through the protocol witness table.
    func streamChatCompletion(
        messages: [ChatMessage],
        temperature: Double?
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - Default Implementations

extension LLMServiceProtocol {

    public func chatCompletion(
        messages: [ChatMessage],
        temperature: Double? = nil,
        responseFormat: ResponseFormat? = nil
    ) async throws -> String {
        try await chatCompletion(
            messages: messages,
            temperature: temperature,
            responseFormat: responseFormat
        )
    }

    /// Default: ignores tools and falls back to plain chatCompletion, returning `.text`.
    public func chatCompletionWithTools(
        messages: [ChatMessage],
        tools: [Tool],
        temperature: Double? = nil
    ) async throws -> ToolCallResponse {
        let text = try await chatCompletion(
            messages: messages,
            temperature: temperature,
            responseFormat: nil
        )
        return .text(text)
    }

    /// Default: falls back to a single non-streaming request.
    public func streamChatCompletion(
        messages: [ChatMessage],
        temperature: Double? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await chatCompletion(
                        messages: messages,
                        temperature: temperature,
                        responseFormat: nil
                    )
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
