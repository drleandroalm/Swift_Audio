import Foundation
import os

/// A lightweight serial executor for CPU-heavy inference tasks.
/// Ensures work does not run on the main thread and is executed sequentially.
actor InferenceExecutor {
    static let shared = InferenceExecutor()
    private let log = Logger(subsystem: "com.swift.examples.scribe", category: "Inference")

    /// Run a synchronous job serially off the main thread.
    @preconcurrency
    func run<T>(_ op: @escaping () throws -> T) async throws -> T {
        return try op()
    }

    /// Run an async job serially off the main thread.
    @preconcurrency
    func runAsync<T>(_ op: @escaping () async throws -> T) async throws -> T {
        return try await op()
    }

}
