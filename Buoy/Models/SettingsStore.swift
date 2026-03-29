import SwiftUI

@Observable
final class SettingsStore {
    var value: AppSettings {
        didSet { value.save() }
    }
    init() { value = AppSettings.load() }
}
