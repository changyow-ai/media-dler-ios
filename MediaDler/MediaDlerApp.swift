import SwiftUI

@main
struct MediaDlerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .onAppear {
                    model.start()
                    // TEMP diagnostic hook: headless launches can't trigger
                    // onOpenURL, so accept a URL via the environment instead.
                    // Remove once the extract investigation is done.
                    if let u = ProcessInfo.processInfo.environment["MDLER_TEST_URL"], !u.isEmpty {
                        model.handle(text: u)
                    }
                }
                .onOpenURL { model.handle(deepLink: $0) }
        }
    }
}
