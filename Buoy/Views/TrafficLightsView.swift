import SwiftUI
import AppKit

/// The panel's traffic lights, drawn by AppKit itself.
///
/// Buoy's panel is borderless, so it has no titlebar to inherit window buttons
/// from. Instead of hand-drawing circles, this hosts the *real* buttons AppKit
/// vends via `NSWindow.standardWindowButton(_:for:)`, which gives us the system
/// gradients, glyphs, pressed/inactive states, Reduce Transparency and
/// Increase Contrast treatments, and accessibility roles for free.
struct TrafficLightsView: NSViewRepresentable {
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose, onMinimize: onMinimize, onExpand: onExpand)
    }

    func makeNSView(context: Context) -> TrafficLightGroupView {
        TrafficLightGroupView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: TrafficLightGroupView, context: Context) {
        context.coordinator.onClose = onClose
        context.coordinator.onMinimize = onMinimize
        context.coordinator.onExpand = onExpand
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TrafficLightGroupView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var onClose: () -> Void
        var onMinimize: () -> Void
        var onExpand: () -> Void

        init(onClose: @escaping () -> Void, onMinimize: @escaping () -> Void, onExpand: @escaping () -> Void) {
            self.onClose = onClose
            self.onMinimize = onMinimize
            self.onExpand = onExpand
        }

        @objc func close(_ sender: Any?) { onClose() }
        @objc func minimize(_ sender: Any?) { onMinimize() }
        @objc func expand(_ sender: Any?) { onExpand() }
    }
}

/// Container that lays the three standard window buttons out on the native
/// 20pt pitch and reports group hover back to their cells.
final class TrafficLightGroupView: NSView {
    /// Horizontal distance between button origins in a real titlebar.
    private static let buttonPitch: CGFloat = 20

    private var buttons: [NSButton] = []
    private var isMouseInGroup = false

    init(coordinator: TrafficLightsView.Coordinator) {
        super.init(frame: .zero)

        // The style mask only describes which buttons to vend; these are
        // detached buttons, unrelated to the panel's own (borderless) mask.
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let specs: [(NSWindow.ButtonType, Selector)] = [
            (.closeButton, #selector(TrafficLightsView.Coordinator.close(_:))),
            (.miniaturizeButton, #selector(TrafficLightsView.Coordinator.minimize(_:))),
            (.zoomButton, #selector(TrafficLightsView.Coordinator.expand(_:)))
        ]

        for (index, spec) in specs.enumerated() {
            guard let button = NSWindow.standardWindowButton(spec.0, for: styleMask) else { continue }
            button.target = coordinator
            button.action = spec.1
            button.isEnabled = true
            button.setFrameOrigin(NSPoint(x: CGFloat(index) * Self.buttonPitch, y: 0))
            addSubview(button)
            buttons.append(button)
        }

        setFrameSize(intrinsicContentSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: buttons.last?.frame.maxX ?? 0,
            height: buttons.map { $0.frame.height }.max() ?? 0
        )
    }

    // A titlebar answers this for its own window buttons; the standard button
    // cells ask their superview for it to decide whether to draw the ×, − and +
    // glyphs. Implementing it here makes all three light up together on hover,
    // exactly like a real titlebar.
    @objc func _mouseInGroup(_ button: NSButton) -> Bool { isMouseInGroup }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { setMouseInGroup(true) }

    override func mouseExited(with event: NSEvent) { setMouseInGroup(false) }

    private func setMouseInGroup(_ inside: Bool) {
        guard isMouseInGroup != inside else { return }
        isMouseInGroup = inside
        for button in buttons { button.needsDisplay = true }
    }
}
