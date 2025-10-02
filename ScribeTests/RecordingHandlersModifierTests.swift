import XCTest
import SwiftUI
import SwiftData
@testable import SwiftScribe

@MainActor
final class RecordingHandlersModifierTests: XCTestCase {

    private final class Driver: ObservableObject {
        @Published var isRecording: Bool = false
        @Published var isPlaying: Bool = false
        @Published var url: URL? = nil
    }

    struct Harness: View {
        @ObservedObject var driver: Driver
        let memo: Memo

        // Callbacks wired to expectations/counters
        let onRecordingChange: (_ old: Bool, _ new: Bool) -> Void
        let onPlayingChange: () -> Void
        let onMemoURLChange: (_ url: URL?) -> Void
        let onFirstBuffer: () -> Void
        let onRecorderStop: (_ cause: String?) -> Void
        let onBackpressure: (_ liveSeconds: Double, _ consecutiveDrops: Int) -> Void
        let onMemoIdChange: () -> Void
        let onAppear: () -> Void
        let onTask: () -> Void
        let onDisappear: () -> Void
        @State var enhancementError: String? = nil
        @State var showClearConfirm: Bool = false

        var body: some View {
            Text("Harness")
                .modifier(RecordingHandlersModifier(
                    onRecordingChange: onRecordingChange,
                    onPlayingChange: onPlayingChange,
                    onMemoURLChange: onMemoURLChange,
                    onFirstBuffer: onFirstBuffer,
                    onRecorderStop: onRecorderStop,
                    onBackpressure: onBackpressure,
                    onMemoIdChange: onMemoIdChange,
                    onAppear: onAppear,
                    onTask: onTask,
                    onDisappear: onDisappear,
                    enhancementError: $enhancementError,
                    showClearConfirm: $showClearConfirm,
                    onClearConfirmed: {},
                    isRecording: $driver.isRecording,
                    isPlaying: $driver.isPlaying,
                    memoId: memo.id,
                    memoURL: driver.url
                ))
        }
    }

    func test_ModifierFiresHandlers_OnStateAndNotifications() throws {
        let driver = Driver()
        let memo = Memo.blank()

        let expRecording = expectation(description: "onRecordingChange")
        let expPlaying = expectation(description: "onPlayingChange")
        let expURL = expectation(description: "onMemoURLChange")
        let expFirstBuffer = expectation(description: "onFirstBuffer")
        let expStop = expectation(description: "onRecorderStop")
        let expBackpressure = expectation(description: "onBackpressure")
        let expAppear = expectation(description: "onAppear")
        let expTask = expectation(description: "onTask")
        let expDisappear = expectation(description: "onDisappear")

        let host = NSHostingView(rootView: Harness(
            driver: driver,
            memo: memo,
            onRecordingChange: { old, new in if old == false && new == true { expRecording.fulfill() } },
            onPlayingChange: { expPlaying.fulfill() },
            onMemoURLChange: { _ in expURL.fulfill() },
            onFirstBuffer: { expFirstBuffer.fulfill() },
            onRecorderStop: { cause in if cause == "silenceTimeout" { expStop.fulfill() } },
            onBackpressure: { live, drops in if drops >= 2 && live.isFinite { expBackpressure.fulfill() } },
            onMemoIdChange: { },
            onAppear: { expAppear.fulfill() },
            onTask: { expTask.fulfill() },
            onDisappear: { expDisappear.fulfill() }
        ))

        // Attach to a temporary window to trigger .onAppear / .task
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 50),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)

        // Drive state changes to trigger .onChange handlers
        driver.isRecording = true
        driver.isPlaying = true
        driver.url = URL(fileURLWithPath: "/tmp/dummy.wav")

        // Post notifications to exercise notification handlers
        NotificationCenter.default.post(name: Recorder.firstBufferNotification, object: nil)
        NotificationCenter.default.post(name: Recorder.didStopWithCauseNotification, object: nil, userInfo: ["cause": "silenceTimeout"])
        NotificationCenter.default.post(name: DiarizationManager.backpressureNotification, object: nil, userInfo: ["liveSeconds": 2.3, "consecutive": 2])

        // Remove from window to trigger .onDisappear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            window.contentView = nil
        }

        wait(for: [expAppear, expTask, expRecording, expPlaying, expURL, expFirstBuffer, expStop, expBackpressure, expDisappear], timeout: 5.0, enforceOrder: false)
    }
}

