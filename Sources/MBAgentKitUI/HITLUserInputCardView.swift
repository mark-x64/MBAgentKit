//
//  HITLUserInputCardView.swift
//  MBAgentKitUI
//

import SwiftUI
import MBAgentKit

public struct HITLUserInputCardView: View {
    public let request: PendingUserInput
    public let onSubmit: (String) -> Void
    public let onCancel: () -> Void

    @State private var textValue = ""
    @State private var selectedChoice: String?
    @FocusState private var textFieldFocused: Bool

    public init(
        request: PendingUserInput,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
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
                    Label("Cancel", systemImage: "xmark")
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
                    placeholder: placeholder ?? "请输入",
                    keyboardType: .default
                )

            case .singleChoice(let options):
                choiceSection(options: options, allowsCustomInput: false, customPlaceholder: nil)

            case .number(let placeholder):
                textInputSection(
                    placeholder: placeholder ?? "请输入数字",
                    keyboardType: .decimalPad
                )

            case .singleChoiceWithOther(let options, let customPlaceholder):
                choiceSection(
                    options: options,
                    allowsCustomInput: true,
                    customPlaceholder: customPlaceholder
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

            Button("提交") {
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
                                .foregroundStyle(.indigo)
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
                TextField(customPlaceholder ?? "请补充说明", text: $textValue, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($textFieldFocused)

                Button("提交") {
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
}
