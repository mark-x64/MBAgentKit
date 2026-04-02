//
//  AgentRunningView.swift
//  MBAgentKitUI
//

import SwiftUI
import MBAgentKit

/// Master component for displaying real-time Agent execution.
///
/// Renders the thought process, tool call timeline, HITL confirmation,
/// and final answer in a unified view.
public struct AgentRunningView: View {
    public let thought: String
    public let events: [AgentEvent]
    public let answer: String
    public let isRunning: Bool
    public let iterationCount: Int
    public let pendingConfirmation: PendingConfirmation?
    public let onConfirm: () -> Void
    public let onReject: () -> Void

    public init(
        thought: String,
        events: [AgentEvent],
        answer: String,
        isRunning: Bool,
        iterationCount: Int = 0,
        pendingConfirmation: PendingConfirmation?,
        onConfirm: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.thought = thought
        self.events = events
        self.answer = answer
        self.isRunning = isRunning
        self.iterationCount = iterationCount
        self.pendingConfirmation = pendingConfirmation
        self.onConfirm = onConfirm
        self.onReject = onReject
    }

    @State private var showSteps = true

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !thought.isEmpty {
                ThoughtBubbleView(text: thought)
                    .transition(.opacity)
            }

            if !events.isEmpty {
                DisclosureGroup(
                    isExpanded: $showSteps,
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                                renderEvent(event)
                                    .transition(.opacity.combined(with: .blurReplace))
                            }
                        }
                        .padding(.top, 4)
                    },
                    label: {
                        Text("\(events.count) steps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                )
            }

            if let pending = pendingConfirmation {
                HITLConfirmationCardView(
                    id: pending.id,
                    toolName: pending.toolName,
                    arguments: pending.arguments,
                    onConfirm: onConfirm,
                    onReject: onReject
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if !answer.isEmpty {
                AnswerBubbleView(text: answer)
                    .transition(.opacity)
            } else if isRunning && pendingConfirmation == nil {
                HStack {
                    ProgressView()
                        .padding(.leading, 8)
                    Spacer()
                    if iterationCount > 0 {
                        Text("Iteration \(iterationCount)")
                            .font(.caption2)
                            .foregroundStyle(.quinary)
                    }
                }
            }
        }
        .animation(.spring(), value: events.count)
        .animation(.spring(), value: pendingConfirmation != nil)
        .animation(.easeInOut, value: thought)
        .animation(.easeInOut, value: answer)
    }

    @ViewBuilder
    private func renderEvent(_ event: AgentEvent) -> some View {
        switch event {
        case .toolCalling(_, let name, let args):
            ToolCallStatusRow(name: name, arguments: args, status: .calling)
        case .toolResult(_, let name, let result):
            ToolCallStatusRow(name: name, arguments: .empty, status: .completed(result))
        default:
            EmptyView()
        }
    }
}
