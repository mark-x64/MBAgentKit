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
}
