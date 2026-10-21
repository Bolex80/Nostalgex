import XCTest
import SwiftUI
@testable import Nostalgex

/// Contrast on the connect screens, measured the WCAG way (relative luminance ratio),
/// so a colour tweak can't quietly make typed text or password dots hard to read again.
/// AA asks 4.5:1 for normal text; typed text here is held to 7:1.
final class OnboardingContrastTests: XCTestCase {

    private func rgba(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// `top` painted over an opaque `bottom`.
    private func over(_ top: Color, _ bottom: Color) -> (r: Double, g: Double, b: Double) {
        let t = rgba(top), u = rgba(bottom)
        return (t.r * t.a + u.r * (1 - t.a), t.g * t.a + u.g * (1 - t.a), t.b * t.a + u.b * (1 - t.a))
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private func ratio(_ text: Color, on background: Color) -> Double {
        let bg = over(background, .black)
        let fg = over(text, Color(red: bg.r, green: bg.g, blue: bg.b))
        let (l1, l2) = (luminance(fg), luminance(bg))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testTypedTextAndPasswordDotsReadFocusedAndNot() {
        // Password dots are drawn in the same colour as typed text.
        XCTAssertGreaterThanOrEqual(ratio(OnboardingFieldPalette.focusedText, on: OnboardingFieldPalette.focusedWell), 7)
        XCTAssertGreaterThanOrEqual(ratio(OnboardingFieldPalette.unfocusedText, on: OnboardingFieldPalette.unfocusedWell), 7)
        XCTAssertGreaterThanOrEqual(ratio(OnboardingFieldPalette.caret, on: OnboardingFieldPalette.focusedWell), 7)
    }

    func testPlaceholdersAreReadable() {
        XCTAssertGreaterThanOrEqual(ratio(OnboardingFieldPalette.focusedPlaceholder, on: OnboardingFieldPalette.focusedWell), 4.5)
        XCTAssertGreaterThanOrEqual(ratio(OnboardingFieldPalette.unfocusedPlaceholder, on: OnboardingFieldPalette.unfocusedWell), 4.5)
    }

    /// The focused field's frame has to stand out from the page and from its own well.
    func testFocusedFrameStandsOut() {
        XCTAssertGreaterThanOrEqual(ratio(OnboardingPalette.cyan, on: .black), 3)
        XCTAssertGreaterThanOrEqual(ratio(OnboardingPalette.cyan, on: OnboardingFieldPalette.focusedWell), 3)
    }

    /// Dark text on the focused button slab.
    func testTextOnTheFocusedSlab() {
        XCTAssertGreaterThanOrEqual(ratio(OnboardingPalette.onFocus, on: OnboardingPalette.cyan), 7)
    }

    func testPrintRatios() {
        let rows: [(String, Double)] = [
            ("typed text, focused", ratio(OnboardingFieldPalette.focusedText, on: OnboardingFieldPalette.focusedWell)),
            ("typed text, unfocused", ratio(OnboardingFieldPalette.unfocusedText, on: OnboardingFieldPalette.unfocusedWell)),
            ("placeholder, focused", ratio(OnboardingFieldPalette.focusedPlaceholder, on: OnboardingFieldPalette.focusedWell)),
            ("placeholder, unfocused", ratio(OnboardingFieldPalette.unfocusedPlaceholder, on: OnboardingFieldPalette.unfocusedWell)),
            ("cyan frame on page", ratio(OnboardingPalette.cyan, on: .black)),
            ("text on focused slab", ratio(OnboardingPalette.onFocus, on: OnboardingPalette.cyan)),
        ]
        for (name, value) in rows { print(String(format: "[CONTRAST] %@: %.1f:1", name, value)) }
    }
}
