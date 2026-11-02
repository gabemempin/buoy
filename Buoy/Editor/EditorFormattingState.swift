import AppKit
import Observation

/// The formats that apply at the caret or across the selection, for the
/// toolbar's pressed-in buttons.
///
/// `ContentView` owns one and hands it to every editor it mounts, so the
/// state survives the editor remounting on a note switch. Only the toolbar
/// reads it, so a caret move re-renders the toolbar and nothing else.
@Observable
final class EditorFormattingState {
    enum Format: Hashable {
        case bold, italic, underline, strikethrough, bullet, todo, link
    }

    private(set) var active: Set<Format> = []

    func contains(_ format: Format) -> Bool { active.contains(format) }

    /// Assigns only on a real change: Observation notifies on every set, and
    /// this runs on every caret move.
    func update(_ formats: Set<Format>) {
        if formats != active { active = formats }
    }
}
