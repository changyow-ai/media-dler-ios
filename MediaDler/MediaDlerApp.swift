import SwiftUI

@main
struct MediaDlerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .onAppear { model.start() }
                .onOpenURL { model.handle(deepLink: $0) }
        }
    }
}
