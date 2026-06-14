import SwiftUI

struct SketchTheme {
    // MARK: - Colors

    // Voyage palette (token names kept so every view re-skins at once):
    // paper/ink/soft/card + pine·terra·sand·gate·blue accents.
    static let cream = Color(hex: "F7F4EE")        // paper — app background
    static let warmWhite = Color(hex: "FFFFFF")    // card surface
    static let softBrown = Color(hex: "1B201D")    // ink — primary text
    static let lightBrown = Color(hex: "6B675F")   // soft — muted text/hairline
    static let dustyRose = Color(hex: "C8643C")    // terra — primary accent
    static let sageGreen = Color(hex: "1F6F5C")    // pine — positive
    static let softBlue = Color(hex: "2D6CA8")     // blue
    static let warmOrange = Color(hex: "E9C46A")   // sand
    static let mutedRed = Color(hex: "B23A3A")     // gate — destructive
    static let mutedPurple = Color(hex: "A84E2C")  // deep terra (gradient pair)
    static let paperShadow = Color(hex: "E4DED2").opacity(0.5)  // rule

    // MARK: - Fonts

    static func titleFont(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func headlineFont(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func bodyFont(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func amountFont(_ size: CGFloat = 36) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func captionFont(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    // MARK: - Gradients

    static let primaryGradient = LinearGradient(
        colors: [dustyRose, mutedPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [cream, Color(hex: "EFEAE0")],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View Modifiers

struct SketchCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(SketchTheme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(SketchTheme.lightBrown.opacity(0.35), lineWidth: 1.5)
            )
            .shadow(color: SketchTheme.paperShadow, radius: 6, y: 3)
    }
}

struct PaperBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SketchTheme.cream.ignoresSafeArea())
    }
}

extension View {
    func sketchCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(SketchCardModifier(cornerRadius: cornerRadius))
    }

    func paperBackground() -> some View {
        modifier(PaperBackgroundModifier())
    }
}
