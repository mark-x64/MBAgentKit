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

    nonisolated private func prepareForRun() {
        let staleConfirmation: CheckedContinuation<Bool, Never>?
        let staleUserInput: CheckedContinuation<UserInputResponse, Never>?
        lock.lock()
        staleConfirmation = _pendingConfirmation
        staleUserInput = _pendingUserInput
        _pendingConfirmation = nil
        _pendingUserInput = nil
        _autoApproveAll = false
        _finalSessionMessages = []
        lock.unlock()

        staleConfirmation?.resume(returning: false)
        staleUserInput?.resume(returning: .cancelled)
    }

    nonisolated private func takePendingConfirmation() -> CheckedContinuation<Bool, Never>? {
        lock.withLock {
            let cont = _pendingConfirmation
            _pendingConfirmation = nil
            return cont
        }
    }

    nonisolated private func takePendingUserInput() -> CheckedContinuation<UserInputResponse, Never>? {
        lock.withLock {
            let cont = _pendingUserInput
            _pendingUserInput = nil
            return cont
        }
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
        prepareForRun()

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

                        let response: ToolCallResponse
                        if configuration.streaming {
                            response = try await Self.streamingResponse(
                                llm: llm,
                                messages: session.getHistory(),
                                tools: toolDefinitions,
                                temperature: configuration.temperature,
                                continuation: continuation
                            )
                        } else {
                            response = try await llm.chatCompletionWithTools(
                                messages: session.getHistory(),
                                tools: toolDefinitions,
                                temperature: configuration.temperature
                            )
                        }

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

                                    let approved = await withTaskCancellationHandler {
                                        await withCheckedContinuation { (resCont: CheckedContinuation<Bool, Never>) in
                                            self.pendingConfirmation = resCont
                                        }
                                    } onCancel: {
                                        self.takePendingConfirmation()?.resume(returning: false)
                                    }

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
                                        let response = await withTaskCancellationHandler {
                                            await withCheckedContinuation { (resCont: CheckedContinuation<UserInputResponse, Never>) in
                                                self.pendingUserInput = resCont
                                            }
                                        } onCancel: {
                                            self.takePendingUserInput()?.resume(returning: .cancelled)
                                        }
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
                self.takePendingConfirmation()?.resume(returning: false)
                self.takePendingUserInput()?.resume(returning: .cancelled)
            }
        }
    }

    /// Resume after a HITL confirmation prompt.
    ///
    /// - Parameter approved: Whether the user approved the operation.
    nonisolated public func resume(approved: Bool) {
        takePendingConfirmation()?.resume(returning: approved)
    }

    /// Approve the current pending confirmation and all future confirmations in this run.
    ///
    /// Call this when the user taps "Approve All" to skip individual HITL prompts for the remainder of the agent loop.
    nonisolated public func approveAll() {
        let cont = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            _autoApproveAll = true
            let cont = _pendingConfirmation
            _pendingConfirmation = nil
            return cont
        }
        cont?.resume(returning: true)
    }

    nonisolated public func submitUserInput(_ value: String) {
        takePendingUserInput()?.resume(returning: .submitted(value))
    }

    nonisolated public func cancelUserInput() {
        takePendingUserInput()?.resume(returning: .cancelled)
    }

    // MARK: - Streaming

    /// Consume the LLM's streaming chunk sequence, forward token-level deltas
    /// to the executor's event continuation, and collapse the accumulated
    /// chunks into a non-streaming ``ToolCallResponse`` so the rest of the
    /// ReAct loop can stay shape-identical to the non-streaming path.
    ///
    /// Tool-call deltas are merged by their `index` because OpenAI emits
    /// `id` / `name` once at the head and then a long tail of `argumentsDelta`
    /// fragments that must be concatenated in arrival order.
    nonisolated private static func streamingResponse(
        llm: any LLMServiceProtocol,
        messages: [ChatMessage],
        tools: [Tool],
        temperature: Double?,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> ToolCallResponse {
        var textBuffer = ""
        var partialCalls: [Int: PartialToolCall] = [:]
        var orderedIndices: [Int] = []
        // Tracks whether *any* delta has been forwarded to the preview so far,
        // so that subsequent tool-call headers get a leading newline separator
        // (and the very first delta does not).
        var hasEmittedAnyDelta = false

        let stream = llm.streamChatCompletionWithTools(
            messages: messages,
            tools: tools,
            temperature: temperature
        )

        for try await chunk in stream {
            try Task.checkCancellation()
            switch chunk {
            case .textDelta(let delta):
                guard !delta.isEmpty else { continue }
                textBuffer += delta
                continuation.yield(.outputDelta(delta))
                hasEmittedAnyDelta = true
            case .reasoningDelta(let delta):
                guard !delta.isEmpty else { continue }
                continuation.yield(.outputDelta(delta))
                hasEmittedAnyDelta = true
            case .toolCallDelta(let index, let id, let name, let argumentsDelta):
                if partialCalls[index] == nil {
                    partialCalls[index] = PartialToolCall()
                    orderedIndices.append(index)
                }
                let priorName = partialCalls[index]?.name
                partialCalls[index]?.merge(id: id, name: name, argumentsDelta: argumentsDelta)
                // Surface tool-call construction as text deltas so the
                // streaming preview keeps moving when the model is producing
                // JSON instead of prose. The first time we know a function
                // name we emit a header like "→ batch_modify(", and every
                // subsequent argument fragment is appended verbatim.
                if let resolvedName = partialCalls[index]?.name, priorName == nil {
                    let prefix = hasEmittedAnyDelta
                        ? "\n→ \(resolvedName)("
                        : "→ \(resolvedName)("
                    continuation.yield(.outputDelta(prefix))
                    hasEmittedAnyDelta = true
                }
                if let argumentsDelta, !argumentsDelta.isEmpty {
                    continuation.yield(.outputDelta(argumentsDelta))
                    hasEmittedAnyDelta = true
                }
            case .finish:
                // Falls through to post-loop assembly. Some providers omit the
                // finish chunk entirely, so we don't rely on it as a sentinel.
                continue
            }
        }

        if !partialCalls.isEmpty {
            let calls: [ToolCall] = orderedIndices.compactMap { idx in
                partialCalls[idx]?.build()
            }
            let assistantMsg = ChatMessage.assistantWithToolCalls(calls)
            return .toolCalls(calls, assistantMessage: assistantMsg)
        }
        return .text(textBuffer)
    }

    /// Mutable accumulator for one streaming tool-call slot.
    private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments: String = ""

        mutating func merge(id newID: String?, name newName: String?, argumentsDelta: String?) {
            if let newID, self.id == nil { self.id = newID }
            if let newName, self.name == nil { self.name = newName }
            if let argumentsDelta { self.arguments += argumentsDelta }
        }

        func build() -> ToolCall? {
            guard let name else { return nil }
            return ToolCall(
                id: id ?? UUID().uuidString,
                function: ToolCall.ToolCallFunction(name: name, arguments: arguments)
            )
        }
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
