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
    public let onConfirm: () -> Void
    public let onReject: () -> Void

    public init(
        id: String,
        toolName: String,
        arguments: ToolArguments,
        onConfirm: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.onConfirm = onConfirm
        self.onReject = onReject
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
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonBorderShape(.circle)
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)

                    Button(action: onConfirm) {
                        Text("Confirm")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
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
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
