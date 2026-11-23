import Foundation
import XCTest
@testable import XShot

final class VideoTimelineEngineTests: XCTestCase {
    func testSplitDeleteAndTrimToPlayheadOperations() throws {
        let initial = [VideoClipSegment(sourceStart: 0, sourceEnd: 10, speed: 1.0)]

        // 1. Split at 3.0s -> [0...3], [3...10]
        let split1 = try XCTUnwrap(VideoTimelineMapper.splitClip(initial, atOutputTime: 3.0))
        XCTAssertEqual(split1.clips.count, 2)
        XCTAssertEqual(split1.clips[0].sourceStart, 0, accuracy: 0.001)
        XCTAssertEqual(split1.clips[0].sourceEnd, 3.0, accuracy: 0.001)
        XCTAssertEqual(split1.clips[1].sourceStart, 3.0, accuracy: 0.001)
        XCTAssertEqual(split1.clips[1].sourceEnd, 10.0, accuracy: 0.001)

        // 2. Split second clip at 6.0s -> [0...3], [3...6], [6...10]
        let split2 = try XCTUnwrap(VideoTimelineMapper.splitClip(split1.clips, atOutputTime: 6.0))
        XCTAssertEqual(split2.clips.count, 3)

        // 3. Delete middle boring pause [3...6] -> [0...3], [6...10] (output duration = 7.0s)
        let afterDelete = try XCTUnwrap(VideoTimelineMapper.deleteClip(split2.clips, id: split2.clips[1].id))
        XCTAssertEqual(afterDelete.count, 2)
        XCTAssertEqual(VideoTimelineMapper.totalOutputDuration(of: afterDelete), 7.0, accuracy: 0.001)

        // 4. Cannot delete the last remaining clip
        let oneClip = try XCTUnwrap(VideoTimelineMapper.deleteClip(afterDelete, id: afterDelete[0].id))
        XCTAssertEqual(oneClip.count, 1)
        XCTAssertNil(VideoTimelineMapper.deleteClip(oneClip, id: oneClip[0].id))

        // 5. Trim In / Out to playhead on multi-clip timeline
        let trimmedIn = try XCTUnwrap(VideoTimelineMapper.trimToPlayhead(afterDelete, atOutputTime: 1.5, isStart: true))
        XCTAssertEqual(trimmedIn.count, 2)
        XCTAssertEqual(trimmedIn[0].sourceStart, 1.5, accuracy: 0.001)
        XCTAssertEqual(VideoTimelineMapper.totalOutputDuration(of: trimmedIn), 5.5, accuracy: 0.001)

        let trimmedOut = try XCTUnwrap(VideoTimelineMapper.trimToPlayhead(trimmedIn, atOutputTime: 3.5, isStart: false))
        XCTAssertEqual(trimmedOut.count, 2)
        XCTAssertEqual(trimmedOut[1].sourceEnd, 8.0, accuracy: 0.001)
        XCTAssertEqual(VideoTimelineMapper.totalOutputDuration(of: trimmedOut), 3.5, accuracy: 0.001)
    }

