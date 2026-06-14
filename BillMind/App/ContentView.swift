import SwiftUI
import AuthenticationServices
import CryptoKit

/// Launch gate: a brief splash while tokens resolve, the sign-in screen when
/// signed out, the main tabs when signed in.
struct ContentView: View {
    @EnvironmentObject private var auth: AuthSession

    static let welcomeSeenKey = "hasSeenFirstLaunchNotice"

    var body: some View {
        switch auth.state {
        case .loading:
            SplashView()
        case .signedOut:
            SignInView()
        case .signedIn:
            MainTabView()
        }
    }
}

// MARK: - Main tabs (signed in)

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showWelcome = false

    var body: some View {
        TabView(selection: $selectedTab) {
            JournalsListView()
                .tabItem {
                    Image(systemName: "book.closed.fill")
                    Text("Trips")
                }
                .tag(0)

            RecordView()
                .tabItem {
                    Image(systemName: "text.bubble.fill")
                    Text("Record")
                }
                .tag(1)

            StatsPageView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Statistics")
                }
                .tag(2)

            MindsView()
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("Minds")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(4)
        }
        .tint(SketchTheme.dustyRose)
        .sheet(isPresented: $showWelcome) {
            WelcomeNoticeView {
                UserDefaults.standard.set(true, forKey: ContentView.welcomeSeenKey)
                showWelcome = false
            }
        }
        .onAppear(perform: maybeShowWelcome)
    }

    private func maybeShowWelcome() {
        #if DEBUG
        if CommandLine.arguments.contains("--uitesting-show-notice") {
            showWelcome = true
            return
        }
        #endif
        if !UserDefaults.standard.bool(forKey: ContentView.welcomeSeenKey) {
            showWelcome = true
        }
    }
}

// MARK: - Splash

struct SplashView: View {
    var body: some View {
        ZStack {
            SketchTheme.cream.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("BillMind")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(SketchTheme.softBrown)
                ProgressView().tint(SketchTheme.dustyRose)
            }
        }
    }
}

// MARK: - Sign in

struct SignInView: View {
    @EnvironmentObject private var auth: AuthSession
    @State private var currentNonce: String?

    var body: some View {
        ZStack {
            SketchTheme.cream.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()

                Text("BillMind")
                    .font(.system(size: 46, weight: .bold, design: .serif))
                    .foregroundStyle(SketchTheme.softBrown)
                Text("Your travel-and-money agent")
                    .font(.title3)
                    .foregroundStyle(SketchTheme.softBrown.opacity(0.7))
                Text("Talk to record. Watch it add up.")
                    .font(.body.italic())
                    .foregroundStyle(SketchTheme.softBrown.opacity(0.55))
                    .multilineTextAlignment(.center)

                Spacer()

                SignInWithAppleButton(.signIn, onRequest: { request in
                    let nonce = Self.randomNonce()
                    currentNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(nonce)
                }, onCompletion: handleApple)
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 32)

                // Google sign-in on iOS needs the GoogleSignIn SDK + URL scheme;
                // wired in a later slice. The server already supports /v1/auth/google.
                Button {
                } label: {
                    Text("Continue with Google")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(SketchTheme.softBrown.opacity(0.4))
                .disabled(true)
                .padding(.horizontal, 32)

                if auth.isWorking {
                    ProgressView().tint(SketchTheme.dustyRose)
                }
                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Text("Never guess money.")
                    .font(.footnote.italic())
                    .foregroundStyle(SketchTheme.softBrown.opacity(0.4))
                    .padding(.bottom, 24)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        guard case let .success(authResults) = result,
              let credential = authResults.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            return  // user canceled or no token — stay on the gate
        }
        let nonce = currentNonce
        Task { await auth.signIn(provider: "apple", idToken: idToken, nonce: nonce) }
    }

    // Apple-recommended nonce: random raw value sent to the server, SHA-256 set
    // on the request so the ID token's nonce claim can be verified.
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            if Int(byte) < charset.count {
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
