import XCTest
@testable import MediaDlerCore

final class FormatPickerTests: XCTestCase {
    private func fmt(
        _ id: String, height: Int? = nil, hasVideo: Bool, hasAudio: Bool,
        isImage: Bool = false, filesize: Int64? = nil
    ) -> MediaFormat {
        MediaFormat(
            formatId: id, ext: "mp4", label: id, height: height,
            hasVideo: hasVideo, hasAudio: hasAudio, isImage: isImage, filesizeBytes: filesize
        )
    }

    func testBestVideoPrefersHighestMuxed() {
        let formats = [
            fmt("low", height: 360, hasVideo: true, hasAudio: true),
            fmt("high", height: 1080, hasVideo: true, hasAudio: true),
        ]
        XCTAssertEqual(["high"], FormatPicker.pick(formats, selection: .bestVideo))
    }

    func testBestVideoPairsVideoOnlyWithAudio() {
        let formats = [
            fmt("v", height: 1080, hasVideo: true, hasAudio: false),
            fmt("a", hasVideo: false, hasAudio: true),
        ]
        XCTAssertEqual(["v", "a"], FormatPicker.pick(formats, selection: .bestVideo))
    }

    func testCappedPicksWithinLimitAndPairsAudio() {
        let formats = [
            fmt("v1080", height: 1080, hasVideo: true, hasAudio: false),
            fmt("v720", height: 720, hasVideo: true, hasAudio: false),
            fmt("a", hasVideo: false, hasAudio: true),
        ]
        XCTAssertEqual(["v720", "a"], FormatPicker.pick(formats, selection: .cappedVideo(maxHeight: 720)))
    }

    func testCappedFallsBackWhenNoneWithinLimit() {
        let formats = [
            fmt("v1080", height: 1080, hasVideo: true, hasAudio: true),
        ]
        XCTAssertEqual(["v1080"], FormatPicker.pick(formats, selection: .cappedVideo(maxHeight: 480)))
    }

    func testAudioPrefersAudioOnly() {
        let formats = [
            fmt("muxed", height: 720, hasVideo: true, hasAudio: true),
            fmt("a", hasVideo: false, hasAudio: true),
        ]
        XCTAssertEqual(["a"], FormatPicker.pick(formats, selection: .audio(.mp3)))
    }

    func testSpecificVideoOnlyAddsAudio() {
        let formats = [
            fmt("v", height: 1080, hasVideo: true, hasAudio: false),
            fmt("a", hasVideo: false, hasAudio: true),
        ]
        let v = formats[0]
        XCTAssertEqual(["v", "a"], FormatPicker.pick(formats, selection: .specificFormat(v)))
    }

    func testSpecificMuxedUsedAlone() {
        let muxed = fmt("m", height: 720, hasVideo: true, hasAudio: true)
        XCTAssertEqual(["m"], FormatPicker.pick([muxed], selection: .specificFormat(muxed)))
    }

    func testImagePicksLargestImage() {
        let formats = [
            fmt("small", hasVideo: false, hasAudio: false, isImage: true, filesize: 100),
            fmt("big", hasVideo: false, hasAudio: false, isImage: true, filesize: 900),
        ]
        XCTAssertEqual(["big"], FormatPicker.pick(formats, selection: .imageOriginal))
    }
}
