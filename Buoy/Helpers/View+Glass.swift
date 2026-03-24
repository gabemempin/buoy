import SwiftUI

private enum BuoyGlassMetrics {
    static let windowCornerRadius: CGFloat = 20
}

extension View {
    /// Applies Liquid Glass on macOS 26+, NSVisualEffectView on macOS 15.
    /// Main window — includes edge depth border.
    @ViewBuilder
    func buoyGlass(material: NSVisualEffectView.Material = .menu) -> some View {
        buoyRoundedGlass(
            material: material,
            cornerRadius: BuoyGlassMetrics.windowCornerRadius
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
        buoyRoundedGlass(
            material: material,
            cornerRadius: cornerRadius ?? max(0, BuoyGlassMetrics.windowCornerRadius - inset)
        )
    }

    @ViewBuilder
    private func buoyRoundedGlass(
        material: NSVisualEffectView.Material,
        cornerRadius: CGFloat
    ) -> some View {
        if #available(macOS 26, *) {
            self.background(
                    VisualEffectBackground(material: .underPageBackground, blendingMode: .behindWindow)  // ← blur layer; try .underPageBackground, .menu, .sidebar
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .opacity(0.85)  // ← tune 0.5–1.0 for blur intensity
                )
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.accentColor.opacity(0.0)],  // ← tune 0.04–0.12
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
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
            self.background(
                VisualEffectBackground(material: material, blendingMode: .behindWindow)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
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
    func buoyAccentCircle() -> some View {
        self.background(Color.accentColor, in: Circle())
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(Circle())
                .allowsHitTesting(false)
            )
            .shadow(color: Color.accentColor.opacity(0.4), radius: 4, x: 0, y: 2)
    }

    /// Solid accent-colored capsule with specular highlight and shadow.
    func buoyAccentCapsule() -> some View {
        self.background(Color.accentColor, in: Capsule())
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(Capsule())
                .allowsHitTesting(false)
            )
            .shadow(color: Color.accentColor.opacity(0.4), radius: 4, x: 0, y: 2)
    }

    /// Applies a capsule Liquid Glass effect on macOS 26+, subtle filled capsule on macOS 15.
    @ViewBuilder
    func buoyGlassCapsule() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        } else {
            self.background(
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        }
    }
}
