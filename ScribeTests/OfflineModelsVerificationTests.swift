import XCTest

final class OfflineModelsVerificationTests: XCTestCase {
    func test_BundledModelsExist_InBuiltAppBundle() throws {
        // Locate the built products directory from the test bundle
        let testBundleURL = Bundle(for: type(of: self)).bundleURL
        let fm = FileManager.default
        // Climb up to locate the built SwiftScribe.app bundle (covers macOS layout: SwiftScribe.app/Contents/PlugIns/*.xctest)
        var cursor = testBundleURL
        var appURL: URL? = nil
        for _ in 0..<6 { // enough to walk out of PlugIns/Contents
            let parent = cursor.deletingLastPathComponent()
            // If parent is the .app, use it
            if parent.pathExtension == "app", parent.lastPathComponent.hasSuffix("SwiftScribe.app") {
                appURL = parent
                break
            }
            // Otherwise, search siblings of parent for the .app bundle
            if let items = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
                if let found = items.first(where: { $0.pathExtension == "app" && $0.lastPathComponent.hasSuffix("SwiftScribe.app") }) {
                    appURL = found
                    break
                }
            }
            cursor = parent
        }
        guard let appURL else {
            XCTFail("SwiftScribe.app not found near test bundle at: \(testBundleURL.path)")
            return
        }

        // Resolve app resources path (macOS vs iOS layout)
        let resourcesURLMac = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let resourcesURLiOS = appURL // iOS bundles keep resources at the root of .app
        let resourcesURL = fm.fileExists(atPath: resourcesURLMac.path) ? resourcesURLMac : resourcesURLiOS

        let modelsRoot = resourcesURL.appendingPathComponent("speaker-diarization-coreml", isDirectory: true)
        XCTAssertTrue(fm.fileExists(atPath: modelsRoot.path), "speaker-diarization-coreml folder missing in app bundle at \(modelsRoot.path)")

        // Check required models
        let segDir = modelsRoot.appendingPathComponent("pyannote_segmentation.mlmodelc", isDirectory: true)
        let embDir = modelsRoot.appendingPathComponent("wespeaker_v2.mlmodelc", isDirectory: true)
        XCTAssertTrue(fm.fileExists(atPath: segDir.path), "pyannote_segmentation.mlmodelc missing")
        XCTAssertTrue(fm.fileExists(atPath: embDir.path), "wespeaker_v2.mlmodelc missing")

        // Check coremldata.bin within each model directory
        let segCore = segDir.appendingPathComponent("coremldata.bin")
        let embCore = embDir.appendingPathComponent("coremldata.bin")
        XCTAssertTrue(fm.fileExists(atPath: segCore.path), "Missing coremldata.bin in pyannote_segmentation.mlmodelc")
        XCTAssertTrue(fm.fileExists(atPath: embCore.path), "Missing coremldata.bin in wespeaker_v2.mlmodelc")
    }
}
