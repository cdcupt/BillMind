import SwiftUI

/// One-time, informational first-launch notice. Local-first reassurance + a link
/// to the privacy policy. Gates nothing (AI keeps its own separate consent); the
/// "seen" flag lives in UserDefaults, so no SwiftData schema change.
struct WelcomeNoticeView: View {
    let onContinue: () -> Void

    private let privacyURL = URL(string: "https://cdcupt.github.io/BillMind/docs/privacy-policy.html")!

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(SketchTheme.lightBrown.opacity(0.5)).frame(width: 40, height: 4).padding(.top, 8)

            Image(AnimalType.cat.imageName)
                .resizable().scaledToFill().frame(width: 56, height: 56).clipShape(Circle())

            Text("Welcome to BillMind")
                .font(SketchTheme.titleFont(24)).foregroundStyle(SketchTheme.softBrown)
                .accessibilityIdentifier("welcome-title")

            VStack(alignment: .leading, spacing: 12) {
                point("🔒", "Your journals and bills stay on this device. No servers, no account.")
                point("✨", "AI recognition sends a photo to your chosen provider — only after you agree, the first time.")
                point("🗂", "Delete a journal anytime — it removes its bills too.")
            }
            .padding(.horizontal, 4)

            Link("Read the Privacy Policy", destination: privacyURL)
                .font(SketchTheme.captionFont(13)).foregroundStyle(SketchTheme.softBlue)

            Spacer(minLength: 4)

            Button(action: onContinue) {
                Text("Get started")
                    .font(SketchTheme.headlineFont(18)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(SketchTheme.dustyRose)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome-get-started")
        }
        .padding(20)
        .paperBackground()
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon).font(.system(size: 16))
            Text(text).font(SketchTheme.bodyFont(13)).foregroundStyle(SketchTheme.softBrown)
            Spacer(minLength: 0)
        }
    }
}
