//
//  ToolCallStatusRow.swift
//  MBAgentKitUI
//

import SwiftUI
import MBAgentKit

/// Displays the status of a single tool call in a timeline row.
public struct ToolCallStatusRow: View {

    public enum Status: Sendable {
        case calling
        case completed(String)
    }

    public let name: String
    public let arguments: ToolArguments
    public let status: Status

    public init(name: String, arguments: ToolArguments, status: Status) {
        self.name = name
        self.arguments = arguments
        self.status = status
    }

    @State private var isExpanded = false

    public var body: some View {
        Button {
            if case .completed = status {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Status indicator
                ZStack {
                    switch status {
                    case .completed:
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    case .calling:
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if case .completed = status {
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                                .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        }
                    }

                    switch status {
                    case .completed(let result):
                        Text(result)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 1)
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    case .calling:
                        if !arguments.parsed.isEmpty {
                            Text(arguments.parsed.values.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
