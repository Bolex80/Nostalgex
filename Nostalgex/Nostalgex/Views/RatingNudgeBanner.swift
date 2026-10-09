import SwiftUI

/// The quiet "Enjoying Nostalgex?" banner at the bottom of the guide.
///
/// It never takes focus on its own: the guide keeps the live row focused, and the
/// viewer can move down to it. Untouched, AppState dismisses it after 8 seconds; once
/// the viewer focuses it, it stays until they choose. Whether it may appear at all is
/// `RatingNudgePolicy`'s call.
struct RatingNudgeBanner: View {
    @Environment(AppState.self) var appState
    @Environment(\.openURL) private var openURL
    @FocusState private var focused: Choice?

    private enum Choice: Hashable { case rate, notNow }

    var body: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enjoying Nostalgex?")
                    .font(.custom("DMMono-Medium", size: 22))
                    .foregroundStyle(.white)
                Text("A star rating helps other people find it.")
                    .font(.custom("DMMono-Regular", size: 20))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 24)

            HStack(spacing: 16) {
                choiceButton("RATE", choice: .rate) {
                    appState.ratingNudgeRateTapped()
                    openURL(AppStoreLink.productPage)
                }
                .accessibilityIdentifier("ratingNudgeRate")
                .accessibilityHint("Opens Nostalgex in the App Store to leave a star rating")

                choiceButton("NOT NOW", choice: .notNow) {
                    appState.dismissRatingNudge()
                }
                .accessibilityIdentifier("ratingNudgeNotNow")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .frame(maxWidth: 1240)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.12).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color("BrandCyan").opacity(focused == nil ? 0.25 : 0.5), lineWidth: 1.5)
        )
        .focusSection()
        .onChange(of: appState.ratingNudgeFocusRequested) { _, requested in
            guard requested else { return }
            focused = .rate
            appState.ratingNudgeFocusRequested = false
        }
        .onChange(of: focused) { _, newValue in
            // Touched: keep it up until the viewer chooses.
            if newValue != nil { appState.ratingNudgeDismissTask?.cancel() }
        }
        .onExitCommand { appState.dismissRatingNudge() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ratingNudgeBanner")
    }

    private func choiceButton(_ title: String, choice: Choice, action: @escaping () -> Void) -> some View {
        let isFocused = focused == choice
        return Button(action: action) {
            Text(title)
                .font(.custom("DMMono-Medium", size: 22))
                .foregroundStyle(isFocused ? .white : .white.opacity(0.6))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isFocused ? .white.opacity(0.07) : .white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? Color("BrandCyan").opacity(0.5) : .clear, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(NoHighlightButtonStyle())
        .focused($focused, equals: choice)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
