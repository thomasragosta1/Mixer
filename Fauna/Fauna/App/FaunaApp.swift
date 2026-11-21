import Combine
import SwiftUI

@main
struct FaunaApp: App {
    @State private var store: AppStore

    init() {
        // `-FaunaDemo` launches with sample history (used for App Store screenshots);
        // `-FaunaOnboarding` starts fresh without touching saved progress.
        let args = ProcessInfo.processInfo.arguments
        let store: AppStore
        if args.contains("-FaunaDemo") {
            store = AppStore.demo()
            if let i = args.firstIndex(of: "-FaunaTab"), i + 1 < args.count {
                switch args[i + 1] {
                case "journal": store.selectedTab = .journal
                case "focus": store.selectedTab = .focus
                default: break
                }
            }
        } else if args.contains("-FaunaOnboarding") {
            store = AppStore(fileURL: nil)
        } else {
            store = AppStore()
        }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(.accentColor)
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if store.state.hasOnboarded {
                MainTabs()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.6), value: store.state.hasOnboarded)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.refreshDay()
            Task { await Reminders.reschedule(store) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            store.refreshDay()
        }
    }
}

struct MainTabs: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.horizon.fill") }
                .tag(AppStore.Tab.today)
            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
                .tag(AppStore.Tab.journal)
            FocusView()
                .tabItem { Label("Focus", systemImage: "scope") }
                .tag(AppStore.Tab.focus)
        }
    }
}

#Preview("Today") {
    MainTabs()
        .environment(AppStore.demo())
        .tint(.accentColor)
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(AppStore(fileURL: nil))
}
