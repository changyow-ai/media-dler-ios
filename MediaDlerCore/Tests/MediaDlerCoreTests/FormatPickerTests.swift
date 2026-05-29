import XCTest
@testable import MediaDlerCore

final class FormatPickerTests: XCTestCase {
    private func fmt(
        _ id: String, height: Int? = nil, hasVideo: Bool, hasAudio: Bool,
        isImage: Bool = false, filesize: Int64? = nil, vcodec: String? = nil,
        ext: String = "mp4", acodec: String? = nil
    ) -> MediaFormat {
        MediaFormat(
            formatId: id, ext: ext, label: id, height: height,
            hasVideo: hasVideo, hasAudio: hasAudio, isImage: isImage, filesizeBytes: filesize,
            vcodec: vcodec, acodec: acodec
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

    func testBestVideoPrefersPhotoCompatibleMp4OverHigherVp9() {
        let formats = [
            fmt("audio", hasVideo: false, hasAudio: true),
            fmt("vp9", height: 1080, hasVideo: true, hasAudio: false, vcodec: "vp09.00.40.08"),
            fmt("hd", hasVideo: true, hasAudio: false),
        ]
        XCTAssertEqual(["hd", "audio"], FormatPicker.pick(formats, selection: .bestVideo))
    }

    // The cap must read 'hd'/'sd'-style ids via inferredHeight, not height ?? 0,
    // otherwise a height-less 'hd' (720p) slips under a 360p cap.
    func testCapUsesInferredHeightForHdSdIds() {
        let formats = [
            fmt("hd", hasVideo: true, hasAudio: false),
            fmt("sd", hasVideo: true, hasAudio: false),
            fmt("a", hasVideo: false, hasAudio: true),
        ]
        XCTAssertEqual(["sd", "a"], FormatPicker.pick(formats, selection: .cappedVideo(maxHeight: 360)))
    }

    // The merge can't read Opus/webm, so audio pairing must prefer AAC/m4a even
    // when an Opus stream is larger.
    func testVideoPairsCompatibleAacAudioOverLargerOpus() {
        let formats = [
            fmt("v", height: 1080, hasVideo: true, hasAudio: false),
            fmt("opus", hasVideo: false, hasAudio: true, filesize: 9_000, ext: "webm", acodec: "opus"),
            fmt("m4a", hasVideo: false, hasAudio: true, filesize: 3_000, ext: "m4a", acodec: "mp4a.40.2"),
        ]
        XCTAssertEqual(["v", "m4a"], FormatPicker.pick(formats, selection: .bestVideo))
    }

    // When only incompatible audio exists, fall back to it rather than dropping audio.
    func testVideoFallsBackToOpusWhenNoCompatibleAudio() {
        let formats = [
            fmt("v", height: 1080, hasVideo: true, hasAudio: false),
            fmt("opus", hasVideo: false, hasAudio: true, filesize: 9_000, ext: "webm", acodec: "opus"),
        ]
        XCTAssertEqual(["v", "opus"], FormatPicker.pick(formats, selection: .bestVideo))
    }
}
