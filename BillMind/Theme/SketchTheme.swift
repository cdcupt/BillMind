import SwiftUI

struct SketchTheme {
    // MARK: - Colors

    static let cream = Color(hex: "FDF6EC")
    static let warmWhite = Color(hex: "FEFCF7")
    static let softBrown = Color(hex: "8B7355")
    static let lightBrown = Color(hex: "B8A080")
    static let dustyRose = Color(hex: "D4A0A0")
    static let sageGreen = Color(hex: "A8BFA0")
    static let softBlue = Color(hex: "9CB8C8")
    static let warmOrange = Color(hex: "E8B87A")
    static let mutedRed = Color(hex: "C27070")
    static let mutedPurple = Color(hex: "A88BBE")
    static let paperShadow = Color(hex: "D4C5A9").opacity(0.3)

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
        colors: [cream, Color(hex: "F5EDE0")],
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
