//
//  StreamingPreviewView.swift
//  MBAgentKitUI
//
//  Tail-anchored preview for token-level Agent streaming output.
//  Renders only the last N lines of accumulating text so the UI stays compact.
//

import SwiftUI

/// Compact preview that tails the live streaming output of an Agent.
///
/// Layout strategy: lay out the text at its full natural height, then trap it
/// inside a fixed-height frame anchored to the bottom edge. Anything older
/// than the visible window simply overflows above and gets clipped — no
/// truncation marker, no jumping cursor, the tail just scrolls naturally as
/// new tokens arrive.
///
/// **Performance notes**
/// - The displayed text is capped to the last ``displayCharBudget`` characters
///   regardless of how much output the executor has accumulated. Without that
///   cap, every token would re-trigger O(N) multi-line text layout — and
///   since outputDelta events fire many times per second, the preview view
///   would visibly stutter as the buffer grew.
/// - The trailing dot that marks "still typing" is appended inline to the
///   `Text` itself rather than drawn by a custom `TextRenderer` inside a
///   `TimelineView(.animation)`. The earlier renderer-based cursor was
///   repainting the *full* layout at 60 Hz; the inline dot costs nothing
///   beyond the normal layout pass.
/// - A 1-line probe in the same font is rendered hidden in the background to
///   measure the per-line height, so the box sizes correctly under any
///   Dynamic Type setting. Until the probe reports back, a sensible default
///   of 22 pt is used.
public struct StreamingPreviewView: View {
    public let text: String
    public let maxLineCount: Int
    public let font: Font

    @State private var lineHeight: CGFloat = 22

    /// Hard cap on how many trailing characters are handed to `Text`.
    /// 600 covers ~10 lines of dense Chinese text — far more than the 1-3 we
    /// actually display, but cheap and resilient against wide-glyph wrapping.
    private static let displayCharBudget = 600

    /// - Parameters:
    ///   - text: The accumulated streaming text.
    ///   - maxLineCount: Number of lines to keep visible. Clamped to `1...3`.
    ///   - font: Body font. Defaults to `.callout`.
    public init(
        text: String,
        maxLineCount: Int = 3,
        font: Font = .callout
    ) {
        self.text = text
        self.maxLineCount = max(1, min(3, maxLineCount))
        self.font = font
    }

    /// Tail-window of `text`. Bounded to keep layout O(1) per token.
    private var displayText: String {
        let cap = Self.displayCharBudget
        guard text.count > cap else { return text }
        let start = text.index(text.endIndex, offsetBy: -cap)
        return String(text[start...])
    }

    public var body: some View {
        // Compose body + inline trailing dot so the cursor flows with the
        // wrapped tail and never extends past the line's right edge.
        let composed: Text = displayText.isEmpty
            ? Text(verbatim: " ")
            : Text(verbatim: displayText) + Text(verbatim: " ●").foregroundColor(.secondary)

        return composed
            .font(font)
            // Reserve a sliver on the right so the trailing dot stays well
            // inside the frame even when the line wraps right up to the edge.
            .padding(.trailing, 4)
            // Crucial: without this, a height-constrained `Text` simply
            // truncates to the *first* N lines instead of overflowing — and
            // we'd never have anything to clip from the top. `fixedSize`
            // forces the Text to keep its full natural multi-line height
            // regardless of the proposed height, so the head can overflow
            // upward and `.clipped()` removes it.
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                maxHeight: lineHeight * CGFloat(maxLineCount),
                alignment: .bottomLeading
            )
            .clipped()
            .foregroundStyle(.secondary)
            .background(alignment: .topLeading) {
                // 1-line probe in the requested font. Its intrinsic size is a
                // single text line; the inner GeometryReader reports that
                // height up via PreferenceKey so the visible frame matches
                // `maxLineCount` lines exactly under any Dynamic Type setting.
                Text(verbatim: "M")
                    .font(font)
                    .lineLimit(1, reservesSpace: true)
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: LineHeightKey.self, value: geo.size.height)
                        }
                    }
                    .hidden()
                    .accessibilityHidden(true)
            }
            .onPreferenceChange(LineHeightKey.self) { value in
                if value > 0, abs(value - lineHeight) > 0.5 {
                    lineHeight = value
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Streaming output preview"))
            .accessibilityIdentifier("agent_streaming_preview")
    }
}

private struct LineHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Preview

#Preview("StreamingPreviewView — Simulated Stream", traits: .sizeThatFitsLayout) {
    StreamingPreviewSimulation()
        .padding()
}

private struct StreamingPreviewSimulation: View {
    private let fullText = """
    Looking at the project tree to find the right node…
    Found 3 candidate projects in your library.
    Cross-checking against today's calendar to surface conflicts before suggesting an adjustment.
    Analysing the latest todo completion ratios.
    Composing a final recommendation.
    Almost done — bundling everything into a structured reply.
    """
    @State private var shown: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("1 line (tails the latest)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingPreviewView(text: shown, maxLineCount: 1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("3 lines (default — older lines clip off the top)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingPreviewView(text: shown, maxLineCount: 3)
            }
        }
        .task {
            while !Task.isCancelled {
                shown = ""
                try? await Task.sleep(for: .milliseconds(400))
                for char in fullText {
                    if Task.isCancelled { return }
                    shown.append(char)
                    try? await Task.sleep(for: .milliseconds(30))
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
