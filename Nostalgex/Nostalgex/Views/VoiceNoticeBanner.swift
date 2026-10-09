import SwiftUI

/// Non-blocking banner for Siri requests that could not be carried out as asked
/// ("No channel 12 in your lineup", "Still loading your channels"). Never takes focus.
struct VoiceNoticeBanner: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack {
            if let notice = appState.voiceNotice {
                Text(notice)
                    .font(.custom("DMMono-Medium", size: 30))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.82))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.25), lineWidth: 2)
                    )
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: appState.voiceNotice)
        .allowsHitTesting(false)
        .focusable(false)
        .accessibilityHidden(appState.voiceNotice == nil)
    }
}
