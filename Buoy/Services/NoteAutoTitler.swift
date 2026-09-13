import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates short, on-device titles for a brand-new note as it grows, and
/// hands each result to `NoteStore` for a guarded apply.
///
/// Runs in stages, tracked by `Note.autoTitleStage`: a first title once the
/// note reaches `thresholds[0]` characters, then a refinement at each later
/// threshold. `NoteStore` locks the note (`autoTitleLocked`) the
/// moment the user types a title by hand, which this class checks before
/// every request — a locked note is never touched again.
///
/// Runs entirely through Apple's Foundation Models framework — no network,
/// no bundled weights. Everything that touches `FoundationModels` symbols is
/// gated behind `#available(macOS 26, *)`; on any older system (or with
/// Apple Intelligence off) `isSupported` is `false` and the class is inert.
@MainActor
final class NoteAutoTitler {
    private unowned let store: NoteStore
    private var debounceWork: [String: DispatchWorkItem] = [:]
    private var didPrewarm = false
    private var activeTask: Task<Void, Never>?
    private var activeNoteID: String?
    /// Identifies the "current" generation attempt. `Task.cancel()` only sets
    /// a cooperative flag — it doesn't force `session.respond` to return, so a
    /// cancelled task can keep running in the background for as long as a
    /// normal request takes. Bumped whenever a request starts or is cancelled,
    /// so a stale task's eventual completion can tell it's been superseded
    /// and must not touch `activeTask`/`activeNoteID`/`titleThinking` again.
    private var generation = 0

    /// Character counts that arm stage 0 (first title) and each later
    /// refinement. `Note.autoTitleStage` indexes into this; a note whose
    /// stage has reached `thresholds.count` is finished.
    ///
    /// Changing this array changes what "finished" means for notes already in
    /// the database — add a migration alongside it (see `v7_autoTitleRestage`)
    /// so previously-completed notes aren't re-armed by the longer array.
    private static let thresholds = [50, 100, 500]

    /// How long to let typing settle before considering a run. Short enough
    /// to feel responsive right at the threshold rather than after a pause.
    private static let coalesceDelay: TimeInterval = 0.3

    /// Warm the model once a note has *some* text, well before stage 0's
    /// threshold, so the first real request isn't also paying cold-start cost.
    private static let prewarmCharacterCount = 20

    init(store: NoteStore) {
        self.store = store
    }

    /// Whether this Mac can run the on-device model right now: Apple Silicon,
    /// macOS 26+, Apple Intelligence enabled, model ready. Anything else
    /// (including "still downloading") reports `false` — the feature simply
    /// stays hidden rather than half-working.
    static var isSupported: Bool {
        guard #available(macOS 26, *) else { return false }
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }

    /// Called by `NoteStore.saveContent` whenever the current note is still
    /// unlocked. Cheap to call on every keystroke — it only resets a short
    /// coalescing timer.
    func noteContentDidChange(noteID: String) {
        guard Self.isSupported else { return }
        guard let note = store.notes.first(where: { $0.id == noteID }),
              !note.autoTitleLocked,
              note.autoTitleStage < Self.thresholds.count
        else { return }

        let plainText = NotePlainText.of(note).trimmingCharacters(in: .whitespacesAndNewlines)

        if !didPrewarm, plainText.count >= Self.prewarmCharacterCount {
            didPrewarm = true
            prewarmModel()
        }

        debounceWork[noteID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.debounceWork[noteID] = nil
            self?.evaluate(noteID: noteID)
        }
        debounceWork[noteID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceDelay, execute: work)
    }

    /// Stops any pending or in-flight work for a note whose auto-title state
    /// just changed underneath it — locked by a hand-typed title, or reverted
    /// to "Note N". `NoteStore`'s own stage guard would also catch a stale
    /// result, but this also clears the "thinking" shimmer immediately and
    /// frees the single in-flight slot right away, rather than leaving every
    /// future request blocked until the cancelled one gets around to
    /// finishing on its own (see `generation`).
    func cancel(noteID: String) {
        debounceWork[noteID]?.cancel()
        debounceWork[noteID] = nil
        if activeNoteID == noteID {
            activeTask?.cancel()
            activeTask = nil
            activeNoteID = nil
            store.titleThinking = nil
            generation += 1
        }
    }

    private func prewarmModel() {
        guard #available(macOS 26, *) else { return }
        #if canImport(FoundationModels)
        LanguageModelSession().prewarm()
        #endif
    }

