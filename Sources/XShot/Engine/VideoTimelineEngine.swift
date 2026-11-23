@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// A single non-destructive segment referencing `[sourceStart, sourceEnd]` in the original recording
/// with an optional playback speed multiplier (`0.25x` slow-mo up to `4.0x` fast-forward).
public struct VideoClipSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var sourceStart: Double
    public var sourceEnd: Double
    public var speed: Double

    public init(
        id: UUID = UUID(),
        sourceStart: Double,
        sourceEnd: Double,
        speed: Double = 1.0
    ) {
        self.id = id
        self.sourceStart = max(0, sourceStart)
        self.sourceEnd = max(self.sourceStart + 0.05, sourceEnd)
        self.speed = min(max(speed, 0.25), 4.0)
    }

    public var sourceDuration: Double {
        max(0.05, sourceEnd - sourceStart)
    }

    public var outputDuration: Double {
        sourceDuration / min(max(speed, 0.25), 4.0)
    }
}

/// Optional smooth fade-in / fade-out applied to both video and audio at the start/end of the edited timeline.
public struct VideoFadeConfig: Codable, Equatable, Sendable {
    public var fadeInDuration: Double
    public var fadeOutDuration: Double

    public static let none = VideoFadeConfig(fadeInDuration: 0, fadeOutDuration: 0)

    public init(fadeInDuration: Double = 0, fadeOutDuration: Double = 0) {
        self.fadeInDuration = min(max(fadeInDuration, 0), 2.0)
        self.fadeOutDuration = min(max(fadeOutDuration, 0), 2.0)
    }
}

/// Undo/redo state snapshot for non-destructive timeline edits in XShot Studio.
public struct VideoTimelineSnapshot: Equatable, Sendable {
    public var clipSegments: [VideoClipSegment]
    public var zoomSegments: [ZoomSegment]

    public init(clipSegments: [VideoClipSegment], zoomSegments: [ZoomSegment]) {
        self.clipSegments = clipSegments
        self.zoomSegments = zoomSegments
    }
}

public struct OutputTimeMapping: Equatable, Sendable {
    public let sourceTime: Double
    public let clipIndex: Int
    public let clipID: UUID
    public let speed: Double
}

