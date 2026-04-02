//
//  ContextStrategyTests.swift
//  MBAgentKitTests
//

import Testing
@testable import MBAgentKit

@Suite("ContextStrategy")
struct ContextStrategyTests {

    // MARK: - SlidingWindowStrategy

    @Test("SlidingWindow: messages within limit are untouched")
    func slidingWindowNoOp() async throws {
        let strategy = SlidingWindowStrategy()
        let messages: [ChatMessage] = [
            .system("System"),
            .user("Hello"),
            .assistant("Hi")
        ]
        let result = try await strategy.compress(messages: messages, limit: 5)
        #expect(result.count == 3)
    }

    @Test("SlidingWindow: drops oldest non-system messages")
    func slidingWindowDrops() async throws {
        let strategy = SlidingWindowStrategy()
        let messages: [ChatMessage] = [
            .system("System"),
            .user("First"),
            .assistant("Reply1"),
            .user("Second"),
            .assistant("Reply2"),
            .user("Third")
        ]
        let result = try await strategy.compress(messages: messages, limit: 4)
        #expect(result.count == 4)
        #expect(result[0].role == .system)
        // "First" and "Reply1" should be gone
        let contents = result.compactMap(\.content)
        #expect(!contents.contains("First"))
        #expect(!contents.contains("Reply1"))
        #expect(contents.contains("Third"))
    }

    // MARK: - SummarizingStrategy

    @Test("SummarizingStrategy: inserts summary message for old context")
    func summarizingBasic() async throws {
        let mock = MockLLMService()
        // The summarization LLM call returns this
        mock.responses = [.text("User asked about weather. Assistant provided Tokyo forecast.")]

        let strategy = SummarizingStrategy(llm: mock, recentToKeep: 2)
        let messages: [ChatMessage] = [
            .system("System"),
            .user("What's the weather?"),
            .assistant("Let me check..."),
            .user("In Tokyo"),
            .assistant("22°C sunny")
        ]

        let result = try await strategy.compress(messages: messages, limit: 4)
        // Should be: [system, summary, user("In Tokyo"), assistant("22°C sunny")]
        #expect(result[0].role == .system)
        #expect(result[0].content == "System")
        // Summary message
        #expect(result[1].role == .user)
        #expect(result[1].content?.contains("[Previous conversation summary]") == true)
        #expect(result[1].content?.contains("weather") == true)
        // Recent messages preserved
        #expect(result[2].content == "In Tokyo")
        #expect(result[3].content == "22°C sunny")
    }

    @Test("SummarizingStrategy: falls back to sliding window on LLM failure")
    func summarizingFallback() async throws {
        let mock = MockLLMService()
        // No responses queued → LLM call will throw
        mock.responses = []

        let strategy = SummarizingStrategy(llm: mock, recentToKeep: 2)
        let messages: [ChatMessage] = [
            .system("System"),
            .user("A"),
            .assistant("B"),
            .user("C"),
            .assistant("D")
        ]

        // Should not throw — falls back to sliding window
        let result = try await strategy.compress(messages: messages, limit: 4)
        #expect(result.count <= 4)
        #expect(result[0].role == .system)
    }

    // MARK: - Safe Split Point

    @Test("findSafeSplitPoint: skips tool messages")
    func safeSplitPoint() {
        let messages: [ChatMessage] = [
            .user("Go"),                                              // 0
            .assistantWithToolCalls([ToolCall(                         // 1
                id: "c1",
                function: ToolCall.ToolCallFunction(name: "search", arguments: "{}")
            )]),
            .toolResult(id: "c1", content: "found it"),               // 2
            .user("Thanks"),                                          // 3
        ]

        // Ideal split at index 1 (middle of tool sequence) → should advance to 3
        let safe = SummarizingStrategy.findSafeSplitPoint(in: messages, idealPoint: 1)
        #expect(safe == 3)
    }
}
