import XCTest
@testable import MediaDlerCore

final class UrlExtractorTests: XCTestCase {
    func testPlainUrl() {
        XCTAssertEqual("https://youtu.be/abc", UrlExtractor.firstUrl("https://youtu.be/abc"))
    }

    func testUrlEmbeddedInText() {
        XCTAssertEqual(
            "https://www.instagram.com/p/XYZ/",
            UrlExtractor.firstUrl("看這個 https://www.instagram.com/p/XYZ/ 很酷")
        )
    }

    func testStripsTrailingPunctuation() {
        XCTAssertEqual("https://x.com/a/123", UrlExtractor.firstUrl("see https://x.com/a/123)."))
    }

    func testTakesFirstOfMany() {
        XCTAssertEqual("https://one.com", UrlExtractor.firstUrl("a https://one.com b https://two.com"))
    }

    func testNullWhenNone() {
        XCTAssertNil(UrlExtractor.firstUrl("no link here"))
        XCTAssertNil(UrlExtractor.firstUrl(nil))
        XCTAssertNil(UrlExtractor.firstUrl(""))
    }

    func testKeepsBalancedParensInPath() {
        XCTAssertEqual(
            "https://en.wikipedia.org/wiki/Python_(programming_language)",
            UrlExtractor.firstUrl("https://en.wikipedia.org/wiki/Python_(programming_language)")
        )
    }

    func testKeepsBalancedParensButDropsSentencePeriod() {
        XCTAssertEqual(
            "https://en.wikipedia.org/wiki/Python_(programming_language)",
            UrlExtractor.firstUrl("read https://en.wikipedia.org/wiki/Python_(programming_language).")
        )
    }
}
