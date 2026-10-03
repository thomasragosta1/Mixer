import SwiftUI
import FourTrackCore

@main
struct FourTrackApp: App {
    @State private var settings = AppSettings.shared
    private let store = ProjectsViewModel.makeStore()

    init() {
        Exporter.purgeOldExports()
    }

    var body: some Scene {
        WindowGroup {
            ProjectsListView(store: store, settings: settings)
        }
    }
}
