import XCTest
@testable import MediaDlerCore

final class WindowPlannerTests: XCTestCase {
    func testEmptyForZeroOrNegativeDuration() {
        XCTAssertEqual(WindowPlanner.plan(totalMs: 0, windowMs: 60_000, overlapMs: 3_000), [])
        XCTAssertEqual(WindowPlanner.plan(totalMs: -5, windowMs: 60_000, overlapMs: 3_000), [])
    }

    func testSingleWindowWhenShorterThanWindow() {
        let w = WindowPlanner.plan(totalMs: 45_000, windowMs: 60_000, overlapMs: 3_000)
        XCTAssertEqual(w, [TimeWindow(index: 0, startMs: 0, endMs: 45_000)])
    }

    func testExactlyOneWindowAtBoundary() {
        let w = WindowPlanner.plan(totalMs: 60_000, windowMs: 60_000, overlapMs: 3_000)
        XCTAssertEqual(w, [TimeWindow(index: 0, startMs: 0, endMs: 60_000)])
    }

    func testOverlappingWindowsAdvanceByStep() {
        // window 60s, overlap 3s → step 57s
        let w = WindowPlanner.plan(totalMs: 150_000, windowMs: 60_000, overlapMs: 3_000)
        XCTAssertEqual(w, [
            TimeWindow(index: 0, startMs: 0, endMs: 60_000),
            TimeWindow(index: 1, startMs: 57_000, endMs: 117_000),
            TimeWindow(index: 2, startMs: 114_000, endMs: 150_000),
        ])
    }

    func testLastWindowClampsToTotal() {
        let w = WindowPlanner.plan(totalMs: 120_000, windowMs: 60_000, overlapMs: 3_000)
        XCTAssertEqual(w.last?.endMs, 120_000)
        // Every window covers [0, total] with overlaps and no gaps.
        for i in 1..<w.count {
            XCTAssertLessThan(w[i].startMs, w[i - 1].endMs, "windows must overlap")
        }
    }

    func testZeroOverlapTilesCleanly() {
        let w = WindowPlanner.plan(totalMs: 25_000, windowMs: 10_000, overlapMs: 0)
        XCTAssertEqual(w, [
            TimeWindow(index: 0, startMs: 0, endMs: 10_000),
            TimeWindow(index: 1, startMs: 10_000, endMs: 20_000),
            TimeWindow(index: 2, startMs: 20_000, endMs: 25_000),
        ])
    }

    func testCloudSizedWindows() {
        // WAV cloud cap ~5min; a 12min clip → 3 windows.
        let w = WindowPlanner.plan(totalMs: 720_000, windowMs: 300_000, overlapMs: 3_000)
        XCTAssertEqual(w.count, 3)
        XCTAssertEqual(w.first?.startMs, 0)
        XCTAssertEqual(w.last?.endMs, 720_000)
    }
}
