import CoreGraphics
import Observation

enum PanelFullSizeMode: Equatable {
    case compact
    case expanded
}

@Observable
final class PanelPresentationModel {
    let harborTimer = HarborTimer()
    var isMinimized = false
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
