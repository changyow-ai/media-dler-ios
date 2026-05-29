import UIKit
import UniformTypeIdentifiers
import MediaDlerCore

/// The share extension must never run yt-dlp — an App Extension's tight memory
/// budget (≈120 MB) can't host the Python runtime + download, and would be
/// jetsam-killed. It only extracts the shared URL and hands off to the main app
/// via the `mediadler://` URL scheme (no App Group needed, which matters under
/// free personal-team signing where App Groups aren't available).
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        extractURL { [weak self] urlString in
            if let urlString {
                self?.openMainApp(with: urlString)
            }
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func extractURL(_ completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            completion(nil)
            return
        }
        let group = DispatchGroup()
        var found: String?

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { obj, _ in
                    if found == nil, let url = obj as? URL { found = url.absoluteString }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { obj, _ in
                    if found == nil, let text = obj as? String { found = UrlExtractor.firstUrl(text) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(found) }
    }

    private func openMainApp(with urlString: String) {
        var components = URLComponents()
        components.scheme = "mediadler"
        components.host = "download"
        components.queryItems = [URLQueryItem(name: "url", value: urlString)]
        guard let deepLink = components.url else { return }

        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: deepLink)
                return
            }
            responder = r.next
        }
    }
}
