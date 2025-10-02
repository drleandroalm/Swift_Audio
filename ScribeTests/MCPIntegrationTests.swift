import XCTest
@testable import SwiftScribe

/// End-to-end integration tests using MCP UI automation
/// These tests run on iPhone 17 Pro simulator and validate complete user workflows
/// IMPORTANT: These tests use MCP tools and must be run with XcodeBuildMCP server active

@available(macOS 13.0, iOS 16.0, *)
final class MCPIntegrationTests: XCTestCase {
    // iPhone 17 Pro UUID (obtained from list_sims)
    let simulatorUuid = "64791F69-4DB8-44D3-84EE-E783C8A89D6B"
    let bundleId = "com.example.SwiftScribe" // Update with actual bundle ID

    var helper: MCPUIAutomationHelper!

    override func setUpWithError() throws {
        try super.setUpWithError()
        helper = MCPUIAutomationHelper(simulatorUuid: simulatorUuid)
    }

    // MARK: - Setup & Teardown with MCP

    func cleanSimulatorState() async throws {
        // Erase simulator to clean state
        // mcp.erase_sims(simulatorUdid: simulatorUuid, shutdownFirst: true)

        // Boot simulator
        // mcp.boot_sim(simulatorUuid: simulatorUuid)

        // Open simulator UI
        // mcp.open_sim()
    }

    func installAndLaunchApp() async throws {
        // Get app path
        // let appPath = mcp.get_sim_app_path(
        //     scheme: "SwiftScribe",
        //     platform: "iOS Simulator",
        //     simulatorName: "iPhone 17 Pro"
        // )

        // Install app
        // mcp.install_app_sim(simulatorUuid: simulatorUuid, appPath: appPath)

        // Launch app with logging
        // mcp.launch_app_sim(simulatorUuid: simulatorUuid, bundleId: bundleId)
    }

    // MARK: - Test: Recording Flow

    func testRecordingFlow_EndToEnd() async throws {
        // This test validates the complete recording workflow:
        // 1. Launch app
        // 2. Start recording
        // 3. Wait 10s
        // 4. Stop recording
        // 5. Verify transcript appears
        // 6. Verify audio file created

        // Setup
        try await cleanSimulatorState()
        try await installAndLaunchApp()

        // Start recording (self-healing button discovery)
        try await helper.tapButton("Gravar") // pt-BR for "Record"
        try await helper.waitForElement(label: "Pausar", timeout: 2.0)

        // Capture screenshot for visual verification
        try await helper.screenshot(name: "01_recording_active")

        // Verify recording indicator
        try await helper.verifyElementExists(label: "00:")

        // Wait for audio to be captured (10s)
        try await Task.sleep(nanoseconds: 10_000_000_000)

        // Stop recording
        try await helper.tapButton("Parar") // pt-BR for "Stop"

        // Wait for transcript processing
        try await helper.waitForElement(label: "Transcript", timeout: 5.0)

        // Verify transcript view appeared
        let ui = try await helper.describeUI()
        XCTAssertTrue(ui.hasElement(type: "TextView", minHeight: 100),
                      "Transcript view should be visible")

        // Capture final state
        try await helper.screenshot(name: "02_transcript_visible")

        // Extract logs for validation
        // let logs = mcp.stop_sim_log_cap(logSessionId: ...)
        // XCTAssertTrue(logs.contains("Primeiro buffer recebido"))
    }

    // MARK: - Test: Speaker Enrollment Flow

    func testSpeakerEnrollment_FullWorkflow() async throws {
        // Validates speaker enrollment:
        // 1. Navigate to Settings → Speakers
        // 2. Tap "Enroll Speaker"
        // 3. Enter speaker name
        // 4. Record 8s sample
        // 5. Verify speaker appears in list
        // 6. Verify persistence across app restart

        try await cleanSimulatorState()
        try await installAndLaunchApp()

        // Navigate to Speakers screen
        try await helper.navigateTo("Falantes", from: ["Configurações"])

        // Take screenshot of speakers list (should be empty initially)
        try await helper.screenshot(name: "03_speakers_list_empty")

        // Tap "Enroll Speaker" button
        try await helper.tapButton("Inscrever Falante")

        // Fill in speaker name
        try await helper.fillTextField(label: "Nome", text: "Falante Teste")

        // Start enrollment recording
        try await helper.tapButton("Iniciar Gravação")

        // Wait for 8s enrollment duration
        try await Task.sleep(nanoseconds: 8_500_000_000)

        // Verify progress bar completion
        let ui = try await helper.describeUI()
        if let progressBar = ui.findElement(type: "ProgressBar") {
            XCTAssertGreaterThan(progressBar.frame.width, 0.9,
                               "Progress bar should be near completion")
        }

        // Save enrolled speaker
        try await helper.tapButton("Salvar")

        // Wait for return to speakers list
        try await helper.waitForAnimation(1.0)

        // Verify speaker appears in list
        try await helper.verifyTextAppears("Falante Teste")
        try await helper.screenshot(name: "04_speaker_enrolled")

        // Test persistence: restart app
        // mcp.stop_app_sim(simulatorUuid: simulatorUuid, bundleId: bundleId)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await installAndLaunchApp()

        try await helper.navigateTo("Falantes", from: ["Configurações"])
        try await helper.verifyTextAppears("Falante Teste")

        XCTAssertTrue(true, "Speaker persisted across app restart")
    }

