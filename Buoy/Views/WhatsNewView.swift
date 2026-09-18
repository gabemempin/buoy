import SwiftUI
import AppKit

// MARK: - WhatsNewView

/// Full-panel splash shown once after Buoy updates to a version that has notes
/// in `WhatsNewCatalog`. Opaque (not glass) like the onboarding carousel, since
/// it covers the live editor rather than floating over it.
struct WhatsNewView: View {
    let release: WhatsNewRelease
    var onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var appIcon: NSImage?
    /// Drives the staggered entrance: 1 reveals the icon, 2 the title block,
    /// 3 + n the nth content entry.
    @State private var revealStep = 0
    @State private var keyMonitor: Any?

    private var entries: [WhatsNewEntry] {
        WhatsNewEntry.entries(for: release)
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .frame(maxWidth: .infinity)

                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            entryView(entry)
                                .reveal(revealStep >= 3 + index)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    // Enough room to scroll the last row clear of the fade, so
                    // nothing ends up permanently half-hidden under it.
                    .padding(.bottom, 24)
                }
                // Without this the last visible line is sliced flat against the
                // button and reads as a rendering bug rather than as scrolling.
                .overlay(alignment: .bottom) { bottomFade }

                continueButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragBlocker())
        .task {
            if appIcon == nil { appIcon = await loadOnboardingAppIconThumbnail() }
            do {
                try await Task.sleep(for: .milliseconds(60))
                bumpReveal()
                try await Task.sleep(for: .milliseconds(120))
                bumpReveal()
                for _ in entries.indices {
                    try await Task.sleep(for: .milliseconds(40))
                    bumpReveal()
                }
            } catch { return }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: Pieces

    /// Blends the clipped edge of the scroll content into the panel background.
    private var bottomFade: some View {
        LinearGradient(
            colors: [
                OnboardingBackground.fill(for: colorScheme).opacity(0),
                OnboardingBackground.fill(for: colorScheme)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 24)
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Group {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .interpolation(.high)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // Reserve the frame: the icon arrives asynchronously from
                    // QuickLook and the layout must not jump when it lands.
                    Color.clear
                }
            }
            .frame(width: 56, height: 56)
            .shadow(radius: 4)
            .accessibilityHidden(true)
            .reveal(revealStep >= 1)

            VStack(spacing: 4) {
                // Deliberately not "What's New in Buoy": at the panel's width
                // that wraps to two lines, and the icon already says which app.
                SlideHeaderText(text: "What's New")
                Text("Version \(release.version)")
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
            }
            .reveal(revealStep >= 2)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func entryView(_ entry: WhatsNewEntry) -> some View {
        switch entry {
        case let .section(title):
            Text(title.uppercased())
                .font(BuoyFont.caption)
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        case let .item(item):
            WhatsNewRow(item: item)
        }
    }

    private var continueButton: some View {
        Button(action: continueNow) {
            Text("Continue")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        // The panel is non-activating, so without this the button renders in
        // its inactive grey instead of the accent colour.
        .environment(\.controlActiveState, .active)
        .shadow(color: BuoyTheme.current.accent.opacity(0.32), radius: 4, y: 2)
        .accessibilityLabel("Continue")
        .accessibilityHint("Closes What's New. Return does the same.")
        .pointingHandCursor()
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: Reveal

    private func bumpReveal() {
        withAnimation(BuoyMotion.spring(response: 0.52, dampingFraction: 0.7)) {
            revealStep += 1
        }
    }

    // MARK: Key handling

    /// The panel is non-activating and the editor keeps first responder, so
    /// SwiftUI's `.defaultAction` never fires here (same reason as
    /// `DeleteConfirmDialog`). This monitor also stops plain typing from
    /// landing in the real note hidden behind the splash, and swallows ⌘M so
    /// Harbor Mode can't unmount the splash into a compact-height panel.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch event.keyCode {
            case 36, 76, 53: // Return, keypad Enter, Escape
                continueNow()
                return nil
            case 46 where modifiers.contains(.command): // ⌘M
                return nil
            case 48: // Tab — keyboard focus movement
                return event
            default:
                break
            }

            // Let every real chord through (⌘Q, ⌘W, VoiceOver's ctrl+option
            // navigation, the global hotkey). Swallow bare typing.
            if modifiers.intersection([.command, .control, .option]).isEmpty {
                return nil
            }
            return event
        }
    }

    /// Releases the key monitor *before* handing off, rather than waiting for
    /// `onDisappear`. The dismissal fade runs for a beat after this, and during
    /// that beat the monitor would otherwise still be swallowing keystrokes the
    /// user means for the note underneath.
    private func continueNow() {
        removeKeyMonitor()
        onContinue()
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - Row

private struct WhatsNewRow: View {
    let item: WhatsNewItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BuoyTheme.current.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(BuoyFont.control.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.detail)
                    .font(BuoyFont.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Announced as one phrase; the two Texts read as unrelated fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title). \(item.detail)")
    }
}

// MARK: - Flattened content

/// Sections and rows in one list so the entrance stagger can index them
/// uniformly, and so an empty section simply doesn't appear.
private enum WhatsNewEntry: Identifiable {
    case section(String)
    case item(WhatsNewItem)

    var id: String {
        switch self {
        case let .section(title): return "section-\(title)"
        case let .item(item): return "item-\(item.id)"
        }
    }

    static func entries(for release: WhatsNewRelease) -> [WhatsNewEntry] {
        var result: [WhatsNewEntry] = []
        if !release.features.isEmpty {
            result.append(.section("What's New"))
            result.append(contentsOf: release.features.map { .item($0) })
        }
        if !release.fixes.isEmpty {
            result.append(.section("Bug Fixes"))
            result.append(contentsOf: release.fixes.map { .item($0) })
        }
        return result
    }
}

private extension View {
    /// Shared entrance treatment. The offset is movement, so the animation that
    /// drives `isVisible` must come from `BuoyMotion` (Reduce Motion then
    /// collapses it to a crossfade).
    func reveal(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 8)
    }
}
