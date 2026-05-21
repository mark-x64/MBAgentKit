//
//  AgentExecutorTests.swift
//  MBAgentKitTests
//

import Testing
@testable import MBAgentKit

@Suite("AgentExecutor")
struct AgentExecutorTests {

    @Test("Simple text response completes immediately")
    func simpleTextResponse() async throws {
        let mock = MockLLMService()
        mock.responses = [.text("Hello, world!")]

        let executor = AgentExecutor(llm: mock, tools: [])
        let stream = executor.run(messages: [
            .system("You are helpful."),
            .user("Hi")
        ])

        var gotAnswer = false
        var gotCompleted = false

        for try await event in stream {
            switch event {
            case .answer(let text):
                #expect(text == "Hello, world!")
                gotAnswer = true
            case .completed:
                gotCompleted = true
            default:
                break
            }
        }

        #expect(gotAnswer)
        #expect(gotCompleted)
    }

    @Test("Tool call is executed and result returned")
    func toolCallExecution() async throws {
        let toolCall = ToolCall(
            id: "call_1",
            function: ToolCall.ToolCallFunction(
                name: "get_date",
                arguments: "{}"
            )
        )

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([toolCall], assistantMessage: .assistantWithToolCalls([toolCall])),
            .text("Today is 2026-03-12.")
        ]

        let dateTool = BlockTool(
            name: "get_date",
            description: "Get current date",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in
            "2026-03-12"
        }

        let executor = AgentExecutor(llm: mock, tools: [dateTool])
        let stream = executor.run(messages: [.user("What's today?")])

        var toolResults: [String] = []
        var finalAnswer = ""

        for try await event in stream {
            switch event {
            case .toolResult(_, _, let result, _):
                toolResults.append(result)
            case .answer(let text):
                finalAnswer = text
            default:
                break
            }
        }

