import SwiftUI

@main
struct ScreenTranslateApp: App {
    @StateObject private var store = SettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selection) {
                TranslationView(store: store)
                    .tabItem { Label("翻译", systemImage: "text.viewfinder") }.tag(0)
                SettingsView(store: store)
                    .tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(1)
            }
            .environment(\.appTheme, AppTheme(settings: store.settings))
            .tint(AppTheme(settings: store.settings).accent)
            .preferredColorScheme(AppTheme(settings: store.settings).colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.refreshRecent() }
            }
        }
    }
}
