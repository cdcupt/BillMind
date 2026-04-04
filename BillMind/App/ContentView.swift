import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            JournalsListView()
                .tabItem {
                    Image(systemName: "book.closed.fill")
                    Text("Journals")
                }
                .tag(0)

            StatsPageView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Statistics")
                }
                .tag(1)

            MindsView()
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("Minds")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(3)
        }
        .tint(SketchTheme.dustyRose)
    }
}
