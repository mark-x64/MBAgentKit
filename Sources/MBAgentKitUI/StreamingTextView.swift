//
//  StreamingTextView.swift
//  MBAgentKitUI
//
//  Displays streaming text with one of two mutually exclusive visual styles:
//  - `.fade`: each new character independently fades in from opacity 0 → 1
//  - `.cursor`: text shows at full opacity with a blinking round cursor at the tail
//

import SwiftUI

/// Shared component for rendering streamed text output from an Agent.
///
/// Built on iOS 18 / macOS 15 `TextRenderer`:
/// - `.fade` iterates `Line → Run → RunSlice` and draws each glyph with its own
///   opacity derived from when that character first appeared.
/// - `.cursor` draws the text normally and overlays a blinking circular cursor
///   anchored to the end of the last line.
///
/// Both styles share a single `TimelineView(.animation)` driver so the caller
/// does not need to manage any animation state.
public struct StreamingTextView: View {
    /// Visual style. The two modes are mutually exclusive.
    public enum Style: Sendable {
        /// New characters fade in one by one over ``StreamingTextView/fadeDuration``.
        case fade
        /// Full-opacity text with a blinking round cursor at the tail.
        case cursor
    }

    public let text: String
    public let style: Style
    public let font: Font
    public let cursorSize: CGFloat
    public let fadeDuration: TimeInterval

    /// Timestamp of first appearance for every character in `text`.
    /// Index aligned with `text`'s character index.
    @State private var appearTimes: [Date] = []
    /// Snapshot of the last observed text to distinguish append-vs-replace.
    @State private var previousText: String = ""

    /// - Parameters:
    ///   - text: The text to display.
    ///   - style: `.fade` (default, per-char opacity fade-in) or `.cursor`.
    ///   - font: The font to use. Defaults to `.body`.
    ///   - cursorSize: Cursor diameter in points. Only applied when `style == .cursor`.
    ///     Defaults to `12` which balances visually with `.body` text.
    ///   - fadeDuration: How long each character takes to go from opacity 0 → 1.
    ///     Only applied when `style == .fade`. Defaults to `0.5` seconds.
    public init(
        text: String,
        style: Style = .fade,
        font: Font = .body,
        cursorSize: CGFloat = 12,
        fadeDuration: TimeInterval = 0.5
    ) {
        self.text = text
        self.style = style
        self.font = font
        self.cursorSize = cursorSize
        self.fadeDuration = fadeDuration
    }

    /// When `text` is empty, fall back to a single space so `Text.Layout` still
    /// produces one line. This keeps the `.cursor` style able to anchor the
    /// cursor on the first frame before any chunk has arrived.
    private var renderedText: String {
        text.isEmpty ? " " : text
    }

    public var body: some View {
        TimelineView(.animation) { context in
            Text(verbatim: renderedText)
                .font(font)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textRenderer(
                    StreamingTextRenderer(
                        style: style,
                        appearTimes: appearTimes,
                        now: context.date,
                        fadeDuration: fadeDuration,
                        cursorOpacity: cursorOpacity(at: context.date),
                        cursorSize: cursorSize
                    )
                )
        }
        .onAppear { syncAppearTimes() }
        .onChange(of: text) { _, _ in syncAppearTimes() }
    }

    /// Aligns `appearTimes` with the current `text`:
    /// - Append (new text prefixes the old text) → stamp only the new characters.
    /// - Replace / reset → stamp every character at the current time, so the
    ///   entire string re-fades in.
    private func syncAppearTimes() {
        let now = Date()
        if text.hasPrefix(previousText) {
            let added = text.count - previousText.count
            if added > 0 {
                appearTimes.append(contentsOf: Array(repeating: now, count: added))
            }
        } else {
            appearTimes = Array(repeating: now, count: text.count)
        }
        previousText = text
    }

    /// Cursor blink: continuous sine wave driven by `now`.
    /// Period ≈ 1.2 s, amplitude 0.3 → 1.0.
    private func cursorOpacity(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let phase = (sin(t * .pi / 0.6) + 1) / 2
        return 0.3 + 0.7 * phase
    }
}

// MARK: - TextRenderer

/// Custom `TextRenderer` that branches on `style`.
private struct StreamingTextRenderer: TextRenderer {
    var style: StreamingTextView.Style
    var appearTimes: [Date]
    var now: Date
    var fadeDuration: TimeInterval
    var cursorOpacity: Double
    var cursorSize: CGFloat

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        switch style {
        case .fade:
            drawFading(layout: layout, in: &ctx)
        case .cursor:
            drawWithCursor(layout: layout, in: &ctx)
        }
    }

    /// `.fade`: walk `Line → Run → RunSlice`, draw each slice with an opacity
    /// derived from that character's birth time.
    private func drawFading(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var charIndex = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let born: Date
                    if charIndex < appearTimes.count {
                        born = appearTimes[charIndex]
                    } else {
                        // Fewer stamps than slices (rare; e.g. emoji grapheme clusters).
                        // Fall back to the last known timestamp so nothing flickers.
                        born = appearTimes.last ?? .distantPast
                    }
                    let age = now.timeIntervalSince(born)
                    let opacity = min(1.0, max(0.0, age / fadeDuration))

                    var sliceCtx = ctx
                    sliceCtx.opacity = opacity
                    sliceCtx.draw(slice)

                    charIndex += 1
                }
            }
        }
    }

    /// `.cursor`: draw text normally, then overlay a blinking cursor at the tail.
    private func drawWithCursor(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            ctx.draw(line)
        }

        guard let lastLine = layout.last else { return }
        let bounds = lastLine.typographicBounds.rect

        let cursorRect = CGRect(
            x: bounds.maxX + 6,
            y: bounds.midY - cursorSize / 2,
            width: cursorSize,
            height: cursorSize
        )

        var cursorCtx = ctx
        cursorCtx.opacity = cursorOpacity
        cursorCtx.fill(
            Circle().path(in: cursorRect),
            with: .color(.secondary)
        )
    }
}

// MARK: - Preview

#Preview("StreamingTextView — All Cases") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Single line (fade)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingTextView(text: "Hello")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Multi line (fade, wraps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingTextView(
                    text: "Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World"
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Empty (cursor, waiting for first chunk)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingTextView(text: "", style: .cursor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Trailing newline (cursor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingTextView(text: "Hello\n", style: .cursor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Simulated streaming — fade (default, loops)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingSimulationPreview(style: .fade)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Simulated streaming — cursor (loops)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StreamingSimulationPreview(style: .cursor)
            }
        }
        .padding()
    }
}

/// Preview helper: appends a chunk of text every 80 ms, pauses, resets, repeats.
private struct StreamingSimulationPreview: View {
    let style: StreamingTextView.Style
    private let fullText = "This is a simulated streaming sentence; each character should fade in."
    @State private var shown: String = ""

    var body: some View {
        StreamingTextView(text: shown, style: style)
            .task {
                while !Task.isCancelled {
                    shown = ""
                    try? await Task.sleep(for: .milliseconds(600))
                    for char in fullText {
                        if Task.isCancelled { return }
                        shown.append(char)
                        try? await Task.sleep(for: .milliseconds(80))
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }
}
