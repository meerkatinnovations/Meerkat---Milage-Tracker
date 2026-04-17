import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct MeerkatMilageTrackerApp: App {
    @UIApplicationDelegateAdaptor(MeerkatAppDelegate.self) private var appDelegate

    init() {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    SharedAppModel.shared.handleIncomingURL(url)
                }
        }
    }
}
