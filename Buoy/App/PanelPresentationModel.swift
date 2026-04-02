import CoreGraphics
import Observation

enum PanelFullSizeMode: Equatable {
    case compact
    case expanded
}

@Observable
final class PanelPresentationModel {
    var isMinimized = false
    var fullSizeMode: PanelFullSizeMode = .compact
    var minimizedContentWidth: CGFloat = PanelLayoutMetrics.minimizedWindowMinimumWidth
}
