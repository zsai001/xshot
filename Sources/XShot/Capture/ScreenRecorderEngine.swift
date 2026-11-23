import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import VideoToolbox

public struct RecordingConfiguration {
    public var targetFPS: Int
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool
    public var hideNativeCursor: Bool
    public var enableKeystrokes: Bool
    public var keystrokeStyle: KeystrokeStyleConfig
    public var enableTypingFocusZoom: Bool

    public init(
        targetFPS: Int = 60,
        captureSystemAudio: Bool = true,
        captureMicrophone: Bool = false,
        hideNativeCursor: Bool = true,
        enableKeystrokes: Bool = true,
        keystrokeStyle: KeystrokeStyleConfig = .default,
        enableTypingFocusZoom: Bool = true
    ) {
        self.targetFPS = targetFPS
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.hideNativeCursor = hideNativeCursor
        self.enableKeystrokes = enableKeystrokes
        self.keystrokeStyle = keystrokeStyle
        self.enableTypingFocusZoom = enableTypingFocusZoom
    }
}

public enum ScreenRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case displayNotFound
    case windowNotFound
    case writerSetupFailed(String)
    case noFramesCaptured

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: return L10n.t(.errAlreadyRecording)
        case .notRecording: return L10n.t(.errNotRecording)
        case .displayNotFound: return L10n.t(.errDisplayNotFound)
        case .windowNotFound: return L10n.t(.errWindowNotFound)
        case .writerSetupFailed(let msg): return L10n.format(.errWriterSetupFailedFormat, msg)
        case .noFramesCaptured: return L10n.t(.errNoFramesCaptured)
        }
    }
}

