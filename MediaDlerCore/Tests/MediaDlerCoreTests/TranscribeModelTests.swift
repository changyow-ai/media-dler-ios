import XCTest
@testable import MediaDlerCore

final class TranscribeModelTests: XCTestCase {
    func testBackendDerivation() {
        XCTAssertEqual(TranscribeModel.base.backend, .whisperCpp)
        XCTAssertEqual(TranscribeModel.small.backend, .whisperCpp)
        XCTAssertEqual(TranscribeModel.turboQ5.backend, .whisperCpp)
        XCTAssertEqual(TranscribeModel.senseVoice.backend, .sherpa)
        XCTAssertEqual(TranscribeModel.paraformer.backend, .sherpa)
        XCTAssertEqual(TranscribeModel.qwen3.backend, .sherpa)
    }

    func testAllModelsHaveLabel() {
        for m in TranscribeModel.allCases {
            XCTAssertFalse(m.label.isEmpty)
        }
    }

    func testExistingSettingsStillDecode() throws {
        // A settings blob written by an older build (only base/small known)
        // must still decode — adding cases is backward compatible.
        let json = #"{"shareMode":"ask","transcribeModel":"small"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.transcribeModel, .small)
        XCTAssertEqual(settings.transcribeModel.backend, .whisperCpp)
    }
}
