import SwiftUI

@main
struct BuoyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — all window management is in AppDelegate
        Settings {
            EmptyView()
        }
    }
}
