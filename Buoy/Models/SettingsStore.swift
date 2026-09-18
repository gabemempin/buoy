import SwiftUI

/// Owns the live `AppSettings` value for the whole app.
///
/// A mutation is published immediately and written to disk on a short debounce.
/// The split matters for anything the user *drags*: the colour wheel on the
/// Appearance page retints the panel on every drag frame, and writing
/// `settings.json` at pointer rate would stall the drag for no benefit. Readers
/// never see the delay — `AppSettings.current` is updated synchronously and
/// `.settingsDidChange` is posted synchronously, so only the file lags.
@Observable
final class SettingsStore {
    /// Long enough to swallow a drag, short enough that a crash right after a
    /// click cannot plausibly lose the change.
    private static let writeDebounce: TimeInterval = 0.25

    @ObservationIgnored private var pendingWrite: DispatchWorkItem?

    var value: AppSettings {
        didSet {
            AppSettings.current = value
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
            scheduleWrite()
        }
    }

    init() {
        let loaded = AppSettings.load()
        value = loaded
        AppSettings.current = loaded
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        // Capture the value at schedule time. Reading `self.value` inside the
        // work item would write whatever is current when the timer fires, which
        // is the same "resolve late, write the wrong thing" trap as the
        // debounced note saves in NoteStore.
        let snapshot = value
        let work = DispatchWorkItem { snapshot.writeToDisk() }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.writeDebounce, execute: work)
    }

    /// Writes any debounced change straight away. Call on termination.
    func flush() {
        guard let pendingWrite else { return }
        pendingWrite.cancel()
        self.pendingWrite = nil
        value.writeToDisk()
    }
}
