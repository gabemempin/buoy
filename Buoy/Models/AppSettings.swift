import Foundation
import AppKit

enum AppTheme: String, Codable, CaseIterable {
    case system, light, dark
}

struct AppSettings: Codable {
    var showInDock: Bool = false
    var alwaysOnTop: Bool = true
    var launchAtLogin: Bool = false
    var fontSize: CGFloat = 14
    var theme: AppTheme = .system
    var globalShortcut: String = "Option+Cmd+N"
    var onboarded: Bool = false
    var hasSeenHarborModeTip: Bool = false
    var lastSelectedNoteID: String? = nil
    var dismissedUpdateVersion: String? = nil
    var lastSeenWhatsNewVersion: String? = nil
    var autoTitleEnabled: Bool = true

    /// The live settings value, kept in step by `SettingsStore`.
    ///
    /// `.settingsDidChange` observers must read this rather than calling
    /// `load()`: the disk write is debounced, so the file can be a beat behind
    /// the value the rest of the app is already running on.
    static var current: AppSettings = AppSettings()

    private static var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".buoy")
            .appendingPathComponent("settings.json")
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    /// Writes the JSON file. Does not notify — `SettingsStore` posts the change
    /// the moment the value is set, well before this lands.
    func writeToDisk() {
        let url = Self.fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Writes immediately and notifies. For the few callers that mutate a local
    /// copy rather than going through `SettingsStore`.
    func save() {
        Self.current = self
        writeToDisk()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("BuoySettingsDidChange")
}
