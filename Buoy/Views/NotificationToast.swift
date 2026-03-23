import SwiftUI

struct NotificationToast: View {
    let message: String
    let isError: Bool

    var body: some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isError ? Color(hex: "#FF3B30") : Color.accentColor)
            )
            .shadow(radius: 4)
    }
}

// MARK: - Toast State

@Observable
final class ToastState {
    var message: String = ""
    var isError: Bool = false
    var isShowing: Bool = false

    private var hideTask: Task<Void, Never>?

    func show(_ message: String, isError: Bool = false) {
        hideTask?.cancel()
        self.message = message
        self.isError = isError
        withAnimation(.easeIn(duration: 0.15)) {
            isShowing = true
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) {
                isShowing = false
            }
        }
    }
}

// MARK: - Toast Container

struct ToastContainer: View {
    @State var state: ToastState

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if state.isShowing {
                    NotificationToast(message: state.message, isError: state.isError)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(12)
                }
            }
        }
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
