import AppKit
import SwiftUI

/// State for find-in-note (⌘F).
///
/// Buoy's own find bar rather than AppKit's `usesFindBar`: the system bar has a
/// minimum width wider than Buoy's narrowest panel, overflows the scroll view
/// and paints outside the window while the panel is resized. This one is a
/// capsule over the top of the editor that compresses with the panel.
///
/// Matches are recomputed on every step rather than cached, so text edited
/// while the bar is open can never leave a highlight pointing at the wrong
/// characters.
@Observable
final class NoteFindController {
    private(set) var isPresented = false
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            currentIndex = firstMatchIndex(in: currentRanges())
            refresh()
        }
    }
    private(set) var matchCount = 0
    private(set) var currentIndex: Int?

    @ObservationIgnored private weak var textView: BuoyTextView?

    /// Opens the bar, or re-focuses it if already open. A selection of one
    /// line or less seeds the query, as ⌘E / ⌘F do in other Mac apps.
    func present(for textView: BuoyTextView?) {
        guard let textView else { return }
        self.textView = textView
        let selection = textView.selectedRange()
        if selection.length > 0, selection.length <= 120 {
            let selected = (textView.string as NSString).substring(with: selection)
            if !selected.contains("\n") { query = selected }
        }
        if isPresented {
            // Already open: ⌘F again only moves focus back into the field.
            NotificationCenter.default.post(name: .buoyFocusFindField, object: nil)
        }
        isPresented = true
        refresh()
    }

    /// Closes the bar and hands focus back to the editor, with the caret on the
    /// match that was showing.
    func dismiss(focusingEditor: Bool = true) {
        guard isPresented else { return }
        // Animated here rather than at each call site: Escape, the close
        // button and a note switch all close it, and all should fade.
        // A pure crossfade, so it is left ungated by BuoyMotion.
        withAnimation(.easeOut(duration: 0.16)) { isPresented = false }
        textView?.clearFindHighlights()
        matchCount = 0
        currentIndex = nil
        if focusingEditor, let textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func next() { step(by: 1) }
    func previous() { step(by: -1) }

    private func step(by delta: Int) {
        let ranges = currentRanges()
        guard !ranges.isEmpty else { refresh(); return }
        let start = currentIndex ?? (delta > 0 ? -1 : 0)
        currentIndex = (start + delta + ranges.count) % ranges.count
        show(ranges)
    }

    private func refresh() {
        show(currentRanges())
    }

    private func show(_ ranges: [NSRange]) {
        matchCount = ranges.count
        if let index = currentIndex, !ranges.indices.contains(index) {
            currentIndex = ranges.isEmpty ? nil : ranges.count - 1
        }
        if currentIndex == nil, !ranges.isEmpty { currentIndex = 0 }
        guard isPresented else { return }
        textView?.showFindResults(ranges, current: currentIndex)
    }

    private func currentRanges() -> [NSRange] {
        textView?.findRanges(of: query) ?? []
    }

    /// The first match at or after the caret, so typing a query starts from
    /// where the user is rather than jumping to the top of a long note.
    private func firstMatchIndex(in ranges: [NSRange]) -> Int? {
        guard !ranges.isEmpty else { return nil }
        let caret = textView?.selectedRange().location ?? 0
        return ranges.firstIndex { $0.location >= caret } ?? 0
    }
}

extension Notification.Name {
    static let buoyFocusFindField = Notification.Name("BuoyFocusFindField")
}

/// The find capsule shown over the top of the editor.
struct NoteFindBar: View {
    @Bindable var controller: NoteFindController

    private var countText: String {
        guard !controller.query.isEmpty else { return "" }
        guard controller.matchCount > 0, let index = controller.currentIndex else {
            return "No matches"
        }
        return "\(index + 1) of \(controller.matchCount)"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            FindField(controller: controller)
                .frame(height: 20)
                .frame(minWidth: 60)

            Text(countText)
                .font(BuoyFont.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(countText)

            FindBarButton(systemName: "chevron.up", label: "Previous match", action: controller.previous)
                .disabled(controller.matchCount == 0)
            FindBarButton(systemName: "chevron.down", label: "Next match", action: controller.next)
                .disabled(controller.matchCount == 0)
            FindBarButton(systemName: "xmark", label: "Close find") {
                controller.dismiss()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .buoyGlassCapsule()
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        .background(WindowDragBlocker())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find in note")
    }
}

/// The search field inside the find bar. Its own view so the field can be
/// re-focused when ⌘F is pressed while the bar is already open.
private struct FindField: View {
    @Bindable var controller: NoteFindController
    @State private var focusToken = 0

    var body: some View {
        SearchFieldWrapper(
            text: $controller.query,
            placeholder: "Find in note",
            accessibilityLabel: "Find in note",
            focusesOnAppear: true,
            onMoveUp: { controller.previous(); return true },
            onMoveDown: { controller.next(); return true },
            onSubmit: { shift in
                shift ? controller.previous() : controller.next()
                return true
            },
            onCancel: { controller.dismiss(); return true }
        )
        // A new identity remounts the field, which runs its focus-on-appear.
        .id(focusToken)
        .onReceive(NotificationCenter.default.publisher(for: .buoyFocusFindField)) { _ in
            focusToken += 1
        }
    }
}

private struct FindBarButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(RowActionButtonStyle())
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
        .pointingHandCursor()
    }
}
