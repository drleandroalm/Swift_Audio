import Foundation
import CoreML
import os

/// Preloads CoreML models used by diarization to avoid cold-start hitches.
/// Warmup is idempotent and safe to call multiple times.
final class ModelWarmupService: @unchecked Sendable {
    static let shared = ModelWarmupService()
    private let log = Logger(subsystem: "com.swift.examples.scribe", category: "MLWarmup")
    private var warmed = false
    private let lock = NSLock()

    func warmupIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !warmed else { return }
        warmed = true
        Task.detached(priority: .utility) { [log] in
            let started = Date()
            do {
                // Attempt to warm the diarization models if present in the bundle
                try Self.loadModel(named: "pyannote_segmentation")
                try Self.loadModel(named: "wespeaker_v2")
                let dt = Date().timeIntervalSince(started)
                log.info("ML warmup completed in \(dt, format: .fixed(precision: 3))s")
            } catch {
                log.error("ML warmup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func loadModel(named name: String) throws {
        // Models are packaged under a folder reference: speaker-diarization-coreml/
        let subdir = "speaker-diarization-coreml"
        let bundle = Bundle.main
        // First attempt: direct subdirectory lookup
        if let url = bundle.url(forResource: name, withExtension: "mlmodelc", subdirectory: subdir) {
            _ = try MLModel(contentsOf: url)
            return
        }
        // Fallback: resourceURL + appendingPathComponent for robustness
        if let base = bundle.resourceURL?.appendingPathComponent(subdir, isDirectory: true) {
            let url = base.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try MLModel(contentsOf: url)
                return
            }
        }
        throw NSError(domain: "ModelWarmup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(name).mlmodelc in bundle under \(subdir)"])
    }
}
