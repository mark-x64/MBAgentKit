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
    public let onConfirm: () -> Void
    public let onReject: () -> Void
    /// Optional: approve this and all future confirmations in the current run.
    public let onApproveAll: (() -> Void)?

    public init(
        id: String,
        toolName: String,
        arguments: ToolArguments,
        confirmLabel: String = "Confirm",
        cancelLabel: String = "Cancel",
        onConfirm: @escaping () -> Void,
        onReject: @escaping () -> Void,
        onApproveAll: (() -> Void)? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.onConfirm = onConfirm
        self.onReject = onReject
        self.onApproveAll = onApproveAll
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

                    Button(action: onConfirm) {
                        Text(confirmLabel)
                    }
                    .buttonStyle(.borderedProminent)
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
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
