import SwiftUI

/// The focus look for the connect and sign-in screens, built to read from across a room.
///
/// The old look moved a thin outline from 55% to 100% and a fill from 8% to 16%, which on
/// a TV at couch distance is the same picture. Here the focused control is a solid cyan
/// slab with dark text that grows and glows, and every other control is an outline, so
/// there is only ever one bright thing on screen and it is where the remote is.
enum OnboardingRole {
    /// The thing most people want on this screen. Unfocused: cyan outline and text.
    case primary
    /// Other choices. Unfocused: thin grey outline, dimmer text.
    case secondary
    /// BACK, CANCEL, demo mode. Unfocused: plain grey text, no box.
    case quiet
}

enum OnboardingPalette {
    static let cyan = Color("BrandCyan")
    static let pink = Color("BrandPink")
    /// Text on the focused cyan slab.
    static let onFocus = Color(red: 0.0, green: 0.06, blue: 0.09)
    static let error = Color(hex: "#FF2244")
    static let warning = Color(hex: "#FFB020")
}

struct OnboardingButtonStyle: ButtonStyle {
    var role: OnboardingRole = .secondary
    var fullWidth = true
    var fontSize: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        OnboardingButtonBody(configuration: configuration, role: role, fullWidth: fullWidth, fontSize: fontSize)
    }
}

private struct OnboardingButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let role: OnboardingRole
    let fullWidth: Bool
    let fontSize: CGFloat?
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    private var size: CGFloat {
        if let fontSize { return fontSize }
        switch role {
        case .primary: return 34
        case .secondary: return 28
        case .quiet: return 24
        }
    }

    var body: some View {
        configuration.label
            .font(.custom("DMMono-Medium", size: size))
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, role == .quiet ? 28 : 36)
            .padding(.vertical, role == .quiet ? 12 : (role == .primary ? 24 : 20))
            .background {
                if role == .quiet {
                    Capsule(style: .continuous).fill(focused ? OnboardingPalette.cyan : Color.clear)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(focused ? OnboardingPalette.cyan : Color.white.opacity(0.03))
                }
            }
            .overlay {
                if !focused && role != .quiet {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(stroke, lineWidth: role == .primary ? 2.5 : 1.5)
                }
            }
            .shadow(color: OnboardingPalette.cyan.opacity(focused ? 0.6 : 0), radius: 28)
            .scaleEffect(configuration.isPressed ? 1.03 : (focused ? 1.07 : 1.0))
            .opacity(enabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.14), value: focused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var foreground: Color {
        if focused { return OnboardingPalette.onFocus }
        switch role {
        case .primary: return OnboardingPalette.cyan
        case .secondary: return .white.opacity(0.62)
        case .quiet: return .white.opacity(0.42)
        }
    }

    private var stroke: Color {
        switch role {
        case .primary: return OnboardingPalette.cyan.opacity(0.75)
        case .secondary: return .white.opacity(0.28)
        case .quiet: return .clear
        }
    }
}

/// A text field with the same focus language: focused is a bright cyan frame that grows
/// and glows over a lighter well, with its caption lit; unfocused is a dim well.
struct OnboardingField: View {
    let caption: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var submitLabel: SubmitLabel = .next
    let id: String
    var focus: FocusState<String?>.Binding
    var onSubmit: () -> Void = {}

    private var focused: Bool { focus.wrappedValue == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.custom("DMMono-Medium", size: 20))
                .tracking(2)
                .foregroundStyle(focused ? OnboardingPalette.cyan : .white.opacity(0.4))
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .textFieldStyle(.plain)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .focused(focus, equals: id)
            .font(.custom("DMMono-Regular", size: 28))
            // tvOS paints its own light pill inside a focused field; white text (and
            // password dots) on it all but vanished, so it turns dark while focused.
            .foregroundStyle(focused ? OnboardingPalette.onFocus : Color.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(focused ? 0.14 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? OnboardingPalette.cyan : Color.white.opacity(0.2), lineWidth: focused ? 4 : 1.5))
            .shadow(color: OnboardingPalette.cyan.opacity(focused ? 0.5 : 0), radius: 24)
            .scaleEffect(focused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.14), value: focused)
        }
    }
}
