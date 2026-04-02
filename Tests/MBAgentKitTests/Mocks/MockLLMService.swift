//
//  MockLLMService.swift
//  MBAgentKitTests
//

import Foundation
@testable import MBAgentKit

/// A mock LLM service for testing ``AgentExecutor``.
///
/// Returns pre-configured responses in sequence. Each call to
/// `chatCompletionWithTools` pops the next response from the queue.
final class MockLLMService: LLMServiceProtocol, @unchecked Sendable {
    var responses: [ToolCallResponse] = []
    private var callIndex = 0

    func chatCompletion(
        messages: [ChatMessage],
        temperature: Double?,
        responseFormat: ResponseFormat?
    ) async throws -> String {
        guard callIndex < responses.count else {
            throw LLMError.emptyResponse
        }
        let response = responses[callIndex]
        callIndex += 1
        if case .text(let content) = response {
            return content
        }
        throw LLMError.emptyResponse
    }

    func chatCompletionWithTools(
        messages: [ChatMessage],
        tools: [Tool],
        temperature: Double?
    ) async throws -> ToolCallResponse {
        guard callIndex < responses.count else {
            throw LLMError.emptyResponse
        }
        let response = responses[callIndex]
        callIndex += 1
        return response
    }

    func streamChatCompletion(
        messages: [ChatMessage],
        temperature: Double?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
