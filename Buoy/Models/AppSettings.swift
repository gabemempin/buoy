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
    static let settingsDidChange = Notification.Name("BuoySettingsDidChange")
}
