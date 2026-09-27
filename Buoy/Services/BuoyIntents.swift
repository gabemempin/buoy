import AppIntents
import AppKit

// MARK: - Bridge

/// What the Shortcuts actions reach into the running app through.
///
/// App Intents are plain structs the system instantiates, so they cannot be
/// handed the app's objects. `AppDelegate` installs them here at launch, and
/// `ContentView` keeps `editor` pointed at the live editor.
@MainActor
enum NoteIntentBridge {
    static weak var noteStore: NoteStore?
    /// The editor showing the current note, while one is mounted.
    static weak var editor: BuoyTextView?
    static var fontSize: () -> CGFloat = { 14 }
    static var showPanel: () -> Void = {}

    static func install(
        noteStore: NoteStore,
        fontSize: @escaping () -> CGFloat,
        showPanel: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.fontSize = fontSize
        self.showPanel = showPanel
    }

    static func store() throws -> NoteStore {
        guard let noteStore else { throw BuoyIntentError.notReady }
        return noteStore
    }

    /// Appends `text` to a note with the same formatting rules as typing.
    ///
    /// The note open in the editor is appended *through* the editor. Its
    /// content lives in the text view until the next debounced save, so a
    /// database write would be overwritten by that save — and the editor, which
    /// only reloads on a note switch, would never show it anyway. Any other
    /// note is edited in an offscreen editor so the result is byte-for-byte
    /// what the real one would have produced.
    static func append(_ text: String, toNoteID noteID: String) throws {
        let store = try store()
        guard let note = store.notes.first(where: { $0.id == noteID }) else {
            throw BuoyIntentError.noteNotFound
        }
        if store.currentNote?.id == noteID, let editor, editor.window != nil {
            editor.appendExternalText(text)
            return
        }
        guard let rtf = renderedRTF(appending: text, to: note.contentRTF) else {
            throw BuoyIntentError.couldNotWrite
        }
        store.replaceContent(rtf, forNoteID: noteID)
    }

    /// Plain text of a note, from the live editor when it is the open one.
    static func plainText(ofNoteID noteID: String) throws -> String {
        let store = try store()
        if store.currentNote?.id == noteID, let editor, editor.window != nil {
            return editor.plainTextContent()
        }
        guard let note = store.notes.first(where: { $0.id == noteID }) else {
            throw BuoyIntentError.noteNotFound
        }
        return NotePlainText.of(note)
    }

    private static func renderedRTF(appending text: String, to rtf: Data) -> Data? {
        let editor = BuoyTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        editor.fontSize = fontSize()
        editor.loadRTF(rtf)
        editor.appendExternalText(text)
        return editor.rtfContent()
    }
}

enum BuoyIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case noteNotFound
    case couldNotWrite

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: return "Buoy is still starting up. Try again in a moment."
        case .noteNotFound: return "That note no longer exists in Buoy."
        case .couldNotWrite: return "Buoy couldn't save the text to that note."
        }
    }
}

// MARK: - Note entity

struct BuoyNoteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Buoy Note"
    static var defaultQuery = BuoyNoteQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(_ note: Note) {
        id = note.id
        title = note.title.isEmpty ? "Untitled" : note.title
    }
}

struct BuoyNoteQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [BuoyNoteEntity] {
        let notes = try NoteIntentBridge.store().notes
        return identifiers.compactMap { id in
            notes.first { $0.id == id }.map(BuoyNoteEntity.init)
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [BuoyNoteEntity] {
        try NoteIntentBridge.store().notes
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map(BuoyNoteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [BuoyNoteEntity] {
        try NoteIntentBridge.store().notes.map(BuoyNoteEntity.init)
    }
}

// MARK: - Intents

struct CreateBuoyNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Buoy Note"
    static var description = IntentDescription(
        "Creates a new note in Buoy. Lines starting with - become bullets, and - [ ] becomes a to-do."
    )

    @Parameter(title: "Title", description: "Leave empty to let Buoy name the note.")
    var noteTitle: String?

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String?

    @Parameter(title: "Show Buoy", default: false)
    var showsPanel: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Create Buoy note \(\.$noteTitle) with \(\.$text)") {
            \.$showsPanel
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BuoyNoteEntity> {
        let store = try NoteIntentBridge.store()
        let trimmedTitle = noteTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        store.createNote(titled: (trimmedTitle?.isEmpty ?? true) ? nil : trimmedTitle)
        guard let note = store.currentNote else { throw BuoyIntentError.couldNotWrite }
        if let text, !text.isEmpty {
            // The new note is current but its editor has not loaded yet, so
            // writing the store is enough: the editor reads this on mount.
            let editor = BuoyTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
            editor.fontSize = NoteIntentBridge.fontSize()
            editor.appendExternalText(text)
            if let rtf = editor.rtfContent() {
                store.replaceContent(rtf, forNoteID: note.id)
            }
        }
        if showsPanel { NoteIntentBridge.showPanel() }
        return .result(value: BuoyNoteEntity(note))
    }
}

struct AppendToBuoyNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Buoy Note"
    static var description = IntentDescription(
        "Adds text to the end of a Buoy note. Lines starting with - become bullets, and - [ ] becomes a to-do."
    )

    @Parameter(title: "Note")
    var note: BuoyNoteEntity

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try NoteIntentBridge.append(text, toNoteID: note.id)
        return .result()
    }
}

struct GetBuoyNoteTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Buoy Note Text"
    static var description = IntentDescription("Returns the plain text of a Buoy note.")

    @Parameter(title: "Note")
    var note: BuoyNoteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the text of \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try NoteIntentBridge.plainText(ofNoteID: note.id))
    }
}

struct OpenBuoyNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Buoy Note"
    static var description = IntentDescription("Shows Buoy with a note open.")

    @Parameter(title: "Note")
    var note: BuoyNoteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$note) in Buoy")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = try NoteIntentBridge.store()
        guard let target = store.notes.first(where: { $0.id == note.id }) else {
            throw BuoyIntentError.noteNotFound
        }
        store.switchNote(to: target)
        NoteIntentBridge.showPanel()
        return .result()
    }
}

// MARK: - Shortcuts app

struct BuoyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateBuoyNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New \(.applicationName) note"
            ],
            shortTitle: "New Note",
            systemImageName: "note.text.badge.plus"
        )
        AppShortcut(
            intent: AppendToBuoyNoteIntent(),
            phrases: ["Add to a \(.applicationName) note"],
            shortTitle: "Add to Note",
            systemImageName: "text.append"
        )
        AppShortcut(
            intent: OpenBuoyNoteIntent(),
            phrases: ["Open a \(.applicationName) note"],
            shortTitle: "Open Note",
            systemImageName: "note.text"
        )
    }
}
