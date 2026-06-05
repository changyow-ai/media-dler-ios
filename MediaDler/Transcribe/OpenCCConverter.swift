import Foundation
#if canImport(OpenCC)
import OpenCC
#endif

/// Simplified → Taiwan-traditional conversion (OpenCC `s2twp`: traditionalize +
/// Taiwan standard + idiom/phrase localisation). Phrase-level beats the
/// character-level conversion Android currently uses.
///
/// Guarded by `canImport(OpenCC)` so the app still builds before the
/// SwiftyOpenCC package is wired in (identity fallback); once the package is
/// present the real conversion activates with no other change.
enum OpenCCConverter {
    #if canImport(OpenCC)
    private static let converter: ChineseConverter? = {
        try? ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
    }()
    #endif

    static func s2twp(_ text: String) -> String {
        #if canImport(OpenCC)
        guard let converter else { return text }
        return converter.convert(text)
        #else
        return text
        #endif
    }
}