/// Pure, deterministic mapper between edited output timeline time and original source recording time,
/// plus non-destructive clip split/delete/trim operations and pitch-preserving AVComposition audio builder.
public enum VideoTimelineMapper {
    public static let speedPresets: [Double] = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]

    /// Normalizes and clamps clip segments against `assetDuration`, falling back to `fallbackStart...fallbackEnd`
    /// when `clips` is empty. Guarantees chronological non-overlapping order and valid durations.
    public static func normalizedClips(
        _ clips: [VideoClipSegment],
        fallbackStart: Double,
        fallbackEnd: Double,
        assetDuration: Double
    ) -> [VideoClipSegment] {
        let safeAssetDur = max(0.1, assetDuration)
        let sourceList: [VideoClipSegment]
        if clips.isEmpty {
            let s = min(max(0, fallbackStart), max(0, safeAssetDur - 0.1))
            let e = max(s + 0.1, min(fallbackEnd, safeAssetDur))
            sourceList = [VideoClipSegment(sourceStart: s, sourceEnd: e, speed: 1.0)]
        } else {
            sourceList = clips.sorted { $0.sourceStart < $1.sourceStart }
        }

        var result: [VideoClipSegment] = []
        var minStart = 0.0
        for raw in sourceList {
            let s = min(max(raw.sourceStart, minStart), safeAssetDur)
            let e = min(max(raw.sourceEnd, s), safeAssetDur)
            guard e - s >= 0.05 else { continue }
            result.append(VideoClipSegment(
                id: raw.id,
                sourceStart: s,
                sourceEnd: e,
                speed: min(max(raw.speed, 0.25), 4.0)
            ))
            minStart = e
        }

        if result.isEmpty {
            return [VideoClipSegment(sourceStart: 0, sourceEnd: safeAssetDur, speed: 1.0)]
        }
        return result
    }

    public static func totalOutputDuration(of clips: [VideoClipSegment]) -> Double {
        max(0.05, clips.reduce(0.0) { $0 + $1.outputDuration })
    }

    /// Returns the `[start, end]` range in output-timeline seconds for each clip.
    public static func outputRanges(of clips: [VideoClipSegment]) -> [(clip: VideoClipSegment, outputStart: Double, outputEnd: Double)] {
        var cursor = 0.0
        var out: [(VideoClipSegment, Double, Double)] = []
        out.reserveCapacity(clips.count)
        for clip in clips {
            let dur = clip.outputDuration
            out.append((clip, cursor, cursor + dur))
            cursor += dur
        }
        return out
    }

    /// Maps an output-timeline timestamp `t` (in `0...totalOutputDuration`) to the exact timestamp in the raw source video.
    public static func mapOutputTimeToSource(_ outputTime: Double, clips: [VideoClipSegment]) -> OutputTimeMapping? {
        guard !clips.isEmpty else { return nil }
        let t = max(0, outputTime)
        var cursor = 0.0
        for (idx, clip) in clips.enumerated() {
            let outDur = clip.outputDuration
            let isLast = (idx == clips.count - 1)
            if t <= cursor + outDur || isLast {
                let localOut = min(max(0, t - cursor), outDur)
                let srcTime = min(clip.sourceEnd, clip.sourceStart + localOut * clip.speed)
                return OutputTimeMapping(sourceTime: srcTime, clipIndex: idx, clipID: clip.id, speed: clip.speed)
            }
            cursor += outDur
        }
        if let last = clips.last {
            return OutputTimeMapping(sourceTime: last.sourceEnd, clipIndex: clips.count - 1, clipID: last.id, speed: last.speed)
        }
        return nil
    }

    /// Maps a source-recording timestamp to the edited output timeline (or `nil` if that moment was cut out).
    public static func mapSourceTimeToOutput(_ sourceTime: Double, clips: [VideoClipSegment]) -> Double? {
        var cursor = 0.0
        for clip in clips {
            if sourceTime >= clip.sourceStart && sourceTime <= clip.sourceEnd {
                return cursor + (sourceTime - clip.sourceStart) / clip.speed
            }
            cursor += clip.outputDuration
        }
        return nil
    }

    /// Maps a source-space time interval `[sourceStart, sourceEnd]` onto the output timeline (clamping to kept clips).
    public static func mapSourceIntervalToOutput(
        sourceStart: Double,
        sourceEnd: Double,
        clips: [VideoClipSegment]
    ) -> (start: Double, end: Double)? {
        var minOut: Double?
        var maxOut: Double?
        var cursor = 0.0
        for clip in clips {
            let overlapStart = max(sourceStart, clip.sourceStart)
            let overlapEnd = min(sourceEnd, clip.sourceEnd)
            if overlapEnd > overlapStart {
                let oStart = cursor + (overlapStart - clip.sourceStart) / clip.speed
                let oEnd = cursor + (overlapEnd - clip.sourceStart) / clip.speed
                minOut = minOut.map { min($0, oStart) } ?? oStart
                maxOut = maxOut.map { max($0, oEnd) } ?? oEnd
            }
            cursor += clip.outputDuration
        }
        guard let s = minOut, let e = maxOut, e > s else { return nil }
        return (s, e)
    }

    /// Splits the clip containing `outputTime` into two clips at the exact playhead position.
    public static func splitClip(
        _ clips: [VideoClipSegment],
        atOutputTime outputTime: Double,
        minSourceDuration: Double = 0.20
    ) -> (clips: [VideoClipSegment], rightClipID: UUID)? {
        guard let mapping = mapOutputTimeToSource(outputTime, clips: clips) else { return nil }
        let idx = mapping.clipIndex
        let clip = clips[idx]
        let splitSource = mapping.sourceTime

        guard (splitSource - clip.sourceStart) >= minSourceDuration,
              (clip.sourceEnd - splitSource) >= minSourceDuration else {
            return nil
        }

        let left = VideoClipSegment(
            id: clip.id,
            sourceStart: clip.sourceStart,
            sourceEnd: splitSource,
            speed: clip.speed
        )
        let right = VideoClipSegment(
            sourceStart: splitSource,
            sourceEnd: clip.sourceEnd,
            speed: clip.speed
        )
        var updated = clips
        updated.replaceSubrange(idx...idx, with: [left, right])
        return (updated, right.id)
    }

    /// Removes the clip with `id`, keeping at least 1 clip in the timeline.
    public static func deleteClip(_ clips: [VideoClipSegment], id: UUID) -> [VideoClipSegment]? {
        guard clips.count > 1, let idx = clips.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var updated = clips
        updated.remove(at: idx)
        return updated
    }

    /// Trims the timeline head (`isStart = true`) or tail (`isStart = false`) to the current `outputTime` (In/Out shortcuts).
    public static func trimToPlayhead(
        _ clips: [VideoClipSegment],
        atOutputTime outputTime: Double,
        isStart: Bool,
        minSourceDuration: Double = 0.20
    ) -> [VideoClipSegment]? {
        guard let mapping = mapOutputTimeToSource(outputTime, clips: clips) else { return nil }
        let idx = mapping.clipIndex
        let splitSrc = mapping.sourceTime
        var updated: [VideoClipSegment]

        if isStart {
            var first = clips[idx]
            let remainingInFirst = first.sourceEnd - splitSrc
            if remainingInFirst >= minSourceDuration {
                first.sourceStart = splitSrc
                updated = [first] + Array(clips[(idx + 1)...])
            } else if idx + 1 < clips.count {
                updated = Array(clips[(idx + 1)...])
            } else {
                return nil
            }
        } else {
            var last = clips[idx]
            let remainingInLast = splitSrc - last.sourceStart
            if remainingInLast >= minSourceDuration {
                last.sourceEnd = splitSrc
                updated = Array(clips[..<idx]) + [last]
            } else if idx > 0 {
                updated = Array(clips[..<idx])
            } else {
                return nil
            }
        }

        return updated.isEmpty ? nil : updated
    }

    /// Returns true if `clips[index]` and `clips[index + 1]` are contiguous in source time and can be glued back together.
    public static func canMergeWithNext(_ clips: [VideoClipSegment], at index: Int) -> Bool {
        guard index >= 0, index + 1 < clips.count else { return false }
        return abs(clips[index].sourceEnd - clips[index + 1].sourceStart) <= 0.025
    }

    /// Merges two contiguous adjacent clips (`index` and `index + 1`) back into a single clip.
    public static func mergeAdjacentClips(_ clips: [VideoClipSegment], at index: Int) -> [VideoClipSegment]? {
        guard canMergeWithNext(clips, at: index) else { return nil }
        let left = clips[index]
        let right = clips[index + 1]
        let merged = VideoClipSegment(
            id: left.id,
            sourceStart: left.sourceStart,
            sourceEnd: right.sourceEnd,
            speed: left.speed
        )
        var updated = clips
        updated.replaceSubrange(index...(index + 1), with: [merged])
        return updated
    }

    /// Magnetic snapping helper: snaps `rawTime` to the nearest candidate within `thresholdSeconds`.
    public static func snapOutputTime(
        _ rawTime: Double,
        candidates: [Double],
        thresholdSeconds: Double
    ) -> (time: Double, snapped: Bool) {
        guard thresholdSeconds > 0 else { return (rawTime, false) }
        var bestDist = thresholdSeconds
        var bestTarget: Double?
        for c in candidates {
            let d = abs(c - rawTime)
            if d <= bestDist {
                bestDist = d
                bestTarget = c
            }
        }
        if let target = bestTarget {
            return (target, true)
        }
        return (rawTime, false)
    }

    /// Returns the safe `[minStart, maxEnd]` source-time bounds for a zoom segment so resizing/moving never overlaps neighbors.
    public static func nonOverlappingZoomBounds(
        for segmentID: UUID,
        in segments: [ZoomSegment],
        totalSourceDuration: Double,
        minGap: Double = 0.04
    ) -> (minStart: Double, maxEnd: Double) {
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        guard let idx = sorted.firstIndex(where: { $0.id == segmentID }) else {
            return (0, max(0.4, totalSourceDuration))
        }
        let minStart = idx > 0 ? min(totalSourceDuration, sorted[idx - 1].endTime + minGap) : 0
        let maxEnd = idx + 1 < sorted.count ? max(minStart, sorted[idx + 1].startTime - minGap) : totalSourceDuration
        return (minStart, maxEnd)
    }

    /// Computes smooth quintic fade-in / fade-out opacity multiplier (`0...1`) at `outputTime`.
    public static func fadeOpacity(atOutputTime t: Double, totalDuration: Double, fade: VideoFadeConfig) -> Double {
        let safeDur = max(0.05, totalDuration)
        var alpha = 1.0
        if fade.fadeInDuration > 0.01 {
            let d = min(fade.fadeInDuration, safeDur * 0.45)
            if t < d {
                alpha = min(alpha, AutoZoomEngine.smootherstep(t / max(0.001, d)))
            }
        }
        if fade.fadeOutDuration > 0.01 {
            let d = min(fade.fadeOutDuration, safeDur * 0.45)
            let remaining = safeDur - t
            if remaining < d {
                alpha = min(alpha, AutoZoomEngine.smootherstep(remaining / max(0.001, d)))
            }
        }
        return min(max(alpha, 0), 1)
    }

    /// Builds a sample-accurate `AVMutableComposition` containing all audio tracks stitched across `clips`,
    /// time-scaled per clip speed, plus an `AVMutableAudioMix` applying gain & smooth fade-in / fade-out.
    /// Used by BOTH Studio live audio playback AND final MP4 export for 1:1 WYSIWYG A/V synchronization.
    public static func buildAudioComposition(
        from asset: AVAsset,
        clips: [VideoClipSegment],
        fade: VideoFadeConfig,
        volume: Float
    ) async throws -> (composition: AVMutableComposition, audioMix: AVMutableAudioMix?)? {
        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !sourceAudioTracks.isEmpty, !clips.isEmpty else { return nil }

        let composition = AVMutableComposition()
        let timescale: CMTimeScale = 48_000
        var mixParams: [AVMutableAudioMixInputParameters] = []
        var totalCompDuration: CMTime = .zero

        for srcTrack in sourceAudioTracks {
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            var insertCursor: CMTime = .zero
            for clip in clips {
                let srcStart = CMTime(seconds: clip.sourceStart, preferredTimescale: timescale)
                let srcDur = CMTime(seconds: clip.sourceDuration, preferredTimescale: timescale)
                guard srcDur.seconds > 0.01 else { continue }

                let range = CMTimeRange(start: srcStart, duration: srcDur)
                do {
                    try compTrack.insertTimeRange(range, of: srcTrack, at: insertCursor)
                    let targetDur = CMTime(seconds: clip.outputDuration, preferredTimescale: timescale)
                    if abs(clip.speed - 1.0) > 0.005 {
                        compTrack.scaleTimeRange(
                            CMTimeRange(start: insertCursor, duration: srcDur),
                            toDuration: targetDur
                        )
                    }
                    insertCursor = CMTimeAdd(insertCursor, targetDur)
                } catch {
                    continue
                }
            }
            if insertCursor > totalCompDuration {
                totalCompDuration = insertCursor
            }

            let params = AVMutableAudioMixInputParameters(track: compTrack)
            params.audioTimePitchAlgorithm = .timeDomain
            let clampedVol = min(max(volume, 0.0), 2.0)
            params.setVolume(clampedVol, at: .zero)

            let totalSec = totalCompDuration.seconds
            if totalSec > 0.05 {
                if fade.fadeInDuration > 0.01 {
                    let d = min(fade.fadeInDuration, totalSec * 0.45)
                    params.setVolumeRamp(
                        fromStartVolume: 0.0,
                        toEndVolume: clampedVol,
                        timeRange: CMTimeRange(
                            start: .zero,
                            duration: CMTime(seconds: d, preferredTimescale: timescale)
                        )
                    )
                }
                if fade.fadeOutDuration > 0.01 {
                    let d = min(fade.fadeOutDuration, totalSec * 0.45)
                    let startOut = max(0, totalSec - d)
                    params.setVolumeRamp(
                        fromStartVolume: clampedVol,
                        toEndVolume: 0.0,
                        timeRange: CMTimeRange(
                            start: CMTime(seconds: startOut, preferredTimescale: timescale),
                            duration: CMTime(seconds: d, preferredTimescale: timescale)
                        )
                    )
                }
            }
            mixParams.append(params)
        }

        guard totalCompDuration.seconds > 0.01 else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = mixParams
        return (composition, mix)
    }
}

