import XCTest
@testable import MediaDlerCore

final class SelectionPlannerTests: XCTestCase {
    private let video = MediaItem(
        sourceUrl: "u", playlistIndex: nil, id: "id", title: "t",
        thumbnailUrl: nil, durationSeconds: nil, isImage: false, formats: []
    )
    private var image: MediaItem {
        MediaItem(
            sourceUrl: "u", playlistIndex: nil, id: "id", title: "t",
            thumbnailUrl: nil, durationSeconds: nil, isImage: true, formats: []
        )
    }

    func testImageAlwaysOriginalEvenWhenAudioDefault() {
        XCTAssertEqual(
            .imageOriginal,
            SelectionPlanner.defaultSelection(image, settings: AppSettings(defaultMediaKind: .audio))
        )
    }

    func testAudioWhenKindAudio() {
        XCTAssertEqual(
            .audio(.m4a),
            SelectionPlanner.defaultSelection(
                video,
                settings: AppSettings(defaultMediaKind: .audio, audioFormat: .m4a)
            )
        )
    }

    func testBestWhenQualityBest() {
        XCTAssertEqual(
            .bestVideo,
            SelectionPlanner.defaultSelection(video, settings: AppSettings(defaultVideoQuality: .best))
        )
    }

    func testCappedWhenQualitySet() {
        XCTAssertEqual(
            .cappedVideo(maxHeight: 720),
            SelectionPlanner.defaultSelection(video, settings: AppSettings(defaultVideoQuality: .p720))
        )
    }
}
