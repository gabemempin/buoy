import SwiftUI
import AppKit

private enum BuoyGlassMetrics {
    static let windowCornerRadius: CGFloat = 20
    static let enableWindowFocusPolish = true
    static let liquidGlassBackdropActiveOpacity: CGFloat = 0.62
    static let liquidGlassBackdropInactiveOpacity: CGFloat = 0.67
    static let liquidGlassActiveTintOpacity: CGFloat = 0.05
    static let liquidGlassInactiveTintOpacity: CGFloat = 0.045
    static let inactiveFrostVeilOpacity: CGFloat = 0.015
    static let inactiveFrostBorderOpacity: CGFloat = 0.18
    static let windowFocusAnimation = Animation.easeInOut(duration: 0.22)
}

extension View {
    /// Applies Liquid Glass on macOS 26+, NSVisualEffectView on macOS 15.
    /// Main window — includes edge depth border.
    @ViewBuilder
    func buoyGlass(material: NSVisualEffectView.Material = .menu) -> some View {
        modifier(
            BuoyRegularGlassModifier(
                shape: RoundedRectangle(cornerRadius: BuoyGlassMetrics.windowCornerRadius),
                fallbackMaterial: material
            )
        )
    }

    /// Rounded glass inset from the main window edge. Keeps corners aligned with the
    /// host window by deriving the inner radius from the outer window radius.
    @ViewBuilder
    func buoyInsetGlass(
        inset: CGFloat,
        cornerRadius: CGFloat? = nil,
        material: NSVisualEffectView.Material = .menu
    ) -> some View {
        modifier(
            BuoyRoundedGlassModifier(
                cornerRadius: cornerRadius ?? max(0, BuoyGlassMetrics.windowCornerRadius - inset)
            )
        )
    }

    /// More opaque glass for overlay panels (Settings, Shortcuts, AllNotes).
    @ViewBuilder
    func buoyGlassPanel(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                )
        } else {
            self.background(
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Applies a circular Liquid Glass effect on macOS 26+, subtle filled circle on macOS 15.
    @ViewBuilder
    func buoyGlassCircle() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        } else {
            self.background(
                Circle()
                    .fill(Color.primary.opacity(0.12))
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        }
    }

    /// Solid accent-colored circle button with specular highlight and shadow.
    func buoyAccentCircle(color: Color = .accentColor) -> some View {
        self.background(color, in: Circle())
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(Circle())
                .allowsHitTesting(false)
            )
            .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
    }

    /// Solid accent-colored capsule with specular highlight and shadow.
    func buoyAccentCapsule(color: Color = .accentColor) -> some View {
        self.background(color, in: Capsule())
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(Capsule())
                .allowsHitTesting(false)
            )
            .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
    }

    /// Tinted interactive glass rounded rect on macOS 26+, filled tint on macOS 15.
    /// Used for action buttons (Report Bug, Check for Updates, Quit).
    @ViewBuilder
    func buoyGlassButton(tint: Color, tintOpacity: Double = 0.18, stroke: Color? = nil, strokeOpacity: Double = 0.3, cornerRadius: CGFloat = 10) -> some View {
        let strokeColor = stroke ?? tint
        if #available(macOS 26, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(tintOpacity)).interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(strokeColor.opacity(strokeOpacity), lineWidth: 0.5))
        } else {
            self
                .background(tint.opacity(tintOpacity * 0.7), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(strokeColor.opacity(strokeOpacity), lineWidth: 0.5))
        }
    }

    /// Applies a capsule Liquid Glass effect on macOS 26+, subtle filled capsule on macOS 15.
    @ViewBuilder
    func buoyGlassCapsule() -> some View {
        modifier(
            BuoyRegularGlassModifier(
                shape: Capsule(),
                fallbackMaterial: .popover
            )
        )
    }
}

private struct BuoyRegularGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let fallbackMaterial: NSVisualEffectView.Material

    @State private var isWindowFocused = true

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
                .overlay {
                    if BuoyGlassMetrics.enableWindowFocusPolish && !isWindowFocused {
                        shape
                            .fill(Color.white.opacity(BuoyGlassMetrics.inactiveFrostVeilOpacity))
                            .overlay(
                                shape.stroke(
                                    Color.white.opacity(BuoyGlassMetrics.inactiveFrostBorderOpacity),
                                    lineWidth: 0.5
                                )
                            )
                            .allowsHitTesting(false)
                            .animation(BuoyGlassMetrics.windowFocusAnimation, value: isWindowFocused)
                    }
                }
                .background(
                    Group {
                        if BuoyGlassMetrics.enableWindowFocusPolish {
                            BuoyWindowFocusObserver { isFocused in
                                withAnimation(BuoyGlassMetrics.windowFocusAnimation) {
                                    isWindowFocused = isFocused
                                }
                            }
                            .frame(width: 0, height: 0)
                        }
                    }
                )
        } else {
            content
                .background(
                    VisualEffectBackground(material: fallbackMaterial, blendingMode: .behindWindow)
                )
                .clipShape(shape)
        }
    }
}

private struct BuoyRoundedGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isWindowFocused = true

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            let focusPolishEnabled = BuoyGlassMetrics.enableWindowFocusPolish
            let showsInactivePolish = focusPolishEnabled && !isWindowFocused
            let backdropOpacity = showsInactivePolish
                ? BuoyGlassMetrics.liquidGlassBackdropInactiveOpacity
                : BuoyGlassMetrics.liquidGlassBackdropActiveOpacity
            let tintOpacity = showsInactivePolish
                ? BuoyGlassMetrics.liquidGlassInactiveTintOpacity
                : BuoyGlassMetrics.liquidGlassActiveTintOpacity

            content
                .background(
                    ZStack {
                        VisualEffectBackground(material: .underPageBackground, blendingMode: .behindWindow)
                            .opacity(backdropOpacity)
                        shape
                            .fill(Color.accentColor.opacity(tintOpacity))
                        if showsInactivePolish {
                            shape
                                .fill(Color.white.opacity(BuoyGlassMetrics.inactiveFrostVeilOpacity))
                        }
                    }
                    .clipShape(shape)
                    .animation(BuoyGlassMetrics.windowFocusAnimation, value: isWindowFocused)
                )
                .background(
                    Group {
                        if focusPolishEnabled {
                            BuoyWindowFocusObserver { isFocused in
                                withAnimation(BuoyGlassMetrics.windowFocusAnimation) {
                                    isWindowFocused = isFocused
                                }
                            }
                            .frame(width: 0, height: 0)
                        }
                    }
                )
                .glassEffect(.clear, in: shape)
                .clipShape(shape)
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .clear, .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        } else {
            content
                .background(
                    VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
                        .opacity(0.7)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

private struct BuoyWindowFocusObserver: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = onChange
        DispatchQueue.main.async {
            nsView.refreshObservation()
        }
    }
}

private final class ObserverView: NSView {
    var onChange: ((Bool) -> Void)?
    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshObservation()
    }

    deinit {
        removeObservers()
    }

    func refreshObservation() {
        guard window !== observedWindow else { return }

        removeObservers()
        observedWindow = window

        guard let window else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onChange?(window.isKeyWindow)
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onChange?(true)
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onChange?(false)
            }
        ]
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }
}