/// Fast native AVFoundation audio waveform peak extractor for visualizing speech/pauses on the Studio timeline.
public enum AudioWaveformExtractor {
    /// Decodes audio tracks into `bucketCount` normalized peak amplitudes in `0.0...1.0`.
    public static func extractPeaks(from url: URL, bucketCount: Int = 320) async -> [Float] {
        let buckets = max(24, min(1000, bucketCount))
        let asset = AVURLAsset(url: url)
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
              !audioTracks.isEmpty else {
            return []
        }

        let durationSec = (try? await asset.load(.duration).seconds) ?? 0
        guard durationSec > 0.05 else { return [] }

        return await Task.detached(priority: .utility) {
            guard let reader = try? AVAssetReader(asset: asset) else { return [] }
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { return [] }

            let expectedSamples = max(1, Int(durationSec * 16_000.0))
            let samplesPerBucket = max(1, expectedSamples / buckets)
            var rawPeaks = [Float](repeating: 0, count: buckets)
            var sampleCursor = 0

            while let sampleBuffer = output.copyNextSampleBuffer() {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                var lengthAtOffset: Int = 0
                var totalLength: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: &lengthAtOffset,
                    totalLengthOut: &totalLength,
                    dataPointerOut: &dataPointer
                )
                guard status == kCMBlockBufferNoErr, let ptr = dataPointer, totalLength >= 2 else { continue }
                let count = totalLength / MemoryLayout<Int16>.size
                ptr.withMemoryRebound(to: Int16.self, capacity: count) { int16Ptr in
                    let strideStep = max(1, samplesPerBucket / 64)
                    var i = 0
                    while i < count {
                        let globalIdx = sampleCursor + i
                        let bucketIdx = min(buckets - 1, globalIdx / samplesPerBucket)
                        let sampleVal = abs(Float(int16Ptr[i])) / 32768.0
                        if sampleVal > rawPeaks[bucketIdx] {
                            rawPeaks[bucketIdx] = sampleVal
                        }
                        i += strideStep
                    }
                }
                sampleCursor += count
            }

            let maxPeak = rawPeaks.max() ?? 0
            let normDiv = max(0.10, maxPeak)
            return rawPeaks.map { min(1.0, pow($0 / normDiv, 0.72)) }
        }.value
    }
}
