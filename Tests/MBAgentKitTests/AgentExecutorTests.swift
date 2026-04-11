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
}
