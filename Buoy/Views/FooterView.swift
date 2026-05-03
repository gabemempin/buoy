import SwiftUI

struct FooterView: View {
    var createdAt: Int64
    var updatedAt: Int64
    var plainText: String = ""
    var selectedText: String = ""
    var onShortcuts: () -> Void
    var onSettings: () -> Void
    var onTransferToAppleNotes: () -> Void
    var onCopy: () -> Void
    var isBugReport: Bool = false
    var onSendBugReport: (() -> Void)? = nil
    var onCancelBugReport: (() -> Void)? = nil

    private enum InfoMode: Int, CaseIterable {
        case lastEdited, created, characters, words
    }

    @State private var showTransfer = false
    @State private var infoMode: InfoMode = .lastEdited
    @State private var isCancelHovering = false

    private var infoLabel: String {
        switch infoMode {
        case .lastEdited:  return "Last edited: \(TimestampFormatter.format(updatedAt))"
        case .created:     return "Created: \(TimestampFormatter.format(createdAt))"
        case .characters:
            if selectedText.isEmpty {
                return "\(plainText.count) characters"
            } else {
                return "\(selectedText.count) of \(plainText.count) characters"
            }
        case .words:
            if selectedText.isEmpty {
                return "\(plainText.split(whereSeparator: \.isWhitespace).count) words"
            } else {
                return "\(selectedText.split(whereSeparator: \.isWhitespace).count) of \(plainText.split(whereSeparator: \.isWhitespace).count) words"
            }
        }
    }

    private var infoHelp: String {
        switch infoMode {
        case .lastEdited:  return "Tap to see creation time"
        case .created:     return "Tap to see character count"
        case .characters:  return "Tap to see word count"
        case .words:       return "Tap to see last edited time"
        }
    }

    @State private var isShortcutsHovering = false
    @State private var isSettingsHovering = false
    @State private var isSendHovering = false
    @State private var isMoreHovering = false
    @State private var isCopyHovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        let all = InfoMode.allCases
                        let next = (infoMode.rawValue + 1) % all.count
                        infoMode = all[next]
                    }
                } label: {
                    Text(infoLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(infoHelp)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .onChange(of: createdAt) { _, _ in infoMode = .lastEdited }

            if showTransfer && !isBugReport {
                HStack {
                    Spacer()
                    Button(action: onTransferToAppleNotes) {
                        Text("Transfer to Apple Notes")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .overlay(Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Send to Apple Notes")
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 6) {
                if isBugReport {
                    Button(action: { onCancelBugReport?() }) {
                        Text("Cancel Report")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Cancel bug report")
                    .buoyAccentCapsule(color: .red, isHovering: isCancelHovering)
                    .onHover { isCancelHovering = $0 }
                } else {
                    Button(action: onShortcuts) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12))
                            .foregroundStyle(isShortcutsHovering ? .white : .white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                            .buoyAccentCircle(isHovering: isShortcutsHovering)
                    }
                    .buttonStyle(.plain)
                    .help("Keyboard Shortcuts")
                    .onHover { isShortcutsHovering = $0 }

                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundStyle(isSettingsHovering ? .white : .white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                            .buoyAccentCircle(isHovering: isSettingsHovering)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .onHover { isSettingsHovering = $0 }
                }

                Spacer()

                if isBugReport {
                    Button(action: { onSendBugReport?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.right")
                                .font(.system(size: 11))
                            Text("Send Report")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Send bug report via browser")
                    .buoyAccentCapsule(color: .blue, isHovering: isSendHovering)
                    .onHover { isSendHovering = $0 }
                } else {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { showTransfer.toggle() }
                        } label: {
                            Image(systemName: showTransfer ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(isMoreHovering ? .white : .white.opacity(0.75))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                                .buoyAccentChevronHoverPlate(isHovering: isMoreHovering)
                        }
                        .buttonStyle(.plain)
                        .help("More actions")
                        .onHover { isMoreHovering = $0 }

                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1, height: 16)

                        Button(action: onCopy) {
                            HStack(spacing: 3) {
                                Text("Copy")
                                    .font(.system(size: 11, weight: .medium))
                                Text("⌘⏎")
                                    .font(.system(size: 10))
                                    .opacity(0.8)
                            }
                            .foregroundStyle(isCopyHovering ? .white : .white.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard (⌘Return)")
                        .onHover { isCopyHovering = $0 }
                    }
                    .buoyAccentCapsule(isHovering: isMoreHovering || isCopyHovering)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(WindowDragHandle())
        }
    }
}
