import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import XCTest
@testable import XShot

private final class LockedDouble: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func set(_ newValue: Double) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Double { lock.lock(); defer { lock.unlock() }; return value }
}

final class VideoCompositorExporterTests: XCTestCase {
    /// Generates a synthetic 1-second 60fps 960x600 test MOV using AVAssetWriter so we can verify the full Metal GPU compositing & X-MP4 + GIF export pipeline end-to-end!
    private func createSyntheticSourceVideo(at url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let w = 960
        let h = 600
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let fps = 30
        let totalFrames = 30 // 1.0 second

        for i in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var pbOpt: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pbOpt)
            let pb = pbOpt!
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pb),
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                space: cs,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) {
                ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.11, blue: 0.18, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                let bx = CGFloat(100 + i * 18)
                ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.72, blue: 0.51, alpha: 1))
                ctx.fill(CGRect(x: bx, y: 200, width: 140, height: 140))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            let pts = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            XCTAssertTrue(adaptor.append(pb, withPresentationTime: pts))
        }

        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    func testEndToEndXOptimizedMP4AndGIFExport() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let rawURL = tmpDir.appendingPathComponent("xshot-raw-\(UUID().uuidString).mov")
        let mp4URL = tmpDir.appendingPathComponent("xshot-out-\(UUID().uuidString).mp4")
        let gifURL = tmpDir.appendingPathComponent("xshot-out-\(UUID().uuidString).gif")
        defer {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: mp4URL)
            try? FileManager.default.removeItem(at: gifURL)
        }

        try await createSyntheticSourceVideo(at: rawURL)

        let telemetry = RecordingTelemetry(
            captureQuartzRect: CGRect(x: 0, y: 0, width: 480, height: 300),
            cursorSamples: [
                CursorSample(time: 0.0, x: 0.2, y: 0.3, isInside: true, isPressed: false),
                CursorSample(time: 0.5, x: 0.6, y: 0.5, isInside: true, isPressed: true),
                CursorSample(time: 1.0, x: 0.7, y: 0.6, isInside: true, isPressed: false)
            ],
            clickEvents: [ClickEvent(time: 0.5, x: 0.6, y: 0.5)],
            keystrokeEvents: [KeystrokeEvent(time: 0.3, text: "⌘⇧7")],
            duration: 1.0,
            hidNativeCursor: true
        )

        let zooms = AutoZoomEngine.generateAutoZoomSegments(clicks: telemetry.clickEvents, duration: 1.0)
        let exporter = VideoCompositorExporter()

        // 1. Export X-Optimized 1080p 60fps MP4
        let mp4Options = VideoCompositeOptions(
            style: .defaultVideo,
            zoomSegments: zooms,
            enableAutoZoom: true,
            enableSmoothCursor: true,
            enableClickRipples: true,
            enableKeystrokes: true,
            cursorScale: 1.3,
            trimStart: 0.0,
            trimEnd: 0.9,
            exportPreset: .xOptimal1080p60,
            includeAudio: false,
            telemetry: telemetry
        )

        let progressBox = LockedDouble()
        let exportedMP4 = try await exporter.exportVideo(
            sourceURL: rawURL,
            outputURL: mp4URL,
            options: mp4Options,
            progressHandler: { p in progressBox.set(p) }
        )

        XCTAssertEqual(exportedMP4, mp4URL)
        XCTAssertEqual(progressBox.get(), 1.0, accuracy: 0.05)

        let outAsset = AVURLAsset(url: exportedMP4)
        let tracks = try await outAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let size = try await tracks[0].load(.naturalSize)
        XCTAssertEqual(Int(size.width) % 2, 0)
        XCTAssertEqual(Int(size.height) % 2, 0)
        XCTAssertEqual(Double(size.width) / Double(size.height), 16.0 / 9.0, accuracy: 0.02)
        let nominalFPS = try await tracks[0].load(.nominalFrameRate)
        XCTAssertGreaterThanOrEqual(nominalFPS, 58.0, "Exported MP4 must be smooth 60fps")

        // 2. Export Smooth 24fps GIF
        var gifOptions = mp4Options
        gifOptions.exportPreset = .gifSmooth
        gifOptions.trimEnd = 0.4
        let exportedGIF = try await exporter.exportVideo(
            sourceURL: rawURL,
            outputURL: gifURL,
            options: gifOptions,
            progressHandler: { _ in }
        )
        let gifAttrs = try FileManager.default.attributesOfItem(atPath: exportedGIF.path)
        XCTAssertGreaterThan((gifAttrs[.size] as? Int) ?? 0, 2_000)
    }

    func testMetalBakedOrientationAndHighSpeedExportBenchmark() async throws {
        // 1. Verify chrome bar sits at the TOP (not flipped upside-down by MTLTexture baking!)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let srcCtx = CGContext(
            data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Top half pure red, bottom half pure blue in CG coords (top = y >= 200)
        srcCtx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        srcCtx.fill(CGRect(x: 0, y: 0, width: 640, height: 200))
        srcCtx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        srcCtx.fill(CGRect(x: 0, y: 200, width: 640, height: 200))
        let srcCG = srcCtx.makeImage()!

        var style = BeautifyStyle.defaultVideo
        style.windowChrome = .macOSLight // Light bar at TOP
        style.padding = 40
        let exporter = VideoCompositorExporter()
        let opts = VideoCompositeOptions(
            style: style,
            enableAutoZoom: false,
            enableSmoothCursor: true,
            enableClickRipples: false,
            enableKeystrokes: false,
            trimStart: 0,
            trimEnd: 1.0,
            telemetry: RecordingTelemetry(
                cursorSamples: [CursorSample(time: 0, x: 0.5, y: 0.5, isInside: true)],
                duration: 1.0,
                hidNativeCursor: true
            )
        )
        let preview = exporter.renderPreviewFrame(
            sourceCGImage: srcCG,
            time: 0,
            options: opts,
            smoothedCursorPath: opts.telemetry.cursorSamples,
            maxPreviewEdge: 800
        )
        XCTAssertNotNil(preview)
        if let cg = preview {
            let rep = NSBitmapImageRep(cgImage: cg)
            // Sample upper content (row ~35% from top) -> red, lower content (row ~68% from top) -> blue
            let topColor = rep.colorAt(x: cg.width / 2, y: Int(Double(cg.height) * 0.35))!
            let botColor = rep.colorAt(x: cg.width / 2, y: Int(Double(cg.height) * 0.68))!
            XCTAssertGreaterThan(topColor.redComponent, 0.7, "Top half of video should remain red (not vertically flipped)")
            XCTAssertGreaterThan(botColor.blueComponent, 0.7, "Bottom half of video should remain blue (not vertically flipped)")

            // Also verify light macOS titlebar sits at the TOP edge of card (not flipped to bottom!)
            let layout = CoordinateConverter.computeCanvasLayout(
                sourceSize: CGSize(width: 640, height: 400),
                style: style,
                maxLongEdge: 800,
                evenDimensions: true
            )
            let chromeMidY = Int(layout.contentRect.minY - layout.chromeHeight / 2)
            let chromeSample = rep.colorAt(x: cg.width / 2, y: max(0, chromeMidY))!
            XCTAssertGreaterThan(chromeSample.redComponent, 0.85, "Light macOS chrome bar must be at TOP of card")
            XCTAssertGreaterThan(chromeSample.greenComponent, 0.85, "Light macOS chrome bar must be at TOP of card")
            XCTAssertGreaterThan(chromeSample.blueComponent, 0.85, "Light macOS chrome bar must be at TOP of card")
        }

        // 2. Benchmark 3-second 1080p60 export (180 frames)
        let tmpDir = FileManager.default.temporaryDirectory
        let rawURL = tmpDir.appendingPathComponent("xshot-bench-raw-\(UUID().uuidString).mov")
        let mp4URL = tmpDir.appendingPathComponent("xshot-bench-out-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: mp4URL)
        }
        try await createSyntheticSourceVideo(at: rawURL)

        let t0 = ProcessInfo.processInfo.systemUptime
        let benchOpts = VideoCompositeOptions(
            style: .defaultVideo,
            zoomSegments: [ZoomSegment(startTime: 0.1, endTime: 0.9, focusX: 0.5, focusY: 0.5, scale: 1.8)],
            enableAutoZoom: true,
            enableSmoothCursor: true,
            enableClickRipples: true,
            enableKeystrokes: true,
            trimStart: 0.0,
            trimEnd: 1.0,
            exportPreset: .xOptimal1080p60,
            includeAudio: false,
            telemetry: RecordingTelemetry(
                cursorSamples: [
                    CursorSample(time: 0.0, x: 0.2, y: 0.3, isInside: true),
                    CursorSample(time: 1.0, x: 0.8, y: 0.7, isInside: true)
                ],
                clickEvents: [ClickEvent(time: 0.4, x: 0.5, y: 0.5)],
                keystrokeEvents: [KeystrokeEvent(time: 0.2, text: "⌘⇧7")],
                duration: 1.0,
                hidNativeCursor: true
            )
        )
        _ = try await exporter.exportVideo(sourceURL: rawURL, outputURL: mp4URL, options: benchOpts, progressHandler: { _ in })
        let elapsed = ProcessInfo.processInfo.systemUptime - t0
        print("⚡️ [Benchmark] 1.0s 1080p60 full-effects export completed in \(String(format: "%.3f", elapsed))s (\(String(format: "%.1f", 60.0 / elapsed)) fps)")
        XCTAssertLessThan(elapsed, 2.0, "1080p60 export should run much faster than real-time on Apple Silicon")
    }

    /// Regression test for the AVAssetWriter video/audio interleaving deadlock (~88% hang):
    /// Generates a 5-second source video WITH a real 48kHz stereo AAC audio track and exports 300 frames at 1080p60 with audio enabled!
    func testMultiTrackVideoWithAudioExportCompletesWithoutDeadlock() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let rawURL = tmpDir.appendingPathComponent("xshot-av-raw-\(UUID().uuidString).mov")
        let mp4URL = tmpDir.appendingPathComponent("xshot-av-out-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: mp4URL)
        }

        // Create a 5.0s source MOV with BOTH video AND 48kHz stereo audio
        let writer = try AVAssetWriter(outputURL: rawURL, fileType: .mov)
        let w = 960, h = 600
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vIn,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h
            ]
        )
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        writer.add(vIn)
        writer.add(aIn)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var fmtDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmtDesc)

        // Interleave 5 seconds cleanly (150 video frames @ 30fps + 50 audio 0.1s chunks)
        // Drive whichever track AVAssetWriter is ready for so the test fixture can NEVER deadlock!
        var vIdx = 0
        var aIdx = 0
        let totalV = 150
        let totalA = 50
        let samplesPerChunk = 4800 // 0.1s at 48kHz
        while (vIdx < totalV || aIdx < totalA) && writer.status == .writing {
            var progressed = false
            if vIdx < totalV && vIn.isReadyForMoreMediaData {
                var pbOpt: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pbOpt)
                let pb = pbOpt!
                CVPixelBufferLockBaseAddress(pb, [])
                if let ctx = CGContext(
                    data: CVPixelBufferGetBaseAddress(pb), width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                    space: cs, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                ) {
                    ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.14, blue: 0.22, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
                XCTAssertTrue(adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(vIdx), timescale: 30)))
                vIdx += 1
                if vIdx == totalV { vIn.markAsFinished() }
                progressed = true
            }
            if aIdx < totalA && aIn.isReadyForMoreMediaData {
                let byteCount = samplesPerChunk * 4
                var blockBuf: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &blockBuf)
                CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuf!, offsetIntoDestination: 0, dataLength: byteCount)
                let pts = CMTime(value: CMTimeValue(aIdx * samplesPerChunk), timescale: 48_000)
                var sampleBuf: CMSampleBuffer?
                CMAudioSampleBufferCreateWithPacketDescriptions(
                    allocator: nil, dataBuffer: blockBuf, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                    formatDescription: fmtDesc!, sampleCount: samplesPerChunk, presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sampleBuf
                )
                XCTAssertTrue(aIn.append(sampleBuf!))
                aIdx += 1
                if aIdx == totalA { aIn.markAsFinished() }
                progressed = true
            }
            if !progressed {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)

        // Now export full 4.6s (276 frames at 1080p60) WITH audio + typing focus zoom + physical keycaps + live typing pill!
        let exporter = VideoCompositorExporter()
        let typingFocusEvents = [
            TypingFocusEvent(time: 1.2, x: 0.30, y: 0.45, hasExactFocusBounds: true),
            TypingFocusEvent(time: 2.0, x: 0.55, y: 0.45, hasExactFocusBounds: true)
        ]
        let autoSegments = AutoZoomEngine.generateAutoZoomSegments(
            clicks: [ClickEvent(time: 0.8, x: 0.30, y: 0.45)],
            typingEvents: typingFocusEvents,
            includeClicks: true,
            includeTypingFocus: true,
            duration: 5.0
        )
        let opts = VideoCompositeOptions(
            style: .defaultVideo,
            zoomSegments: autoSegments,
            enableAutoZoom: true,
            enableSmoothCursor: true,
            enableClickRipples: true,
            enableKeystrokes: true,
            trimStart: 0.2,
            trimEnd: 4.8,
            exportPreset: .xOptimal1080p60,
            includeAudio: true,
            telemetry: RecordingTelemetry(
                cursorSamples: [
                    CursorSample(time: 0.0, x: 0.2, y: 0.2, isInside: true),
                    CursorSample(time: 5.0, x: 0.8, y: 0.8, isInside: true)
                ],
                clickEvents: [ClickEvent(time: 0.8, x: 0.30, y: 0.45)],
                keystrokeEvents: [
                    KeystrokeEvent(time: 0.5, text: "⌘⇧P", keycaps: ["⌘", "⇧", "P"], isTypingText: false),
                    KeystrokeEvent(time: 1.5, text: "hello xtags", keycaps: ["hello xtags"], isTypingText: true)
                ],
                typingFocusEvents: typingFocusEvents,
                duration: 5.0,
                hidNativeCursor: true
            )
        )

        let progressBox = LockedDouble()
        let t0 = ProcessInfo.processInfo.systemUptime
        let outURL = try await exporter.exportVideo(
            sourceURL: rawURL,
            outputURL: mp4URL,
            options: opts,
            progressHandler: { p in progressBox.set(p) }
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - t0
        print("⚡️ [Multi-Track A/V Test] 4.6s 1080p60 + Stereo Audio exported in \(String(format: "%.3f", elapsed))s (\(String(format: "%.1f", (4.6 * 60.0) / elapsed)) fps)")

        XCTAssertEqual(progressBox.get(), 1.0, accuracy: 0.01)
        let outAsset = AVURLAsset(url: outURL)
        let vTracks = try await outAsset.loadTracks(withMediaType: .video)
        let aTracks = try await outAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(vTracks.count, 1, "Exported MP4 must contain video track")
        XCTAssertEqual(aTracks.count, 1, "Exported MP4 must contain mixed stereo audio track")
        let dur = try await outAsset.load(.duration).seconds
        XCTAssertEqual(dur, 4.6, accuracy: 0.15)

        // Now also verify Multi-Clip Cut + 2x Speed + Audio Pitch-Preserving Mix + Fade In/Out!
        // Source 5.0s -> Clip 1: 0.0..1.0s @ 1.0x (1.0s) + Deleted 1.0..2.5s + Clip 2: 2.5..4.5s @ 2.0x (1.0s) = 2.0s total!
        let editedMP4URL = FileManager.default.temporaryDirectory.appendingPathComponent("xshot-multiclip-out-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: editedMP4URL) }

        let cutOpts = VideoCompositeOptions(
            style: .defaultVideo,
            zoomSegments: autoSegments,
            enableAutoZoom: true,
            enableSmoothCursor: true,
            enableClickRipples: true,
            enableKeystrokes: true,
            trimStart: 0.0,
            trimEnd: 5.0,
            clipSegments: [
                VideoClipSegment(sourceStart: 0.0, sourceEnd: 1.0, speed: 1.0),
                VideoClipSegment(sourceStart: 2.5, sourceEnd: 4.5, speed: 2.0)
            ],
            audioVolume: 1.25,
            fadeConfig: VideoFadeConfig(fadeInDuration: 0.3, fadeOutDuration: 0.3),
            exportPreset: .xOptimal1080p60,
            includeAudio: true,
            telemetry: opts.telemetry
        )

        let cutOutURL = try await exporter.exportVideo(
            sourceURL: rawURL,
            outputURL: editedMP4URL,
            options: cutOpts,
            progressHandler: { _ in }
        )
        let cutAsset = AVURLAsset(url: cutOutURL)
        let cutVideoTracks = try await cutAsset.loadTracks(withMediaType: .video)
        let cutAudioTracks = try await cutAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(cutVideoTracks.count, 1)
        XCTAssertEqual(cutAudioTracks.count, 1)
        let cutDur = try await cutAsset.load(.duration).seconds
        XCTAssertEqual(cutDur, 2.0, accuracy: 0.15, "Cut + 2x speed export should compress 5.0s source to ~2.0s")

        // Verify local video loader opens exported MP4 cleanly into RecordingSession
        let loadedSession = try await RecordingSession.loadLocalVideo(url: cutOutURL)
        XCTAssertEqual(loadedSession.duration, cutDur, accuracy: 0.1)
        XCTAssertTrue(loadedSession.hasSystemAudio)
        XCTAssertEqual(loadedSession.clipSegments.count, 1)

        // Verify audio waveform extractor decodes exact bucket count cleanly
        let peaks = await AudioWaveformExtractor.extractPeaks(from: cutOutURL, bucketCount: 64)
        XCTAssertEqual(peaks.count, 64)
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1.0 })
    }

    func testAllKeystrokeStylesAndPositionsRenderCleanly() {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.14, blue: 0.20, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        let srcCG = ctx.makeImage()!

        let exporter = VideoCompositorExporter()
        let sampleShortcut = KeystrokeEvent(time: 0.5, text: "⌘⇧P", keycaps: ["⌘", "⇧", "P"], isTypingText: false)
        let sampleTyping = KeystrokeEvent(time: 0.8, text: "xshot demo", keycaps: ["xshot demo"], isTypingText: true)

        // Verify filterMode == .shortcutsOnly excludes typing events
        XCTAssertNil(AutoZoomEngine.activeKeystroke(at: 0.9, keystrokes: [sampleTyping], filterMode: .shortcutsOnly))
        XCTAssertNotNil(AutoZoomEngine.activeKeystroke(at: 0.9, keystrokes: [sampleTyping], filterMode: .all))

        for style in KeystrokeVisualStyle.allCases {
            for pos in KeystrokePosition.allCases {
                let ksConfig = KeystrokeStyleConfig(
                    visualStyle: style,
                    position: pos,
                    customX: 0.72,
                    customY: 0.28,
                    sizeScale: 1.15,
                    filterMode: .all
                )
                let opts = VideoCompositeOptions(
                    style: .defaultVideo,
                    enableAutoZoom: false,
                    enableSmoothCursor: false,
                    enableClickRipples: false,
                    enableKeystrokes: true,
                    keystrokeStyle: ksConfig,
                    previewSampleKeystroke: sampleShortcut,
                    trimStart: 0,
                    trimEnd: 1.0
                )
                let frame = exporter.renderPreviewFrame(
                    sourceCGImage: srcCG,
                    time: 0.5,
                    options: opts,
                    smoothedCursorPath: [],
                    maxPreviewEdge: 800
                )
                XCTAssertNotNil(frame, "Keystroke style \(style) at position \(pos) must render cleanly")
            }
        }
    }
}
