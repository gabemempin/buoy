import SwiftUI

// MARK: - Toast Action

/// An offer attached to a toast — "we did this, press here to take it back".
///
/// Deliberately not a filled button. The pill is already a floating object
/// over the note, and a second solid shape inside it reads as a dialog; a
/// hairline and accent-coloured text carry it.
struct ToastAction {
    let title: String
    let handler: () -> Void
}

// MARK: - Toast Style

/// Register of a toast. Neutral confirms an action the user just took, info
/// is a tip or a next step (no checkmark: nothing has finished yet), warning
/// reports a soft failure nothing needs doing about (auto-titling declined the
/// note), error reports one that blocked what they asked for.
///
/// Copy rules for every pill: sentence case, no trailing period, "Couldn't" /
/// "Can't" rather than "Cannot" or a raw "Error: …" dump.
enum ToastStyle {
    case neutral
    case info
    case warning
    case error

    var symbolName: String {
        switch self {
        case .neutral: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "exclamationmark.circle.fill"
        }
    }

    /// How long a pill of this register stays up when the caller doesn't say.
    /// A confirmation only needs a glance; anything the user has to read and
    /// act on gets longer.
    var defaultDuration: TimeInterval {
        switch self {
        case .neutral: return 2
        case .info:    return 5
        case .warning, .error: return 4
        }
    }

    /// System colors rather than literal hexes so the tint tracks the
    /// appearance, Graphite and Increase Contrast like every other alert.
    var tint: Color {
        switch self {
        case .neutral, .info: return BuoyTheme.current.accent
        case .warning: return Color(nsColor: .systemOrange)
        case .error:   return Color(nsColor: .systemRed)
        }
    }

    /// Wash laid over the glass so a warning or error pill reads as tinted at
    /// a glance, not just by its glyph. Neutral stays plain glass.
    var washOpacity: Double {
        switch self {
        case .neutral, .info: return 0
        case .warning, .error: return BuoyContrast.opacity(0.14, boosted: 0.3)
        }
    }

    var stroke: Color {
        switch self {
        case .neutral, .info: return .buoyOverlayStroke
        case .warning, .error: return tint.opacity(BuoyContrast.opacity(0.45, boosted: 0.9))
        }
    }
}

// MARK: - Toast

/// Floating glass pill anchored at the lower center of the note panel.
///
/// The one pill for everything that appears there — toasts, tips and the
/// update notice (`UpdateBubble`) — so they share a shape, type, spacing,
/// position (`footerPillBottomPadding`) and the `BuoyMotion.pillPop` entrance.
/// Build new lower-center notices from this rather than a bespoke view.
///
/// Shares `buoyGlassCapsule()` with the Harbor pill, so it inherits the Reduce
/// Transparency opaque fallback and the pre-26 static glass for free. Text is
/// `.primary` on every style; the style speaks through the glyph, a tinted
/// wash and the stroke rather than a solid fill, which kept white text legible
/// only while the accent happened to be dark.
struct NotificationToast: View {
    let message: String
    var style: ToastStyle = .neutral
    /// Overrides the style's glyph (the update notice's arrow); the tint still
    /// comes from the style.
    var symbolName: String? = nil
    var action: ToastAction? = nil
    /// Adds a trailing close button, for a notice that stays until dismissed.
    var onClose: (() -> Void)? = nil

    @Environment(\.buoyTheme) private var theme
    @State private var isActionHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName ?? style.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.tint)
                .accessibilityHidden(true)

            Text(message)
                .font(BuoyFont.secondaryEmphasized)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

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

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(isCloseHovering ? Color.buoyControlFill : .clear))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovering = $0 }
                .padding(.leading, 2)
                .padding(.trailing, -4)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(style.tint.opacity(style.washOpacity)))
        .overlay(Capsule().strokeBorder(style.stroke, lineWidth: 0.8))
        // A press on an interactive pill must not start a window drag.
        .background { if isInteractive { WindowDragBlocker() } }
        .buoyGlassCapsule()
    }

    private var isInteractive: Bool { action != nil || onClose != nil }
}

// MARK: - Toast State

@Observable
final class ToastState {
    var message: String = ""
    var style: ToastStyle = .neutral
    var action: ToastAction? = nil
    var isShowing: Bool = false
    /// Bumped on every `show`, and used as the pill's identity, so a toast
    /// that replaces one already up pops in afresh instead of swapping its
    /// text in place.
    var presentationID: Int = 0

    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(
        _ message: String,
        style: ToastStyle = .neutral,
        actionTitle: String? = nil,
        duration: TimeInterval? = nil,
        action: (() -> Void)? = nil
    ) {
        hideTask?.cancel()
        self.message = message
        self.style = style
        if let actionTitle, let action {
            // Wrapped so pressing it puts the pill away too; leaving it up
            // after its offer has been taken reads as a no-op.
            self.action = ToastAction(title: actionTitle) { [weak self] in
                action()
                self?.dismiss()
            }
        } else {
            self.action = nil
        }
        presentationID &+= 1
        isShowing = true
        let duration = duration ?? style.defaultDuration
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            isShowing = false
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        isShowing = false
    }
}

// MARK: - Toast Container

struct ToastContainer: View {
    var state: ToastState

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.isShowing {
                NotificationToast(message: state.message, style: state.style, action: state.action)
                    .id(state.presentationID)
                    .padding(.bottom, PanelLayoutMetrics.footerPillBottomPadding)
                    .transition(BuoyMotion.pillPop)
                    // Spoken as soon as it appears; it is the only feedback
                    // for actions like Copy and Transfer.
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(BuoyMotion.pillAnimation, value: state.isShowing)
        .animation(BuoyMotion.pillAnimation, value: state.presentationID)
        // An informational pill must never swallow a click meant for the
        // editor or footer beneath it. One carrying an action has to be
        // clickable, so hit testing follows the action rather than being off
        // outright.
        .allowsHitTesting(state.isShowing && state.action != nil)
    }
}
