import SwiftUI
import AppKit

struct TrafficLightsView: View {
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onExpand: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            TrafficButton(
                color: Color(hex: "#FF5F57"),
                icon: isHovering ? "xmark" : nil,
                action: onClose
            )
            TrafficButton(
                color: Color(hex: "#FEBC2E"),
                icon: isHovering ? "minus" : nil,
                action: onMinimize
            )
            TrafficButton(
                color: Color(hex: "#28C840"),
                icon: isHovering ? "arrow.up.left.and.arrow.down.right" : nil,
                action: onExpand
            )
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

private struct TrafficButton: View {
    let color: Color
    let icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.black.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .contentShape(Circle())
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int & 0xFF0000) >> 16) / 255
        let g = Double((int & 0x00FF00) >> 8) / 255
        let b = Double(int & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
