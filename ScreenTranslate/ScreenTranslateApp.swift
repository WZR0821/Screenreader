import SwiftUI

@main
struct ScreenTranslateApp: App {
    @StateObject private var store = SettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshRecent() }
                }
        }
    }
}

/// The two tabs, with the user's theme applied.
struct RootView: View {
    @ObservedObject var store: SettingsStore
    @State var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TranslationView(store: store)
                .tabItem { Label("翻译", systemImage: "character.bubble.fill") }.tag(0)
            SettingsView(store: store)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }.tag(1)
        }
        .environment(\.appTheme, AppTheme(settings: store.settings))
        .tint(AppTheme(settings: store.settings).accent)
        .preferredColorScheme(AppTheme(settings: store.settings).colorScheme)
    }
}
