import SwiftUI

@main
struct FloatNotes2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — all window management is in AppDelegate
        Settings {
            EmptyView()
        }
    }
}
