import SwiftUI

@main
struct MediaDlerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .onAppear { model.start() }
                .onOpenURL { url in
                    // Local file shared in via CFBundleDocumentTypes → transcribe
                    // path; mediadler:// deep-link → existing URL download path.
                    if url.isFileURL {
                        model.handle(localFile: url)
                    } else {
                        model.handle(deepLink: url)
                    }
                }
        }
    }
}
