# Manual Testing Guide: Phase 1 + Phase 2A Validation

**Date**: 2025-10-01
**Integration**: FluidAudio Configuration Optimization + ANE Memory Optimization
**Status**: Ready for Manual Testing

---

## 🎯 Testing Objective

Validate two major enhancements:
1. **Phase 1**: Configuration optimization (minSegmentDuration 0.5→1.0s, maxLiveBufferSeconds 15→20s)
2. **Phase 2A**: ANE memory optimization for 10-15% performance improvement

---

## ✅ Automated Tests Completed

### Build Verification
- ✅ macOS build: **SUCCEEDED**
- ✅ Test suite: **21/21 tests PASSED**
- ✅ ANE object files confirmed compiled:
  - `ANEMemoryOptimizer.o`
  - `ANEMemoryUtils.o`
  - `FeatureFlags.o`

**Conclusion**: No regressions introduced, ready for functional testing.

---

## 📋 Manual Test Plan

### Prerequisites

1. **Open Console.app** (for monitoring ANE metrics):
   ```bash
   open -a Console
   ```
   - Filter to process: "SwiftScribe"
   - Search for: "DiarizationManager" or "ANE"

2. **Prepare test audio**:
   - Known test file: `/Users/leandroalmeida/swift-scribe/Audio_Files_Tests/Audio_One_Speaker_Test.wav`
   - Or record live audio (recommended for real-world testing)

3. **Launch SwiftScribe**:
   ```bash
   open /Users/leandroalmeida/Library/Developer/Xcode/DerivedData/SwiftScribe-cfkjqczrqzfogldpotprdvqdzbwt/Build/Products/Debug/SwiftScribe.app
   ```

---

## 🧪 Test Cases

### Test 1: Basic Functionality - 30 Second Recording
**Estimated Time**: 5 minutes
**Objective**: Verify transcription works and ANE metrics appear

**Steps**:
1. Launch SwiftScribe
2. Select "Meeting" preset (default settings)
3. Start recording
4. Speak clearly for 30 seconds (vary volume, include pauses)
5. Stop recording
6. Wait for transcription to complete

**Monitor Console For**:
```
[DiarizationManager] ✅ ANE-aligned allocation: XXXX samples
[ANE Metrics] Conversions: X, Avg: X.XXms, FastPath: X, ANE Success: XX.X%, Fallbacks: X
```

**Success Criteria**:
- ✅ Transcription text appears correctly
- ✅ Speaker colors assigned (if diarization enabled)
- ✅ ANE metrics visible in Console
- ✅ ANE Success Rate ≥ 90%
- ✅ Average conversion time < 5ms
- ✅ No crashes or errors

**Expected Console Output Example**:
```
[DiarizationManager] ✅ ANE-aligned allocation: 16000 samples
[ANE Metrics] Conversions: 45, Avg: 2.3ms, FastPath: 5, ANE Success: 95.6%, Fallbacks: 2
[DiarizationManager] ✅ ANE-aligned allocation: 16000 samples
[ANE Metrics] Conversions: 90, Avg: 2.4ms, FastPath: 10, ANE Success: 94.4%, Fallbacks: 5
```

---

### Test 2: Preset Validation
**Estimated Time**: 10 minutes
**Objective**: Verify Phase 1 config changes work across all presets

**Test 2.1: Meeting Preset**
1. Select "Reunião" (Meeting) preset
2. Record 1-minute audio
3. Check Settings → Verify `minSegmentDuration = 1.0s`
4. Verify no segments < 1.0s in timeline

**Test 2.2: Interview Preset**
1. Select "Entrevista" (Interview) preset
2. Record 1-minute audio
3. Check Settings → Verify `minSegmentDuration = 1.0s`
4. Verify max 2 speakers detected

**Test 2.3: Podcast Preset**
1. Select "Podcast" preset
2. Record 1-minute audio
3. Check Settings → Verify `minSegmentDuration = 1.0s`
4. Verify max 4 speakers if multi-speaker audio