    func testOutputToSourceMappingWithMiddleCutAndMixedSpeeds() throws {
        // Clip 1: 0..4s @ 2.0x -> output 0..2s
        // Cut:    4..6s (deleted!)
        // Clip 2: 6..8s @ 0.5x -> output 2..6s
        let clips = [
            VideoClipSegment(sourceStart: 0, sourceEnd: 4, speed: 2.0),
            VideoClipSegment(sourceStart: 6, sourceEnd: 8, speed: 0.5)
        ]

        XCTAssertEqual(VideoTimelineMapper.totalOutputDuration(of: clips), 6.0, accuracy: 0.001)

        // Midpoint of clip 1 (output 1.0s -> source 2.0s)
        let m1 = try XCTUnwrap(VideoTimelineMapper.mapOutputTimeToSource(1.0, clips: clips))
        XCTAssertEqual(m1.sourceTime, 2.0, accuracy: 0.001)
        XCTAssertEqual(m1.clipIndex, 0)
        XCTAssertEqual(m1.speed, 2.0, accuracy: 0.001)

        // Midpoint of clip 2 (output 4.0s -> source 7.0s)
        let m2 = try XCTUnwrap(VideoTimelineMapper.mapOutputTimeToSource(4.0, clips: clips))
        XCTAssertEqual(m2.sourceTime, 7.0, accuracy: 0.001)
        XCTAssertEqual(m2.clipIndex, 1)
        XCTAssertEqual(m2.speed, 0.5, accuracy: 0.001)

        // Deleted middle source time returns nil
        XCTAssertNil(VideoTimelineMapper.mapSourceTimeToOutput(5.0, clips: clips))

        // Kept source times round-trip cleanly
        XCTAssertEqual(VideoTimelineMapper.mapSourceTimeToOutput(2.0, clips: clips) ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(VideoTimelineMapper.mapSourceTimeToOutput(7.0, clips: clips) ?? -1, 4.0, accuracy: 0.001)

        // Zoom segment spanning [3.0, 7.0] maps cleanly across the cut onto [1.5, 4.0]
        let mappedZoom = try XCTUnwrap(VideoTimelineMapper.mapSourceIntervalToOutput(sourceStart: 3.0, sourceEnd: 7.0, clips: clips))
        XCTAssertEqual(mappedZoom.start, 1.5, accuracy: 0.001)
        XCTAssertEqual(mappedZoom.end, 4.0, accuracy: 0.001)
    }

    func testFadeOpacityCurveBounds() {
        let fade = VideoFadeConfig(fadeInDuration: 1.0, fadeOutDuration: 1.0)
        XCTAssertEqual(VideoTimelineMapper.fadeOpacity(atOutputTime: 0.0, totalDuration: 5.0, fade: fade), 0.0, accuracy: 0.001)
        XCTAssertEqual(VideoTimelineMapper.fadeOpacity(atOutputTime: 0.5, totalDuration: 5.0, fade: fade), 0.5, accuracy: 0.01)
        XCTAssertEqual(VideoTimelineMapper.fadeOpacity(atOutputTime: 2.5, totalDuration: 5.0, fade: fade), 1.0, accuracy: 0.001)
        XCTAssertEqual(VideoTimelineMapper.fadeOpacity(atOutputTime: 4.5, totalDuration: 5.0, fade: fade), 0.5, accuracy: 0.01)
        XCTAssertEqual(VideoTimelineMapper.fadeOpacity(atOutputTime: 5.0, totalDuration: 5.0, fade: fade), 0.0, accuracy: 0.001)
    }

    func testMergeAdjacentClipsMagneticSnapAndNonOverlappingZoomBounds() throws {
        // 1. Merge contiguous clips vs reject non-contiguous clips after a middle delete
        let contiguous = [
            VideoClipSegment(sourceStart: 0.0, sourceEnd: 3.0, speed: 1.5),
            VideoClipSegment(sourceStart: 3.0, sourceEnd: 7.0, speed: 1.0)
        ]
        XCTAssertTrue(VideoTimelineMapper.canMergeWithNext(contiguous, at: 0))
        let merged = try XCTUnwrap(VideoTimelineMapper.mergeAdjacentClips(contiguous, at: 0))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sourceStart, 0.0, accuracy: 0.001)
        XCTAssertEqual(merged[0].sourceEnd, 7.0, accuracy: 0.001)
        XCTAssertEqual(merged[0].speed, 1.5, accuracy: 0.001)

        let gapped = [
            VideoClipSegment(sourceStart: 0.0, sourceEnd: 2.0, speed: 1.0),
            VideoClipSegment(sourceStart: 4.5, sourceEnd: 7.0, speed: 1.0)
        ]
        XCTAssertFalse(VideoTimelineMapper.canMergeWithNext(gapped, at: 0))
        XCTAssertNil(VideoTimelineMapper.mergeAdjacentClips(gapped, at: 0))

        // 2. Magnetic snapping hits nearest candidate inside threshold and leaves free values untouched
        let snapHit = VideoTimelineMapper.snapOutputTime(2.96, candidates: [0.0, 3.0, 6.0], thresholdSeconds: 0.12)
        XCTAssertTrue(snapHit.snapped)
        XCTAssertEqual(snapHit.time, 3.0, accuracy: 0.0001)

        let snapMiss = VideoTimelineMapper.snapOutputTime(2.40, candidates: [0.0, 3.0, 6.0], thresholdSeconds: 0.12)
        XCTAssertFalse(snapMiss.snapped)
        XCTAssertEqual(snapMiss.time, 2.40, accuracy: 0.0001)

        // 3. Non-overlapping zoom bounds clamp middle segment tightly between its neighbors
        let z1 = ZoomSegment(startTime: 1.0, endTime: 2.5, focusX: 0.5, focusY: 0.5)
        let z2 = ZoomSegment(startTime: 4.0, endTime: 6.0, focusX: 0.5, focusY: 0.5)
        let z3 = ZoomSegment(startTime: 7.5, endTime: 9.0, focusX: 0.5, focusY: 0.5)
        let bounds = VideoTimelineMapper.nonOverlappingZoomBounds(
            for: z2.id,
            in: [z1, z2, z3],
            totalSourceDuration: 10.0,
            minGap: 0.05
        )
        XCTAssertEqual(bounds.minStart, 2.55, accuracy: 0.001)
        XCTAssertEqual(bounds.maxEnd, 7.45, accuracy: 0.001)
    }
}
