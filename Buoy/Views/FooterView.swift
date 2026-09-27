import SwiftUI

struct FooterView: View {
    var createdAt: Int64
    var updatedAt: Int64
    var plainText: String = ""
    var selectedText: String = ""
    @Binding var isSettingsPresented: Bool
    @Binding var settings: AppSettings
    var onReportBug: () -> Void
    var onQuit: () -> Void
    var onTransferToAppleNotes: () -> Void
    var onCopy: () -> Void
    var isBugReport: Bool = false
    var onSendBugReport: (() -> Void)? = nil
    var onCancelBugReport: (() -> Void)? = nil
    /// The folder the note is filed in, shown at the left of the info row,
    /// above the gear. Clicking it opens All Notes.
    var folderName: String? = nil
    var onFolderClick: () -> Void = {}

    private enum InfoMode: Int, CaseIterable {
        case lastEdited, created, characters, words
    }

    @State private var showTransfer = false
    @State private var isCancelHovering = false

    /// The chosen readout sticks until the user clicks it again — including
    /// across note switches and relaunches. It used to snap back to "Last
    /// edited" whenever the note changed, so anyone who wanted a live word count
    /// had to re-select it every time they navigated.
    @AppStorage("buoy.footer.infoMode") private var storedInfoMode: Int = InfoMode.lastEdited.rawValue

    private var infoMode: InfoMode {
        InfoMode(rawValue: storedInfoMode) ?? .lastEdited
    }

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

