import SwiftUI

struct LinkDialog: View {
    @Binding var isShowing: Bool
    var selectedText: String
    var onInsert: (String, String) -> Void

    @State private var linkText: String = ""
    @State private var linkURL: String = ""
    @FocusState private var textFocused: Bool
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Insert Link")
                    .font(BuoyFont.secondaryProminent)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close Insert Link")
            }

            VStack(spacing: 6) {
                LinkField(placeholder: "Text", text: $linkText, isFocused: $textFocused) {
                    urlFocused = true
                }
                LinkField(placeholder: "URL", text: $linkURL, isFocused: $urlFocused) {
                    submit()
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                Button("Insert") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insert Link")
        .onAppear {
            linkText = selectedText
            textFocused = true
        }
    }

    private func submit() {
        guard !linkURL.isEmpty else { return }
        onInsert(linkText, linkURL)
        dismiss()
    }

    private func dismiss() {
        isShowing = false
    }
}

private struct LinkField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(BuoyFont.control)
            .accessibilityLabel(placeholder)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.buoyControlFill)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .focused(isFocused)
            .onSubmit(onSubmit)
    }
}
