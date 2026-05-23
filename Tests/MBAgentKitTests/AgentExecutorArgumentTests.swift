//
//  AgentExecutorArgumentTests.swift
//  MBAgentKitTests
//

import Testing
@testable import MBAgentKit

@Suite("AgentExecutor tool arguments")
struct AgentExecutorArgumentTests {

    @Test("Invalid non-empty tool arguments do not execute the tool")
    func invalidToolArgumentsDoNotExecuteTool() async throws {
        let call = ToolCall(
            id: "bad_args",
            function: ToolCall.ToolCallFunction(
                name: "mutate",
                arguments: #"{"unterminated": true"#
            )
        )

        let mock = MockLLMService()
        mock.responses = [
            .toolCalls([call], assistantMessage: .assistantWithToolCalls([call])),
            .text("I could not apply the change.")
        ]

        final class ExecutionFlag: @unchecked Sendable {
            var value = false
        }
        let flag = ExecutionFlag()
        let tool = BlockTool(
            name: "mutate",
            description: "Mutates data",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in
            flag.value = true
            return "mutated"
        }

        let executor = AgentExecutor(llm: mock, tools: [tool])
        let stream = executor.run(messages: [.user("Run")])

        var argumentError = ""
        for try await event in stream {
            if case .toolResult(_, _, let result, _) = event,
               result.contains("Tool arguments JSON is invalid") {
                argumentError = result
            }
        }

        #expect(!flag.value)
        #expect(!argumentError.isEmpty)
    }
}
