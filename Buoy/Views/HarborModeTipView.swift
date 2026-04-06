import SwiftUI

struct HarborModeTipView: View {
    let noteTitle: String
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Try Harbor Mode")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Press ⌘M")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            MinimizedNotePillView(title: noteTitle, theme: theme, onRestore: {})
                .frame(height: PanelLayoutMetrics.minimizedPillHeight)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
                )
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .buoyGlassPanel(cornerRadius: 14)
    }
}
