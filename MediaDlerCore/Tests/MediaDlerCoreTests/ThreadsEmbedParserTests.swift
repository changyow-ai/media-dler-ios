import XCTest
@testable import MediaDlerCore

final class ThreadsEmbedParserTests: XCTestCase {
    private let post = "https://www.threads.com/@u/post/ABC123"

    func testVideoPostExtractsVideoNotAvatarAndKeepsQuery() {
        let html = """
        <video src="https://scontent-x.cdninstagram.com/o1/v/t16/f2/m84/AQ.mp4?efg=a&amp;oe=2"></video>
        <img class="img" src="https://scontent-x.cdninstagram.com/v/t51.82787-19/527_n.jpg?stp=dst-jpg_s100x100"/>
        """
        let items = ThreadsEmbedParser.parse(embedHtml: html, postUrl: post)
        XCTAssertEqual(1, items.count)
        XCTAssertFalse(items[0].isImage)
        XCTAssertTrue(items[0].sourceUrl.contains("AQ.mp4"))
        XCTAssertTrue(items[0].sourceUrl.contains("oe=2"))
        XCTAssertEqual("ThreadsVideo_ABC123", items[0].title)
    }

    func testImageCoverExtractedAvatarAndStaticSkipped() {
        let html = """
        <img class="img" src="https://scontent-x.cdninstagram.com/v/t51.82787-19/514_n.jpg?x=1"/>
        <img src="https://static.cdninstagram.com/rsrc.php/y.webp"/>
        data="https://scontent-x.cdninstagram.com/v/t51.82787-15/522_n.jpg?stp=dst-jpg_e35&amp;oh=9"
        """
        let items = ThreadsEmbedParser.parse(embedHtml: html, postUrl: post)
        XCTAssertEqual(1, items.count)
        XCTAssertTrue(items[0].isImage)
        XCTAssertTrue(items[0].sourceUrl.contains("522_n.jpg"))
    }

    func testVideoPlusImageGivesTwo() {
        let html = """
        <video src="https://s.cdninstagram.com/o1/v/AQ.mp4?a=1"></video>
        <img src="https://s.cdninstagram.com/v/t51.1-15/77_n.jpg?b=2"/>
        <img src="https://s.cdninstagram.com/v/t51.1-19/av.jpg?c=3"/>
        """
        let items = ThreadsEmbedParser.parse(embedHtml: html, postUrl: post)
        XCTAssertEqual(2, items.count)
        XCTAssertFalse(items[0].isImage)
        XCTAssertTrue(items[1].isImage)
    }

    func testTextOnlyReturnsEmpty() {
        XCTAssertEqual(0, ThreadsEmbedParser.parse(embedHtml: "<div>hello world</div>", postUrl: post).count)
    }
}
