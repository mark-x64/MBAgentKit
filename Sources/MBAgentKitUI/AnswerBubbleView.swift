//
//  AnswerBubbleView.swift
//  MBAgentKitUI
//

import SwiftUI

/// Displays the Agent's final answer in a styled bubble.
public struct AnswerBubbleView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Answer")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