        #expect(toolResults.contains("2026-03-12"))
        #expect(finalAnswer == "Today is 2026-03-12.")
    }

    @Test("Tool call and result events preserve IDs and session pairing")
    func toolCallResultPairing() async throws {
        let firstCall = ToolCall(
            id: "call_first",
            function: ToolCall.ToolCallFunction(
                name: "echo",
                arguments: #"{"value":"first"}"#
            )
        )
        let secondCall = ToolCall(
            id: "call_second",
            function: ToolCall.ToolCallFunction(
                name: "echo",
                arguments: #"{"value":"second"}"#
            )
        )

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([firstCall, secondCall], assistantMessage: .assistantWithToolCalls([firstCall, secondCall])),
            .text("Done.")
        ]

        let echoTool = BlockTool(
            name: "echo",
            description: "Echo a value",
            parameters: ToolParameters(
                properties: ["value": ToolProperty(type: "string", description: "Value to echo")],
                required: ["value"]
            )
        ) { arguments in
            "echo:\(arguments["value"]?.stringValue ?? "")"
        }

        let executor = AgentExecutor(llm: mock, tools: [echoTool])
        let stream = executor.run(messages: [.user("Echo twice")])

        var callingIDs: [String] = []
        var resultIDs: [String] = []
        var resultNames: [String] = []

        for try await event in stream {
            switch event {
            case .toolCalling(let id, _, _, _):
                callingIDs.append(id)
            case .toolResult(let id, let name, _, _):
                resultIDs.append(id)
                resultNames.append(name)
            default:
                break
            }
        }

        #expect(callingIDs == ["call_first", "call_second"])
        #expect(resultIDs == callingIDs)
        #expect(resultNames == ["echo", "echo"])

        let session = executor.finalSessionMessages
        let assistantToolCalls = session.first(where: { $0.role == .assistant && $0.toolCalls != nil })
        let storedResultIDs = session
            .filter { $0.role == .tool }
            .compactMap(\.toolCallId)
        #expect(assistantToolCalls?.toolCalls?.map(\.id) == callingIDs)
        #expect(storedResultIDs == resultIDs)
    }

    @Test("Unknown tool returns error message")
    func unknownTool() async throws {
        let toolCall = ToolCall(
            id: "call_1",
            function: ToolCall.ToolCallFunction(
                name: "nonexistent_tool",
                arguments: "{}"
            )
        )

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([toolCall], assistantMessage: .assistantWithToolCalls([toolCall])),
            .text("Done.")
        ]

        let executor = AgentExecutor(llm: mock, tools: [])
        let stream = executor.run(messages: [.user("Test")])

        var toolResults: [String] = []

        for try await event in stream {
            if case .toolResult(_, _, let result, _) = event {
                toolResults.append(result)
            }
        }

        #expect(toolResults.first?.contains("not found") == true)
    }

    @Test("Max iterations limit is respected")
    func maxIterationsLimit() async throws {
        // Always request a tool call — executor should stop after maxIterations
        let toolCall = ToolCall(
            id: "call_1",
            function: ToolCall.ToolCallFunction(
                name: "echo",
                arguments: "{}"
            )
        )

        let mock = MockLLMService()
        // Provide more responses than maxIterations
        mock.responses = Array(repeating: ToolCallResponse.toolCalls(
            [toolCall],
            assistantMessage: .assistantWithToolCalls([toolCall])
        ), count: 5)

        let echoTool = BlockTool(
            name: "echo",
            description: "Echo",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "ok" }

        let executor = AgentExecutor(llm: mock, tools: [echoTool], maxIterations: 3)
        let stream = executor.run(messages: [.user("Loop")])

        var iterationCount = 0
        var gotCompleted = false

        for try await event in stream {
            switch event {
            case .iterationStarted(let n):
                iterationCount = n
            case .completed:
                gotCompleted = true
            default:
                break
            }
        }

        #expect(iterationCount == 3)
        #expect(gotCompleted)
    }

    @Test("Max iterations emits explicit terminal answer")
    func maxIterationsTerminalAnswer() async throws {
        let toolCall = ToolCall(
            id: "call_1",
            function: ToolCall.ToolCallFunction(
                name: "echo",
                arguments: "{}"
            )
        )

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([toolCall], assistantMessage: .assistantWithToolCalls([toolCall]))
        ]

        let echoTool = BlockTool(
            name: "echo",
            description: "Echo",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "ok" }

        let executor = AgentExecutor(llm: mock, tools: [echoTool], maxIterations: 1)
        let stream = executor.run(messages: [.user("Loop")])

        var answer = ""
        var completedMessage: ChatMessage?

        for try await event in stream {
            switch event {
            case .answer(let text):
                answer = text
            case .completed(let finalMessage):
                completedMessage = finalMessage
            default:
                break
            }
        }

        #expect(answer.contains("Maximum iterations reached"))
        #expect(completedMessage?.content == answer)
    }

    @Test("Context strategy compresses session between tool iterations")
    func contextStrategyCompressionBetweenIterations() async throws {
        let toolCall = ToolCall(
            id: "call_1",
            function: ToolCall.ToolCallFunction(
                name: "echo",
                arguments: "{}"
            )
        )

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([toolCall], assistantMessage: .assistantWithToolCalls([toolCall])),
            .text("Done.")
        ]

        let echoTool = BlockTool(
            name: "echo",
            description: "Echo",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "ok" }

        let executor = AgentExecutor(
            llm: mock,
            tools: [echoTool],
            configuration: AgentConfiguration(
                maxIterations: 2,
                sessionMaxMessages: 6,
                contextStrategy: MarkerCompressionStrategy()
            )
        )
        let stream = executor.run(messages: [
            .system("System"),
            .user("Run")
        ])

        for try await _ in stream {}

        let contents = executor.finalSessionMessages.compactMap(\.content)
        #expect(contents.contains("[compressed context]"))
        #expect(contents.last == "Done.")
    }
}

private struct MarkerCompressionStrategy: ContextStrategy {
    func compress(messages: [ChatMessage], limit: Int) async throws -> [ChatMessage] {
        var compressed: [ChatMessage] = []
        if let system = messages.first(where: { $0.role == .system }) {
            compressed.append(system)
        }
        compressed.append(.user("[compressed context]"))
        compressed.append(contentsOf: messages.suffix(2))
        return Array(compressed.prefix(limit))
    }
}
