import Foundation

/// One line of the What's New splash: an SF Symbol, a short bold heading, and a
/// one-sentence description. Keep headings to two to four words and details to a
/// single sentence — the splash is a summary of the changelog, not a copy of it.
struct WhatsNewItem: Identifiable {
    let symbol: String
    let title: String
    let detail: String

    var id: String { title }
}

/// The notes for one shipped version.
///
/// `version` must match `MARKETING_VERSION` (and therefore
/// `CFBundleShortVersionString`) exactly. A mismatch is silent: the lookup
/// simply finds nothing and no splash is shown.
struct WhatsNewRelease {
    let version: String
    let features: [WhatsNewItem]
    let fixes: [WhatsNewItem]
}

/// Release notes bundled into the app, shown once after an update.
///
/// The catalog is compiled into the build, so a release's entry has to be
/// written *before* the archive step — see the `/newupdate` skill. A version
/// with no entry here shows no splash at all and leaves
/// `AppSettings.lastSeenWhatsNewVersion` untouched, which is the intended
/// behaviour for a release with nothing worth announcing.
enum WhatsNewCatalog {
    /// Newest first.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "1.5.0",
            features: [
                WhatsNewItem(
                    symbol: "paintpalette",
                    title: "Build your Buoy!",
                    detail: "Pick a window tint and an accent color in Settings ▸ Appearance."
                ),
                WhatsNewItem(
                    symbol: "folder",
                    title: "Folders",
                    detail: "Group your notes into folders, and drag to reorder anything in All Notes."
                ),
                WhatsNewItem(
                    symbol: "sparkles",
                    title: "Notes that name themselves",
                    detail: "On Macs with Apple Intelligence, new notes get a short title as you write."
                ),
                WhatsNewItem(
                    symbol: "gearshape",
                    title: "New Settings",
                    detail: "Settings now opens from the gear, and every shortcut can be changed."
                ),
                WhatsNewItem(
                    symbol: "rectangle.compress.vertical",
                    title: "Compact Mode",
                    detail: "Make the window smaller and Buoy's controls shrink to fit."
                ),
                WhatsNewItem(
                    symbol: "timer",
                    title: "Harbor timers",
                    detail: "Title a note \"5m\" or \"1h30\" and it counts down in Harbor Mode."
                ),
                WhatsNewItem(
                    symbol: "cloud.fog",
                    title: "Fog Mode",
                    detail: "Shake the window to blur everything behind Buoy. Shake again to clear it."
                )
            ],
            fixes: [
                WhatsNewItem(
                    symbol: "arrow.down.right.and.arrow.up.left",
                    title: "Smoother Harbor Mode",
                    detail: "Harbor Mode opens and closes more smoothly."
                ),
                WhatsNewItem(
                    symbol: "checklist",
                    title: "Checklists that travel",
                    detail: "Checkboxes survive sending to Apple Notes or copying as Markdown."
                ),
                WhatsNewItem(
                    symbol: "arrow.left.arrow.right",
                    title: "Shift to switch notes, everywhere",
                    detail: "Now works on trackpads and Magic Mice too."
                )
            ]
        ),
        WhatsNewRelease(
            version: "1.4.5",
            features: [
                WhatsNewItem(
                    symbol: "link",
                    title: "Links in a popover",
                    detail: "Press ⌘K and a small popover opens next to your selection. A URL you just copied is filled in for you."
                ),
                WhatsNewItem(
                    symbol: "pencil.line",
                    title: "Editable links",
                    detail: "Put your cursor inside a link and press ⌘K to change its text or address."
                ),
                WhatsNewItem(
                    symbol: "arrow.left.arrow.right",
                    title: "Shift to switch notes",
                    detail: "Hold Shift while scrolling to move between notes on a mouse with no horizontal scroll."
                ),
                WhatsNewItem(
                    symbol: "checkmark.bubble",
                    title: "Confirmations in one place",
                    detail: "Messages like Copied to clipboard now appear as a small pill near the bottom of the note."
                )
            ],
            fixes: [
                WhatsNewItem(
                    symbol: "text.cursor",
                    title: "Simpler placeholder",
                    detail: "An empty note just says Start typing, without the keyboard shortcut hint."
                )
            ]
        )
    ]

    /// The running build's version. Same read as `UpdateService`.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func release(for version: String) -> WhatsNewRelease? {
        releases.first { $0.version == version }
    }

    /// True on the first launch of an upgraded build that has notes to show.
    ///
    /// Gated on `onboarded` so a fresh install gets the onboarding carousel
    /// instead; `OnboardingView.complete()` stamps the current version so the
    /// splash doesn't then appear on that user's second launch.
    static func shouldPresent(settings: AppSettings) -> Bool {
        settings.onboarded
            && settings.lastSeenWhatsNewVersion != currentVersion
            && release(for: currentVersion) != nil
    }
}
