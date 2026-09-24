import AppKit
import Observation

/// An in-memory countdown that survives transitions out of Harbor Mode.
@Observable
final class HarborTimer {
    private(set) var noteID: String?
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var remainingSeconds = 0
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var pausedDuration: Duration = .zero
    @ObservationIgnored private var ticker: Timer?
    // Retain the sound for asynchronous playback, independently for each note.
    @ObservationIgnored private var completionSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "TimerComplete", withExtension: "aiff") else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }()

    var isFinished: Bool { isActive && remainingSeconds == 0 }

    var displayText: String {
        if isFinished { return "Time’s up" }
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Match the entire title, so ordinary titles mentioning a duration stay notes.
    static func duration(in title: String) -> TimeInterval? {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^([0-9]+(?:\.[0-9]+)?)\s*(secs?|mins?|hrs?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let amount = Double(text[numberRange]) else { return nil }
        let unit = text[unitRange].lowercased()
        let seconds = amount * (unit.hasPrefix("hr") ? 3600 : unit.hasPrefix("min") ? 60 : 1)
        // Bound arithmetic and keep the countdown readable within the pill.
        guard seconds.isFinite, seconds >= 1, seconds <= 359_999 else { return nil }
        return seconds
    }

    func start(title: String, noteID: String?) {
        guard !isActive else { return }
        stop()
        guard let seconds = Self.duration(in: title) else { return }
        self.noteID = noteID
        isActive = true
        remainingSeconds = Int(ceil(seconds))
        deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        startTicker()
    }

    func togglePause() {
        guard isActive, !isFinished else { return }
        if isPaused {
            deadline = ContinuousClock.now.advanced(by: pausedDuration)
            isPaused = false
            startTicker()
        } else {
            updateRemaining()
            guard !isFinished, let deadline else { return }
            pausedDuration = ContinuousClock.now.duration(to: deadline)
            self.deadline = nil
            isPaused = true
            ticker?.invalidate()
            ticker = nil
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        pausedDuration = .zero
        noteID = nil
        isActive = false
        isPaused = false
        remainingSeconds = 0
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateRemaining()
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateRemaining() {
        guard let deadline else { return }
        let components = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        remainingSeconds = max(0, Int(ceil(seconds)))
        if remainingSeconds == 0 {
            ticker?.invalidate()
            ticker = nil
            self.deadline = nil
            if completionSound?.play() != true {
                NSSound.beep()
            }
        }
    }

    deinit { ticker?.invalidate() }
}