**Success Criteria**:
- ✅ All presets use `minSegmentDuration = 1.0s`
- ✅ No spurious short segments (< 1.0s)
- ✅ Speaker segmentation cleaner than previous version

---

### Test 3: Audio Format Compatibility
**Estimated Time**: 15 minutes
**Objective**: Verify ANE works with different audio inputs

**Test 3.1: Built-in Microphone**
1. Switch to built-in mic (System Settings → Sound)
2. Record 30-second clip
3. Check console for "FastPath" hits (should be high)

**Test 3.2: Bluetooth Headset** (if available)
1. Connect Bluetooth audio device
2. Record 30-second clip
3. Check console for ANE conversion (48kHz → 16kHz)
4. Verify `ANE Success ≥ 95%`

**Test 3.3: USB Microphone** (if available)
1. Connect USB microphone
2. Record 30-second clip
3. Check console for ANE conversion (44.1kHz → 16kHz)
4. Verify `ANE Success ≥ 95%`

**Success Criteria**:
- ✅ All audio formats produce correct transcription
- ✅ No format-related crashes
- ✅ ANE handles conversions correctly
- ✅ Built-in mic uses fast path (already 16kHz)

---

### Test 4: Performance Comparison (Recommended)
**Estimated Time**: 30 minutes
**Objective**: Measure actual ANE performance improvement

**Baseline Test (ANE DISABLED)**:
1. Edit `Scribe/Helpers/FeatureFlags.swift`:
   ```swift
   static let useANEMemoryOptimization = false
   ```
2. Rebuild app (⌘B)
3. Launch app
4. Record 5-minute audio
5. Note final Console metrics:
   - Avg time: ____ ms
   - Total conversions: ____

**ANE Test (ANE ENABLED)**:
1. Edit `Scribe/Helpers/FeatureFlags.swift`:
   ```swift
   static let useANEMemoryOptimization = true
   ```
2. Rebuild app (⌘B)
3. Launch app
4. Record same 5-minute audio (or similar length)
5. Note final Console metrics:
   - Avg time: ____ ms
   - Total conversions: ____
   - ANE Success: ____%
   - Fallbacks: ____

**Calculate Improvement**:
```
Improvement % = (Baseline Avg - ANE Avg) / Baseline Avg × 100%
Target: 10-15% improvement
```

**Success Criteria**:
- ✅ ANE average time ≥ 10% faster
- ✅ ANE success rate ≥ 95%
- ✅ Transcription quality unchanged
- ✅ Speaker attribution unchanged

---

### Test 5: Stability - 30 Minute Stress Test (Optional)
**Estimated Time**: 45 minutes
**Objective**: Validate long-term stability

**Steps**:
1. Launch Activity Monitor (monitor memory)
2. Start 30-minute recording (podcast, meeting, etc.)
3. Monitor Console every 5 minutes for:
   - ANE success rate trends
   - Memory usage (should stabilize)
   - Warnings/errors

**Success Criteria**:
- ✅ Recording completes without crash
- ✅ ANE success rate stays ≥ 95%
- ✅ Memory doesn't grow continuously
- ✅ No "Slow conversion" warnings (>50ms)
- ✅ Transcription quality maintained throughout

**Expected Console Output** (every 100 conversions):
```
[ANE Metrics] Conversions: 100, Avg: 2.5ms, ANE Success: 98.0%, Fallbacks: 2
[ANE Metrics] Conversions: 200, Avg: 2.6ms, ANE Success: 97.5%, Fallbacks: 5
[ANE Metrics] Conversions: 300, Avg: 2.5ms, ANE Success: 97.3%, Fallbacks: 8
...
[ANE Metrics] Conversions: 3000, Avg: 2.6ms, ANE Success: 96.8%, Fallbacks: 96
```

---

## 🔍 What to Look For

### ✅ Good Signs
- ANE metrics appearing in Console
- ANE Success rate ≥ 95%
- Average conversion time 2-3ms
- Fallback rate < 5%
- Clean speaker segmentation (no segments < 1.0s)
- Transcription quality excellent

