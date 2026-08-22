import SwiftUI

struct NotificationToast: View {
    let message: String
    let isError: Bool

    var body: some View {
        Text(message)
            .font(BuoyFont.secondaryEmphasized)
            .foregroundStyle(Color.buoyOnAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    // System red rather than a literal hex, so it tracks the
                    // appearance and Increase Contrast like every other alert.
                    .fill(isError ? Color(nsColor: .systemRed) : Color.accentColor)
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
        withAnimation(BuoyMotion.easeIn(0.15)) {
            isShowing = true
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(BuoyMotion.easeOut(0.3)) {
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
                        .transition(BuoyMotion.transition(.opacity.combined(with: .move(edge: .bottom))))
                        .padding(12)
                        // Spoken as soon as it appears; it is the only feedback
                        // for actions like Copy and Transfer.
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
    }
}
