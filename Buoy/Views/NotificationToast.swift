import SwiftUI

// MARK: - Toast Style

/// Register of a toast. Neutral confirms an action the user just took, warning
/// reports a soft failure nothing needs doing about (auto-titling declined the
/// note), error reports one that blocked what they asked for.
enum ToastStyle {
    case neutral
    case warning
    case error

    var symbolName: String {
        switch self {
        case .neutral: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "exclamationmark.circle.fill"
        }
    }

    /// System colors rather than literal hexes so the tint tracks the
    /// appearance, Graphite and Increase Contrast like every other alert.
    var tint: Color {
        switch self {
        case .neutral: return BuoyTheme.current.accent
        case .warning: return Color(nsColor: .systemOrange)
        case .error:   return Color(nsColor: .systemRed)
        }
    }

    /// Wash laid over the glass so a warning or error pill reads as tinted at
    /// a glance, not just by its glyph. Neutral stays plain glass.
    var washOpacity: Double {
        switch self {
        case .neutral: return 0
        case .warning, .error: return BuoyContrast.opacity(0.14, boosted: 0.3)
        }
    }

    var stroke: Color {
        switch self {
        case .neutral: return .buoyOverlayStroke
        case .warning, .error: return tint.opacity(BuoyContrast.opacity(0.45, boosted: 0.9))
        }
    }
}

// MARK: - Toast Action

/// An offer attached to a toast — "we did this, press here to take it back".
///
/// Deliberately not a filled button. The pill is already a floating object
/// over the note, and a second solid shape inside it reads as a dialog. A
/// hairline and accent-coloured text carry it.
struct ToastAction {
    let title: String
    let handler: () -> Void
}

// MARK: - Toast

/// Floating glass pill anchored at the lower center of the note panel.
///
/// Shares `buoyGlassCapsule()` with the Harbor pill, so it inherits the Reduce
/// Transparency opaque fallback and the pre-26 static glass for free. Text is
/// `.primary` on every style; the style speaks through the glyph, a tinted
/// wash and the stroke rather than a solid fill, which kept white text legible
/// only while the accent happened to be dark.
struct NotificationToast: View {
    let message: String
    var style: ToastStyle = .neutral
    var action: ToastAction? = nil

    @Environment(\.buoyTheme) private var theme
    @State private var isActionHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: style.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.tint)
                .accessibilityHidden(true)

            Text(message)
                .font(BuoyFont.secondaryEmphasized)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()

            if let action {
                Rectangle()
                    .fill(Color.buoyOverlayStroke)
                    .frame(width: 1, height: 12)
                    .padding(.leading, 3)
                    .accessibilityHidden(true)

                Button(action: action.handler) {
                    Text(action.title)
                        .font(BuoyFont.secondaryProminent)
                        .foregroundStyle(theme.accent)
                        .opacity(isActionHovering ? 0.7 : 1)
                        .lineLimit(1)
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isActionHovering = $0 }
                .pointingHandCursor()
                .accessibilityLabel(action.title)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(style.tint.opacity(style.washOpacity)))
        .overlay(Capsule().strokeBorder(style.stroke, lineWidth: 0.8))
        .buoyGlassCapsule()
    }
}

// MARK: - Toast State

@Observable
final class ToastState {
    var message: String = ""
    var style: ToastStyle = .neutral
    var action: ToastAction? = nil
    var isShowing: Bool = false
    /// Tags a toast so a later event can retract that specific one without
    /// clearing whatever has since taken its place.
    @ObservationIgnored private(set) var identity: String? = nil

    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// A plain toast is gone in two seconds; one carrying an action stays for
    /// six, because a button nobody can reach in time is worse than no button.
    private static let plainDuration: TimeInterval = 2
    private static let actionableDuration: TimeInterval = 6

    func show(
        _ message: String,
        style: ToastStyle = .neutral,
        identity: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        hideTask?.cancel()
        self.message = message
        self.style = style
        self.identity = identity
        if let actionTitle, let action {
            // Wrapped so pressing it dismisses the toast as well; leaving the
            // pill up after its offer has been taken reads as a no-op.
            self.action = ToastAction(title: actionTitle) { [weak self] in
                action()
                self?.dismiss()
            }
        } else {
            self.action = nil
        }
        withAnimation(BuoyMotion.easeIn(0.15)) {
            isShowing = true
        }
        let duration = self.action == nil ? Self.plainDuration : Self.actionableDuration
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(BuoyMotion.easeOut(0.3)) {
                isShowing = false
            }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        identity = nil
        withAnimation(BuoyMotion.easeOut(0.2)) { isShowing = false }
    }

    /// Retracts a toast only if it is still the one on screen.
    func dismiss(ifShowing identity: String) {
        guard isShowing, self.identity == identity else { return }
        dismiss()
    }
}

// MARK: - Toast Container

struct ToastContainer: View {
    @State var state: ToastState

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.isShowing {
                NotificationToast(message: state.message, style: state.style, action: state.action)
                    // `buoyGlassCapsule` pads the pill by `glassEdgeInset` for
                    // its shadow ring; subtract it so the visible capsule sits
                    // on the same line as the update bubble, just above the footer.
                    .padding(.bottom, PanelLayoutMetrics.footerOverlayBottomInset - PanelLayoutMetrics.glassEdgeInset)
                    .transition(BuoyMotion.transition(.opacity.combined(with: .move(edge: .bottom))))
                    // Spoken as soon as it appears; it is the only feedback
                    // for actions like Copy and Transfer.
                    .accessibilityAddTraits(state.action == nil ? .isStaticText : .isSummaryElement)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // An informational pill must never swallow a click meant for the
        // editor or footer beneath it. One carrying an action has to be
        // clickable, so hit testing follows the action rather than being off
        // outright — and the pill is only ever a few points tall at the very
        // bottom of the panel.
        .allowsHitTesting(state.isShowing && state.action != nil)
    }
}
