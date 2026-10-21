import SwiftUI
import UIKit

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
    /// Focused as a cyan outline and glow over a dark button instead of the solid slab.
    /// For a screen whose main thing is not a button (a sign-in code), so the focused
    /// button stays plain to find but never outshines what the viewer is reading.
    var quietFocus = false

    func makeBody(configuration: Configuration) -> some View {
        OnboardingButtonBody(configuration: configuration, role: role, fullWidth: fullWidth,
                             fontSize: fontSize, quietFocus: quietFocus)
    }
}

private struct OnboardingButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let role: OnboardingRole
    let fullWidth: Bool
    let fontSize: CGFloat?
    let quietFocus: Bool
    @Environment(\.isFocused) private var focused

    /// The solid slab: focused, and not asked to stay quiet.
    private var slab: Bool { focused && !quietFocus }
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
                    Capsule(style: .continuous).fill(slab ? OnboardingPalette.cyan : Color.clear)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(slab ? OnboardingPalette.cyan : Color.white.opacity(focused ? 0.07 : 0.03))
                }
            }
            .overlay {
                if focused && quietFocus {
                    if role == .quiet {
                        Capsule(style: .continuous).strokeBorder(OnboardingPalette.cyan, lineWidth: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OnboardingPalette.cyan, lineWidth: 3)
                    }
                } else if !focused && role != .quiet {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(stroke, lineWidth: role == .primary ? 2.5 : 1.5)
                }
            }
            .shadow(color: OnboardingPalette.cyan.opacity(focused ? (quietFocus ? 0.45 : 0.6) : 0),
                    radius: quietFocus ? 18 : 28)
            .scaleEffect(configuration.isPressed ? 1.03 : (focused ? (quietFocus ? 1.04 : 1.07) : 1.0))
            .opacity(enabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.14), value: focused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var foreground: Color {
        if slab { return OnboardingPalette.onFocus }
        if focused { return .white }
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

/// Colours for the onboarding text fields, in one place so every field (address,
/// username, password) reads the same and the contrast test can check them.
enum OnboardingFieldPalette {
    /// Focused well: near-black with a cyan tint, under a cyan frame and glow.
    static let focusedWell = Color(red: 0.03, green: 0.10, blue: 0.13)
    /// Unfocused well: barely off the black page.
    static let unfocusedWell = Color(red: 0.06, green: 0.06, blue: 0.06)
    static let focusedText = Color.white
    static let unfocusedText = Color.white.opacity(0.78)
    static let focusedPlaceholder = Color.white.opacity(0.6)
    static let unfocusedPlaceholder = Color.white.opacity(0.48)
    static let unfocusedBorder = Color.white.opacity(0.18)
    static let caret = Color.white.opacity(0.9)
}

/// A text field in the buttons' focus language, drawn by us.
///
/// A SwiftUI TextField on tvOS always draws the system's own platter inside it: a white
/// pill when focused (white text and password dots all but vanished on it) and a grey
/// one when not, and neither `.plain` nor `focusEffectDisabled()` turns it off. So the
/// real field still takes focus, opens the keyboard and holds the text, but sits under
/// an opaque drawing of the field made from the same text and focus state.
///
/// Focused: a dark well, cyan frame and glow, white text and a light caret.
/// Unfocused: a dim well with a thin grey edge and softer text.
struct OnboardingField: View {
    let caption: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    /// The keyboard's return key: `.next` moves on, `.go` submits.
    var submitLabel: SubmitLabel = .next
    var contentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default
    let id: String
    var focus: FocusState<String?>.Binding
    /// Done on the keyboard. Closing it any way also posts UITextField's end-editing.
    var onSubmit: () -> Void = {}

    private var focused: Bool { focus.wrappedValue == id }

    private var shown: String { secure ? String(repeating: "\u{2022}", count: text.count) : text }

    private var caret: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(OnboardingFieldPalette.caret)
            .frame(width: 3, height: 34)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.custom("DMMono-Medium", size: 20))
                .tracking(2)
                .foregroundStyle(focused ? OnboardingPalette.cyan : .white.opacity(0.45))
            ZStack(alignment: .leading) {
                // The real field: focus, keyboard, text. Its own text is clear and it sits,
                // shrunk, under the opaque drawing below, so its platter never shows.
                Group {
                    if secure {
                        SecureField(caption, text: $text)
                    } else {
                        TextField(caption, text: $text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .textFieldStyle(.plain)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .foregroundStyle(Color.clear)
                .tint(Color.clear)
                .focused(focus, equals: id)
                .frame(maxWidth: .infinity)
                // tvOS lifts a focused field past its own frame, and clipping doesn't hold
                // the lift; drawn at 60% the lifted platter stays well inside the drawing.
                .scaleEffect(0.6)
                .frame(maxWidth: .infinity, minHeight: 78)

                // What the viewer sees, opaque, on top. Presses still go to the focused
                // field underneath; this only draws.
                HStack(spacing: 4) {
                    if text.isEmpty {
                        if focused { caret }
                        Text(placeholder)
                            .foregroundStyle(focused ? OnboardingFieldPalette.focusedPlaceholder : OnboardingFieldPalette.unfocusedPlaceholder)
                    } else {
                        Text(shown)
                            .foregroundStyle(focused ? OnboardingFieldPalette.focusedText : OnboardingFieldPalette.unfocusedText)
                            .tracking(secure ? 4 : 0)
                        if focused { caret }
                    }
                    Spacer(minLength: 0)
                }
                .font(.custom("DMMono-Regular", size: 28))
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(focused ? OnboardingFieldPalette.focusedWell : OnboardingFieldPalette.unfocusedWell))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? OnboardingPalette.cyan : OnboardingFieldPalette.unfocusedBorder,
                                  lineWidth: focused ? 4 : 1.5))
                .shadow(color: OnboardingPalette.cyan.opacity(focused ? 0.55 : 0), radius: 26)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .scaleEffect(focused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.14), value: focused)
        }
    }
}
