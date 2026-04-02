//
//  AgentRunState.swift
//  MBAgentKitUI
//

import Foundation
import MBAgentKit

/// Pending HITL confirmation descriptor.
public struct PendingConfirmation: Sendable {
    public let id: String
    public let toolName: String
    public let arguments: ToolArguments

    public init(id: String, toolName: String, arguments: ToolArguments) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
    }
}

/// Observable state accumulator for Agent run events.
///
/// Feed ``AgentEvent`` values into ``handleEvent(_:)`` and bind
/// the published properties to your SwiftUI views.
@Observable
public final class AgentRunState {
    public var isRunning = false
    public var currentThought = ""
    public var currentAnswer = ""
    public var events: [AgentEvent] = []
    public var pendingConfirmation: PendingConfirmation?
    public var iterationCount = 0
    public var errorMessage: String?

    public init() {}

    public func reset() {
        isRunning = false
        currentThought = ""
        currentAnswer = ""
        events = []
        pendingConfirmation = nil
        iterationCount = 0
        errorMessage = nil
    }

    public func handleEvent(_ event: AgentEvent) {
        switch event {
        case .iterationStarted(let n):
            iterationCount = n
        case .thought(let delta):
            currentThought += delta
        case .answer(let delta):
            currentAnswer += delta
        case .toolCalling:
            events.append(event)
        case .toolResult(let id, _, _):
            if let idx = events.firstIndex(where: {
                if case .toolCalling(let cId, _, _) = $0 { return cId == id }
                return false
            }) {
                events[idx] = event
            } else {
                events.append(event)
            }
        case .awaitingConfirmation(let id, let name, let args):
            pendingConfirmation = PendingConfirmation(id: id, toolName: name, arguments: args)
        case .completed(let msg):
            if currentAnswer.isEmpty { currentAnswer = msg.content ?? "" }
        case .error(let err):
            errorMessage = err.localizedDescription
        }
    }
}
