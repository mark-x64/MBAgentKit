//
//  AgentSessionTests.swift
//  MBAgentKitTests
//

import Testing
@testable import MBAgentKit

@Suite("AgentSession")
struct AgentSessionTests {

    @Test("System prompt is preserved after compression")
    func systemPromptPreserved() {
        var session = AgentSession(systemPrompt: "You are helpful.", maxMessageCount: 4)

        // Add enough messages to trigger compression
        for i in 1...5 {
            session.append(.user("Message \(i)"))
        }

        let history = session.getHistory()
        #expect(history.first?.role == .system)
        #expect(history.first?.content == "You are helpful.")
        #expect(history.count <= 4)
    }

    @Test("Messages within limit are not compressed")
    func noCompressionWithinLimit() {
        var session = AgentSession(systemPrompt: "System", maxMessageCount: 10)
        session.append(.user("Hello"))
        session.append(.assistant("Hi"))

        let history = session.getHistory()
        // system + user + assistant = 3
        #expect(history.count == 3)
    }

    @Test("Oldest non-system messages are discarded on overflow")
    func oldestDiscarded() {
        var session = AgentSession(systemPrompt: "System", maxMessageCount: 3)
        session.append(.user("First"))
        session.append(.assistant("Reply 1"))
        session.append(.user("Second"))

        let history = session.getHistory()
        // system + 2 most recent = 3
        #expect(history.count == 3)
        #expect(history.first?.role == .system)
        // "First" should have been discarded
        let contents = history.compactMap(\.content)
        #expect(!contents.contains("First"))
    }

    @Test("Batch append triggers compression")
    func batchAppend() {
        var session = AgentSession(systemPrompt: "System", maxMessageCount: 3)
        session.append(contentsOf: [
            .user("A"),
            .assistant("B"),
            .user("C"),
            .assistant("D")
        ])

        let history = session.getHistory()
        #expect(history.count <= 3)
        #expect(history.first?.role == .system)
    }

    @Test("Trimming does not leave orphaned tool result at start")
    func trimmingDropsLeadingOrphanedToolResult() {
        let call = ToolCall(
            id: "c1",
            function: ToolCall.ToolCallFunction(name: "lookup", arguments: "{}")
        )
        var session = AgentSession(systemPrompt: "System", maxMessageCount: 3)

        session.append(contentsOf: [
            .assistantWithToolCalls([call]),
            .toolResult(id: "c1", content: "found"),
            .user("Next")
        ])

        let history = session.getHistory()
        #expect(history.first?.role == .system)
        #expect(history.dropFirst().first?.role != .tool)
        #expect(history.compactMap(\.toolCallId).isEmpty)
        #expect(history.last?.content == "Next")
    }

    @Test("Trimming drops assistant tool call group when results are partial")
    func trimmingDropsPartialToolCallGroup() {
        let firstCall = ToolCall(
            id: "c1",
            function: ToolCall.ToolCallFunction(name: "lookup", arguments: "{}")
        )
        let secondCall = ToolCall(
            id: "c2",
            function: ToolCall.ToolCallFunction(name: "lookup", arguments: "{}")
        )
        var session = AgentSession(systemPrompt: "System", maxMessageCount: 4)

        session.append(contentsOf: [
            .user("Old"),
            .assistantWithToolCalls([firstCall, secondCall]),
            .toolResult(id: "c1", content: "first result"),
            .user("Next")
        ])

        let history = session.getHistory()
        #expect(history.first?.role == .system)
        #expect(history.contains(where: { $0.toolCalls != nil }) == false)
        #expect(history.compactMap(\.toolCallId).isEmpty)
        #expect(history.last?.content == "Next")
    }
}
