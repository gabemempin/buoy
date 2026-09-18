import AppKit
import QuartzCore
import SwiftUI

// MARK: - SearchFieldWrapper

struct SearchFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        // No focus ring by design, matching the title field: AppKit's masks to
        // the cell frame and lands as a hard box on this borderless field, and a
        // drawn substitute read as clutter. The caret marks focus, and the
        // accessibility label carries it for VoiceOver.
        searchField.focusRingType = .none
        searchField.setAccessibilityLabel("Search notes")
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

        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
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
