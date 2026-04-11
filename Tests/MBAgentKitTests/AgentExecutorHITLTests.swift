//
//  AgentExecutorHITLTests.swift
//  MBAgentKitTests
//
//  测试覆盖 AgentExecutor 未被 AgentExecutorTests 触及的行为：
//    - HITL 批准路径：工具正常执行并返回结果
//    - HITL 拒绝路径：工具结果包含 "rejected"
//    - approveAll()：首次批准后后续工具不再暂停
//    - thought 事件：assistantMessage 携带 content 时发出
//    - LLM 错误：流发出 .error 事件并终止
//    - isWaitingForConfirmation：挂起时为 true，恢复后为 false
//

import Testing
import Foundation
@testable import MBAgentKit

@Suite("AgentExecutor HITL & Advanced")
struct AgentExecutorHITLTests {

    // MARK: - Helpers

    private func makeEmptyParams() -> ToolParameters {
        ToolParameters(properties: [:], required: [])
    }

    /// 用 Codable 绕过 ChatMessage 的 private init，
    /// 构造同时携带 toolCalls 和 content 的 assistant 消息（用于测试 thought 事件）。
    private func makeAssistantMessage(content: String, toolCalls: [ToolCall]) throws -> ChatMessage {
        struct Payload: Encodable {
            let role: String
            let content: String
            let tool_calls: [ToolCall]
        }
        let data = try JSONEncoder().encode(Payload(role: "assistant", content: content, tool_calls: toolCalls))
        return try JSONDecoder().decode(ChatMessage.self, from: data)
    }

    // MARK: - HITL 批准

    @Test("HITL tool executes when approved")
    func hitlApproved() async throws {
        let call = ToolCall(id: "c1", function: .init(name: "delete", arguments: "{}"))

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([call], assistantMessage: .assistantWithToolCalls([call])),
            .text("Done.")
        ]

        let tool = BlockTool(
            name: "delete",
            description: "Delete something",
            parameters: makeEmptyParams(),
            requiresConfirmation: true
        ) { _ in "deleted" }

        let executor = AgentExecutor(llm: mock, tools: [tool])
        let stream = executor.run(messages: [.user("Delete")])

        var gotConfirmation = false
        var toolResult = ""

        for try await event in stream {
            switch event {
            case .awaitingConfirmation:
                gotConfirmation = true
                executor.resume(approved: true)
            case .toolResult(_, _, let result, _):
                toolResult = result
            default:
                break
            }
        }

        #expect(gotConfirmation)
        #expect(toolResult == "deleted")
    }

    // MARK: - HITL 拒绝

    @Test("HITL tool is skipped when rejected — result contains 'rejected'")
    func hitlRejected() async throws {
        let call = ToolCall(id: "c1", function: .init(name: "delete", arguments: "{}"))

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([call], assistantMessage: .assistantWithToolCalls([call])),
            .text("Understood.")
        ]

        let tool = BlockTool(
            name: "delete",
            description: "Delete something",
            parameters: makeEmptyParams(),
            requiresConfirmation: true
        ) { _ in "deleted" }

        let executor = AgentExecutor(llm: mock, tools: [tool])
        let stream = executor.run(messages: [.user("Delete")])

        var toolResult = ""
        for try await event in stream {
            switch event {
            case .awaitingConfirmation:
                executor.resume(approved: false)
            case .toolResult(_, _, let result, _):
                toolResult = result
            default:
                break
            }
        }

        #expect(toolResult.lowercased().contains("rejected"))
    }

    // MARK: - approveAll

    @Test("approveAll skips confirmation for all subsequent tools in same iteration")
    func approveAllSkipsFutureHITL() async throws {
        let call1 = ToolCall(id: "c1", function: .init(name: "op", arguments: "{}"))
        let call2 = ToolCall(id: "c2", function: .init(name: "op", arguments: "{}"))

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([call1, call2], assistantMessage: .assistantWithToolCalls([call1, call2])),
            .text("Done.")
        ]

        let tool = BlockTool(
            name: "op",
            description: "Op",
            parameters: makeEmptyParams(),
            requiresConfirmation: true
        ) { _ in "ok" }

        let executor = AgentExecutor(llm: mock, tools: [tool])
        let stream = executor.run(messages: [.user("Run")])

        var confirmationCount = 0
        var toolResultCount = 0

        for try await event in stream {
            switch event {
            case .awaitingConfirmation:
                confirmationCount += 1
                executor.approveAll() // 批准第一个并自动跳过后续
            case .toolResult:
                toolResultCount += 1
            default:
                break
            }
        }

        // 只有第一个工具弹出确认；approveAll 后第二个直接执行
        #expect(confirmationCount == 1)
        // 两个工具都应执行并返回结果
        #expect(toolResultCount == 2)
    }

    // MARK: - thought 事件

    @Test("Thought event emitted when assistant message carries reasoning content")
    func thoughtEvent() async throws {
        let call = ToolCall(id: "c1", function: .init(name: "noop", arguments: "{}"))
        let assistantMsg = try makeAssistantMessage(
            content: "I need to check the data first.",
            toolCalls: [call]
        )

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([call], assistantMessage: assistantMsg),
            .text("Done.")
        ]

        let tool = BlockTool(
            name: "noop",
            description: "No-op",
            parameters: makeEmptyParams()
        ) { _ in "ok" }

        let executor = AgentExecutor(llm: mock, tools: [tool])
        let stream = executor.run(messages: [.user("Go")])

        var thoughtText = ""
        for try await event in stream {
            if case .thought(let text) = event { thoughtText = text }
        }

        #expect(thoughtText == "I need to check the data first.")
    }

    // MARK: - LLM 错误处理

    @Test("LLM error emits error event and stream terminates")
    func llmErrorEmitsEvent() async throws {
        let mock = MockLLMService()
        mock.responses = [] // 空队列 → 抛出 LLMError.emptyResponse

        let executor = AgentExecutor(llm: mock, tools: [])
        let stream = executor.run(messages: [.user("Test")])

        var gotError = false
        do {
            for try await event in stream {
                if case .error = event { gotError = true }
            }
        } catch {
            gotError = true
        }

        #expect(gotError)
    }

    // MARK: - isWaitingForConfirmation

    @Test("isWaitingForConfirmation is true while suspended, false after resume")
    func isWaitingForConfirmationFlag() async throws {
        let call = ToolCall(id: "c1", function: .init(name: "op", arguments: "{}"))

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([call], assistantMessage: .assistantWithToolCalls([call])),
            .text("Done.")
        ]

        let tool = BlockTool(
            name: "op",
            description: "Op",
            parameters: makeEmptyParams(),
            requiresConfirmation: true
        ) { _ in "ok" }

        let executor = AgentExecutor(llm: mock, tools: [tool])
        let stream = executor.run(messages: [.user("Run")])

        var wasWaiting = false
        for try await event in stream {
            if case .awaitingConfirmation = event {
                wasWaiting = executor.isWaitingForConfirmation
                executor.resume(approved: true)
            }
        }

        #expect(wasWaiting)
        #expect(!executor.isWaitingForConfirmation)
    }
}
