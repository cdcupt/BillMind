import SwiftUI

struct WobblyRoundedRectangle: Shape {
    var cornerRadius: CGFloat = 16
    var wobbleAmount: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        // Seeded randomness based on rect dimensions for consistency
        let seed = Int(rect.width * 100 + rect.height * 37) % 1000
        var offsets: [CGFloat] = []
        var s = seed
        for _ in 0..<20 {
            s = (s &* 1103515245 &+ 12345) % (1 << 16)
            let normalized = CGFloat(s % 1000) / 500.0 - 1.0
            offsets.append(normalized * wobbleAmount)
        }

        var path = Path()
        let cr = min(cornerRadius, min(rect.width, rect.height) / 2)

        // Top-left corner
        path.move(to: CGPoint(x: rect.minX + cr + offsets[0], y: rect.minY + offsets[1]))

        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX - cr + offsets[2], y: rect.minY + offsets[3]))

        // Top-right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + offsets[4], y: rect.minY + cr + offsets[5]),
            control: CGPoint(x: rect.maxX + offsets[4] * 0.5, y: rect.minY + offsets[5] * 0.5)
        )

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX + offsets[6], y: rect.maxY - cr + offsets[7]))

        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cr + offsets[8], y: rect.maxY + offsets[9]),
            control: CGPoint(x: rect.maxX + offsets[8] * 0.5, y: rect.maxY + offsets[9] * 0.5)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + cr + offsets[10], y: rect.maxY + offsets[11]))

        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + offsets[12], y: rect.maxY - cr + offsets[13]),
            control: CGPoint(x: rect.minX + offsets[12] * 0.5, y: rect.maxY + offsets[13] * 0.5)
        )

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX + offsets[14], y: rect.minY + cr + offsets[15]))

        // Top-left corner close
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cr + offsets[0], y: rect.minY + offsets[1]),
            control: CGPoint(x: rect.minX + offsets[14] * 0.5, y: rect.minY + offsets[1] * 0.5)
        )

        path.closeSubpath()
        return path
    }
}