    private func evaluate(noteID: String) {
        guard #available(macOS 26, *) else { return }
        #if canImport(FoundationModels)
        guard activeTask == nil else { return }
        guard let note = store.notes.first(where: { $0.id == noteID }),
              !note.autoTitleLocked
        else { return }

        let originalStage = note.autoTitleStage
        guard originalStage < Self.thresholds.count else { return }

        let plainText = NotePlainText.of(note).trimmingCharacters(in: .whitespacesAndNewlines)

        // A paste (or any single large edit) can satisfy more than one
        // threshold at once. Run only the furthest stage the text already
        // qualifies for — otherwise stage 0 fires, completes, and its own
        // cleanup immediately re-evaluates to find stage 1 already met too,
        // renaming the note twice in a row for one paste.
        guard let targetStage = (originalStage..<Self.thresholds.count)
            .last(where: { plainText.count >= Self.thresholds[$0] })
        else { return }

        generate(
            noteID: noteID,
            // What the note's stage must still be for the result to count...
            expectedStage: originalStage,
            // ...and what it advances to. Skipping ahead means one request can
            // clear both thresholds, so this is not always expectedStage + 1.
            nextStage: targetStage + 1,
            plainText: plainText,
            currentTitle: note.title,
            // Only true once stage 0 has actually run — if we jumped straight
            // to stage 1 on a big paste, `currentTitle` is still the "Note N"
            // placeholder, not something worth asking the model to "keep".
            hasExistingAutoTitle: originalStage > 0
        )
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func generate(noteID: String, expectedStage: Int, nextStage: Int, plainText: String, currentTitle: String, hasExistingAutoTitle: Bool) {
        let excerpt = String(plainText.prefix(1200))
        activeNoteID = noteID
        store.titleThinking = noteID
        generation += 1
        let myGeneration = generation

        activeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                // `cancel()` may already have moved on (bumping `generation`)
                // by the time this task — cancelled or not — actually finishes
                // running `session.respond`. A stale task must not clear state
                // a newer, still-running request owns.
                if self.generation == myGeneration {
                    self.activeTask = nil
                    self.activeNoteID = nil
                    // A note that crossed the next threshold while this request
                    // was in flight shouldn't have to wait for another keystroke.
                    //
                    // Only re-enter if the request actually moved the note's
                    // stage. If it didn't, retrying immediately would produce
                    // the identical no-op and spin the model forever; a later
                    // keystroke re-arms it through the debounce instead.
                    let stageNow = self.store.notes.first(where: { $0.id == noteID })?.autoTitleStage
                    if stageNow != expectedStage {
                        self.evaluate(noteID: noteID)
                    }
                }
            }

            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let prompt = hasExistingAutoTitle
                    ? """
                      This note has grown. Its current title is "\(currentTitle)". \
                      Suggest a title for it — keep the current one if it still \
                      fits, or replace it if the note has moved on:

                      \(excerpt)
                      """
                    : "Suggest a title for this note:\n\n\(excerpt)"
                let response = try await session.respond(
                    to: prompt,
                    generating: NoteTitleSuggestion.self,
                    options: GenerationOptions(temperature: 0.3)
                )
                guard !Task.isCancelled, self.generation == myGeneration else { return }
                if let title = Self.sanitize(response.content.title) {
                    if title != currentTitle {
                        self.store.applyAutoTitle(
                            title,
                            noteID: noteID,
                            expectedStage: expectedStage,
                            nextStage: nextStage
                        )
                    } else {
                        // The model chose to keep the current title. Not a
                        // failure — the shimmer just ends with nothing to show.
                        self.store.spendAutoTitleStage(
                            noteID: noteID,
                            expectedStage: expectedStage,
                            nextStage: nextStage
                        )
                    }
                } else {
                    // Empty or all-punctuation response — from the user's side
                    // indistinguishable from a refusal.
                    self.reportFailure(noteID: noteID, expectedStage: expectedStage, nextStage: nextStage)
                }
            } catch {
                // Guardrail refusal, unsupported content, model hiccup — any
                // failure spends the stage rather than retrying forever on
                // content the model won't touch.
                if !Task.isCancelled, self.generation == myGeneration {
                    self.reportFailure(noteID: noteID, expectedStage: expectedStage, nextStage: nextStage)
                }
            }
        }
    }

    /// Spends the stage for a request that produced no title, and tells the
    /// UI so the "thinking" shimmer doesn't just end in silence.
    ///
    /// Only posts when the stage was actually spent — a note the user has
    /// since titled by hand, or one that already moved on, is dropped by
    /// `NoteStore`'s guard and shouldn't surface a warning — and only for the
    /// note on screen, since a toast about some other note would be confusing.
    /// Wording is deliberately mild: the guardrail declines ordinary personal
    /// content often enough that this is routine, not an error.
    private func reportFailure(noteID: String, expectedStage: Int, nextStage: Int) {
        let didSpend = store.spendAutoTitleStage(
            noteID: noteID,
            expectedStage: expectedStage,
            nextStage: nextStage
        )
        guard didSpend, store.currentNote?.id == noteID else { return }
        NotificationCenter.default.post(name: .buoyAutoTitleFailed, object: noteID)
    }

    @available(macOS 26, *)
    private static let instructions = """
        You name sticky notes. Given the note's text, reply with a short title: \
        one to three words, Title Case, no punctuation, no quotation marks, no \
        emoji. Describe what the note is about, not its first few words.
        """
    #endif

    /// Belt-and-braces cleanup of the model's output. `@Guide` steers the
    /// model but doesn't enforce the shape of a `String` property, so this is
    /// the actual guarantee behind "3 words max".
    private static func sanitize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        while let last = text.last, ".!?,:;".contains(last) {
            text.removeLast()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let words = text.split(separator: " ", omittingEmptySubsequences: true).prefix(3)
        guard !words.isEmpty else { return nil }
        let title = words.joined(separator: " ")
        guard title.count <= 40 else { return String(title.prefix(40)) }
        return title
    }
}

extension Notification.Name {
    /// Posted by `NoteAutoTitler` when a request for the current note fails
    /// to produce a title. `object` is the note id. `ContentView` routes it to
    /// the lower-center toast as a warning.
    static let buoyAutoTitleFailed = Notification.Name("BuoyAutoTitleFailed")
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
private struct NoteTitleSuggestion {
    @Guide(description: "A title of one to three words in Title Case, no punctuation, no quotes")
    var title: String
}
#endif
