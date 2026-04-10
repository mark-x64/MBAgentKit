//
//  AgentRunningView.swift
//  MBAgentKitUI
//

import SwiftUI
import MBAgentKit

// MARK: - Display Mode

/// Controls whether tool call progress is displayed as a horizontal compact strip
/// or a vertical list. Mirrors the pattern of `isExpanded: Binding<Bool>` on
/// `DisclosureGroup` — the caller owns and persists the state.
public enum AgentStripDisplayMode: String {
    case compact
    case list
}

// MARK: - AgentRunningView

/// Master component for displaying real-time Agent execution.
///
/// Renders the thought process, tool call timeline, HITL confirmation,
/// and final answer in a unified view.
///
/// The caller owns `displayMode` and can back it with `@AppStorage` for persistence:
/// ```swift
/// @AppStorage("agentStripDisplayMode") var mode: AgentStripDisplayMode = .compact
/// AgentRunningView(..., displayMode: $mode, ...)
/// ```
public struct AgentRunningView: View {
    public let thought: String
    public let events: [AgentEvent]
    public let answer: String
    public let isRunning: Bool
    public let iterationCount: Int
    public let pendingConfirmation: PendingConfirmation?
    public let pendingUserInput: PendingUserInput?
    @Binding public var displayMode: AgentStripDisplayMode
    public let onConfirm: () -> Void
    public let onReject: () -> Void
    /// Optional: approve current and all future confirmations in this run.
    public let onApproveAll: (() -> Void)?
    public let onSubmitInput: (String) -> Void
    public let onCancelInput: () -> Void

    public init(
        thought: String,
        events: [AgentEvent],
        answer: String,
        isRunning: Bool,
        iterationCount: Int = 0,
        pendingConfirmation: PendingConfirmation?,
        pendingUserInput: PendingUserInput? = nil,
        displayMode: Binding<AgentStripDisplayMode>,
        onConfirm: @escaping () -> Void,
        onReject: @escaping () -> Void,
        onApproveAll: (() -> Void)? = nil,
        onSubmitInput: @escaping (String) -> Void = { _ in },
        onCancelInput: @escaping () -> Void = {}
    ) {
        self.thought = thought
        self.events = events
        self.answer = answer
        self.isRunning = isRunning
        self.iterationCount = iterationCount
        self.pendingConfirmation = pendingConfirmation
        self.pendingUserInput = pendingUserInput
        self._displayMode = displayMode
        self.onConfirm = onConfirm
        self.onReject = onReject
        self.onApproveAll = onApproveAll
        self.onSubmitInput = onSubmitInput
        self.onCancelInput = onCancelInput
    }

    @State private var showSteps = true

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !thought.isEmpty {
                ThoughtBubbleView(text: thought)
                    .transition(.opacity)
            }

            if !events.isEmpty {
                switch displayMode {
                case .compact:
                    HStack(alignment: .center, spacing: 6) {
                        CompactToolCallStrip(events: events)
                        modeToggleButton
                    }
                case .list:
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
                            HStack(spacing: 0) {
                                Text("\(events.count) steps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                modeToggleButton
                            }
                        }
                    )
                }
            }

            if let pending = pendingConfirmation {
                HITLConfirmationCardView(
                    id: pending.id,
                    toolName: pending.toolName,
                    arguments: pending.arguments,
                    onConfirm: onConfirm,
                    onReject: onReject,
                    onApproveAll: onApproveAll
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if let pendingInput = pendingUserInput {
                HITLUserInputCardView(
                    request: pendingInput,
                    onSubmit: onSubmitInput,
                    onCancel: onCancelInput
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if !answer.isEmpty {
                AnswerBubbleView(text: answer)
                    .transition(.opacity)
            } else if isRunning && pendingConfirmation == nil && pendingUserInput == nil {
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
        .animation(.snappy, value: displayMode == .compact)
        .animation(.spring(), value: events.count)
        .animation(.spring(), value: pendingConfirmation != nil)
        .animation(.spring(), value: pendingUserInput != nil)
        .animation(.easeInOut, value: thought)
        .animation(.easeInOut, value: answer)
    }

    // MARK: - Mode Toggle

    private var modeToggleButton: some View {
        Button {
            displayMode = displayMode == .compact ? .list : .compact
        } label: {
            Image(systemName: displayMode == .compact ? "list.bullet" : "capsule.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List Mode Row

    @ViewBuilder
    private func renderEvent(_ event: AgentEvent) -> some View {
        switch event {
        case .toolCalling(_, let name, let args, _):
            ToolCallStatusRow(name: name, arguments: args, status: .calling)
        case .toolResult(_, let name, let result, _):
            ToolCallStatusRow(name: name, arguments: .empty, status: .completed(result))
        default:
            EmptyView()
        }
    }
}

// MARK: - Preview

#Preview("Compact 模式（运行中）", traits: .sizeThatFitsLayout) {
    @Previewable @State var mode: AgentStripDisplayMode = .compact
    @Previewable @State var events: [AgentEvent] = [
        .toolResult(id: "1", name: "get_balance_info", result: "招商银行 ¥34,120", iconName: "banknote"),
        .toolResult(id: "2", name: "web_search",       result: "iPhone 16 Pro 最低 ¥7,999", iconName: "magnifyingglass"),
        .toolCalling(id: "3", name: "fetch_webpage",   arguments: .empty, iconName: "link"),
    ]

    AgentRunningView(
        thought: "正在获取网页详情…",
        events: events,
        answer: "",
        isRunning: true,
        iterationCount: 3,
        pendingConfirmation: nil,
        displayMode: $mode,
        onConfirm: {},
        onReject: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("List 模式（已完成）", traits: .sizeThatFitsLayout) {
    @Previewable @State var mode: AgentStripDisplayMode = .list
    let events: [AgentEvent] = [
        .toolResult(id: "1", name: "get_balance_info",  result: "招商银行 ¥34,120 / 支付宝 ¥32,050", iconName: "banknote"),
        .toolResult(id: "2", name: "get_items_info",    result: "MacBook Pro 14、Sony A7C II",       iconName: "tray.full"),
        .toolResult(id: "3", name: "web_search",        result: "iPhone 16 Pro 最低 ¥7,999",         iconName: "magnifyingglass"),
        .toolResult(id: "4", name: "fetch_webpage",     result: "Apple 官网：¥8,999 起",              iconName: "link"),
    ]

    AgentRunningView(
        thought: "",
        events: events,
        answer: "",
        isRunning: false,
        iterationCount: 4,
        pendingConfirmation: nil,
        displayMode: $mode,
        onConfirm: {},
        onReject: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
