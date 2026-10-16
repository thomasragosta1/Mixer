import SwiftUI
import FourTrackCore

@main
struct FourTrackApp: App {
    @State private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    private let store = ProjectsViewModel.makeStore()

    init() {
        Exporter.purgeOldExports()
        CloudSync.shared.configure(store: store, enabled: AppSettings.shared.iCloudSync)
    }

    var body: some Scene {
        WindowGroup {
            ProjectsListView(store: store, settings: settings)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: CloudSync.shared.appBecameActive()
            case .background: CloudSync.shared.appWillResignActive()
            default: break
            }
        }
    }
}
