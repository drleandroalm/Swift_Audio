import AVFoundation
import XCTest
@testable import SwiftScribe

@MainActor
final class SpokenWordTranscriberRecoveryTests: XCTestCase {
    func testStreamingNotifiesWhenInputBuilderIsMissing() async throws {
        #if DEBUG
        let memo = Memo.blank()
        let transcriber = SpokenWordTranscriber(memo: memo)

        try await transcriber.setUpTranscriber()
        let format = try XCTUnwrap(transcriber.analyzerFormat, "Analyzer format should be resolved after setup")
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            XCTFail("Failed to create audio buffer")
            return
        }
        buffer.frameLength = buffer.frameCapacity
        if let channel = buffer.floatChannelData?.pointee {
            let count = Int(buffer.frameLength)
            for index in 0..<count {
                channel[index] = 0
            }
        }

        transcriber._test_dropInputBuilder()
        let expectation = expectation(forNotification: SpokenWordTranscriber.inputBuilderLostNotification, object: transcriber)

        try await transcriber.streamAudioToTranscriber(buffer)
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertEqual(transcriber.inputBuilderLossCount, 1)
        #else
        throw XCTSkip("Debug helper unavailable in non-Debug builds")
        #endif
    }
}
