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
    static let hoverAnimation = Animation.easeInOut(duration: 0.14)
    static let accentHoverGlowOpacity: CGFloat = 0.58
    static let accentHoverHighlightOpacity: CGFloat = 0.2
    static let accentHoverBorderOpacity: CGFloat = 0.24
    static let glassButtonHoverBoost: Double = 0.08
    static let glassButtonHoverStrokeBoost: Double = 0.18
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
    func buoyAccentCircle(color: Color = .accentColor, isHovering: Bool = false) -> some View {
        self.background(color.opacity(isHovering ? 1 : 0.96), in: Circle())
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(isHovering ? 0.4 : 0.28), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(Circle())
                .allowsHitTesting(false)
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovering ? BuoyGlassMetrics.accentHoverBorderOpacity : 0.08), lineWidth: 0.7)
                    .padding(0.5)
                    .allowsHitTesting(false)
            )
            .shadow(color: color.opacity(isHovering ? BuoyGlassMetrics.accentHoverGlowOpacity : 0.4), radius: isHovering ? 8 : 4, x: 0, y: isHovering ? 3 : 2)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(isHovering ? BuoyGlassMetrics.accentHoverHighlightOpacity : 0))
                    .blur(radius: isHovering ? 5 : 0)
                    .allowsHitTesting(false)
            )
            .animation(BuoyGlassMetrics.hoverAnimation, value: isHovering)
    }

    /// Solid accent-colored capsule with specular highlight and shadow.
    func buoyAccentCapsule(color: Color = .accentColor, isHovering: Bool = false) -> some View {
        self.background(color.opacity(isHovering ? 1 : 0.96), in: Capsule())
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(isHovering ? 0.38 : 0.28), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(Capsule())
                .allowsHitTesting(false)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isHovering ? BuoyGlassMetrics.accentHoverBorderOpacity : 0.08), lineWidth: 0.7)
                    .padding(0.5)
                    .allowsHitTesting(false)
            )
            .shadow(color: color.opacity(isHovering ? BuoyGlassMetrics.accentHoverGlowOpacity : 0.4), radius: isHovering ? 9 : 4, x: 0, y: isHovering ? 3 : 2)
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(isHovering ? BuoyGlassMetrics.accentHoverHighlightOpacity : 0))
                    .blur(radius: isHovering ? 5 : 0)
                    .allowsHitTesting(false)
            )
            .animation(BuoyGlassMetrics.hoverAnimation, value: isHovering)
    }

    /// Tinted interactive glass rounded rect on macOS 26+, filled tint on macOS 15.
    /// Used for action buttons (Report Bug, Check for Updates, Quit).
    @ViewBuilder
    func buoyGlassButton(tint: Color, tintOpacity: Double = 0.18, stroke: Color? = nil, strokeOpacity: Double = 0.3, cornerRadius: CGFloat = 10, isHovering: Bool = false) -> some View {
        let strokeColor = stroke ?? tint
        let fillOpacity = tintOpacity + (isHovering ? BuoyGlassMetrics.glassButtonHoverBoost : 0)
        let effectiveStrokeOpacity = strokeOpacity + (isHovering ? BuoyGlassMetrics.glassButtonHoverStrokeBoost : 0)
        if #available(macOS 26, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(fillOpacity)).interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeColor.opacity(effectiveStrokeOpacity), lineWidth: isHovering ? 0.8 : 0.5)
                )
                .shadow(color: tint.opacity(isHovering ? 0.22 : 0.08), radius: isHovering ? 8 : 3, x: 0, y: 2)
                .animation(BuoyGlassMetrics.hoverAnimation, value: isHovering)
        } else {
            self
                .background(tint.opacity(fillOpacity * 0.7), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeColor.opacity(effectiveStrokeOpacity), lineWidth: isHovering ? 0.8 : 0.5)
                )
                .shadow(color: tint.opacity(isHovering ? 0.18 : 0.08), radius: isHovering ? 7 : 2, x: 0, y: 2)
                .animation(BuoyGlassMetrics.hoverAnimation, value: isHovering)
        }
    }

    func buoyAccentHoverPlate(isHovering: Bool, cornerRadius: CGFloat = 8) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(isHovering ? 0.16 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(isHovering ? 0.16 : 0), lineWidth: 0.6)
                )
                .shadow(color: Color.accentColor.opacity(isHovering ? 0.28 : 0), radius: isHovering ? 6 : 0, x: 0, y: 2)
                .animation(BuoyGlassMetrics.hoverAnimation, value: isHovering)
        )
    }

    func buoyAccentChevronHoverPlate(isHovering: Bool, cornerRadius: CGFloat = 999) -> some View {
        self.background(
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8
            )
            .fill(Color.white.opacity(isHovering ? 0.16 : 0))
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: 8,
                    topTrailingRadius: 8
                )
                .stroke(Color.white.opacity(isHovering ? 0.16 : 0), lineWidth: 0.6)
            )
            .shadow(color: Color.accentColor.opacity(isHovering ? 0.28 : 0), radius: isHovering ? 6 : 0, x: 0, y: 2)
            .animation(BuoyGlassMetrics.hoverAnimation, value: isHovering)
        )
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