/// Pure native ScreenCaptureKit + VideoToolbox 60fps/120fps screen & audio recorder.
public final class ScreenRecorderEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    private let sampleQueue = DispatchQueue(label: "top.xtags.xshot.recorder.samples", qos: .userInteractive)
    private let telemetryRecorder = InputTelemetryRecorder()

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?

    private var outputURL: URL?
    private var recordingConfig = RecordingConfiguration()
    private var videoPixelSize: CGSize = .zero

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false
    private var sessionStartPTS: CMTime = .invalid
    private var lastVideoPTS: CMTime = .invalid
    private var pauseStartedPTS: CMTime = .invalid
    private var totalPausedTime: CMTime = .zero
    private var capturedFrameCount: Int = 0
    private var startWallTime: TimeInterval = 0
    private var totalPausedWallTime: TimeInterval = 0
    private var pauseWallStart: TimeInterval?

    public var onStatsUpdate: ((Double, Int) -> Void)?
    public var onStreamError: ((Error) -> Void)?

    public func startRecording(
        target: SelectedCaptureTarget,
        configuration: RecordingConfiguration
    ) async throws {
        guard !isRecording else { throw ScreenRecorderError.alreadyRecording }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedIDs = await CaptureWindowFilter.internalOverlayWindowIDs()
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }

        let filter: SCContentFilter
        let streamConfig = SCStreamConfiguration()
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(30, configuration.targetFPS)))
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.colorSpaceName = CGColorSpace.sRGB
        streamConfig.showsCursor = !configuration.hideNativeCursor
        streamConfig.queueDepth = 8
        streamConfig.scalesToFit = true

        // System audio & mic audio (macOS 15+ native ScreenCaptureKit)
        streamConfig.capturesAudio = configuration.captureSystemAudio
        streamConfig.excludesCurrentProcessAudio = true
        streamConfig.sampleRate = 48_000
        streamConfig.channelCount = 2
        if configuration.captureMicrophone {
            streamConfig.captureMicrophone = true
        }

        let pixelW: Int
        let pixelH: Int

        switch target {
        case .area(let displayID, _, _, let displayLocalRect, let scaleFactor):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw ScreenRecorderError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let effectiveScale = max(scaleFactor, CGFloat(filter.pointPixelScale))
            streamConfig.sourceRect = displayLocalRect
            pixelW = CoordinateConverter.evenPixelDimension(displayLocalRect.width * effectiveScale)
            pixelH = CoordinateConverter.evenPixelDimension(displayLocalRect.height * effectiveScale)

        case .window(let windowID, _, _, let quartzFrame, let scaleFactor):
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenRecorderError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            streamConfig.ignoreShadowsSingleWindow = true
            let nativeScale = max(1.0, CGFloat(filter.pointPixelScale))
            let effectiveScale = nativeScale > 0 ? nativeScale : scaleFactor
            let contentSize = (filter.contentRect.width > 1 && filter.contentRect.height > 1)
                ? filter.contentRect.size
                : quartzFrame.size
            pixelW = CoordinateConverter.evenPixelDimension(contentSize.width * effectiveScale)
            pixelH = CoordinateConverter.evenPixelDimension(contentSize.height * effectiveScale)

        case .display(let displayID, let quartzFrame, let scaleFactor):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw ScreenRecorderError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let effectiveScale = max(scaleFactor, CGFloat(filter.pointPixelScale))
            pixelW = CoordinateConverter.evenPixelDimension(quartzFrame.width * effectiveScale)
            pixelH = CoordinateConverter.evenPixelDimension(quartzFrame.height * effectiveScale)
        }

        streamConfig.width = pixelW
        streamConfig.height = pixelH

        let rawURL = ExportHelpers.temporaryRecordingsDirectory
            .appendingPathComponent(ExportHelpers.timestampedFilename(prefix: "XShot-Raw", ext: "mov"))
        try? FileManager.default.removeItem(at: rawURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: rawURL, fileType: .mov)
        } catch {
            throw ScreenRecorderError.writerSetupFailed(error.localizedDescription)
        }

        // High-bitrate hardware mezzanine so Studio post-export keeps crystal-clear Retina sharpness
        let pixelCount = Double(pixelW * pixelH)
        let rawBitrate = Int(max(24_000_000, min(65_000_000, pixelCount * 14.0)))
        let vInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: pixelW,
                AVVideoHeightKey: pixelH,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: rawBitrate,
                    AVVideoExpectedSourceFrameRateKey: configuration.targetFPS,
                    AVVideoMaxKeyFrameIntervalKey: configuration.targetFPS,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
        )
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)

        var sysAInput: AVAssetWriterInput?
        if configuration.captureSystemAudio {
            let a = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000
                ]
            )
            a.expectsMediaDataInRealTime = true
            writer.add(a)
            sysAInput = a
        }

        var micAInput: AVAssetWriterInput?
        if configuration.captureMicrophone {
            let m = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 128_000
                ]
            )
            m.expectsMediaDataInRealTime = true
            writer.add(m)
            micAInput = m
        }

        guard writer.startWriting() else {
            throw ScreenRecorderError.writerSetupFailed(writer.error?.localizedDescription ?? "Unknown")
        }

        let scStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if configuration.captureSystemAudio {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        if configuration.captureMicrophone {
            try scStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
        }

        self.outputURL = rawURL
        self.recordingConfig = configuration
        self.videoPixelSize = CGSize(width: pixelW, height: pixelH)
        self.assetWriter = writer
        self.videoInput = vInput
        self.systemAudioInput = sysAInput
        self.micAudioInput = micAInput
        self.stream = scStream

        self.isRecording = true
        self.isPaused = false
        self.sessionStarted = false
        self.sessionStartPTS = .invalid
        self.lastVideoPTS = .invalid
        self.pauseStartedPTS = .invalid
        self.totalPausedTime = .zero
        self.capturedFrameCount = 0
        self.startWallTime = ProcessInfo.processInfo.systemUptime
        self.totalPausedWallTime = 0
        self.pauseWallStart = nil

        telemetryRecorder.start(
            captureQuartzRect: target.quartzRect,
            hidNativeCursor: configuration.hideNativeCursor
        )

        try await scStream.startCapture()
    }

    public func togglePause() -> Bool {
        sampleQueue.sync {
            guard isRecording else { return false }
            if isPaused {
                isPaused = false
                if let pWall = pauseWallStart {
                    totalPausedWallTime += (ProcessInfo.processInfo.systemUptime - pWall)
                    pauseWallStart = nil
                }
                telemetryRecorder.resume()
            } else {
                isPaused = true
                pauseWallStart = ProcessInfo.processInfo.systemUptime
                pauseStartedPTS = .invalid
                telemetryRecorder.pause()
            }
            return isPaused
        }
    }

    public func stopRecording() async throws -> RecordingSession {
        guard isRecording, let scStream = stream, let writer = assetWriter, let rawURL = outputURL else {
            throw ScreenRecorderError.notRecording
        }

        try? await scStream.stopCapture()

        let finalStats: (duration: Double, frames: Int, started: Bool) = sampleQueue.sync {
            self.isRecording = false
            self.isPaused = false
            self.videoInput?.markAsFinished()
            self.systemAudioInput?.markAsFinished()
            self.micAudioInput?.markAsFinished()

            let wallElapsed = max(0.1, ProcessInfo.processInfo.systemUptime - startWallTime - totalPausedWallTime)
            let ptsElapsed: Double
            if sessionStarted && lastVideoPTS.isValid && sessionStartPTS.isValid {
                ptsElapsed = max(0.1, CMTimeSubtract(lastVideoPTS, sessionStartPTS).seconds)
            } else {
                ptsElapsed = wallElapsed
            }
            return (max(wallElapsed, ptsElapsed), capturedFrameCount, sessionStarted)
        }

        let telemetry = telemetryRecorder.stop(finalDuration: finalStats.duration)

        if finalStats.started {
            await writer.finishWriting()
        } else {
            writer.cancelWriting()
        }

        self.stream = nil
        self.assetWriter = nil
        self.videoInput = nil
        self.systemAudioInput = nil
        self.micAudioInput = nil

        guard finalStats.frames > 0 else {
            throw ScreenRecorderError.noFramesCaptured
        }

        // Load exact duration from finalized asset
        let asset = AVURLAsset(url: rawURL)
        let loadedDuration = (try? await asset.load(.duration).seconds) ?? finalStats.duration
        let actualDuration = max(0.2, loadedDuration.isFinite ? loadedDuration : finalStats.duration)

        let autoZooms = AutoZoomEngine.generateAutoZoomSegments(
            clicks: telemetry.clickEvents,
            typingEvents: telemetry.typingFocusEvents,
            includeClicks: true,
            includeTypingFocus: recordingConfig.enableTypingFocusZoom,
            duration: actualDuration
        )

        return RecordingSession(
            rawVideoURL: rawURL,
            videoSize: videoPixelSize,
            duration: actualDuration,
            fps: recordingConfig.targetFPS,
            hasSystemAudio: recordingConfig.captureSystemAudio,
            hasMicAudio: recordingConfig.captureMicrophone,
            telemetry: telemetry,
            style: .defaultVideo,
            zoomSegments: autoZooms,
            enableKeystrokesByDefault: recordingConfig.enableKeystrokes,
            keystrokeStyle: recordingConfig.keystrokeStyle,
            enableTypingFocusZoom: recordingConfig.enableTypingFocusZoom
        )
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let writer = assetWriter, writer.status == .writing else { return }

        let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard rawPTS.isValid else { return }

        if isPaused {
            if !pauseStartedPTS.isValid {
                pauseStartedPTS = rawPTS
            }
            return
        } else if pauseStartedPTS.isValid {
            let delta = CMTimeSubtract(rawPTS, pauseStartedPTS)
            if delta.seconds > 0 {
                totalPausedTime = CMTimeAdd(totalPausedTime, delta)
            }
            pauseStartedPTS = .invalid
        }

        let adjustedPTS = CMTimeSubtract(rawPTS, totalPausedTime)

        switch type {
        case .screen:
            // Only accept complete frames with valid image buffers
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete,
                  CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
                return
            }

            if !sessionStarted {
                writer.startSession(atSourceTime: adjustedPTS)
                sessionStarted = true
                sessionStartPTS = adjustedPTS
            }

            guard let vInput = videoInput, vInput.isReadyForMoreMediaData else { return }
            let bufferToAppend = (totalPausedTime == .zero)
                ? sampleBuffer
                : (retime(sampleBuffer, subtracting: totalPausedTime) ?? sampleBuffer)

            if vInput.append(bufferToAppend) {
                capturedFrameCount += 1
                lastVideoPTS = adjustedPTS
                if capturedFrameCount % 6 == 0 {
                    let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startWallTime - totalPausedWallTime)
                    let frames = capturedFrameCount
                    DispatchQueue.main.async { [weak self] in
                        self?.onStatsUpdate?(elapsed, frames)
                    }
                }
            }

        case .audio:
            guard sessionStarted, adjustedPTS >= sessionStartPTS,
                  let aInput = systemAudioInput, aInput.isReadyForMoreMediaData else { return }
            let buf = (totalPausedTime == .zero) ? sampleBuffer : (retime(sampleBuffer, subtracting: totalPausedTime) ?? sampleBuffer)
            aInput.append(buf)

        case .microphone:
            guard sessionStarted, adjustedPTS >= sessionStartPTS,
                  let mInput = micAudioInput, mInput.isReadyForMoreMediaData else { return }
            let buf = (totalPausedTime == .zero) ? sampleBuffer : (retime(sampleBuffer, subtracting: totalPausedTime) ?? sampleBuffer)
            mInput.append(buf)

        @unknown default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onStreamError?(error)
        }
    }

    private func retime(_ sampleBuffer: CMSampleBuffer, subtracting offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr,
              count > 0 else { return nil }
        var infos = Array(repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &infos, entriesNeededOut: &count) == noErr else { return nil }

        for i in 0..<count {
            if infos[i].presentationTimeStamp.isValid {
                infos[i].presentationTimeStamp = CMTimeSubtract(infos[i].presentationTimeStamp, offset)
            }
            if infos[i].decodeTimeStamp.isValid {
                infos[i].decodeTimeStamp = CMTimeSubtract(infos[i].decodeTimeStamp, offset)
            }
        }
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count,
            sampleTimingArray: &infos,
            sampleBufferOut: &out
        )
        return status == noErr ? out : nil
    }
}
