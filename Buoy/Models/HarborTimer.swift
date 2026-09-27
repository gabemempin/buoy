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

    /// The whole title has to be a duration, so an ordinary title that merely
    /// mentions one ("Notes from the 5 min standup") stays a note.
    ///
    /// Accepts, case-insensitively and with an optional "timer" before or after:
    /// - a number and a unit, spelled any usual way: `5m`, `5 min`, `5 mins`,
    ///   `5 minutes`, `90s`, `2 hrs`, `1.5 hours`, `1,5 h`, `5-minute`
    /// - compounds in any order, each unit once: `1h30m`, `1 hr 30 min`,
    ///   `1 hour and 30 minutes`, `2m 30s`
    /// - a trailing bare number meaning the next smaller unit: `1h30`, `2m30`
    /// - words: `a minute`, `an hour`, `five minutes`, `forty-five seconds`,
    ///   `half an hour`, `a quarter hour`
    /// - clock form: `1:30` (minutes and seconds), `1:02:03` (hours too)
    static func duration(in title: String) -> TimeInterval? {
        var text = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".!".contains(last) { text.removeLast() }
        if text.hasPrefix("timer") {
            text = String(text.dropFirst("timer".count))
            if text.hasPrefix(":") { text.removeFirst() }
        } else if text.hasSuffix("timer") {
            text = String(text.dropLast("timer".count))
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty,
              let seconds = clockDuration(text) ?? unitDuration(text)
        else { return nil }
        // Bound arithmetic and keep the countdown readable within the pill.
        guard seconds.isFinite, seconds >= 1, seconds <= 359_999 else { return nil }
        return seconds
    }

    /// `m:ss` or `h:mm:ss`.
    private static func clockDuration(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              parts.dropFirst().allSatisfy({ $0.count == 2 }),
              parts[0].count <= 3
        else { return nil }
        let values = parts.compactMap { Double($0) }
        guard values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return values.reduce(0) { $0 * 60 + $1 }
    }

    private static let unitSeconds: [String: Double] = [
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600
    ]

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "ninety": 90
    ]

    /// One or more number-and-unit pairs.
    private static func unitDuration(_ text: String) -> TimeInterval? {
        var normalized = " " + text + " "
        for (phrase, replacement) in [
            ("half an hour", "30 min"), ("half a hour", "30 min"), ("half hour", "30 min"),
            ("half a minute", "30 sec"), ("half minute", "30 sec"),
            ("a quarter of an hour", "15 min"), ("quarter of an hour", "15 min"),
            ("a quarter hour", "15 min"), ("quarter hour", "15 min")
        ] {
            normalized = normalized.replacingOccurrences(of: phrase, with: replacement)
        }
        normalized = normalized
            .replacingOccurrences(of: " and ", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ", ", with: " ")

        // Split into runs of digits (with one decimal separator) and letters.
        var tokens: [String] = []
        var current = ""
        var currentIsNumber = false
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        for character in normalized {
            if character.isASCII && character.isNumber
                || ((character == "." || character == ",") && currentIsNumber) {
                if !currentIsNumber { flush() }
                currentIsNumber = true
                current.append(character)
            } else if character.isLetter {
                if currentIsNumber { flush() }
                currentIsNumber = false
                current.append(character)
            } else if character == " " {
                flush()
            } else {
                return nil
            }
        }
        flush()

        var components: [(amount: Double, unit: Double?)] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            var amount: Double
            if let first = token.first, first.isNumber {
                guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return nil }
                amount = value
            } else if let word = numberWords[token] {
                amount = word
                // "forty five" -> 45
                if word >= 20, word.truncatingRemainder(dividingBy: 10) == 0,
                   index + 1 < tokens.count, !["a", "an"].contains(tokens[index + 1]),
                   let ones = numberWords[tokens[index + 1]], ones < 10 {
                    amount += ones
                    index += 1
                }
            } else {
                return nil
            }
            index += 1

            var unit: Double?
            if index < tokens.count, let seconds = unitSeconds[tokens[index]] {
                unit = seconds
                index += 1
            }
            components.append((amount, unit))
        }
        guard !components.isEmpty else { return nil }

        var usedUnits = Set<Double>()
        var total: Double = 0
        for (position, component) in components.enumerated() {
            let unit: Double
            if let explicit = component.unit {
                unit = explicit
            } else {
                // Only a final bare number may omit its unit, and only after
                // one that has a smaller unit to fall to: "1h30", "2m30".
                guard position == components.count - 1, position > 0,
                      let previous = components[position - 1].unit, previous > 1
                else { return nil }
                unit = previous / 60
            }
            guard usedUnits.insert(unit).inserted else { return nil }
            total += component.amount * unit
        }
        return total
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
        // Ticks every 0.2s for a prompt finish, but only publishes when the
        // visible second actually changes; every assignment re-renders the pill.
        let next = max(0, Int(ceil(seconds)))
        guard next != remainingSeconds else { return }
        remainingSeconds = next
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
