import SwiftUI

/// A text setting that is committed only after it passes validation. Invalid input stays in the field with the
/// reason beside it, so the saved value is never replaced by something Host cannot load.
struct ValidatedSettingField<Value: Equatable>: View {
    let title: String
    let value: Value
    let format: (Value) -> String
    let parse: (String) -> Value?
    let invalidMessage: String
    let commit: (Value) -> Void

    @State private var draft: String
    @State private var invalid = false
    @FocusState private var focused: Bool

    init(
        title: String,
        value: Value,
        format: @escaping (Value) -> String,
        parse: @escaping (String) -> Value?,
        invalidMessage: String,
        commit: @escaping (Value) -> Void
    ) {
        self.title = title
        self.value = value
        self.format = format
        self.parse = parse
        self.invalidMessage = invalidMessage
        self.commit = commit
        _draft = State(initialValue: format(value))
    }

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(title, text: $draft)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit { submit() }
                    .accessibilityHint(invalid ? invalidMessage : "")
                if invalid {
                    Text(invalidMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { submit() }
        }
        .onChange(of: value) { _, newValue in
            draft = format(newValue)
            invalid = false
        }
    }

    private func submit() {
        guard let parsed = parse(draft) else {
            invalid = true
            return
        }
        invalid = false
        draft = format(parsed)
        if parsed != value { commit(parsed) }
    }
}
