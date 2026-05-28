import XCTest
@testable import MediaDlerCore

final class ThreadsUrlTests: XCTestCase {
    func testRewritesThreadsComPostToEmbedAndDropsQuery() {
        XCTAssertEqual(
            "https://www.threads.net/@rico_y9527/post/DY3m2JQjXHZ/embed",
            ThreadsUrl.embedUrlOrNull("https://www.threads.com/@rico_y9527/post/DY3m2JQjXHZ?xmt=AQ&slof=1")
        )
    }

    func testRewritesThreadsNetPost() {
        XCTAssertEqual(
            "https://www.threads.net/@u/post/ABC123/embed",
            ThreadsUrl.embedUrlOrNull("https://www.threads.net/@u/post/ABC123")
        )
    }

    func testNullForNonThreads() {
        XCTAssertNil(ThreadsUrl.embedUrlOrNull("https://www.youtube.com/watch?v=abc"))
        XCTAssertNil(ThreadsUrl.embedUrlOrNull("https://www.threads.com/@someone"))
    }

    func testExtractsPostCode() {
        XCTAssertEqual("DY3m2JQjXHZ", ThreadsUrl.postCode("https://www.threads.com/@rico_y9527/post/DY3m2JQjXHZ?x=1"))
        XCTAssertNil(ThreadsUrl.postCode("https://youtube.com/watch?v=x"))
    }
}
