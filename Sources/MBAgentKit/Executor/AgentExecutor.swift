//
//  AgentExecutor.swift
//  MBAgentKit
//

import Foundation

/// Core Agent execution engine implementing a standard ReAct (Reason-Act) loop.
///
/// Features Human-In-The-Loop (HITL) interception for tools that require
/// user confirmation before execution.
@Observable
public final class AgentExecutor: Equatable, @unchecked Sendable {

    public static func == (lhs: AgentExecutor, rhs: AgentExecutor) -> Bool {
        lhs === rhs
    }

    public let llm: any LLMServiceProtocol
    public let tools: [any AgentTool]
    public let configuration: AgentConfiguration

    /// Backward-compatible accessor.
    public var maxIterations: Int { configuration.maxIterations }

    /// Currently suspended HITL confirmation continuation.
    private var pendingConfirmation: CheckedContinuation<Bool, Never>?

    /// Whether the executor is currently waiting for user confirmation.
    public var isWaitingForConfirmation: Bool { pendingConfirmation != nil }

    /// Primary initializer using ``AgentConfiguration``.
    public init(
        llm: any LLMServiceProtocol,
        tools: [any AgentTool],
        configuration: AgentConfiguration = .default
    ) {
        self.llm = llm
        self.tools = tools
        self.configuration = configuration
    }

    /// Legacy convenience initializer for backward compatibility.
    public convenience init(
        llm: any LLMServiceProtocol,
        tools: [any AgentTool],
        maxIterations: Int
    ) {
        self.init(
            llm: llm,
            tools: tools,
            configuration: AgentConfiguration(maxIterations: maxIterations)
        )
    }

    /// Run the Agent ReAct loop.
    ///
    /// - Parameter initialMessages: The initial message chain (system + user).
    /// - Returns: An async stream of ``AgentEvent`` values.
    public func run(messages initialMessages: [ChatMessage]) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream<AgentEvent, Error> { continuation in
            let runner = Task {
                let systemPrompt = initialMessages.first(where: { $0.role == .system })?.content ?? ""
                var session = AgentSession(
                    systemPrompt: systemPrompt,
                    maxMessageCount: configuration.sessionMaxMessages
                )
                session.append(contentsOf: initialMessages.filter { $0.role != .system })
                var iteration = 0

                do {
                    while iteration < maxIterations {
                        try Task.checkCancellation()
                        iteration += 1
                        continuation.yield(.iterationStarted(iteration))

                        let response = try await llm.chatCompletionWithTools(
                            messages: session.getHistory(),
                            tools: tools.map { $0.definition },
                            temperature: configuration.temperature
                        )

                        switch response {
                        case .text(let content):
                            let assistantMsg = ChatMessage.assistant(content)
                            continuation.yield(.answer(content))
                            continuation.yield(.completed(finalMessage: assistantMsg))
                            continuation.finish()
                            return

                        case .toolCalls(let toolCalls, let assistantMessage):
                            if let thought = assistantMessage.content, !thought.isEmpty {
                                continuation.yield(.thought(thought))
                            }
                            session.append(assistantMessage)

                            for call in toolCalls {
                                try Task.checkCancellation()

                                let rawArgs = call.function.arguments
                                let parsedArgs = Self.parseArguments(rawArgs)
                                let toolArgs = ToolArguments(jsonString: rawArgs)

                                continuation.yield(.toolCalling(
                                    id: call.id,
                                    name: call.function.name,
                                    arguments: toolArgs
                                ))

                                guard let tool = tools.first(where: {
                                    $0.definition.function.name == call.function.name
                                }) else {
                                    let result = "Tool '\(call.function.name)' not found"
                                    continuation.yield(.toolResult(
                                        id: call.id,
                                        name: call.function.name,
                                        result: result
                                    ))
                                    session.append(.toolResult(id: call.id, content: result))
                                    continue
                                }

                                // HITL interception
                                if tool.requiresConfirmation {
                                    continuation.yield(.awaitingConfirmation(
                                        id: call.id,
                                        toolName: call.function.name,
                                        arguments: toolArgs
                                    ))

                                    let approved = await withCheckedContinuation { (resCont: CheckedContinuation<Bool, Never>) in
                                        self.pendingConfirmation = resCont
                                    }
                                    self.pendingConfirmation = nil

                                    if !approved {
                                        let result = "User rejected this operation."
                                        continuation.yield(.toolResult(
                                            id: call.id,
                                            name: call.function.name,
                                            result: result
                                        ))
                                        session.append(.toolResult(id: call.id, content: result))
                                        continue
                                    }
                                }

                                // Execute tool
                                let result: String
                                do {
                                    result = try await tool.execute(arguments: parsedArgs)
                                } catch {
                                    result = "Tool execution error: \(error.localizedDescription)"
                                }

                                continuation.yield(.toolResult(
                                    id: call.id,
                                    name: call.function.name,
                                    result: result
                                ))
                                session.append(.toolResult(id: call.id, content: result))
                            }

                            // Apply context strategy compression between iterations
                            if let strategy = configuration.contextStrategy {
                                try await session.compress(using: strategy)
                            }

                            continue
                        }
                    }

                    let note = "Maximum iterations reached. Please re-run if further analysis is needed."
                    let finalMsg = ChatMessage.assistant(note)
                    continuation.yield(.answer(note))
                    continuation.yield(.completed(finalMessage: finalMsg))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                runner.cancel()
            }
        }
    }

    /// Resume after a HITL confirmation prompt.
    ///
    /// - Parameter approved: Whether the user approved the operation.
    public func resume(approved: Bool) {
        pendingConfirmation?.resume(returning: approved)
    }

    // MARK: - Argument Parsing

    private static func parseArguments(_ arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}
