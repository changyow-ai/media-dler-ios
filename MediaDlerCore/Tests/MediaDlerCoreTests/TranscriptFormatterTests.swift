import XCTest
@testable import MediaDlerCore

final class TranscriptFormatterTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(TranscriptFormatter.format(""), "")
        XCTAssertEqual(TranscriptFormatter.format("   \n  "), "")
    }

    func testHardBreakAfterChineseSentenceEnd() {
        XCTAssertEqual(
            TranscriptFormatter.format("今天天氣很好。明天會下雨。"),
            "今天天氣很好。\n明天會下雨。"
        )
    }

    func testHardBreakAfterAsciiSentenceEnd() {
        XCTAssertEqual(
            TranscriptFormatter.format("Hi there! How are you?"),
            "Hi there!\nHow are you?"
        )
    }

    func testKeepsClosingQuoteWithSentence() {
        XCTAssertEqual(
            TranscriptFormatter.format("他說「你好。」對吧"),
            "他說「你好。」\n對吧"
        )
    }

    func testShortTextNotBroken() {
        XCTAssertEqual(TranscriptFormatter.format("hello world"), "hello world")
    }

    func testSoftBreakAtCommaBeforeLimit() {
        XCTAssertEqual(
            TranscriptFormatter.format("一二三四五，六七八九十十一十二", softWrapAt: 10),
            "一二三四五，\n六七八九十十一十二"
        )
    }

    func testDoesNotFabricateSentenceBoundaries() {
        // No punctuation, under the wrap limit → stays one line.
        let raw = "這是一段沒有任何標點的句子"
        XCTAssertEqual(TranscriptFormatter.format(raw, softWrapAt: 40), raw)
    }
}
