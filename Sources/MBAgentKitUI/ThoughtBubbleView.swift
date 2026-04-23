//
//  ThoughtBubbleView.swift
//  MBAgentKitUI
//

import SwiftUI

/// Displays the Agent's reasoning/thought process in a styled bubble.
public struct ThoughtBubbleView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Thinking")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                StreamingTextView(text: text, font: .callout)
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
