import AppKit
import QuartzCore
import SwiftUI

// MARK: - SearchFieldWrapper

struct SearchFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel = "Search notes"
    /// Takes keyboard focus as soon as it is on screen, so the panel it opens
    /// with can be searched by just typing.
    var focusesOnAppear = false
    /// Keys the field forwards instead of handling itself. Each returns
    /// whether it used the key; `false` falls back to the field's default.
    var onMoveUp: (() -> Bool)?
    var onMoveDown: (() -> Bool)?
    /// Return. The flag is true when Shift is held.
    var onSubmit: ((Bool) -> Bool)?
    var onCancel: (() -> Bool)?

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        // No focus ring by design, matching the title field: AppKit's masks to
        // the cell frame and lands as a hard box on this borderless field, and a
        // drawn substitute read as clutter. The caret marks focus, and the
        // accessibility label carries it for VoiceOver.
        searchField.focusRingType = .none
        searchField.setAccessibilityLabel(accessibilityLabel)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.controlSize = .small

        // Drop the magnifier. NSSearchFieldCell sizes its button rect against the
        // bezel, and this field has none, so the glyph lands *on* the text rect
        // and overlaps the placeholder and anything typed. The placeholder
        // already reads "Search notes…", so the button carries no information
        // worth fighting the cell's layout for.
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil

        if focusesOnAppear {
            // The panel is non-activating, so focus has to be taken explicitly
            // through the window, and only once the field is in it.
            DispatchQueue.main.async {
                searchField.window?.makeFirstResponder(searchField)
            }
        }

        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchFieldWrapper

        init(_ parent: SearchFieldWrapper) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                parent.text = field.stringValue
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMoveUp?() ?? false
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMoveDown?() ?? false
            case #selector(NSResponder.insertNewline(_:)):
                let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                return parent.onSubmit?(shift) ?? false
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onCancel?() ?? false
            default:
                return false
            }
        }
    }
}

// MARK: - ThemePickerWrapper

struct ThemePickerWrapper: NSViewRepresentable {
    @Binding var selection: AppTheme

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["Auto", "Light", "Dark"],
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.onChange(_:))
        )
        control.segmentStyle = .roundRect
        control.controlSize = .small
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        switch selection {
        case .system: nsView.selectedSegment = 0
        case .light: nsView.selectedSegment = 1
        case .dark: nsView.selectedSegment = 2
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: ThemePickerWrapper

        init(_ parent: ThemePickerWrapper) {
            self.parent = parent
        }

        @objc func onChange(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0: parent.selection = .system
            case 1: parent.selection = .light
            case 2: parent.selection = .dark
            default: break
            }
        }
    }
}
