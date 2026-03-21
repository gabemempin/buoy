import Foundation
import AppKit

enum AppleNotesService {
    /// Transfers plain text content to Apple Notes via NSAppleScript (in-process).
    /// Using NSAppleScript instead of osascript subprocess avoids the sandbox/shell
    /// access issue where `do shell script` inside osascript cannot reach the app's
    /// sandboxed tmp directory.
    /// Calls completion on main thread with nil on success, error message on failure.
    static func transfer(plainText: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bodyExpression = buildASString(plainText)
            let source = """
tell application "Notes"
    activate
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

    /// Converts a plain text string into a valid AppleScript string expression.
    /// - Splits on `"` and rejoins with ` & quote & ` to safely embed quotes.
    /// - Splits on `\n` and rejoins with ` & return & ` to embed newlines.
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
