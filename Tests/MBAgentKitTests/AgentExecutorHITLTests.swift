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
//

import Testing
@testable import MBAgentKit

@Suite("AgentExecutor HITL & Advanced")
struct AgentExecutorHITLTests {

    // MARK: - Helpers

    private func makeEmptyParams() -> ToolParameters {
        ToolParameters(properties: [:], required: [])
    }

    /// 用 JSON 解码构造同时携带 toolCalls 和 content 的 assistant 消息。
    /// ChatMessage 的 full init 是 private，只能通过 Codable 绕过。
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

    @Test("HITL tool skipped when rejected — result contains 'rejected'")
    func hitlRejected() async throws {
        let call = ToolCall(id: "c1", function: .init(name: "delete", arguments: "{}"))

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([call], assistantMessage: .assistantWithToolCalls([call])),
            .text("Understood.")
        ]

        var toolExecuted = false
        let tool = BlockTool(
            name: "delete",
            description: "Delete something",
            parameters: makeEmptyParams(),
            requiresConfirmation: true
        ) { _ in
            toolExecuted = true
            return "deleted"
        }

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

        #expect(!toolExecuted)
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

        var execCount = 0
        let tool = BlockTool(
            name: "op",
            description: "Op",
            parameters: makeEmptyParams(),
            requiresConfirmation: true
        ) { _ in
            execCount += 1
            return "ok"
        }

        let executor = AgentExecutor(llm: mock, tools: [tool])
        let stream = executor.run(messages: [.user("Run")])

        var confirmationCount = 0
        for try await event in stream {
            if case .awaitingConfirmation = event {
                confirmationCount += 1
                executor.approveAll()
            }
        }

        // 只有第一个工具需要确认；approveAll() 后第二个直接执行
        #expect(confirmationCount == 1)
        #expect(execCount == 2)
    }

    // MARK: - thought 事件

    @Test("Thought event emitted when assistant message carries reasoning content")
    func thoughtEvent() async throws {
        let call = ToolCall(id: "c1", function: .init(name: "noop", arguments: "{}"))
        let assistantMsg = try makeAssistantMessage(content: "I need to check the data first.", toolCalls: [call])

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
