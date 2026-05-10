import SwiftUI

struct RootView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("录音", systemImage: "mic.fill") }

            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.fill") }

            FolderView()
                .tabItem { Label("文件夹", systemImage: "folder.fill") }

            OCRView()
                .tabItem { Label("扫描", systemImage: "camera.viewfinder") }

            LiveTextView()
                .tabItem { Label("识图", systemImage: "text.viewfinder") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
        }
        .tint(accentBlue)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(preferredScheme)
    }
}
