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
    private var activeTask: Task<Void, Never>?
    private var activeNoteID: String?
    /// One warm, instruction-primed session, kept ready for the next request.
    /// Type-erased to `Any?` because a stored property can't be marked
    /// `@available` — only the code that casts it back to
    /// `LanguageModelSession` needs the macOS 26 check. See
    /// `ensureWarmSession()` and `generate(...)`.
    private var warmSessionBox: Any?
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
    /// coalescing timer. Everything that needs the note's plain text (the
    /// prewarm check included) waits for `evaluate`, so this never decodes
    /// RTF on the typing path.
    func noteContentDidChange(noteID: String) {
        guard Self.isSupported else { return }
        guard let note = store.notes.first(where: { $0.id == noteID }),
              !note.autoTitleLocked,
              note.autoTitleStage < Self.thresholds.count
        else { return }

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

    /// Cancels every pending debounce and the in-flight request, if any.
    /// Called when the user turns auto-titling off in Settings — a request
    /// that was already running (or merely queued behind a keystroke) must
    /// not land after the fact.
    func cancelAll() {
        for work in debounceWork.values {
            work.cancel()
        }
        debounceWork.removeAll()
        if let activeNoteID {
            cancel(noteID: activeNoteID)
        }
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

        // Warm the model once the note has *some* text, well before stage 0's
        // threshold, so the first real request isn't also paying cold-start
        // cost. Lives here rather than on every keystroke (`noteContentDidChange`)
        // because this method already pays for the RTF decode above.
        if plainText.count >= Self.prewarmCharacterCount {
            ensureWarmSession()
        }

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
    /// Ensures a warm, instruction-primed session is ready for the next
    /// request. Keeping exactly one session means a note titled an hour after
    /// the last one doesn't pay the model's cold-start cost on the request
    /// the user is most likely watching — see `generate`, which consumes this
    /// and clears it, and the completion `defer`, which re-arms it while the
    /// note is still eligible for another stage.
    @available(macOS 26, *)
    private func ensureWarmSession() {
        guard warmSessionBox == nil else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        warmSessionBox = session
    }

    @available(macOS 26, *)
    private func generate(
        noteID: String,
        expectedStage: Int,
        nextStage: Int,
        plainText: String,
        currentTitle: String,
        hasExistingAutoTitle: Bool,
        isRetry: Bool = false,
        excerptOverride: String? = nil,
        useGreedySampling: Bool = false
    ) {
        let excerpt = excerptOverride ?? String(plainText.prefix(1200))
        activeNoteID = noteID
        store.titleThinking = noteID
        generation += 1
        let myGeneration = generation

        // Hand off the warm session rather than building a fresh one — see
        // `ensureWarmSession`. Do not reuse one across stages or notes: it
        // would carry the previous prompt/answer in the transcript (a second
        // anchoring channel on top of the refinement prompt's own "keep it"
        // permission), it would contaminate across notes unless keyed per
        // note, and a cancelled-but-still-running `respond` on a shared
        // session throws `concurrentRequests` on the next call.
        let session = (warmSessionBox as? LanguageModelSession)
            ?? LanguageModelSession(instructions: Self.instructions)
        warmSessionBox = nil

        activeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                // `cancel()` may already have moved on (bumping `generation`)
                // by the time this task — cancelled or not — actually finishes
                // running `session.respond`. A stale task must not clear state
                // a newer, still-running request owns. This also covers a
                // retry: it re-enters `generate`, which bumps `generation`
                // again before this task's own `defer` runs, so the check
                // below is already false and this cleanup is skipped in favor
                // of the retry's own state.
                if self.generation == myGeneration {
                    self.activeTask = nil
                    self.activeNoteID = nil
                    let noteNow = self.store.notes.first(where: { $0.id == noteID })
                    // A note that crossed the next threshold while this request
                    // was in flight shouldn't have to wait for another keystroke.
                    //
                    // Only re-enter if the request actually moved the note's
                    // stage. If it didn't, retrying immediately would produce
                    // the identical no-op and spin the model forever; a later
                    // keystroke re-arms it through the debounce instead.
                    if noteNow?.autoTitleStage != expectedStage {
                        self.evaluate(noteID: noteID)
                    } else if let noteNow, !noteNow.autoTitleLocked, noteNow.autoTitleStage < Self.thresholds.count {
                        // Otherwise the note still has a stage ahead of it —
                        // pay the next request's model load now, during
                        // typing, rather than when that request fires.
                        self.ensureWarmSession()
                    }
                }
            }

            do {
                let prompt = hasExistingAutoTitle
                    ? """
                      This note has grown. Its current title is "\(currentTitle)".
                      If that title is vague, generic, or no longer describes what the note is
                      about, reply with a better one. If it is already specific and accurate,
                      reply with it unchanged:

                      \(excerpt)
                      """
                    : "Suggest a title for this note:\n\n\(excerpt)"
                let options = useGreedySampling
                    ? GenerationOptions(sampling: .greedy)
                    : GenerationOptions(temperature: 0.3)
                let response = try await session.respond(
                    to: prompt,
                    generating: NoteTitleSuggestion.self,
                    options: options
                )
                guard !Task.isCancelled, self.generation == myGeneration else { return }
                if let title = Self.sanitize(response.content.title) {
                    if title.caseInsensitiveCompare(currentTitle) != .orderedSame {
                        self.store.applyAutoTitle(
                            title,
                            noteID: noteID,
                            expectedStage: expectedStage,
                            nextStage: nextStage
                        )
                    } else {
                        // The model chose to keep the current title (modulo
                        // case). Not a failure — the shimmer just ends with
                        // nothing to show, and no reveal plays for a change
                        // the user wouldn't perceive as one.
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
            } catch let error as LanguageModelSession.GenerationError {
                guard !Task.isCancelled, self.generation == myGeneration else { return }
                switch error {
                case .guardrailViolation, .exceededContextWindowSize:
                    // The guardrail is notoriously over-eager on ordinary
                    // personal text (health, relationships, money), and it
                    // keys off specific phrases — the first line or two is
                    // often clean. One retry on a shorter slice; if it's
                    // declined again, this note is hopeless at every later
                    // stage too, so give up on it outright.
                    if !isRetry {
                        self.generate(
                            noteID: noteID,
                            expectedStage: expectedStage,
                            nextStage: nextStage,
                            plainText: plainText,
                            currentTitle: currentTitle,
                            hasExistingAutoTitle: hasExistingAutoTitle,
                            isRetry: true,
                            excerptOverride: String(excerpt.prefix(240))
                        )
                    } else {
                        self.giveUp(noteID: noteID, expectedStage: expectedStage)
                    }
                case .unsupportedLanguageOrLocale:
                    // Will fail identically at every later stage too.
                    self.giveUp(
                        noteID: noteID,
                        expectedStage: expectedStage,
                        notification: .buoyAutoTitleUnsupportedLanguage
                    )
                case .rateLimited, .concurrentRequests, .assetsUnavailable:
                    // Transient — nothing about the note is at fault. Leave
                    // the stage unspent; the next keystroke re-arms through
                    // the debounce. Retrying immediately from here would
                    // likely just queue behind whatever is still occupying
                    // the on-device daemon (cancelling doesn't stop a
                    // `respond` that's already running — see `cancel`).
                    self.store.titleThinking = nil
                case .decodingFailure:
                    // Guided generation produced something the `@Generable`
                    // decoder couldn't parse. Retry once with greedy sampling
                    // rather than the same random draw that just failed.
                    if !isRetry {
                        self.generate(
                            noteID: noteID,
                            expectedStage: expectedStage,
                            nextStage: nextStage,
                            plainText: plainText,
                            currentTitle: currentTitle,
                            hasExistingAutoTitle: hasExistingAutoTitle,
                            isRetry: true,
                            excerptOverride: excerpt,
                            useGreedySampling: true
                        )
                    } else {
                        self.reportFailure(noteID: noteID, expectedStage: expectedStage, nextStage: nextStage)
                    }
                default:
                    // `unsupportedGuide`, `.refusal`, or any case added by a
                    // later SDK: behave as before this change — spend once.
                    self.reportFailure(noteID: noteID, expectedStage: expectedStage, nextStage: nextStage)
                }
            } catch {
                // Non-`GenerationError` failure: behave as before this change.
                if !Task.isCancelled, self.generation == myGeneration {
                    self.reportFailure(noteID: noteID, expectedStage: expectedStage, nextStage: nextStage)
                }
            }
        }
    }
    #endif

    /// Spends the stage for a request that produced no title, and tells the
    /// UI so the "thinking" shimmer doesn't just end in silence.
    ///
    /// Only posts when the stage was actually spent — a note the user has
    /// since titled by hand, or one that already moved on, is dropped by
    /// `NoteStore`'s guard and shouldn't surface a warning — and only for the
    /// note on screen and only at stage 0: at that point the note still shows
    /// "Note N" and the toast explains why, but a failed *refinement* is
    /// invisible (the note already has a title), so toasting there would just
    /// repeat information the user can already see for themselves. Wording is
    /// deliberately mild: the guardrail declines ordinary personal content
    /// often enough that this is routine, not an error.
    private func reportFailure(noteID: String, expectedStage: Int, nextStage: Int) {
        let didSpend = store.spendAutoTitleStage(
            noteID: noteID,
            expectedStage: expectedStage,
            nextStage: nextStage
        )
        guard didSpend, expectedStage == 0, store.currentNote?.id == noteID else { return }
        NotificationCenter.default.post(name: .buoyAutoTitleFailed, object: noteID)
    }

    /// Gives up on naming this note entirely — used when a failure mode will
    /// recur identically at every later stage (a repeated guardrail refusal,
    /// or a language the model doesn't handle), so retrying at 100 and 500
    /// characters would just be three failures instead of one.
    ///
    /// Spends straight to "finished" (`Self.thresholds.count`) — the same
    /// value normal completion and `v7_autoTitleRestage` both use — rather
    /// than locking the note: `autoTitleLocked` means "the user named this"
    /// and disables revert-on-empty, which should still work if the note's
    /// text is cleared back to empty later. Same stage-0-only toast rule as
    /// `reportFailure`.
    private func giveUp(noteID: String, expectedStage: Int, notification: Notification.Name = .buoyAutoTitleFailed) {
        let didSpend = store.spendAutoTitleStage(
            noteID: noteID,
            expectedStage: expectedStage,
            nextStage: Self.thresholds.count
        )
        guard didSpend, expectedStage == 0, store.currentNote?.id == noteID else { return }
        NotificationCenter.default.post(name: notification, object: noteID)
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static let instructions = """
        You name sticky notes. Given the note's text, reply with a short title: \
        one to three words, Title Case, no punctuation, no quotation marks, no \
        emoji. Describe what the note is about, not its first few words. Write \
        the title in the same language as the note. For a list, name the kind \
        of list (for example Grocery List or Packing List), not one of its \
        items.
        """
    #endif

    /// Belt-and-braces cleanup of the model's output. `@Guide` steers the
    /// model but doesn't enforce the shape of a `String` property, so this is
    /// the actual guarantee behind "3 words max".
    ///
    /// Trims at word boundaries rather than mid-phrase or mid-word: "Ideas
    /// for the Kitchen" -> "Ideas", "Notes on the Meeting" -> "Notes", "Plan
    /// for Q3 Launch" -> "Plan for Q3". A trailing connective word reads
    /// worse than the shorter title it was attached to, and cutting the 40
    /// character cap mid-word is worse still — so whole words come off the
    /// end instead of characters. A single "word" that's still over 40
    /// characters after that returns `nil` (routing to `reportFailure`)
    /// rather than a truncated fragment.
    private static func sanitize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        while let last = text.last, ".!?,:;".contains(last) {
            text.removeLast()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var words = Array(text.split(separator: " ", omittingEmptySubsequences: true).prefix(3))
        let trailingStopwords: Set<String> = [
            "a", "an", "the", "of", "for", "to", "and", "or", "in", "on",
            "with", "at", "by", "from", "vs", "about"
        ]
        while let last = words.last, trailingStopwords.contains(last.lowercased()) {
            words.removeLast()
        }
        while words.count > 1, words.joined(separator: " ").count > 40 {
            words.removeLast()
        }
        guard !words.isEmpty else { return nil }
        let title = words.joined(separator: " ")
        return title.count <= 40 ? title : nil
    }
}

extension Notification.Name {
    /// Posted by `NoteAutoTitler` when a request for the current note fails
    /// to produce a title. `object` is the note id. `ContentView` routes it to
    /// the lower-center toast as a warning.
    static let buoyAutoTitleFailed = Notification.Name("BuoyAutoTitleFailed")
    /// Posted instead of `buoyAutoTitleFailed` when auto-titling gives up on
    /// a note because the model doesn't handle its language. Separate name
    /// (rather than a payload on the existing one) because
    /// `BuoyNotificationRouter`'s routes are plain `() -> Void` closures with
    /// no access to the notification itself.
    static let buoyAutoTitleUnsupportedLanguage = Notification.Name("BuoyAutoTitleUnsupportedLanguage")
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
private struct NoteTitleSuggestion {
    @Guide(description: "A title of one to three words in Title Case, no punctuation, no quotes, never ending on a small connecting word")
    var title: String
}
#endif