    @State private var isSettingsHovering = false
    @State private var isSendHovering = false
    @State private var isMoreHovering = false
    @State private var isCopyHovering = false
    @Environment(\.chromeMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let folderName, !isBugReport {
                    Button(action: onFolderClick) {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 9, weight: .medium))
                            Text(folderName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(metrics.footerInfoFont)
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("In folder \(folderName). Click to show All Notes.")
                    .accessibilityLabel("In folder \(folderName)")
                    .accessibilityHint("Shows All Notes")
                    .pointingHandCursor()
                    .transition(.opacity)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(BuoyMotion.easeInOut(0.12)) {
                        let all = InfoMode.allCases
                        storedInfoMode = all[(infoMode.rawValue + 1) % all.count].rawValue
                    }
                } label: {
                    Text(infoLabel)
                        .font(metrics.footerInfoFont)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(infoHelp)
                .accessibilityLabel(infoLabel)
                .accessibilityHint(infoHelp)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, metrics.footerInfoBottomPadding)

            HStack(spacing: metrics.footerButtonSpacing) {
                if isBugReport {
                    Button(action: { onCancelBugReport?() }) {
                        Text("Cancel Report")
                            .font(metrics.footerActionFont)
                            .foregroundStyle(Color.buoyOnAccent)
                            .padding(.horizontal, metrics.footerBugButtonHorizontalPadding)
                            .padding(.vertical, metrics.footerBugButtonVerticalPadding)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Cancel bug report")
                    .accessibilityLabel("Cancel bug report")
                    .buoyAccentCapsule(color: .red, isHovering: isCancelHovering)
                    .onHover { isCancelHovering = $0 }
                } else {
                    // Shortcuts used to have a button of its own here. It is a
                    // page inside Settings now, and two gateways to the same
                    // window is one more than the footer has room for.
                    Button { isSettingsPresented.toggle() } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: metrics.footerButtonIconSize))
                            .foregroundStyle(Color.buoyOnAccent(isProminent: isSettingsHovering))
                            .frame(width: metrics.footerButtonSize, height: metrics.footerButtonSize)
                            .contentShape(Circle())
                            .buoyAccentCircle(isHovering: isSettingsHovering)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel("Settings")
                    .onHover { isSettingsHovering = $0 }
                    // Anchored to the gear, like the link editor and Transfer
                    // to Apple Notes. Settings was a separate window for a
                    // while and every behaviour it needed — pointing at its
                    // button, moving with the panel, closing on a click away —
                    // had to be built by hand. A popover has all of it.
                    // Opens to the side, not upward. The gear is at the foot
                    // of the panel and a popover above it covers the note the
                    // settings are being changed for — including the window
                    // colour, which is the one thing you need to see while
                    // picking it.
                    .popover(
                        isPresented: $isSettingsPresented,
                        attachmentAnchor: .rect(
                            .rect(
                                CGRect(
                                    x: -SettingsPopoverMetrics.anchorGap,
                                    y: 0,
                                    width: metrics.footerButtonSize + SettingsPopoverMetrics.anchorGap,
                                    height: metrics.footerButtonSize
                                )
                            )
                        ),
                        arrowEdge: .leading
                    ) {
                        SettingsPopover(
                            settings: $settings,
                            onReportBug: onReportBug,
                            onQuit: onQuit
                        )
                    }
                }

                Spacer()

                if isBugReport {
                    Button(action: { onSendBugReport?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.right")
                                .font(.system(size: metrics.footerButtonIconSize - 1))
                            Text("Send Report")
                                .font(metrics.footerActionFont)
                        }
                        .foregroundStyle(Color.buoyOnAccent)
                        .padding(.horizontal, metrics.footerBugButtonHorizontalPadding)
                        .padding(.vertical, metrics.footerBugButtonVerticalPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Send bug report via browser")
                    .accessibilityLabel("Send bug report")
                    .accessibilityHint("Opens the report in your browser")
                    .buoyAccentCapsule(isHovering: isSendHovering)
                    .onHover { isSendHovering = $0 }
                } else {
                    HStack(spacing: 0) {
                        Button {
                            showTransfer.toggle()
                        } label: {
                            Image(systemName: showTransfer ? "chevron.up" : "chevron.down")
                                .font(.system(size: metrics.footerChevronIconSize, weight: .semibold))
                                .foregroundStyle(Color.buoyOnAccent(isProminent: isMoreHovering))
                                .frame(width: metrics.footerButtonSize, height: metrics.footerButtonSize)
                                .contentShape(Rectangle())
                                .buoyAccentChevronHoverPlate(isHovering: isMoreHovering)
                        }
                        .buttonStyle(.plain)
                        .help("More actions")
                        .accessibilityLabel("More actions")
                        .accessibilityValue(showTransfer ? "Expanded" : "Collapsed")
                        .onHover { isMoreHovering = $0 }
                        // A popover rather than a row that unfolds above the
                        // bar: that row pushed the editor up every time it
                        // opened, so glancing at one extra action reflowed the
                        // note you were reading.
                        .popover(isPresented: $showTransfer, arrowEdge: .top) {
                            Button(action: {
                                showTransfer = false
                                onTransferToAppleNotes()
                            }) {
                                Label("Transfer to Apple Notes", systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .accessibilityLabel("Transfer to Apple Notes")
                        }

                        Rectangle()
                            .fill(Color.buoyOnAccentSeparator)
                            .frame(width: 1, height: metrics.footerCapsuleSeparatorHeight)
                            .accessibilityHidden(true)

                        Button(action: onCopy) {
                            HStack(spacing: 3) {
                                Text("Copy")
                                    .font(metrics.footerActionFont)
                                Text(ShortcutStrings.symbols(ShortcutRegistry.combo(for: .copyNote).electronString))
                                    .font(metrics.footerHintFont)
                                    .opacity(0.8)
                            }
                            .foregroundStyle(Color.buoyOnAccent(isProminent: isCopyHovering))
                            .padding(.horizontal, metrics.footerCopyHorizontalPadding)
                            .padding(.vertical, metrics.footerCopyVerticalPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard (\(ShortcutStrings.symbols(ShortcutRegistry.combo(for: .copyNote).electronString)))")
                        .accessibilityLabel("Copy note to clipboard")
                        .onHover { isCopyHovering = $0 }
                    }
                    .buoyAccentCapsule(isHovering: isMoreHovering || isCopyHovering)
                }
            }
            .padding(.horizontal, metrics.footerActionHorizontalPadding)
            .padding(.vertical, metrics.footerActionVerticalPadding)
            .background(WindowDragHandle())
        }
    }
}
