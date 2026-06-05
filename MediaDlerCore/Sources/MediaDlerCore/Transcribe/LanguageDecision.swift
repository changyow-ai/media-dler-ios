import Foundation

/// Decides whether to run the simplified→traditional (OpenCC `s2twp`) pass.
///
/// Two inputs:
/// - `detectedLang`: what the engine reported. On-device whisper reports a
///   language; cloud OpenRouter returns NO language field, so this is nil for
///   AUTO cloud runs — which is exactly why Chinese would otherwise stay in
///   simplified ("正體 caveat").
/// - `knownLanguage`: the user-locked language. Picking `zh` forces conversion
///   regardless of what (if anything) the engine detected.
public enum LanguageDecision {
    public static func shouldConvertToTraditional(
        detectedLang: String?,
        knownLanguage: TranscribeLanguage
    ) -> Bool {
        // An explicit user choice wins over detection.
        switch knownLanguage {
        case .zh: return true
        case .auto: break
        default: return false
        }
        // AUTO: fall back to the engine's detection.
        return isChinese(detectedLang)
    }

    /// True when a language code/name denotes Chinese (zh, zh-CN, zh-Hant,
    /// "chinese", "中文", …). Case-insensitive, tolerant of region subtags.
    static func isChinese(_ lang: String?) -> Bool {
        guard let lang = lang?.lowercased().trimmingCharacters(in: .whitespaces),
              !lang.isEmpty else { return false }
        if lang == "zh" || lang.hasPrefix("zh-") || lang.hasPrefix("zh_") { return true }
        if lang.contains("chinese") || lang.contains("中文") { return true }
        return false
    }
}
