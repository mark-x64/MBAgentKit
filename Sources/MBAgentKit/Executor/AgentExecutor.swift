//
//  AgentExecutor.swift
//  MBAgentKit
//

import Foundation

/// Core Agent execution engine implementing a standard ReAct (Reason-Act) loop.
///
/// Features Human-In-The-Loop (HITL) interception for tools that require
/// user confirmation before execution.
///
/// NOTE: @Observable removed — this class is accessed from both @MainActor and
/// background Tasks. @Observable's _$observationRegistrar is not safe for
/// concurrent multi-actor access, causing EXC_BAD_ACCESS on device.
public final class AgentExecutor: Equatable, @unchecked Sendable {

    nonisolated public static func == (lhs: AgentExecutor, rhs: AgentExecutor) -> Bool {
        lhs === rhs
    }

    nonisolated public let llm: any LLMServiceProtocol
    nonisolated public let tools: [any AgentTool]
    nonisolated public let configuration: AgentConfiguration

    /// Backward-compatible accessor.
    nonisolated public var maxIterations: Int { configuration.maxIterations }

    /// Lock protecting continuations and mutable state across actor boundaries.
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var _pendingConfirmation: CheckedContinuation<Bool, Never>?
    nonisolated(unsafe) private var _pendingUserInput: CheckedContinuation<UserInputResponse, Never>?
    /// Set to true by ``approveAll()`` to skip future HITL prompts in this run.
    nonisolated(unsafe) private var _autoApproveAll: Bool = false
    /// Snapshot of session messages captured at the end of the last run.
    nonisolated(unsafe) private var _finalSessionMessages: [ChatMessage] = []

    nonisolated private var pendingConfirmation: CheckedContinuation<Bool, Never>? {
        get { lock.withLock { _pendingConfirmation } }
        set { lock.withLock { _pendingConfirmation = newValue } }
    }

    nonisolated private var pendingUserInput: CheckedContinuation<UserInputResponse, Never>? {
        get { lock.withLock { _pendingUserInput } }
        set { lock.withLock { _pendingUserInput = newValue } }
    }

    /// Whether the executor is currently waiting for user confirmation.
    nonisolated public var isWaitingForConfirmation: Bool { pendingConfirmation != nil }

    /// Full session messages (excluding system prompt) captured at the end of the last run.
    /// Safe to read after the event stream has finished.
    nonisolated public var finalSessionMessages: [ChatMessage] {
        lock.withLock { _finalSessionMessages }
    }

    /// Primary initializer using ``AgentConfiguration``.
    nonisolated public init(
        llm: any LLMServiceProtocol,
        tools: [any AgentTool],
        configuration: AgentConfiguration = .default
    ) {
        self.llm = llm
        self.tools = tools
        self.configuration = configuration
    }

    /// Legacy convenience initializer for backward compatibility.
    nonisolated public convenience init(
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
    nonisolated public func run(messages initialMessages: [ChatMessage]) -> AsyncThrowingStream<AgentEvent, Error> {
        // Snapshot immutable state before entering the Task to avoid
        // any actor-boundary access to self inside the runner.
        let llm = self.llm
        let tools = self.tools
        let configuration = self.configuration

        return AsyncThrowingStream<AgentEvent, Error> { continuation in
            let runner = Task {
                let systemPrompt = initialMessages.first(where: { $0.role == .system })?.content ?? ""
                var session = AgentSession(
                    systemPrompt: systemPrompt,
                    maxMessageCount: configuration.sessionMaxMessages
                )
                session.append(contentsOf: initialMessages.filter { $0.role != .system })
                var iteration = 0

                // Pre-compute tool definitions once to avoid repeated existential dispatch.
                let toolDefinitions = tools.map { $0.definition }

                do {
                    while iteration < configuration.maxIterations {
                        try Task.checkCancellation()
                        iteration += 1
                        continuation.yield(.iterationStarted(iteration))

                        let response = try await llm.chatCompletionWithTools(
                            messages: session.getHistory(),
                            tools: toolDefinitions,
                            temperature: configuration.temperature
                        )

                        switch response {
                        case .text(let content):
                            let assistantMsg = ChatMessage.assistant(content)
                            session.append(assistantMsg)
                            let snap = session.messages
                            self.lock.withLock { self._finalSessionMessages = snap }
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

                                // Look up tool first so iconName is available for the calling event.
                                let tool = tools.first(where: {
                                    $0.definition.function.name == call.function.name
                                })

                                continuation.yield(.toolCalling(
                                    id: call.id,
                                    name: call.function.name,
                                    arguments: toolArgs,
                                    iconName: tool?.iconName
                                ))

                                guard let tool else {
                                    let result = "Tool '\(call.function.name)' not found"
                                    continuation.yield(.toolResult(
                                        id: call.id,
                                        name: call.function.name,
                                        result: result,
                                        iconName: nil
                                    ))
                                    session.append(.toolResult(id: call.id, content: result))
                                    continue
                                }

                                // HITL interception — skip if user has approved all remaining calls.
                                if tool.requiresConfirmation && !self.lock.withLock({ self._autoApproveAll }) {
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
                                            result: result,
                                            iconName: tool.iconName
                                        ))
                                        session.append(.toolResult(id: call.id, content: result))
                                        continue
                                    }
                                }

                                // Execute tool
                                let result: String
                                do {
                                    let context = AgentToolContext { request in
                                        let requestID = UUID().uuidString
                                        continuation.yield(.awaitingUserInput(id: requestID, request: request))
                                        let response = await withCheckedContinuation { (resCont: CheckedContinuation<UserInputResponse, Never>) in
                                            self.pendingUserInput = resCont
                                        }
                                        self.pendingUserInput = nil
                                        continuation.yield(.userInputResolved(id: requestID))
                                        return response
                                    } reportConfidence: { confidence in
                                        continuation.yield(.confidenceUpdated(confidence))
                                    }
                                    result = try await tool.execute(arguments: parsedArgs, context: context)
                                } catch {
                                    result = "Tool execution error: \(error.localizedDescription)"
                                }

                                try Task.checkCancellation()

                                continuation.yield(.toolResult(
                                    id: call.id,
                                    name: call.function.name,
                                    result: result,
                                    iconName: tool.iconName
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
                    session.append(finalMsg)
                    let snap = session.messages
                    self.lock.withLock { self._finalSessionMessages = snap }
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
    nonisolated public func resume(approved: Bool) {
        pendingConfirmation?.resume(returning: approved)
    }

    /// Approve the current pending confirmation and all future confirmations in this run.
    ///
    /// Call this when the user taps "Approve All" to skip individual HITL prompts for the remainder of the agent loop.
    nonisolated public func approveAll() {
        let cont = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            _autoApproveAll = true
            return _pendingConfirmation
        }
        cont?.resume(returning: true)
    }

    nonisolated public func submitUserInput(_ value: String) {
        pendingUserInput?.resume(returning: .submitted(value))
    }

    nonisolated public func cancelUserInput() {
        pendingUserInput?.resume(returning: .cancelled)
    }

    // MARK: - Argument Parsing

    nonisolated private static func parseArguments(_ arguments: String) -> [String: ToolValue] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: ToolValue].self, from: data) else {
            return [:]
        }
        return json
    }
}
