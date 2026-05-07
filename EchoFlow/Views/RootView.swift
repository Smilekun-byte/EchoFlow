import SwiftUI

struct RootView: View {
    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)

    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("录音", systemImage: "mic.fill")
                }

            HistoryView()
                .tabItem {
                    Label("历史", systemImage: "clock.fill")
                }

            FolderView()
                .tabItem {
                    Label("文件夹", systemImage: "folder.fill")
                }
        }
        .tint(accentBlue)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
