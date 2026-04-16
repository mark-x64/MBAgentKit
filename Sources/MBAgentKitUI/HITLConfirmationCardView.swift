//
//  HITLConfirmationCardView.swift
//  MBAgentKitUI
//

import SwiftUI
import MBAgentKit

/// HITL operation confirmation card — intercepts and displays pending Agent actions.
public struct HITLConfirmationCardView: View {
    public let id: String
    public let toolName: String
    public let arguments: ToolArguments
    public let confirmLabel: String
    public let cancelLabel: String
    public let notePlaceholder: String
    public let onConfirm: () -> Void
    public let onReject: () -> Void
    /// Optional: approve this and all future confirmations in the current run.
    public let onApproveAll: (() -> Void)?
    /// Called when the user submits inline feedback from the bottom composer.
    /// The caller decides how to interpret the note (e.g. reject with reason,
    /// inject as user message into the next turn).
    public let onSendNote: (String) -> Void

    @State private var noteText = ""

    public init(
        id: String,
        toolName: String,
        arguments: ToolArguments,
        confirmLabel: String = "Confirm",
        cancelLabel: String = "Cancel",
        notePlaceholder: String = "Add a note or ask the agent to adjust...",
        onConfirm: @escaping () -> Void,
        onReject: @escaping () -> Void,
        onApproveAll: (() -> Void)? = nil,
        onSendNote: @escaping (String) -> Void = { _ in }
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.notePlaceholder = notePlaceholder
        self.onConfirm = onConfirm
        self.onReject = onReject
        self.onApproveAll = onApproveAll
        self.onSendNote = onSendNote
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(toolName)
                    .font(.system(.headline, design: .monospaced))
                    .bold()

                Spacer()

                HStack(spacing: 12) {
                    Button(role: .destructive, action: onReject) {
                        Label(cancelLabel, systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonBorderShape(.circle)
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("hitl_reject")

                    Button(action: onConfirm) {
                        Text(confirmLabel)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("hitl_confirm")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(arguments.parsed.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(alignment: .top) {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                }
            }

            if let onApproveAll {
                Divider()
                Button(action: onApproveAll) {
                    Label("Approve All", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider()

            noteComposer
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var trimmedNote: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var noteComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(notePlaceholder, text: $noteText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button {
                let note = trimmedNote
                guard !note.isEmpty else { return }
                onSendNote(note)
                noteText = ""
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(trimmedNote.isEmpty)
        }
    }
}
