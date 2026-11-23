@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// Records a synchronized companion webcam `.mov` track alongside ScreenCaptureKit recording,
/// exposing its live `AVCaptureSession` for a zero-copy GPU floating self-preview bubble.
public final class WebcamRecorderEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "top.xtags.xshot.webcam.capture", qos: .userInteractive)
    private let stateLock = NSLock()

    private var captureSession: AVCaptureSession?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false
    private var startPTS: CMTime = .invalid
    private var lastPTS: CMTime = .invalid
    private var pauseStartPTS: CMTime = .invalid
    private var totalPausedTime: CMTime = .zero
    private var writtenFrames: Int = 0

    public override init() {
        super.init()
    }

    /// Starts camera capture + synchronized H.264 recording.
    /// Returns the live `AVCaptureSession` on success, or `nil` if no camera is available or permission is denied.
    public func startRecording() async -> AVCaptureSession? {
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        if auth == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return nil }
        } else if auth != .authorized {
            return nil
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            captureQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let session = self.configureAndStartLocked(device: device)
                continuation.resume(returning: session)
            }
        }
    }

    public func setPaused(_ paused: Bool) {
        captureQueue.async { [weak self] in
            guard let self, self.isRecording, self.isPaused != paused else { return }
            self.isPaused = paused
            if paused {
                self.pauseStartPTS = self.lastPTS
            } else if self.pauseStartPTS.isValid && self.lastPTS.isValid {
                let delta = CMTimeSubtract(self.lastPTS, self.pauseStartPTS)
                if delta.isValid && delta.seconds > 0 {
                    self.totalPausedTime = CMTimeAdd(self.totalPausedTime, delta)
                }
                self.pauseStartPTS = .invalid
            }
        }
    }

    public func stopRecording() async -> URL? {
        await withCheckedContinuation { continuation in
            captureQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                guard self.isRecording else {
                    continuation.resume(returning: nil)
                    return
                }
                self.isRecording = false
                self.isPaused = false
                self.captureSession?.stopRunning()
                self.captureSession = nil

                guard let writer = self.assetWriter,
                      let vIn = self.videoInput,
                      let url = self.outputURL else {
                    continuation.resume(returning: nil)
                    return
                }

                let frameCount = self.writtenFrames
                self.assetWriter = nil
                self.videoInput = nil
                self.outputURL = nil

                if !self.sessionStarted || frameCount == 0 || writer.status != .writing {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: nil)
                    return
                }

                vIn.markAsFinished()
                nonisolated(unsafe) let finishingWriter = writer
                finishingWriter.finishWriting {
                    if finishingWriter.status == .completed {
                        continuation.resume(returning: url)
                    } else {
                        try? FileManager.default.removeItem(at: url)
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    private func configureAndStartLocked(device: AVCaptureDevice) -> AVCaptureSession? {
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return nil
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            return nil
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return nil
        }
        session.addOutput(output)
        session.commitConfiguration()

        let camURL = ExportHelpers.temporaryRecordingsDirectory
            .appendingPathComponent(ExportHelpers.timestampedFilename(prefix: "XShot-Cam", ext: "mov"))
        try? FileManager.default.removeItem(at: camURL)

        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let w = max(320, Int(dims.width > 0 ? dims.width : 1280))
        let h = max(240, Int(dims.height > 0 ? dims.height : 720))

        guard let writer = try? AVAssetWriter(outputURL: camURL, fileType: .mov) else {
            return nil
        }
        let vIn = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: CoordinateConverter.evenPixelDimension(CGFloat(w)),
                AVVideoHeightKey: CoordinateConverter.evenPixelDimension(CGFloat(h)),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_500_000,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
        )
        vIn.expectsMediaDataInRealTime = true
        guard writer.canAdd(vIn) else { return nil }
        writer.add(vIn)
        guard writer.startWriting() else { return nil }

        self.captureSession = session
        self.assetWriter = writer
        self.videoInput = vIn
        self.outputURL = camURL
        self.isRecording = true
        self.isPaused = false
        self.sessionStarted = false
        self.startPTS = .invalid
        self.lastPTS = .invalid
        self.pauseStartPTS = .invalid
        self.totalPausedTime = .zero
        self.writtenFrames = 0

        session.startRunning()
        return session
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isRecording,
              let writer = assetWriter,
              let vIn = videoInput,
              writer.status == .writing else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        lastPTS = pts

        if isPaused {
            if !pauseStartPTS.isValid {
                pauseStartPTS = pts
            }
            return
        }

        if !sessionStarted {
            startPTS = pts
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }

        guard vIn.isReadyForMoreMediaData else { return }
        let adjustedPTS = CMTimeSubtract(CMTimeSubtract(pts, startPTS), totalPausedTime)
        guard adjustedPTS.isValid, adjustedPTS >= .zero else { return }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: adjustedPTS,
            decodeTimeStamp: .invalid
        )
        var retimed: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimed
        )
        if status == noErr, let retimed, vIn.append(retimed) {
            writtenFrames += 1
        }
    }
}
