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
    /// Hue washed over the panel's glass. `nil` is the untinted default.
    var windowTint: HSLColor? = nil
    /// How strongly `windowTint` shows through, 0...1. Half by default, so
    /// picking a colour visibly does something without having to find a
    /// second control first.
    var windowTintOpacity: Double = 0.5
    /// Replaces the macOS accent throughout the app. `nil` follows the system.
    var accentColor: HSLColor? = nil
    /// Rebound in-app shortcuts, keyed by `BuoyCommand.rawValue`. Only the ones
    /// the user actually changed; everything else follows `defaultCombo`.
    var shortcuts: [String: KeyCombo] = [:]

    /// Decodes leniently: any key missing from the file keeps this struct's
    /// default rather than failing the whole decode.
    ///
    /// Swift's synthesized `init(from:)` does **not** fall back to a property's
    /// default value when its key is absent — it throws `keyNotFound`. With
    /// `load()` swallowing errors and returning `AppSettings()`, that made
    /// every new settings field a silent factory reset: the old file failed to
    /// decode, the app came up on defaults, and the next write persisted them
    /// over the user's real settings. Adding `compactChrome` did exactly that.
    ///
    /// Any new field must be added here as well as above.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()

        func flag(_ key: CodingKeys, _ fallback: Bool) -> Bool {
            (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? nil ?? fallback
        }
        func text(_ key: CodingKeys) -> String? {
            try? container.decodeIfPresent(String.self, forKey: key) ?? nil
        }

        showInDock = flag(.showInDock, fallback.showInDock)
        alwaysOnTop = flag(.alwaysOnTop, fallback.alwaysOnTop)
        launchAtLogin = flag(.launchAtLogin, fallback.launchAtLogin)
        onboarded = flag(.onboarded, fallback.onboarded)
        hasSeenHarborModeTip = flag(.hasSeenHarborModeTip, fallback.hasSeenHarborModeTip)
        autoTitleEnabled = flag(.autoTitleEnabled, fallback.autoTitleEnabled)

        fontSize = (try? container.decodeIfPresent(CGFloat.self, forKey: .fontSize)) ?? nil ?? fallback.fontSize
        theme = (try? container.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? nil ?? fallback.theme
        globalShortcut = text(.globalShortcut) ?? fallback.globalShortcut

        windowTint = try? container.decodeIfPresent(HSLColor.self, forKey: .windowTint) ?? nil
        accentColor = try? container.decodeIfPresent(HSLColor.self, forKey: .accentColor) ?? nil
        // `windowTintIntensity` is what this was called before the label
        // changed, so it is read from its own container — the synthesized keys
        // only know the current name — and an existing file keeps its setting.
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        windowTintOpacity = (try? container.decodeIfPresent(Double.self, forKey: .windowTintOpacity)) ?? nil
            ?? (try? legacy?.decodeIfPresent(Double.self, forKey: .windowTintIntensity)) ?? nil
            ?? fallback.windowTintOpacity

        shortcuts = (try? container.decodeIfPresent([String: KeyCombo].self, forKey: .shortcuts)) ?? nil ?? fallback.shortcuts

        lastSelectedNoteID = text(.lastSelectedNoteID)
        dismissedUpdateVersion = text(.dismissedUpdateVersion)
        lastSeenWhatsNewVersion = text(.lastSeenWhatsNewVersion)
    }

    init() {}

    /// The live settings value, kept in step by `SettingsStore`.
    ///
    /// `.settingsDidChange` observers must read this rather than calling
    /// `load()`: the disk write is debounced, so the file can be a beat behind
    /// the value the rest of the app is already running on.
    static var current: AppSettings = AppSettings()

    private enum LegacyKeys: String, CodingKey { case windowTintIntensity }

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