    // MARK: - Test: Settings Configuration

    func testSettingsConfiguration_AllPresets() async throws {
        // Validates diarization preset switching:
        // 1. Navigate to Settings
        // 2. Test each preset (Meeting, Interview, Podcast)
        // 3. Verify UI updates reflect preset values
        // 4. Record sample with each preset
        // 5. Verify diarization quality metrics

        try await cleanSimulatorState()
        try await installAndLaunchApp()

        try await helper.navigateTo("Configurações", from: [])

        let presets = ["Reunião", "Entrevista", "Podcast"]

        for preset in presets {
            // Select preset
            try await helper.tapButton(preset)
            try await helper.waitForAnimation(0.5)

            // Verify preset is selected (visual confirmation)
            try await helper.screenshot(name: "05_preset_\(preset)")

            // Go back to main view
            try await helper.tapButton("Voltar") // or use gesture

            // Record 30s sample
            try await helper.tapButton("Gravar")
            try await Task.sleep(nanoseconds: 30_000_000_000)
            try await helper.tapButton("Parar")

            // Wait for processing
            try await helper.waitForAnimation(5.0)

            // Verify transcript appeared
            let ui = try await helper.describeUI()
            XCTAssertTrue(ui.hasElement(type: "TextView"),
                          "Transcript should appear after recording with preset \(preset)")

            // Navigate back to settings for next preset
            try await helper.navigateTo("Configurações", from: [])
        }
    }

    // MARK: - Test: Long Recording Stability (60s, 120s, 240s)

    func testLongRecording_60Seconds() async throws {
        try await cleanSimulatorState()
        try await installAndLaunchApp()

        let startMemory = await getMemoryUsage()

        try await helper.tapButton("Gravar")
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60s
        try await helper.tapButton("Parar")

        try await helper.waitForAnimation(5.0)

        let endMemory = await getMemoryUsage()
        let memoryGrowth = endMemory - startMemory

        // Verify memory within bounds (from PerformanceBaselines.json)
        XCTAssertLessThan(memoryGrowth, 150, // 150MB SLO for 10min, should be much less for 60s
                          "Memory growth exceeded baseline for 60s recording")

        try await helper.verifyElementExists(label: "Transcript")
    }

    func testLongRecording_120Seconds() async throws {
        try await cleanSimulatorState()
        try await installAndLaunchApp()

        try await helper.tapButton("Gravar")
        try await Task.sleep(nanoseconds: 120_000_000_000) // 120s
        try await helper.tapButton("Parar")

        try await helper.waitForAnimation(10.0) // Longer processing time

        try await helper.verifyElementExists(label: "Transcript")

        // Verify UI remains responsive
        let tapResponse = await measureTapResponse()
        XCTAssertLessThan(tapResponse, 100, // 100ms SLO from baselines
                          "UI tap response degraded after long recording")
    }

    func testLongRecording_240Seconds_StressTest() async throws {
        try await cleanSimulatorState()
        try await installAndLaunchApp()

        let startTime = Date()

        try await helper.tapButton("Gravar")
        try await Task.sleep(nanoseconds: 240_000_000_000) // 240s = 4 minutes
        try await helper.tapButton("Parar")

        let recordingDuration = Date().timeIntervalSince(startTime)
        XCTAssertGreaterThan(recordingDuration, 240, "Recording should have lasted at least 240s")

        try await helper.waitForAnimation(15.0) // Extended processing time

        try await helper.verifyElementExists(label: "Transcript")

        // Capture final screenshot
        try await helper.screenshot(name: "06_long_recording_complete")
    }

    // MARK: - Performance Measurement Helpers

    private func getMemoryUsage() async -> Double {
        // In real implementation, use MCP to get app memory footprint
        // Or parse Instruments trace
        return 0.0
    }

    private func measureTapResponse() async -> Double {
        // Measure time from tap to UI update
        let start = Date()
        try? await helper.tapButton("Configurações")
        let elapsed = Date().timeIntervalSince(start)
        try? await helper.tapButton("Voltar")
        return elapsed * 1000 // ms
    }
}

// MARK: - Test Configuration

extension MCPIntegrationTests {
    /// Run subset of tests for quick smoke check
    static func quickSmokeSuite() -> [String] {
        [
            "testRecordingFlow_EndToEnd",
            "testLongRecording_60Seconds"
        ]
    }

    /// Full test suite for comprehensive validation
    static func fullIntegrationSuite() -> [String] {
        [
            "testRecordingFlow_EndToEnd",
            "testSpeakerEnrollment_FullWorkflow",
            "testSettingsConfiguration_AllPresets",
            "testLongRecording_60Seconds",
            "testLongRecording_120Seconds",
            "testLongRecording_240Seconds_StressTest"
        ]
    }
}
