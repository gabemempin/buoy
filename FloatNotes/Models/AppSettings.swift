import Foundation
import AppKit

enum FontSize: String, Codable, CaseIterable {
    case small, medium, large

    var pointSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 14
        case .large: return 16
        }
    }
}

enum AppTheme: String, Codable, CaseIterable {
    case system, light, dark
}

struct AppSettings: Codable {
    var showInDock: Bool = false
    var alwaysOnTop: Bool = true
    var launchAtLogin: Bool = false
    var fontSize: FontSize = .medium
    var theme: AppTheme = .system
    var globalShortcut: String = "Option+Cmd+N"
    var onboarded: Bool = false

    // MARK: - Persistence

    private static var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".floating-notes")
            .appendingPathComponent("settings.json")
    }

    static func load() -> AppSettings {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        let url = Self.fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("FloatNotes2SettingsDidChange")
}
