import Foundation
import AppKit

enum AppleNotesService {
    /// Transfers HTML content to Apple Notes via NSAppleScript.
    /// Uses NSWorkspace to launch Notes first (sandbox-safe), then sends
    /// Apple Events via NSAppleScript with the temporary-exception entitlement.
    /// Content is passed via a temp file to avoid string escaping issues.
    /// The `body` property of Apple Notes accepts HTML, preserving formatting.
    /// Calls completion on main thread with nil on success, error message on failure.
    static func transfer(html: String, completion: @escaping (String?) -> Void) {
        // Launch Notes via NSWorkspace — this is a sandbox-safe API that ensures
        // Notes is running before we try to send it Apple Events.
        let notesURL = URL(fileURLWithPath: "/System/Applications/Notes.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(at: notesURL, configuration: config) { _, error in
            if let error {
                DispatchQueue.main.async {
                    completion("Failed to launch Notes: \(error.localizedDescription)")
                }
                return
            }

            // Notes is now running. Proceed on a background queue.
            DispatchQueue.global(qos: .userInitiated).async {
                // Write note content to a temp file so AppleScript can read it directly.
                let timestamp = Int(Date().timeIntervalSince1970)
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("fn-content-\(timestamp).txt")
                let tmpPath = tmpURL.path
                do {
                    try html.write(to: tmpURL, atomically: true, encoding: .utf8)
                } catch {
                    DispatchQueue.main.async {
                        completion("Failed to write temp file: \(error.localizedDescription)")
                    }
                    return
                }

                // `read POSIX file` must be outside the `tell` block so it's handled
                // by Standard Additions, not sent to Notes as an event.
                let source = """
set noteBody to read POSIX file "\(tmpPath)" as «class utf8»
tell application "Notes"
    make new note at default account with properties {body:noteBody}
end tell
"""
                var errorDict: NSDictionary?
                let script = NSAppleScript(source: source)
                script?.executeAndReturnError(&errorDict)

                // Clean up temp file regardless of outcome
                try? FileManager.default.removeItem(at: tmpURL)

                DispatchQueue.main.async {
                    if let errorDict {
                        let errorMsg = (errorDict[NSAppleScript.errorMessage] as? String)
                            ?? "Unknown AppleScript error"
                        let errorCode = (errorDict[NSAppleScript.errorNumber] as? Int)
                            .map { " (code \($0))" } ?? ""
                        completion(errorMsg + errorCode)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }
}
