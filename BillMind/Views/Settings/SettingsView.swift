import SwiftUI
import SwiftData

/// Settings for the 2.0 server app. The AI (capture, recognition, Minds) all runs
/// server-side with the app's own key, so there's no provider/API-key/currency
/// configuration on the client — just Privacy, Account, and About.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthSession
    @State private var showDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var accountError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Privacy
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Privacy")
                        settingsCard {
                            Link(destination: URL(string: "https://cdcupt.github.io/BillMind/docs/privacy-policy.html")!) {
                                settingsRow("Privacy Policy") {
                                    Image(systemName: "lock.shield")
                                        .foregroundStyle(SketchTheme.dustyRose)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Text("BillOwl reads your bills with AI on its secure server. Receipts and text you capture are sent there for recognition, and your ledger is saved to your account. See the policy for details.")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SketchTheme.lightBrown)
                            .padding(.horizontal, 4)
                    }

                    // Account
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Account")
                        settingsCard {
                            Button { Task { await auth.signOut() } } label: {
                                settingsRow("Sign Out") {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .foregroundStyle(SketchTheme.softBrown)
                                }
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(SketchTheme.lightBrown.opacity(0.2))
                                .frame(height: 1)
                                .padding(.horizontal, 12)

                            Button(role: .destructive) { showDeleteAccount = true } label: {
                                settingsRow("Delete Account") {
                                    if isDeletingAccount {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "trash")
                                            .foregroundStyle(SketchTheme.mutedRed)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isDeletingAccount)
                            .accessibilityIdentifier("delete-account")
                        }
                        Text(accountError
                            ?? "Deleting your account permanently removes your trips and bills from BillOwl's servers and this device.")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(accountError == nil ? SketchTheme.lightBrown : SketchTheme.mutedRed)
                            .padding(.horizontal, 4)
                    }
                    .confirmationDialog("Delete your account?", isPresented: $showDeleteAccount, titleVisibility: .visible) {
                        Button("Delete Account", role: .destructive) { Task { await performDeleteAccount() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently deletes your account and all trips and bills — on BillOwl's servers and on this device. This can't be undone.")
                    }

                    // About
                    VStack(spacing: 4) {
                        Text("BillOwl v1.0.0")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        Text("Smart bills, wise owl")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SketchTheme.lightBrown.opacity(0.7))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .padding()
            }
            .paperBackground()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Settings")
                            .font(SketchTheme.headlineFont(20))
                            .foregroundStyle(SketchTheme.softBrown)
                        Image("mascot_owl")
                            .resizable().scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(SketchTheme.headlineFont(18))
            .foregroundStyle(SketchTheme.lightBrown)
    }

    /// Delete the account on the server, then wipe the local cache + cursor.
    /// On success AuthSession drops to the sign-in gate.
    private func performDeleteAccount() async {
        isDeletingAccount = true
        accountError = nil
        defer { isDeletingAccount = false }
        guard await auth.deleteAccount() else {
            accountError = auth.errorMessage ?? "Couldn't delete your account. Try again."
            return
        }
        // Server account is gone — discard the disposable local cache too.
        try? modelContext.delete(model: BillRecord.self)
        try? modelContext.delete(model: Journal.self)
        try? modelContext.save()
        SyncCursor.reset()
    }

    @ViewBuilder
    private func settingsCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SketchTheme.lightBrown.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: SketchTheme.paperShadow, radius: 4, y: 2)
    }

    @ViewBuilder
    private func settingsRow<Content: View>(_ label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(SketchTheme.bodyFont(15))
                .foregroundStyle(SketchTheme.softBrown)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - AI Data Sharing Consent
//
// Still used by the legacy photo-import flow (BillImportFlowView). The primary
// 2.0 capture path (Record) runs entirely server-side and does not gate on this.

struct AIDataConsentView: View {
    let provider: AIProvider
    var onConsent: () -> Void
    var onDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AnimalMascotView(animal: .owl, size: 72)

                    Text("AI Data Sharing")
                        .font(SketchTheme.headlineFont(22))
                        .foregroundStyle(SketchTheme.softBrown)

                    Text("BillOwl uses AI to recognize bills from photos and generate timeline images. Before using these features, please review what data is shared.")
                        .font(SketchTheme.bodyFont(15))
                        .foregroundStyle(SketchTheme.lightBrown)
                        .multilineTextAlignment(.center)

                    consentSection(
                        icon: "doc.text.image",
                        title: "What data is sent",
                        items: [
                            "Photos of receipts and invoices you select",
                            "Bill details (merchant names, dates, amounts, categories) for timeline generation",
                        ]
                    )

                    consentSection(
                        icon: "server.rack",
                        title: "Who receives the data",
                        items: [
                            "BillOwl's secure server, which calls the AI provider on your behalf",
                            "Data is sent over an encrypted connection",
                        ]
                    )

                    consentSection(
                        icon: "shield.lefthalf.filled",
                        title: "How your data is protected",
                        items: [
                            "Your financial data is tied to your account",
                            "You can revoke consent anytime in Settings",
                            "You can use the app without AI (manual bill entry)",
                        ]
                    )

                    Link(destination: URL(string: "https://cdcupt.github.io/BillMind/docs/privacy-policy.html")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                            Text("Read Full Privacy Policy")
                                .font(SketchTheme.bodyFont(14))
                        }
                        .foregroundStyle(SketchTheme.dustyRose)
                    }

                    Button {
                        onConsent()
                        dismiss()
                    } label: {
                        Text("I Agree — Enable AI Features")
                            .font(SketchTheme.headlineFont(18))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SketchTheme.primaryGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: SketchTheme.dustyRose.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .font(SketchTheme.bodyFont(15))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDecline()
                        dismiss()
                    }
                    .foregroundStyle(SketchTheme.dustyRose)
                }
            }
        }
    }

    @ViewBuilder
    private func consentSection(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(SketchTheme.dustyRose)
                Text(title)
                    .font(SketchTheme.headlineFont(16))
                    .foregroundStyle(SketchTheme.softBrown)
            }

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(SketchTheme.lightBrown)
                    Text(item)
                        .font(SketchTheme.bodyFont(14))
                        .foregroundStyle(SketchTheme.softBrown)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sketchCard()
    }
}
