import XCTest
import SwiftUI
@testable import SwiftScribe

final class TranscriptViewTests: XCTestCase {
    @MainActor
    func test_Init_SetsShowingEnhancedViewFromMemoSummary() {
        // Given a memo without summary
        let memoNoSummary = Memo.blank()
        var view1 = TranscriptView(memo: memoNoSummary, isRecording: .constant(false))
        XCTAssertFalse(view1.showingEnhancedView)

        // And a memo with summary
        let memoWithSummary = Memo.blank()
        memoWithSummary.summary = "Resumo inicial"
        var view2 = TranscriptView(memo: memoWithSummary, isRecording: .constant(false))
        XCTAssertTrue(view2.showingEnhancedView)
    }

    @MainActor
    func test_BodyBuilds_ForLiveAndFinishedMemo() {
        let memo = Memo.blank()
        let view = TranscriptView(memo: memo, isRecording: .constant(false))

        // Should be able to obtain body without crashing (live recording state)
        _ = view.body

        // When memo is finished, body should still be obtainable without crashing
        memo.isDone = true
        _ = view.body
    }
}

