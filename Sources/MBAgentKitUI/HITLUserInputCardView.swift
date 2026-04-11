//
//  HITLUserInputCardView.swift
//  MBAgentKitUI
//

import SwiftUI
import MBAgentKit

public struct HITLUserInputCardView: View {
    public let request: PendingUserInput
    public let submitLabel: String
    public let cancelLabel: String
    public let textPlaceholder: String
    public let numberPlaceholder: String
    public let otherPlaceholder: String
    public let onSubmit: (String) -> Void
    public let onCancel: () -> Void

    @State private var textValue = ""
    @State private var selectedChoice: String?
    @State private var sliderValue: Double = 0
    @State private var sliderInitialized = false
    @FocusState private var textFieldFocused: Bool

    public init(
        request: PendingUserInput,
        submitLabel: String = "Submit",
        cancelLabel: String = "Cancel",
        textPlaceholder: String = "Enter text",
        numberPlaceholder: String = "Enter a number",
        otherPlaceholder: String = "Enter custom value",
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.submitLabel = submitLabel
        self.cancelLabel = cancelLabel
        self.textPlaceholder = textPlaceholder
        self.numberPlaceholder = numberPlaceholder
        self.otherPlaceholder = otherPlaceholder
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(request.request.title)
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onCancel) {
                    Label(cancelLabel, systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }

            Text(request.request.prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch request.request.kind {
            case .text(let placeholder):
                textInputSection(
                    placeholder: placeholder ?? textPlaceholder,
                    keyboardType: .default
                )

            case .singleChoice(let options):
                choiceSection(options: options, allowsCustomInput: false, customPlaceholder: nil)

            case .number(let placeholder):
                textInputSection(
                    placeholder: placeholder ?? numberPlaceholder,
                    keyboardType: .decimalPad
                )

            case .singleChoiceWithOther(let options, let customPlaceholder):
                choiceSection(
                    options: options,
                    allowsCustomInput: true,
                    customPlaceholder: customPlaceholder
                )

            case .slider(let lower, let upper, let step, let defaultValue, let unit, let labels):
                sliderSection(
                    lower: lower,
                    upper: upper,
                    step: step,
                    defaultValue: defaultValue,
                    unit: unit,
                    labels: labels
                )
            }
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func textInputSection(placeholder: String, keyboardType: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(placeholder, text: $textValue, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboardType)
                .focused($textFieldFocused)

            Button(submitLabel) {
                onSubmit(textValue)
            }
            .buttonStyle(.borderedProminent)
            .disabled(textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func choiceSection(
        options: [String],
        allowsCustomInput: Bool,
        customPlaceholder: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selectedChoice = option
                    if !allowsCustomInput {
                        onSubmit(option)
                    } else {
                        textValue = ""
                    }
                } label: {
                    HStack {
                        Text(option)
                        Spacer()
                        if selectedChoice == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            if allowsCustomInput {
                TextField(customPlaceholder ?? otherPlaceholder, text: $textValue, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($textFieldFocused)

                Button(submitLabel) {
                    let custom = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !custom.isEmpty {
                        onSubmit(custom)
                    } else if let selectedChoice {
                        onSubmit(selectedChoice)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedChoice == nil)
            }
        }
    }

    @ViewBuilder
    private func sliderSection(
        lower: Double,
        upper: Double,
        step: Double?,
        defaultValue: Double,
        unit: String?,
        labels: [String]?
    ) -> some View {
        let safeLower = Swift.min(lower, upper)
        let safeUpper = Swift.max(lower, upper)
        let clampedDefault = Swift.min(Swift.max(defaultValue, safeLower), safeUpper)
        let effectiveLabels = validatedLabels(
            labels,
            lower: safeLower,
            upper: safeUpper,
            step: step
        )

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(sliderDisplayValue(sliderValue, step: step))
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: sliderValue))
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let currentLabel = currentTickLabel(
                    value: sliderValue,
                    lower: safeLower,
                    step: step,
                    labels: effectiveLabels
                ) {
                    Text(currentLabel)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }

            Group {
                if let step, step > 0 {
                    Slider(
                        value: $sliderValue,
                        in: safeLower...safeUpper,
                        step: step
                    )
                } else {
                    Slider(value: $sliderValue, in: safeLower...safeUpper)
                }
            }
            .tint(.accentColor)

            HStack(spacing: 4) {
                Text(sliderDisplayValue(safeLower, step: step))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(sliderDisplayValue(safeUpper, step: step))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let effectiveLabels, !effectiveLabels.isEmpty {
                tickLabelsRow(effectiveLabels)
            }

            Button(submitLabel) {
                onSubmit(formatSliderSubmission(sliderValue, step: step))
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            guard !sliderInitialized else { return }
            sliderValue = clampedDefault
            sliderInitialized = true
        }
    }

    @ViewBuilder
    private func tickLabelsRow(_ labels: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: tickAlignment(for: idx, count: labels.count))
            }
        }
    }

    private func tickAlignment(for index: Int, count: Int) -> Alignment {
        if count <= 1 { return .center }
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }

    /// Returns the labels only if they match the discrete stop count implied by `(lower, upper, step)`.
    /// Otherwise returns `nil` so the slider still renders without broken tick alignment.
    private func validatedLabels(
        _ labels: [String]?,
        lower: Double,
        upper: Double,
        step: Double?
    ) -> [String]? {
        guard let labels, !labels.isEmpty else { return nil }
        guard let step, step > 0 else { return nil }
        let stopCount = Int(((upper - lower) / step).rounded()) + 1
        return labels.count == stopCount ? labels : nil
    }

    /// Label of the tick closest to `value`, or `nil` when not on a labelled stop.
    private func currentTickLabel(
        value: Double,
        lower: Double,
        step: Double?,
        labels: [String]?
    ) -> String? {
        guard let labels, let step, step > 0 else { return nil }
        let rawIdx = ((value - lower) / step).rounded()
        let idx = Int(rawIdx)
        guard idx >= 0, idx < labels.count else { return nil }
        // Only show label when value is very close to the discrete stop.
        let snapped = lower + Double(idx) * step
        guard abs(snapped - value) < step * 0.01 else { return nil }
        return labels[idx]
    }

    /// Format the slider value for display. Uses integer formatting if the step is integral.
    private func sliderDisplayValue(_ value: Double, step: Double?) -> String {
        let isIntegral: Bool = {
            if let step, step > 0 { return step.rounded() == step }
            return false
        }()
        if isIntegral {
            return String(Int(value.rounded()))
        }
        return String(format: "%g", value)
    }

    /// Format the slider value as it will be submitted back to the tool (`Double(String)` must succeed).
    private func formatSliderSubmission(_ value: Double, step: Double?) -> String {
        if let step, step > 0, step.rounded() == step {
            return String(Int(value.rounded()))
        }
        return String(value)
    }
}

// MARK: - Preview

#Preview("Slider — 离散步长 + 刻度文字", traits: .sizeThatFitsLayout) {
    HITLUserInputCardView(
        request: PendingUserInput(
            id: "slider-1",
            request: UserInputRequest(
                title: "每日可投入时长",
                prompt: "你计划每天为这个目标投入多长时间？",
                kind: .slider(
                    min: 0,
                    max: 120,
                    step: 15,
                    defaultValue: 45,
                    unit: "分钟",
                    labels: ["0", "15", "30", "45", "1h", "1.25h", "1.5h", "1.75h", "2h"]
                )
            )
        ),
        submitLabel: "提交",
        cancelLabel: "取消",
        onSubmit: { _ in },
        onCancel: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Slider — 连续", traits: .sizeThatFitsLayout) {
    HITLUserInputCardView(
        request: PendingUserInput(
            id: "slider-2",
            request: UserInputRequest(
                title: "信心指数",
                prompt: "对这个方案的信心有多高？",
                kind: .slider(
                    min: 0,
                    max: 1,
                    step: nil,
                    defaultValue: 0.6,
                    unit: nil,
                    labels: nil
                )
            )
        ),
        onSubmit: { _ in },
        onCancel: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
