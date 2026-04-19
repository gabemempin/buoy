import SwiftUI

struct ShortcutKeyCapsView: View {
    let shortcut: String
    var triggerPress: Bool = false
    var keySize: CGFloat = 50
    var spacing: CGFloat = 8
    var fontSize: CGFloat = 15

    @State private var pressedIndex: Int? = nil
    @State private var hasPressed = false
    @State private var keyPressTask: Task<Void, Never>?

    private var parts: [String] {
        shortcut.components(separatedBy: "+").map { part in
            switch part {
            case "Option": return "⌥"
            case "Cmd":    return "⌘"
            case "Ctrl":   return "⌃"
            case "Shift":  return "⇧"
            default:       return part.uppercased()
            }
        }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, label in
                ShortcutKeyCapView(
                    label: label,
                    isPressed: pressedIndex == index,
                    size: keySize,
                    fontSize: fontSize
                )
            }
        }
        .onChange(of: triggerPress) { _, newValue in
            guard newValue, !hasPressed else { return }
            hasPressed = true
            keyPressTask?.cancel()
            let count = parts.count
            keyPressTask = Task { @MainActor in
                await withTaskGroup(of: Void.self) { group in
                    for index in 0..<count {
                        group.addTask { @MainActor in
                            do {
                                try await Task.sleep(for: .milliseconds(index * 60))
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                    pressedIndex = index
                                }
                                try await Task.sleep(for: .milliseconds(120))
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    if pressedIndex == index { pressedIndex = nil }
                                }
                            } catch {}
                        }
                    }
                }
            }
        }
        .onDisappear {
            keyPressTask?.cancel()
            keyPressTask = nil
        }
    }
}

private struct ShortcutKeyCapView: View {
    let label: String
    var isPressed: Bool = false
    var size: CGFloat = 50
    var fontSize: CGFloat = 15

    @Environment(\.colorScheme) private var colorScheme

    private var cornerRadius: CGFloat {
        max(7, size * 0.18)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(.sRGB, red: 0.26, green: 0.26, blue: 0.30, opacity: 1),
                                Color(.sRGB, red: 0.14, green: 0.14, blue: 0.17, opacity: 1)
                            ]
                            : [Color.white, Color(.sRGB, white: 0.91, opacity: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.65 : 0.22), radius: 0, x: 0, y: max(2, size * 0.06))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: max(4, size * 0.12), x: 0, y: max(3, size * 0.08))

            RoundedRectangle(cornerRadius: max(6, cornerRadius - 1))
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.14 : 0.80), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(max(1, size * 0.03))

            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.10),
                    lineWidth: 1
                )

            Text(label)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color(.sRGB, white: 0.18, opacity: 1))
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.92 : 1.0, anchor: .center)
        .offset(y: isPressed ? 1 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
    }
}

struct ShimmeringShortcutPromptView: View {
    let text: String
    var fontSize: CGFloat = 13
    var minHeight: CGFloat = 50

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            frame(phase: Self.phase(for: timeline.date))
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    private static func phase(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0) / 2.0)
    }

    private func frame(phase: CGFloat) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .overlay {
                Text(text)
                    .font(.system(size: fontSize, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .mask {
                        GeometryReader { geo in
                            Ellipse()
                                .fill(Color.white)
                                .frame(width: 96, height: geo.size.height + 16)
                                .blur(radius: 14)
                                .offset(x: phase * (geo.size.width + 176) - 88)
                        }
                    }
            }
            .foregroundStyle(Color.primary.opacity(0.4))
    }
}
