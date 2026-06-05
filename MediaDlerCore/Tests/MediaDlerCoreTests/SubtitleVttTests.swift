import XCTest
@testable import MediaDlerCore

final class SubtitleVttTests: XCTestCase {
    func testStripsHeaderTimingAndIndices() {
        let vtt = """
        WEBVTT
        Kind: captions
        Language: en

        1
        00:00:00.000 --> 00:00:02.000
        Hello world

        2
        00:00:02.000 --> 00:00:04.000
        Second line
        """
        XCTAssertEqual(SubtitleVtt.toPlainText(vtt), "Hello world\nSecond line")
    }

    func testStripsInlineTags() {
        let vtt = """
        WEBVTT

        00:00:02.000 --> 00:00:04.000
        <00:00:02.500><c>this is</c> a test
        """
        XCTAssertEqual(SubtitleVtt.toPlainText(vtt), "this is a test")
    }

    func testCollapsesRollingDuplicates() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        hello

        00:00:02.000 --> 00:00:04.000
        hello world
        """
        XCTAssertEqual(SubtitleVtt.toPlainText(vtt), "hello world")
    }

    func testDropsExactConsecutiveDuplicates() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        same line

        00:00:02.000 --> 00:00:04.000
        same line
        """
        XCTAssertEqual(SubtitleVtt.toPlainText(vtt), "same line")
    }

    func testStripTagsHelper() {
        XCTAssertEqual(SubtitleVtt.stripTags("<v Bob>hi there</v>"), "hi there")
        XCTAssertEqual(SubtitleVtt.stripTags("no tags"), "no tags")
    }
}
