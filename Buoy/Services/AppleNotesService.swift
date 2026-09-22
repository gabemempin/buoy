import Foundation
import AppKit

enum AppleNotesService {
    /// Opening the file invokes Notes' native importer. Completion confirms
    /// handoff only: the user can still cancel the import confirmation in Notes.
    @available(macOS 26, *)
    static func transferMarkdown(_ markdown: String, completion: @escaping (String?) -> Void) {
        guard let notesURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else {
            completion("Apple Notes not found on this Mac.")
            return
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Buoy-Notes-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("Buoy Note.md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try markdown.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            completion(error.localizedDescription)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([file], withApplicationAt: notesURL, configuration: config) { _, error in
            // Keep the file for the asynchronous import dialog; the OS manages
            // temporary storage. Removing it on successful handoff races Notes.
            if error != nil { try? FileManager.default.removeItem(at: directory) }
            DispatchQueue.main.async { completion(error?.localizedDescription) }
        }
    }

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

    private static func buildASString(_ text: String) -> String {
        if text.isEmpty { return "\"\"" }
        return text.components(separatedBy: "\n").map { line in
            line.components(separatedBy: "\"").map { "\"\($0)\"" }.joined(separator: " & quote & ")
        }.joined(separator: " & return & ")
    }
}
