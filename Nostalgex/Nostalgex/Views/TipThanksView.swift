import SwiftUI

/// Presents the thank-you card from the top of the app, so an Ask to Buy approval that
/// lands while someone is in the guide still gets thanked. Its own container keeps this
/// cover apart from RootView's player cover.
struct TipThanksHost<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Bindable private var tipJar = TipJar.shared

    var body: some View {
        ZStack { content() }
            .fullScreenCover(isPresented: $tipJar.showThanks) {
                TipThanksView { tipJar.dismissThanks() }
            }
    }
}

/// Full-screen card shown once per tip. One button, focused from the start.
struct TipThanksView: View {
    let onDismiss: () -> Void

    @FocusState private var okFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.05, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Thank you")
                    .font(.custom("DMMono-Medium", size: 64))
                    .foregroundStyle(.white)

                Text("This keeps the channels on.")
                    .font(.custom("DMMono-Regular", size: 30))
                    .foregroundStyle(.white.opacity(0.75))

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.custom("DMMono-Medium", size: 26))
                        .foregroundStyle(okFocused ? .black : .white)
                        .frame(minWidth: 220)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(okFocused ? Color("BrandCyan") : .white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color("BrandCyan").opacity(okFocused ? 0 : 0.5), lineWidth: 1.5)
                        )
                        .scaleEffect(okFocused ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: okFocused)
                }
                .buttonStyle(.plain)
                .focused($okFocused)
                .padding(.top, 24)
                .accessibilityLabel("OK")
            }
            .padding(80)
        }
        .defaultFocus($okFocused, true)
        .onAppear { okFocused = true }
        .onExitCommand(perform: onDismiss)
    }
}
