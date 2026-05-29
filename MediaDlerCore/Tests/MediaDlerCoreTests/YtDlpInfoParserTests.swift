import XCTest
@testable import MediaDlerCore

final class YtDlpInfoParserTests: XCTestCase {
    func testSingleVideoDropsStoryboardAndKeepsRealFormats() {
        let json = """
        {"id":"abc","title":"Test Video","ext":"mp4","thumbnail":"http://t/x.jpg","duration":100,
         "webpage_url":"https://youtu.be/abc","formats":[
          {"format_id":"18","ext":"mp4","vcodec":"avc1","acodec":"mp4a","height":360,"filesize":1000},
          {"format_id":"137","ext":"mp4","vcodec":"avc1","acodec":"none","height":1080,"filesize":5000},
          {"format_id":"140","ext":"m4a","vcodec":"none","acodec":"mp4a","filesize":800},
          {"format_id":"sb0","ext":"mhtml","vcodec":"none","acodec":"none"}
         ]}
        """
        let items = YtDlpInfoParser.parse(json, requestUrl: "https://youtu.be/abc")
        XCTAssertEqual(1, items.count)
        let item = items[0]
        XCTAssertFalse(item.isImage)
        XCTAssertNil(item.playlistIndex)
        XCTAssertEqual("https://youtu.be/abc", item.sourceUrl)
        XCTAssertEqual("Test Video", item.title)
        XCTAssertEqual(3, item.formats.count)
        let v137 = item.formats.first { $0.formatId == "137" }!
        XCTAssertTrue(v137.hasVideo)
        XCTAssertFalse(v137.hasAudio)
        XCTAssertEqual(1080, v137.height)
        let a140 = item.formats.first { $0.formatId == "140" }!
        XCTAssertFalse(a140.hasVideo)
        XCTAssertTrue(a140.hasAudio)
    }

    func testCarouselYieldsMultipleItemsWithIndices() {
        let json = """
        {"_type":"playlist","id":"post1","title":"Carousel","entries":[
          {"id":"img1","title":"Pic 1","ext":"jpg","url":"http://img/1.jpg",
           "formats":[{"format_id":"0","ext":"jpg","vcodec":"none","acodec":"none","url":"http://img/1.jpg","height":1080}]},
          {"id":"vid2","title":"Clip 2","ext":"mp4",
           "formats":[{"format_id":"dash","ext":"mp4","vcodec":"avc1","acodec":"mp4a","height":720}]}
        ]}
        """
        let items = YtDlpInfoParser.parse(json, requestUrl: "https://insta/p/post1")
        XCTAssertEqual(2, items.count)
        XCTAssertTrue(items[0].isImage)
        XCTAssertEqual(1, items[0].playlistIndex)
        XCTAssertEqual("https://insta/p/post1", items[0].sourceUrl)
        XCTAssertFalse(items[1].isImage)
        XCTAssertEqual(2, items[1].playlistIndex)
        XCTAssertEqual(720, items[1].formats.first?.height)
    }

    func testSingleImagePost() {
        let json = """
        {"id":"imgpost","title":"Single Pic","ext":"jpg","webpage_url":"https://insta/p/x",
         "url":"http://img/x.jpg",
         "formats":[{"format_id":"0","ext":"jpg","vcodec":"none","acodec":"none","url":"http://img/x.jpg","height":1080}]}
        """
        let items = YtDlpInfoParser.parse(json, requestUrl: "https://insta/p/x")
        XCTAssertEqual(1, items.count)
        XCTAssertTrue(items[0].isImage)
        XCTAssertNil(items[0].playlistIndex)
        XCTAssertEqual("https://insta/p/x", items[0].sourceUrl)
    }

    func testDirectUrlWithoutFormats() {
        let json = #"{"id":"d","title":"Direct","ext":"mp4","url":"http://v/x.mp4"}"#
        let items = YtDlpInfoParser.parse(json, requestUrl: "http://v/x.mp4")
        XCTAssertEqual(1, items.count)
        XCTAssertFalse(items[0].isImage)
        XCTAssertEqual(1, items[0].formats.count)
    }

    func testAllNullEntriesYieldEmpty() {
        let json = #"{"_type":"playlist","id":"p","entries":[null,null]}"#
        XCTAssertEqual(0, YtDlpInfoParser.parse(json, requestUrl: "https://x/p").count)
    }

    func testNestedPlaylistContainerIsDropped() {
        let json = #"{"_type":"playlist","entries":[{"_type":"playlist","entries":[{"id":"v"}]}]}"#
        XCTAssertEqual(0, YtDlpInfoParser.parse(json, requestUrl: "https://x/chan").count)
    }

    func testImageUrlWithDottedQueryIsClassifiedAsImage() {
        let json = #"{"id":"i","title":"P","url":"http://cdn/photo.jpg?v=1.0&x=a.b"}"#
        let items = YtDlpInfoParser.parse(json, requestUrl: "http://cdn/photo.jpg")
        XCTAssertEqual(1, items.count)
        XCTAssertTrue(items[0].isImage)
    }
}
