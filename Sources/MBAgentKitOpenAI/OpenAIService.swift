//
//  OpenAIService.swift
//  MBAgentKitOpenAI
//
//  OpenAI-compatible Chat Completion client (supports DeepSeek, MoonShot, etc.)
//  using MacPaw/OpenAI SDK.
//

import Foundation
import MBAgentKit
import OpenAI

/// OpenAI-compatible LLM service implementation.
///
/// Supports any OpenAI-compatible provider by injecting the API key,
/// base URL, and model name at initialization.
public struct OpenAIService: LLMServiceProtocol {

    private let apiKey: String
    private let baseURL: String
    private let modelName: String

    public init(apiKey: String, baseURL: String, modelName: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelName = modelName
    }

    // MARK: - SDK Client Factory

    private func makeClient() throws -> OpenAI {
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }

        guard let url = URL(string: baseURL),
              let host = url.host else {
            throw LLMError.httpError(statusCode: 0, body: "Invalid base URL: \(baseURL)")
        }

        let scheme = url.scheme ?? "https"
        var basePath = url.path
        if basePath.hasSuffix("/") {
            basePath = String(basePath.dropLast())
        }
        if basePath.isEmpty {
            basePath = "/v1"
        }

        let configuration = OpenAI.Configuration(
            token: apiKey,
            host: host,
            scheme: scheme,
            basePath: basePath,
            parsingOptions: .relaxed
        )

        return OpenAI(
            configuration: configuration,
            middlewares: [DisableThinkingMiddleware()]
        )
    }

    // MARK: - Chat Completion

    public func chatCompletion(
        messages: [ChatMessage],
        temperature: Double?,
        responseFormat: ResponseFormat?
    ) async throws -> String {
        let client = try makeClient()

        var sdkResponseFormat: ChatQuery.ResponseFormat?
        if let responseFormat {
            switch responseFormat.type {
            case .text:
                sdkResponseFormat = .text
            case .jsonObject:
                sdkResponseFormat = .jsonObject
            }
        }

        let query = ChatQuery(
            messages: messages.toSDK(),
            model: .init(modelName),
            responseFormat: sdkResponseFormat,
            temperature: temperature
        )

        let result: ChatResult
        do {
            result = try await client.chats(query: query)
        } catch {
            throw mapSDKError(error)
        }

        guard let content = result.choices.first?.message.content,
              !content.isEmpty else {
            throw LLMError.emptyResponse
        }

        return content
    }

    // MARK: - Function Calling

    public func chatCompletionWithTools(
        messages: [ChatMessage],
        tools: [MBAgentKit.Tool],
        temperature: Double?
    ) async throws -> ToolCallResponse {
        let client = try makeClient()

        let query = ChatQuery(
            messages: messages.toSDK(),
            model: .init(modelName),
            temperature: temperature,
            tools: tools.toSDK()
        )

        let result: ChatResult
        do {
            result = try await client.chats(query: query)
        } catch {
            throw mapSDKError(error)
        }

        guard let choice = result.choices.first else {
            throw LLMError.emptyResponse
        }

        if choice.finishReason == "tool_calls",
           let sdkToolCalls = choice.message.toolCalls, !sdkToolCalls.isEmpty {
            let toolCalls = sdkToolCalls.map { sdkCall in
                ToolCall(
                    id: sdkCall.id,
                    type: "function",
                    function: ToolCall.ToolCallFunction(
                        name: sdkCall.function.name,
                        arguments: sdkCall.function.arguments
                    )
                )
            }
            let assistantMsg = ChatMessage.assistantWithToolCalls(toolCalls)
            return .toolCalls(toolCalls, assistantMessage: assistantMsg)
        }

        guard let content = choice.message.content, !content.isEmpty else {
            throw LLMError.emptyResponse
        }
        return .text(content)
    }

    // MARK: - Streaming

    public func streamChatCompletion(
        messages: [ChatMessage],
        temperature: Double?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let client = try makeClient()

                    let query = ChatQuery(
                        messages: messages.toSDK(),
                        model: .init(modelName),
                        temperature: temperature,
                        stream: true
                    )

                    for try await streamResult in client.chatsStream(query: query) {
                        if Task.isCancelled { break }
                        if let content = streamResult.choices.first?.delta.content,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapSDKError(error))
                }
            }
        }
    }

    // MARK: - Connection Test

    /// Send a simple message to verify API key and connectivity.
    public func testConnection() async throws -> String {
        let testMessage = ChatMessage(role: .user, content: "Hi, reply with 'OK' only.")
        return try await chatCompletion(messages: [testMessage], temperature: nil, responseFormat: nil)
    }

    // MARK: - Error Mapping

    private func mapSDKError(_ error: Error) -> LLMError {
        if let urlError = error as? URLError {
            return .networkError(underlying: urlError)
        }
        return .networkError(underlying: error)
    }
}
