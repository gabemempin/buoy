import AppKit
import SwiftUI

struct LinkDialog: View {
    let context: LinkEditingContext
    var onCancel: () -> Void
    var onInsert: (String, String) -> Void

    @State private var linkText: String
    @State private var linkURL: String
    @State private var clipboardPrefill: String?
    @State private var isSubmitting = false
    @FocusState private var focusedField: LinkFieldFocus?

    init(
        context: LinkEditingContext,
        onCancel: @escaping () -> Void,
        onInsert: @escaping (String, String) -> Void
    ) {
        self.context = context
        self.onCancel = onCancel
        self.onInsert = onInsert
        self._linkText = State(initialValue: context.text)
        self._linkURL = State(initialValue: context.url)
        self._clipboardPrefill = State(initialValue: nil)
    }

    private var destination: URL? {
        LinkDestination.normalizedURL(from: linkURL)
    }

    private var showsValidationError: Bool {
        !linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && destination == nil
    }

    private var title: String {
        context.isEditingExistingLink ? "Edit Link" : "Add Link"
    }

    private var primaryActionTitle: String {
        context.isEditingExistingLink ? "Update" : "Add"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "link")
                    .font(BuoyFont.sectionTitle)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.buoyControlFill))
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close \(title)")
                .pointingHandCursor()
            }

            VStack(alignment: .leading, spacing: 8) {
                if context.hasText {
                    HStack(spacing: 6) {
                        Image(systemName: "textformat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(context.text)
                            .font(BuoyFont.control)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.buoyControlFill, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Link text: \(context.text)")
                } else {
                    LinkField(
                        label: "Text",
                        placeholder: "Text to display",
                        text: $linkText,
                        field: .text,
                        focusedField: $focusedField,
                        detail: nil,
                        accessibilityHint: "Leave blank to display the URL."
                    ) {
                        focusedField = .url
                    }
                }

                LinkField(
                    label: "URL",
                    placeholder: "example.com",
                    text: $linkURL,
                    field: .url,
                    focusedField: $focusedField,
                    detail: clipboardPrefill == linkURL ? "From Clipboard" : nil,
                    accessibilityHint: "A missing scheme is added as HTTPS."
                ) {
                    submit()
                }

                if showsValidationError {
                    Label("Enter a valid URL", systemImage: "exclamationmark.circle")
                        .font(BuoyFont.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                        .accessibilityLabel("Enter a valid URL")
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel")
                    .pointingHandCursor()

                Button(primaryActionTitle) { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(destination == nil || isSubmitting)
                    .accessibilityLabel("\(primaryActionTitle) link")
                    .accessibilityHint(context.isEditingExistingLink ? "Updates the selected link destination." : "Adds the link to the note.")
                    .pointingHandCursor()
            }
        }
        .padding(12)
        .frame(maxWidth: 264)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onAppear {
            let pastedURL = context.url.isEmpty ? ClipboardLink.currentWebURLString() : nil
            if let pastedURL {
                linkURL = pastedURL
                clipboardPrefill = pastedURL
            }
            DispatchQueue.main.async {
                focusedField = context.hasText || pastedURL != nil ? .url : .text
            }
        }
        .onExitCommand(perform: onCancel)
    }

    private func submit() {
        guard !isSubmitting, let destination else { return }
        isSubmitting = true
        onInsert(linkText, destination.absoluteString)
    }
}

/// Owns the AppKit presentation used when a link is invoked from selected text.
/// NSPopover supplies the system material, arrow positioning, and the native
/// materialize/dematerialize animation (including Reduce Motion adaptation).
final class SelectionLinkPopoverController: NSObject, NSPopoverDelegate {
    var onClose: (() -> Void)?

    private var popover: NSPopover?

    func present(content: AnyView, relativeTo anchorRect: NSRect, of view: NSView) {
        if let popover {
            popover.delegate = nil
            popover.close()
        }

        let hostingController = NSHostingController(rootView: content)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        self.popover = popover
        popover.show(relativeTo: anchorRect, of: view, preferredEdge: .maxY)
    }

    func dismiss() {
        popover?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover,
              closedPopover === popover else { return }
        popover = nil
        onClose?()
    }
}

private enum LinkFieldFocus: Hashable {
    case text
    case url
}

/// AppKit exposes the current general pasteboard, not the user's system
/// clipboard-history UI. Check every item in the current copy operation and
/// only prefill values that clearly look like web URLs.
private enum ClipboardLink {
    static func currentWebURLString() -> String? {
        let pasteboard = NSPasteboard.general
        for item in pasteboard.pasteboardItems ?? [] {
            for type in [NSPasteboard.PasteboardType.URL, .string] {
                guard let rawValue = item.string(forType: type) else { continue }
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let lowercased = trimmed.lowercased()
                let hasExplicitWebScheme = lowercased.hasPrefix("https://")
                    || lowercased.hasPrefix("http://")
                let looksLikeHost = !trimmed.contains(where: { $0.isWhitespace })
                    && (trimmed.contains(".") || lowercased.hasPrefix("localhost"))
                guard hasExplicitWebScheme || looksLikeHost,
                      let url = LinkDestination.normalizedURL(from: trimmed),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      url.host?.isEmpty == false else { continue }
                return url.absoluteString
            }
        }
        return nil
    }
}

private struct LinkField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let field: LinkFieldFocus
    var focusedField: FocusState<LinkFieldFocus?>.Binding
    let detail: String?
    let accessibilityHint: String
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(label)
                Spacer()
                if let detail {
                    Label(detail, systemImage: "clipboard")
                        .accessibilityLabel(detail)
                }
            }
            .font(BuoyFont.caption)
            .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(BuoyFont.control)
                .focused(focusedField, equals: field)
                .onSubmit(onSubmit)
                .accessibilityLabel(label)
                .accessibilityHint(accessibilityHint)
        }
    }
}
