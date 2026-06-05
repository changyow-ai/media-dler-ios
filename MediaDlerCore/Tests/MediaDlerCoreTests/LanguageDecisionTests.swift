import XCTest
@testable import MediaDlerCore

final class LanguageDecisionTests: XCTestCase {
    func testLockedZhAlwaysConverts() {
        // Even when the engine reports nothing (the cloud AUTO caveat).
        XCTAssertTrue(LanguageDecision.shouldConvertToTraditional(detectedLang: nil, knownLanguage: .zh))
        XCTAssertTrue(LanguageDecision.shouldConvertToTraditional(detectedLang: "en", knownLanguage: .zh))
    }

    func testLockedNonZhNeverConverts() {
        XCTAssertFalse(LanguageDecision.shouldConvertToTraditional(detectedLang: "zh", knownLanguage: .en))
        XCTAssertFalse(LanguageDecision.shouldConvertToTraditional(detectedLang: nil, knownLanguage: .ja))
    }

    func testAutoFollowsDetection() {
        XCTAssertTrue(LanguageDecision.shouldConvertToTraditional(detectedLang: "zh", knownLanguage: .auto))
        XCTAssertTrue(LanguageDecision.shouldConvertToTraditional(detectedLang: "zh-CN", knownLanguage: .auto))
        XCTAssertFalse(LanguageDecision.shouldConvertToTraditional(detectedLang: "en", knownLanguage: .auto))
    }

    func testAutoWithNoDetectionDoesNotConvert() {
        // This is the documented caveat: cloud AUTO + nil → stays simplified.
        XCTAssertFalse(LanguageDecision.shouldConvertToTraditional(detectedLang: nil, knownLanguage: .auto))
    }

    func testIsChineseTolerant() {
        XCTAssertTrue(LanguageDecision.isChinese("zh"))
        XCTAssertTrue(LanguageDecision.isChinese("ZH-Hant"))
        XCTAssertTrue(LanguageDecision.isChinese("chinese"))
        XCTAssertTrue(LanguageDecision.isChinese("中文"))
        XCTAssertFalse(LanguageDecision.isChinese("en"))
        XCTAssertFalse(LanguageDecision.isChinese(nil))
        XCTAssertFalse(LanguageDecision.isChinese(""))
    }
}
