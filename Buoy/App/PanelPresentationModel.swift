import CoreGraphics
import Observation
import SwiftUI

enum PanelFullSizeMode: Equatable {
    case compact
    case expanded
}

@Observable
final class PanelPresentationModel {
    private var harborTimers: [String: HarborTimer] = [:]
    private let inactiveHarborTimer = HarborTimer()

    /// Reading a note's timer never creates or starts one during view rendering.
    func harborTimer(for noteID: String?) -> HarborTimer {
        guard let noteID else { return inactiveHarborTimer }
        return harborTimers[noteID] ?? inactiveHarborTimer
    }

    func startHarborTimer(for note: Note?) {
        guard let note else { return }
        if let timer = harborTimers[note.id] {
            timer.start(title: note.title, noteID: note.id)
        } else if HarborTimer.duration(in: note.title) != nil {
            let timer = HarborTimer()
            timer.start(title: note.title, noteID: note.id)
            harborTimers[note.id] = timer
        }
    }

    func removeHarborTimers(except noteIDs: Set<String>) {
        for noteID in Array(harborTimers.keys) where !noteIDs.contains(noteID) {
            harborTimers.removeValue(forKey: noteID)?.stop()
        }
    }

    var isMinimized = false
    /// The glass size the full panel is laid out at while the window animates
    /// into or out of Harbor Mode; `nil` the rest of the time.
    ///
    /// Letting the content follow the window meant the header, toolbar and
    /// note text re-laid out — and the editor re-wrapped — on every frame of
    /// the sweep. Held at one size, the glass still follows the window and
    /// the content is revealed or covered by it instead. Set by `AppDelegate`
    /// before the animation starts and cleared by its completion, so it can
    /// never end early on a stale timer.
    var harborTransitionGlassSize: CGSize?
    /// Which edge the window grows from or shrinks toward, so the held
    /// content stays pinned to the edge that is not moving.
    var harborTransitionAlignment: Alignment = .top
    var fullSizeMode: PanelFullSizeMode = .compact
    var minimizedContentWidth: CGFloat = PanelLayoutMetrics.minimizedWindowMinimumWidth
    /// True while a corner is held. Nothing should animate the panel during
    /// that; the drag is the animation.
    var isResizingByDrag = false
    /// The panel window's content size, published by `AppDelegate`.
    ///
    /// The chrome density used to be worked out from a `GeometryReader` on the
    /// panel's own content, which is only the same thing while that content
    /// fills the window. It did not: the content was given a minimum size and
    /// no maximum, so it sat at its ideal width and height inside a larger
    /// window — and the reader, measuring the content, decided a full-size
    /// panel was small enough for compact chrome and shrank it on launch.
    /// The window is the authority on how big the window is.
    var windowSize = CGSize(
        width: PanelLayoutMetrics.regularChromeWindowWidth,
        height: PanelLayoutMetrics.regularChromeWindowHeight
    )
}