### ⚠️ Warning Signs
- ANE Success rate < 90% → Check alignment validation
- Average conversion time > 5ms → May indicate issue
- Frequent fallbacks (>10%) → Investigate error logs
- Crashes during recording → Disable ANE, report issue
- Memory warnings → Check for leaks

### ❌ Failure Conditions
- Crashes during normal use
- Transcription missing or corrupted
- ANE success rate < 80%
- Memory leaks (continuous growth)
- Performance worse than baseline

---

## 🚨 Rollback Procedure

### If Issues Detected

**Quick Disable (Instant)**:
```swift
// Edit: Scribe/Helpers/FeatureFlags.swift
static let useANEMemoryOptimization = false
```
Rebuild (⌘B) → ANE optimization disabled

**Reduce Logging (If Console Spam)**:
```swift
static let logANEMetrics = false
static let validateMemoryAlignment = false
```

**Full Rollback** (if needed):
1. Revert `DiarizationManager.swift` changes
2. Remove ANE files
3. Remove `FeatureFlags.swift`
4. Rebuild

---

## 📊 Test Results Template

**Tester Name**: ______________
**Test Date**: ______________
**macOS Version**: ______________
**Hardware**: ______________

| Test | Status | Notes | Metrics |
|------|--------|-------|---------|
| 1. 30s Recording | ⬜ PASS / ⬜ FAIL | | ANE: __%, Avg: __ms |
| 2.1 Meeting Preset | ⬜ PASS / ⬜ FAIL | | |
| 2.2 Interview Preset | ⬜ PASS / ⬜ FAIL | | |
| 2.3 Podcast Preset | ⬜ PASS / ⬜ FAIL | | |
| 3.1 Built-in Mic | ⬜ PASS / ⬜ FAIL | | FastPath: __ |
| 3.2 Bluetooth | ⬜ PASS / ⬜ FAIL | | ANE: __% |
| 3.3 USB Mic | ⬜ PASS / ⬜ FAIL | | ANE: __% |
| 4. Performance | ⬜ PASS / ⬜ FAIL | | Improvement: __% |
| 5. 30min Stress | ⬜ PASS / ⬜ FAIL | | ANE: __%, Memory: __ MB |

**Overall Result**: ⬜ PASS / ⬜ FAIL
**Recommendation**: ⬜ Approve / ⬜ Fix Issues / ⬜ Rollback

**Notes**:
_____________________________________________________
_____________________________________________________
_____________________________________________________

---

## 📝 Reporting Issues

If you encounter issues during testing:

1. **Console Logs**: Copy relevant Console output
2. **Crash Reports**: Check `~/Library/Logs/DiagnosticReports/`
3. **ANE Metrics**: Note final success rate and fallback count
4. **Steps to Reproduce**: Document exact steps that caused issue
5. **Expected vs Actual**: What should have happened vs what actually happened

**Report Format**:
```
Issue: [Brief description]
Test Case: [Which test]
Expected: [What should happen]
Actual: [What actually happened]
Console Output: [Paste relevant logs]
Reproducible: [Yes/No]
```

---

## 🎯 Success Criteria Summary

**MUST PASS** (Critical):
- ✅ No crashes during normal use
- ✅ Transcription works correctly
- ✅ ANE success rate ≥ 90%
- ✅ All 21 automated tests pass

**SHOULD PASS** (Important):
- ✅ ANE performance improvement ≥ 10%
- ✅ 30-minute stress test completes
- ✅ All presets work correctly
- ✅ Speaker segmentation improved

**NICE TO HAVE** (Optional):
- ✅ ANE success rate ≥ 95%
- ✅ Performance improvement ≥ 15%
- ✅ Zero fallbacks
- ✅ All audio formats tested

---

## 🚀 Next Steps After Testing

1. **If Tests Pass**: Proceed with documentation updates
2. **If Minor Issues**: Fix and retest
3. **If Major Issues**: Rollback and investigate

---

**Questions?** Check the troubleshooting section or disable ANE via FeatureFlags.
