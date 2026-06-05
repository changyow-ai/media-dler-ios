import XCTest
@testable import MediaDlerCore

final class SegmentMergeTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(SegmentMerge.merge([]), "")
        XCTAssertEqual(SegmentMerge.merge(["", "   "]), "")
    }

    func testSingleSegmentTrimmed() {
        XCTAssertEqual(SegmentMerge.merge(["  hello world  "]), "hello world")
    }

    func testRemovesEnglishWordOverlap() {
        XCTAssertEqual(
            SegmentMerge.merge(["hello world", "world peace"]),
            "hello world peace"
        )
    }

    func testRemovesChineseOverlap() {
        XCTAssertEqual(
            SegmentMerge.merge(["今天天氣", "天氣很好"]),
            "今天天氣很好"
        )
    }

    func testNoOverlapConcatenates() {
        XCTAssertEqual(SegmentMerge.merge(["abc", "def"]), "abcdef")
    }

    func testSkipsBlankSegmentsInMiddle() {
        XCTAssertEqual(
            SegmentMerge.merge(["今天天氣", "   ", "天氣很好"]),
            "今天天氣很好"
        )
    }

    func testTakesLongestOverlap() {
        // "aXaX" suffix vs "aXaX..." prefix → longest run wins (4), not 2.
        XCTAssertEqual(SegmentMerge.merge(["__aXaX", "aXaX!!"]), "__aXaX!!")
    }

    func testThreeWayStitch() {
        XCTAssertEqual(
            SegmentMerge.merge(["他說我們", "我們要走", "要走了吧"]),
            "他說我們要走了吧"
        )
    }

    func testLongestOverlapHelper() {
        XCTAssertEqual(SegmentMerge.longestOverlap(Array("abcde"), Array("cdefg")), 3)
        XCTAssertEqual(SegmentMerge.longestOverlap(Array("abc"), Array("xyz")), 0)
        XCTAssertEqual(SegmentMerge.longestOverlap(Array("aaa"), Array("aaa")), 3)
    }
}
