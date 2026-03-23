import Foundation
import AppKit

enum AppleNotesService {
    /// Transfers HTML content to Apple Notes via NSAppleScript.
    /// Launches Notes via NSWorkspace first (sandbox-safe) to guarantee it is running
    /// before the Apple Events call, avoiding the -600 "app not running" error.
    /// Calls completion on main thread with nil on success, error message on failure.
    static func transfer(htmlContent: String, completion: @escaping (String?) -> Void) {
        guard let notesURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else {
            DispatchQueue.main.async { completion("Apple Notes not found on this Mac.") }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(at: notesURL, configuration: config) { _, error in
            if let error {
                DispatchQueue.main.async { completion(error.localizedDescription) }
                return
            }
            // Notes is fully running — run the AppleScript on a background queue
            DispatchQueue.global(qos: .userInitiated).async {
                let bodyExpression = buildASString(htmlContent)
                let source = """
tell application "Notes"
    make new note with properties {body:\(bodyExpression)}
end tell
"""
                var errorDict: NSDictionary?
                let script = NSAppleScript(source: source)
                script?.executeAndReturnError(&errorDict)

                DispatchQueue.main.async {
                    if let errorDict {
                        let msg = (errorDict[NSAppleScript.errorMessage] as? String)
                            ?? (errorDict[NSAppleScript.errorNumber].map { "Error \($0)" })
                            ?? "Unknown AppleScript error"
                        completion(msg)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Encodes a plain string as a valid AppleScript string expression,
    /// safely embedding quotes and newlines.
    private static func buildASString(_ text: String) -> String {
        if text.isEmpty { return "\"\"" }
        let lines = text.components(separatedBy: "\n")
        let encodedLines = lines.map { line -> String in
            let parts = line.components(separatedBy: "\"")
            return parts.map { "\"\($0)\"" }.joined(separator: " & quote & ")
        }
        return encodedLines.joined(separator: " & return & ")
    }
}
