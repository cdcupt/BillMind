import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showWelcome = false

    var body: some View {
        TabView(selection: $selectedTab) {
            JournalsListView()
                .tabItem {
                    Image(systemName: "book.closed.fill")
                    Text("Journals")
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
                UserDefaults.standard.set(true, forKey: Self.welcomeSeenKey)
                showWelcome = false
            }
        }
        .onAppear(perform: maybeShowWelcome)
    }

    static let welcomeSeenKey = "hasSeenFirstLaunchNotice"

    private func maybeShowWelcome() {
        #if DEBUG
        if CommandLine.arguments.contains("--uitesting-show-notice") {
            showWelcome = true
            return
        }
        #endif
        if !UserDefaults.standard.bool(forKey: Self.welcomeSeenKey) {
            showWelcome = true
        }
    }
}
