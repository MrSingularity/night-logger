import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        TabView {
            RecordingView()
                .tabItem {
                    Label("Record", systemImage: "moon.zzz.fill")
                }

            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
        }
        .accentColor(Color("AccentNight"))
    }
}
