import XCTest
@testable import MediaDlerCore

final class FormatSelectorTests: XCTestCase {
    private func fmt(_ id: String, hasAudio: Bool, isImage: Bool = false) -> MediaFormat {
        MediaFormat(
            formatId: id, ext: "mp4", label: "label", height: 1080,
            hasVideo: !isImage, hasAudio: hasAudio, isImage: isImage, filesizeBytes: nil
        )
    }

    func testBestVideo() {
        XCTAssertEqual(["-f", "bv*+ba/b"], FormatSelector.args(.bestVideo))
    }

    func testCappedVideo() {
        XCTAssertEqual(
            ["-f", "bv*[height<=720]+ba/b[height<=720]/bv*+ba/b", "-S", "res:720"],
            FormatSelector.args(.cappedVideo(maxHeight: 720))
        )
    }

    func testAudioMp3() {
        XCTAssertEqual(
            ["-x", "--audio-format", "mp3", "-f", "ba/b"],
            FormatSelector.args(.audio(.mp3))
        )
    }

    func testSpecificVideoOnlyMergesAudio() {
        XCTAssertEqual(
            ["-f", "137+ba/b"],
            FormatSelector.args(.specificFormat(fmt("137", hasAudio: false)))
        )
    }

    func testSpecificProgressiveUsesIdDirectly() {
        XCTAssertEqual(
            ["-f", "18"],
            FormatSelector.args(.specificFormat(fmt("18", hasAudio: true)))
        )
    }

    func testImageNeedsNoFormatArgs() {
        XCTAssertEqual([], FormatSelector.args(.imageOriginal))
    }
}
