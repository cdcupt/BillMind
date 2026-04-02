import SwiftUI

struct AnimalMascotView: View {
    let animal: AnimalType
    var size: CGFloat = 64
    var animated: Bool = false

    @State private var bounceOffset: CGFloat = 0

    var body: some View {
        Text(animal.emoji)
            .font(.system(size: size))
            .offset(y: bounceOffset)
            .onAppear {
                if animated {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        bounceOffset = -8
                    }
                }
            }
    }
}

struct EmptyStateView: View {
    let animal: AnimalType
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            AnimalMascotView(animal: animal, size: 72, animated: true)
            Text(title)
                .font(SketchTheme.headlineFont(22))
                .foregroundStyle(SketchTheme.softBrown)
            Text(subtitle)
                .font(SketchTheme.bodyFont(14))
                .foregroundStyle(SketchTheme.lightBrown)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

struct HandDrawnButton: View {
    let title: String
    var icon: String? = nil
    var style: ButtonStyle = .primary

    enum ButtonStyle {
        case primary, secondary
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Text(icon)
            }
            Text(title)
                .font(SketchTheme.headlineFont(18))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            switch style {
            case .primary:
                SketchTheme.primaryGradient
            case .secondary:
                Color.clear
            }
        }
        .foregroundStyle(style == .primary ? .white : SketchTheme.softBrown)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if style == .secondary {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(SketchTheme.lightBrown, lineWidth: 1.5)
            }
        }
        .shadow(
            color: style == .primary ? SketchTheme.dustyRose.opacity(0.3) : .clear,
            radius: style == .primary ? 6 : 0,
            y: style == .primary ? 3 : 0
        )
    }
}
