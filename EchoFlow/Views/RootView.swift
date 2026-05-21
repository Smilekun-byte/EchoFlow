import SwiftUI

struct RootView: View {
    @AppStorage("appearanceMode")    private var appearanceMode    = "system"
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"

    private let accentBlue = Color(red: 0.231, green: 0.510, blue: 0.965)

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    // AppleLanguages 覆盖 en/ja（bundle 级别）；locale environment 覆盖 zh-Hans
    // （source language 没有独立 .lproj，必须通过 SwiftUI 环境注入才能切回中文）
    private var locale: Locale {
        interfaceLanguage == "system" ? .current : Locale(identifier: interfaceLanguage)
    }

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("录音", systemImage: "mic.fill") }

            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.fill") }

            ImageLiveTextViewer()
                .tabItem { Label("识图", systemImage: "photo.circle.fill") }

            FolderView()
                .tabItem { Label("文件夹", systemImage: "folder.fill") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
        }
        .tint(accentBlue)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(preferredScheme)
        .environment(\.locale, locale)
    }
}
