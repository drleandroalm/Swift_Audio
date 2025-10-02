import Foundation

/// Centralized feature flags for experimental optimizations
/// Use these to enable/disable features without code changes
@available(macOS 13.0, iOS 16.0, *)
struct FeatureFlags {

    // MARK: - ANE Optimizations

    /// Enable ANE-aligned memory allocation for audio buffers
    /// Expected: 10-15% performance improvement in diarization
    /// Rollback: Set to false if issues detected
    static let useANEMemoryOptimization = true

    /// Only use ANE optimization for specific presets during rollout
    /// nil = all presets, otherwise specify preset
    static let aneOptimizationPresetFilter: DiarizationPreset? = nil  // Start with nil for all presets

    /// Log detailed ANE optimization metrics (disable in production)
    static let logANEMetrics = true

    // MARK: - Performance Monitoring

    /// Track and log conversion performance metrics
    static let enablePerformanceMonitoring = true

    /// Alert threshold: log warning if conversion takes > X ms
    static let conversionWarningThresholdMs: Double = 50.0

    // MARK: - Safety Validations

    /// Validate memory alignment (adds ~1% overhead, disable in production)
    static let validateMemoryAlignment = true

    /// Fallback to standard allocation if ANE allocation fails
    static let enableAutomaticFallback = true
}
