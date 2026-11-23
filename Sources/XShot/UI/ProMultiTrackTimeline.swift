import AppKit
import CoreGraphics
import SwiftUI

/// Professional 3-track NLE Timeline (Sticky Track Headers + Zoomable Scrollable Video/Zoom/Audio Tracks +
/// Real Audio Waveform + Ease-Ramp Zoom Blocks + Hover Skimmer + Magnetic Snapping + Draggable Playhead).
struct ProMultiTrackTimeline: View {
    let sourceDuration: Double
    @Binding var currentTime: Double
    @Binding var clipSegments: [VideoClipSegment]
    @Binding var zoomSegments: [ZoomSegment]
    @Binding var selectedClipID: UUID?
    @Binding var selectedSegmentID: UUID?
    @Binding var includeAudio: Bool
    let audioVolume: Double
    let fadeConfig: VideoFadeConfig
    let hasSourceAudio: Bool
    let timelineZoom: Double
    let enableMagneticSnap: Bool
    let filmstripFrames: [(sourceTime: Double, image: CGImage)]
    let waveformPeaks: [Float]
    let clickEvents: [ClickEvent]
    let typingEvents: [TypingFocusEvent]
    let palette: StudioPalette
    let uiStore: ThemeLocaleStore

    let onWillMutate: () -> Void
    let onScrub: () -> Void
    let onAddZoomAtPlayhead: () -> Void
    let onAddZoomAtSourceTime: (Double) -> Void
    let onRegenerateAutoZooms: () -> Void
    let onSplitAtPlayhead: () -> Void
    let onDeleteClip: (UUID) -> Void
    let onMergeClipAtIndex: (Int) -> Void
    let onDuplicateZoom: (UUID) -> Void
    let onDeleteZoom: (UUID) -> Void

    @State private var draggingZoomInitial: (id: UUID, mode: Int, start: Double, end: Double)?
    @State private var draggingClipTrim: (id: UUID, isLeft: Bool, initialStart: Double, initialEnd: Double)?
    @State private var hoverOutputTime: Double?
    @State private var activeSnapTime: Double?
    @State private var dragReadout: (outputTime: Double, text: String)?

    private let headerWidth: CGFloat = 82
    private let rulerHeight: CGFloat = 22
    private let videoTrackHeight: CGFloat = 44
    private let zoomTrackHeight: CGFloat = 32
    private let audioTrackHeight: CGFloat = 34
    private let rowGap: CGFloat = 5

    private var totalTracksHeight: CGFloat {
        rulerHeight + rowGap + videoTrackHeight + rowGap + zoomTrackHeight + rowGap + audioTrackHeight
    }

    var body: some View {
        let totalOutDur = VideoTimelineMapper.totalOutputDuration(of: clipSegments)
        let clipRanges = VideoTimelineMapper.outputRanges(of: clipSegments)

        GeometryReader { geo in
            let viewportW = max(220, geo.size.width - headerWidth - 1)
            let trackW = max(viewportW, viewportW * CGFloat(max(1.0, timelineZoom)))
            let pps = trackW / CGFloat(max(0.1, totalOutDur))
            let snapThresholdSec = Double(8.0 / max(1, pps))

            HStack(spacing: 0) {
                // Sticky Left Track Header Rail
                trackHeaderRail(clipCount: clipSegments.count)
                    .frame(width: headerWidth, height: totalTracksHeight)

                Rectangle()
                    .fill(palette.divider)
                    .frame(width: 1, height: totalTracksHeight)

                // Horizontally Scrollable & Zoomable Synchronized Multi-Track Canvas
                ScrollView(.horizontal, showsIndicators: timelineZoom > 1.02) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: rowGap) {
                            // Row 0: Adaptive Time Ruler
                            timeRulerRow(totalOutDur: totalOutDur, trackW: trackW, pps: pps, snapThreshold: snapThresholdSec)
                                .frame(width: trackW, height: rulerHeight)

                            // Row 1: Video Clips Filmstrip Track
                            videoClipsTrack(
                                clipRanges: clipRanges,
                                totalOutDur: totalOutDur,
                                trackW: trackW,
                                snapThreshold: snapThresholdSec
                            )
                            .frame(width: trackW, height: videoTrackHeight)

                            // Row 2: Camera Zoom Segments Track (Ease Ramps + Zero-Overlap Resize!)
                            zoomSegmentsTrack(
                                totalOutDur: totalOutDur,
                                trackW: trackW,
                                snapThreshold: snapThresholdSec
                            )
                            .frame(width: trackW, height: zoomTrackHeight)

                            // Row 3: Real Audio Waveform + Fade Envelope Track
                            audioWaveformTrack(
                                clipRanges: clipRanges,
                                totalOutDur: totalOutDur,
                                trackW: trackW
                            )
                            .frame(width: trackW, height: audioTrackHeight)
                        }

                        // Hover Skimmer Hairline & Timecode Pill
                        if let hoverT = hoverOutputTime, draggingZoomInitial == nil, draggingClipTrim == nil {
                            let hx = CGFloat(min(max(hoverT / totalOutDur, 0), 1)) * trackW
                            ZStack(alignment: .top) {
                                Rectangle()
                                    .fill(Color.white.opacity(palette.isDark ? 0.30 : 0.45))
                                    .frame(width: 1, height: totalTracksHeight - 4)
                                    .offset(y: 4)
                                Text(formatShortTime(hoverT))
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                            }
                            .position(x: min(trackW - 20, max(20, hx)), y: totalTracksHeight / 2)
                            .allowsHitTesting(false)
                        }

                        // Magnetic Snap Amber Vertical Guide Line
                        if let snapT = activeSnapTime {
                            let sx = CGFloat(min(max(snapT / totalOutDur, 0), 1)) * trackW
                            Rectangle()
                                .fill(Color(red: 1.0, green: 0.76, blue: 0.14))
                                .frame(width: 1.6, height: totalTracksHeight)
                                .shadow(color: Color.orange.opacity(0.7), radius: 3)
                                .offset(x: sx - 0.8)
                                .allowsHitTesting(false)
                        }

                        // Floating Drag Readout Tooltip (Edge Time & Duration while resizing!)
                        if let readout = dragReadout {
                            let rx = CGFloat(min(max(readout.outputTime / totalOutDur, 0), 1)) * trackW
                            Text(readout.text)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.black.opacity(0.86), in: Capsule())
                                .overlay(Capsule().strokeBorder(palette.accent.opacity(0.8), lineWidth: 0.8))
                                .position(x: min(trackW - 44, max(44, rx)), y: 11)
                                .allowsHitTesting(false)
                        }

                        // Draggable Full-Height Playhead Handle + Needle
                        playheadOverlay(totalOutDur: totalOutDur, trackW: trackW, snapThreshold: snapThresholdSec)
                    }
                    .frame(width: trackW, height: totalTracksHeight, alignment: .topLeading)
                    .coordinateSpace(name: "proTimelineCanvas")
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let frac = min(max(Double(loc.x / max(1, trackW)), 0), 1)
                            hoverOutputTime = frac * totalOutDur
                        case .ended:
                            hoverOutputTime = nil
                        }
                    }
                }
                .frame(width: viewportW, height: totalTracksHeight)
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.cardBackground.opacity(palette.isDark ? 0.65 : 0.85))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.8))
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .frame(height: totalTracksHeight)
    }

    // MARK: - Sticky Left Track Header Column

    private func trackHeaderRail(clipCount: Int) -> some View {
        VStack(spacing: rowGap) {
            // Ruler corner header
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.tertiaryText)
                Text("\(clipCount)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: rulerHeight)

            // Video Track Header
            HStack(spacing: 5) {
                Image(systemName: "film")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(uiStore.t(.trackVideoLabel))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: videoTrackHeight)

            // Zoom Track Header (+ Add Zoom & Auto-Zoom right on the Zoom Track!)
            HStack(spacing: 3) {
                Text(uiStore.t(.trackZoomLabel))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Button(action: onAddZoomAtPlayhead) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.purple)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: Color.purple.opacity(0.15),
                    hoverBackground: Color.purple.opacity(0.28),
                    cornerRadius: 4.5
                ))
                .help(uiStore.t(.addZoomBtn))

                if !clickEvents.isEmpty || !typingEvents.isEmpty {
                    Button(action: onRegenerateAutoZooms) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.accentSoftFill,
                        hoverBackground: palette.accentHoverFill,
                        cornerRadius: 4.5
                    ))
                    .help(uiStore.format(.autoZoomSummaryFormat, clickEvents.count, typingEvents.count))
                }
            }
            .padding(.horizontal, 6)
            .frame(height: zoomTrackHeight)

            // Audio Track Header (with direct Mute/Unmute toggle!)
            HStack(spacing: 5) {
                Button {
                    if hasSourceAudio {
                        includeAudio.toggle()
                    }
                } label: {
                    Image(systemName: (hasSourceAudio && includeAudio && audioVolume > 0.001) ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(
                            hasSourceAudio
                                ? (includeAudio && audioVolume > 0.001 ? Color(red: 0.14, green: 0.80, blue: 0.56) : palette.tertiaryText)
                                : palette.tertiaryText.opacity(0.45)
                        )
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: (hasSourceAudio && includeAudio) ? Color(red: 0.14, green: 0.80, blue: 0.56).opacity(0.15) : palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    cornerRadius: 5
                ))
                .disabled(!hasSourceAudio)
                .help(uiStore.t(.toggleKeepAudio))

                Text(uiStore.t(.trackAudioLabel))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hasSourceAudio && includeAudio ? palette.primaryText : palette.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: audioTrackHeight)
        }
        .background(palette.controlFill.opacity(0.45))
    }

    // MARK: - Row 0: Adaptive Precision Time Ruler

    private func timeRulerRow(totalOutDur: Double, trackW: CGFloat, pps: CGFloat, snapThreshold: Double) -> some View {
        let majorStep = chooseMajorTickInterval(pixelsPerSecond: Double(pps))
        let minorStep = majorStep / 5.0

        return Canvas { ctx, size in
            // Bottom hairline
            ctx.fill(Path(CGRect(x: 0, y: size.height - 0.8, width: size.width, height: 0.8)), with: .color(palette.divider))

            var t = 0.0
            var safety = 0
            while t <= totalOutDur + 0.0001 && safety < 1200 {
                let x = CGFloat(t / totalOutDur) * size.width
                let isMajor = abs((t / majorStep).rounded() * majorStep - t) < (minorStep * 0.25)
                if isMajor {
                    ctx.fill(Path(CGRect(x: x, y: size.height - 7, width: 1, height: 7)), with: .color(palette.secondaryText.opacity(0.65)))
                    let labelText = majorStep < 1.0 ? String(format: "%.1fs", t) : formatShortTime(t)
                    let resolved = ctx.resolve(
                        Text(labelText)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(palette.tertiaryText)
                    )
                    let drawX = min(size.width - 28, max(2, x + 3))
                    ctx.draw(resolved, at: CGPoint(x: drawX, y: 2), anchor: .topLeading)
                } else {
                    ctx.fill(Path(CGRect(x: x, y: size.height - 3.5, width: 0.8, height: 3.5)), with: .color(palette.divider))
                }
                t += minorStep
                safety += 1
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("proTimelineCanvas"))
                .onChanged { val in
                    let raw = min(max(Double(val.location.x / max(1, trackW)), 0), 1) * totalOutDur
                    let snapped = applySnap(raw, excludePlayhead: true, totalOutDur: totalOutDur, threshold: snapThreshold)
                    currentTime = snapped
                    onScrub()
                }
                .onEnded { _ in activeSnapTime = nil }
        )
    }

    // MARK: - Row 1: Video Clips Filmstrip Track

    private func videoClipsTrack(
        clipRanges: [(clip: VideoClipSegment, outputStart: Double, outputEnd: Double)],
        totalOutDur: Double,
        trackW: CGFloat,
        snapThreshold: Double
    ) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(palette.trackFill.opacity(0.65))

            ForEach(Array(clipRanges.enumerated()), id: \.element.clip.id) { idx, entry in
                let clip = entry.clip
                let cx = CGFloat(entry.outputStart / totalOutDur) * trackW
                let cw = max(24, CGFloat((entry.outputEnd - entry.outputStart) / totalOutDur) * trackW)
                let gapInset: CGFloat = clipRanges.count > 1 ? 2.5 : 0
                let insetW = max(18, cw - gapInset)
                let isSelected = (selectedClipID == clip.id)

                ZStack(alignment: .leading) {
                    clipFilmstripView(for: clip, width: insetW, height: videoTrackHeight - 4)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(isSelected ? 0.16 : 0.34),
                                            Color.black.opacity(isSelected ? 0.28 : 0.44)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )

                    // Visual Fade-In / Fade-Out Ramp Wedges on first / last clip
                    if (idx == 0 && fadeConfig.fadeInDuration > 0.01) || (idx == clipRanges.count - 1 && fadeConfig.fadeOutDuration > 0.01) {
                        Canvas { ctx, size in
                            let clipOutDur = max(0.05, clip.outputDuration)
                            if idx == 0 && fadeConfig.fadeInDuration > 0.01 {
                                let w = min(size.width * 0.5, CGFloat(fadeConfig.fadeInDuration / clipOutDur) * size.width)
                                var p = Path()
                                p.move(to: .zero)
                                p.addLine(to: CGPoint(x: w, y: 0))
                                p.addLine(to: CGPoint(x: 0, y: size.height))
                                p.closeSubpath()
                                ctx.fill(p, with: .color(.black.opacity(0.55)))
                                var line = Path()
                                line.move(to: CGPoint(x: 0, y: size.height))
                                line.addLine(to: CGPoint(x: w, y: 0))
                                ctx.stroke(line, with: .color(.white.opacity(0.70)), lineWidth: 1.1)
                            }
                            if idx == clipRanges.count - 1 && fadeConfig.fadeOutDuration > 0.01 {
                                let w = min(size.width * 0.5, CGFloat(fadeConfig.fadeOutDuration / clipOutDur) * size.width)
                                var p = Path()
                                p.move(to: CGPoint(x: size.width, y: 0))
                                p.addLine(to: CGPoint(x: size.width - w, y: 0))
                                p.addLine(to: CGPoint(x: size.width, y: size.height))
                                p.closeSubpath()
                                ctx.fill(p, with: .color(.black.opacity(0.55)))
                                var line = Path()
                                line.move(to: CGPoint(x: size.width - w, y: 0))
                                line.addLine(to: CGPoint(x: size.width, y: size.height))
                                ctx.stroke(line, with: .color(.white.opacity(0.70)), lineWidth: 1.1)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .allowsHitTesting(false)
                    }

                    // Click & Typing Telemetry Markers along bottom edge
                    Canvas { ctx, size in
                        let srcSpan = max(0.05, clip.sourceEnd - clip.sourceStart)
                        for ev in typingEvents where ev.time >= clip.sourceStart && ev.time <= clip.sourceEnd {
                            let fx = CGFloat((ev.time - clip.sourceStart) / srcSpan) * size.width
                            ctx.fill(Path(CGRect(x: fx - 1, y: size.height - 5.5, width: 2.2, height: 3.5)), with: .color(.mint.opacity(0.9)))
                        }
                        for ev in clickEvents where ev.time >= clip.sourceStart && ev.time <= clip.sourceEnd {
                            let fx = CGFloat((ev.time - clip.sourceStart) / srcSpan) * size.width
                            ctx.fill(Path(ellipseIn: CGRect(x: fx - 2.2, y: size.height - 6.8, width: 4.4, height: 4.4)), with: .color(.cyan))
                        }
                    }
                    .allowsHitTesting(false)

                    // Clip Badges (#Index + Speed + Duration)
                    VStack {
                        HStack(spacing: 4) {
                            if clipRanges.count > 1 {
                                Text("#\(idx + 1)")
                                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(Color.black.opacity(0.68), in: Capsule())
                            }
                            if abs(clip.speed - 1.0) > 0.01 {
                                let spdColor: Color = clip.speed > 1.0 ? .orange : Color(red: 0.14, green: 0.68, blue: 0.98)
                                Text(formatSpeed(clip.speed))
                                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(spdColor.opacity(0.92), in: Capsule())
                            }
                            Spacer(minLength: 0)
                            if insetW >= 62 {
                                Text(String(format: "%.1fs", clip.outputDuration))
                                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(Color.black.opacity(0.55), in: Capsule())
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 4)
                    .allowsHitTesting(false)

                    // Selection Border
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? palette.accent : Color.white.opacity(0.22),
                            lineWidth: isSelected ? 1.8 : 0.8
                        )
                        .allowsHitTesting(false)

                    // Left Trim Handle (on selected clip or first clip)
                    if isSelected || idx == 0 {
                        clipTrimHandle(height: videoTrackHeight - 4)
                            .onHover { h in if h { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .named("proTimelineCanvas"))
                                    .onChanged { val in
                                        guard idx < clipSegments.count else { return }
                                        if draggingClipTrim?.id != clip.id || draggingClipTrim?.isLeft != true {
                                            onWillMutate()
                                            draggingClipTrim = (clip.id, true, clipSegments[idx].sourceStart, clipSegments[idx].sourceEnd)
                                            selectedClipID = clip.id
                                            selectedSegmentID = nil
                                        }
                                        guard let initTrim = draggingClipTrim else { return }
                                        let deltaOut = Double(val.translation.width / max(1, trackW)) * totalOutDur
                                        let deltaSrc = deltaOut * clipSegments[idx].speed
                                        let minAllowed = idx > 0 ? clipSegments[idx - 1].sourceEnd : 0.0
                                        let maxAllowed = initTrim.initialEnd - 0.25
                                        let newStart = min(max(initTrim.initialStart + deltaSrc, minAllowed), maxAllowed)
                                        clipSegments[idx].sourceStart = newStart
                                        if let mapped = VideoTimelineMapper.mapSourceTimeToOutput(newStart, clips: clipSegments) {
                                            currentTime = mapped
                                            dragReadout = (mapped, String(format: "%.1fs · %.1fs", newStart, clipSegments[idx].outputDuration))
                                        }
                                        onScrub()
                                    }
                                    .onEnded { _ in
                                        draggingClipTrim = nil
                                        dragReadout = nil
                                        activeSnapTime = nil
                                    }
                            )
                    }

                    // Right Trim Handle (on selected clip or last clip)
                    if isSelected || idx == clipRanges.count - 1 {
                        HStack {
                            Spacer()
                            clipTrimHandle(height: videoTrackHeight - 4)
                                .onHover { h in if h { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
                                .gesture(
                                    DragGesture(minimumDistance: 1, coordinateSpace: .named("proTimelineCanvas"))
                                        .onChanged { val in
                                            guard idx < clipSegments.count else { return }
                                            if draggingClipTrim?.id != clip.id || draggingClipTrim?.isLeft != false {
                                                onWillMutate()
                                                draggingClipTrim = (clip.id, false, clipSegments[idx].sourceStart, clipSegments[idx].sourceEnd)
                                                selectedClipID = clip.id
                                                selectedSegmentID = nil
                                            }
                                            guard let initTrim = draggingClipTrim else { return }
                                            let deltaOut = Double(val.translation.width / max(1, trackW)) * totalOutDur
                                            let deltaSrc = deltaOut * clipSegments[idx].speed
                                            let minAllowed = initTrim.initialStart + 0.25
                                            let maxAllowed = idx + 1 < clipSegments.count ? clipSegments[idx + 1].sourceStart : sourceDuration
                                            let newEnd = max(min(initTrim.initialEnd + deltaSrc, maxAllowed), minAllowed)
                                            clipSegments[idx].sourceEnd = newEnd
                                            if let mapped = VideoTimelineMapper.mapSourceTimeToOutput(newEnd, clips: clipSegments) {
                                                currentTime = mapped
                                                dragReadout = (mapped, String(format: "%.1fs · %.1fs", newEnd, clipSegments[idx].outputDuration))
                                            }
                                            onScrub()
                                        }
                                        .onEnded { _ in
                                            draggingClipTrim = nil
                                            dragReadout = nil
                                            activeSnapTime = nil
                                        }
                                )
                        }
                    }
                }
                .frame(width: insetW, height: videoTrackHeight - 4)
                .offset(x: cx + gapInset / 2.0)
                .onTapGesture(coordinateSpace: .named("proTimelineCanvas")) { pt in
                    selectedClipID = clip.id
                    selectedSegmentID = nil
                    let raw = min(max(Double(pt.x / max(1, trackW)), 0), 1) * totalOutDur
                    currentTime = applySnap(raw, excludePlayhead: true, totalOutDur: totalOutDur, threshold: snapThreshold)
                    activeSnapTime = nil
                    onScrub()
                }
                .contextMenu {
                    Button {
                        onSplitAtPlayhead()
                    } label: {
                        Label(uiStore.t(.splitClipBtn), systemImage: "scissors")
                    }
                    Menu(uiStore.t(.clipSpeedLabel)) {
                        ForEach(VideoTimelineMapper.speedPresets, id: \.self) { spd in
                            Button {
                                onWillMutate()
                                if idx < clipSegments.count {
                                    clipSegments[idx].speed = spd
                                }
                            } label: {
                                Text(formatSpeed(spd) + (abs(clip.speed - spd) < 0.01 ? " ✓" : ""))
                            }
                        }
                    }
                    if VideoTimelineMapper.canMergeWithNext(clipSegments, at: idx) {
                        Button {
                            onMergeClipAtIndex(idx)
                        } label: {
                            Label(uiStore.t(.mergeNextClipBtn), systemImage: "arrow.triangle.merge")
                        }
                    }
                    if clipSegments.count > 1 {
                        Divider()
                        Button(role: .destructive) {
                            onDeleteClip(clip.id)
                        } label: {
                            Label(uiStore.t(.deleteClipBtn), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row 2: Camera Zoom Segments Track (Visual Ease Trapezoids + Zero-Overlap Move & Resize!)

    private func zoomSegmentsTrack(totalOutDur: Double, trackW: CGFloat, snapThreshold: Double) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(palette.trackFill.opacity(0.45))
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .named("proTimelineCanvas")) { pt in
                    let frac = min(max(Double(pt.x / max(1, trackW)), 0), 1)
                    let outT = frac * totalOutDur
                    if let mapped = VideoTimelineMapper.mapOutputTimeToSource(outT, clips: clipSegments) {
                        onAddZoomAtSourceTime(mapped.sourceTime)
                    }
                }
                .onTapGesture(count: 1) {
                    selectedSegmentID = nil
                    selectedClipID = nil
                }

            if zoomSegments.isEmpty {
                Text(uiStore.t(.zoomTimelineEmptyHint))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            } else {
                ForEach($zoomSegments) { $seg in
                    if let mapped = VideoTimelineMapper.mapSourceIntervalToOutput(
                        sourceStart: seg.startTime,
                        sourceEnd: seg.endTime,
                        clips: clipSegments
                    ) {
                        let sx = CGFloat(mapped.start / totalOutDur) * trackW
                        let sw = max(34, CGFloat((mapped.end - mapped.start) / totalOutDur) * trackW)
                        let isSelected = (selectedSegmentID == seg.id)
                        let isTyping = (seg.triggerKind == .typing)
                        let c1: Color = isTyping ? Color(red: 0.06, green: 0.72, blue: 0.55) : Color.purple
                        let c2: Color = isTyping ? Color(red: 0.04, green: 0.54, blue: 0.50) : Color.indigo
                        let segDur = max(0.05, seg.endTime - seg.startTime)
                        let easeFrac = min(0.45, seg.easeDuration / segDur)

                        ZStack {
                            // Base rounded gradient pill + Visual Ease-In / Ease-Out Trapezoid Ramp!
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: isSelected ? [c1.opacity(0.95), c2.opacity(0.95)] : [c1.opacity(0.55), c2.opacity(0.50)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )

                                // Ease-in / hold / ease-out envelope silhouette
                                Canvas { ctx, size in
                                    let rampW = CGFloat(easeFrac) * size.width
                                    var trap = Path()
                                    trap.move(to: CGPoint(x: 0, y: size.height))
                                    trap.addLine(to: CGPoint(x: rampW, y: 3))
                                    trap.addLine(to: CGPoint(x: max(rampW, size.width - rampW), y: 3))
                                    trap.addLine(to: CGPoint(x: size.width, y: size.height))
                                    trap.closeSubpath()
                                    ctx.fill(trap, with: .color(.white.opacity(isSelected ? 0.18 : 0.12)))
                                    ctx.stroke(trap, with: .color(.white.opacity(isSelected ? 0.42 : 0.22)), lineWidth: 1.0)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .allowsHitTesting(false)

                                HStack(spacing: 3) {
                                    Image(systemName: isTyping ? "keyboard" : "magnifyingglass")
                                        .font(.system(size: 8.5, weight: .bold))
                                    Text(String(format: "%.1fx", seg.scale))
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    if sw >= 74 {
                                        Text(String(format: "· %.1fs", mapped.end - mapped.start))
                                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                            .opacity(0.85)
                                    }
                                }
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                            }
                            .frame(width: sw, height: zoomTrackHeight - 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(.white.opacity(isSelected ? 0.92 : 0.25), lineWidth: isSelected ? 1.5 : 0.8)
                            )
                            .onTapGesture {
                                selectedSegmentID = seg.id
                                selectedClipID = nil
                                currentTime = (mapped.start + mapped.end) / 2.0
                                onScrub()
                            }
                            .gesture(
                                DragGesture(minimumDistance: 2, coordinateSpace: .named("proTimelineCanvas"))
                                    .onChanged { val in
                                        if draggingZoomInitial?.id != seg.id || draggingZoomInitial?.mode != 0 {
                                            onWillMutate()
                                            draggingZoomInitial = (seg.id, 0, seg.startTime, seg.endTime)
                                            selectedSegmentID = seg.id
                                            selectedClipID = nil
                                        }
                                        guard let initSpan = draggingZoomInitial else { return }
                                        let bounds = VideoTimelineMapper.nonOverlappingZoomBounds(
                                            for: seg.id,
                                            in: zoomSegments,
                                            totalSourceDuration: sourceDuration
                                        )
                                        let deltaT = Double(val.translation.width / max(1, trackW)) * totalOutDur
                                        let spanLen = initSpan.end - initSpan.start
                                        let maxStart = max(bounds.minStart, bounds.maxEnd - spanLen)
                                        var newStart = min(max(bounds.minStart, initSpan.start + deltaT), maxStart)

                                        if enableMagneticSnap,
                                           let rawOut = VideoTimelineMapper.mapSourceTimeToOutput(newStart, clips: clipSegments) {
                                            let snappedOut = applySnap(rawOut, excludePlayhead: false, totalOutDur: totalOutDur, threshold: snapThreshold)
                                            if activeSnapTime != nil,
                                               let snappedSrc = VideoTimelineMapper.mapOutputTimeToSource(snappedOut, clips: clipSegments)?.sourceTime {
                                                newStart = min(max(bounds.minStart, snappedSrc), maxStart)
                                            }
                                        }

                                        seg.startTime = newStart
                                        seg.endTime = newStart + spanLen
                                        if let midOut = VideoTimelineMapper.mapSourceTimeToOutput(newStart + spanLen / 2.0, clips: clipSegments) {
                                            currentTime = midOut
                                            dragReadout = (midOut, String(format: "%.1fs–%.1fs", newStart, seg.endTime))
                                        }
                                        onScrub()
                                    }
                                    .onEnded { _ in
                                        draggingZoomInitial = nil
                                        dragReadout = nil
                                        activeSnapTime = nil
                                    }
                            )

                            // Left & Right Non-Overlapping Edge Resize Handles
                            HStack {
                                zoomEdgeGrip(isSelected: isSelected)
                                    .gesture(
                                        DragGesture(minimumDistance: 1, coordinateSpace: .named("proTimelineCanvas"))
                                            .onChanged { val in
                                                if draggingZoomInitial?.id != seg.id || draggingZoomInitial?.mode != -1 {
                                                    onWillMutate()
                                                    draggingZoomInitial = (seg.id, -1, seg.startTime, seg.endTime)
                                                    selectedSegmentID = seg.id
                                                    selectedClipID = nil
                                                }
                                                guard let initSpan = draggingZoomInitial else { return }
                                                let bounds = VideoTimelineMapper.nonOverlappingZoomBounds(
                                                    for: seg.id,
                                                    in: zoomSegments,
                                                    totalSourceDuration: sourceDuration
                                                )
                                                let deltaT = Double(val.translation.width / max(1, trackW)) * totalOutDur
                                                var newStart = min(max(bounds.minStart, initSpan.start + deltaT), initSpan.end - 0.40)

                                                if enableMagneticSnap,
                                                   let rawOut = VideoTimelineMapper.mapSourceTimeToOutput(newStart, clips: clipSegments) {
                                                    let snappedOut = applySnap(rawOut, excludePlayhead: false, totalOutDur: totalOutDur, threshold: snapThreshold)
                                                    if activeSnapTime != nil,
                                                       let snappedSrc = VideoTimelineMapper.mapOutputTimeToSource(snappedOut, clips: clipSegments)?.sourceTime {
                                                        newStart = min(max(bounds.minStart, snappedSrc), initSpan.end - 0.40)
                                                    }
                                                }

                                                seg.startTime = newStart
                                                if let outT = VideoTimelineMapper.mapSourceTimeToOutput(newStart, clips: clipSegments) {
                                                    currentTime = outT
                                                    dragReadout = (outT, String(format: "%.1fs (%.1fs)", newStart, seg.endTime - newStart))
                                                }
                                                onScrub()
                                            }
                                            .onEnded { _ in
                                                draggingZoomInitial = nil
                                                dragReadout = nil
                                                activeSnapTime = nil
                                            }
                                    )

                                Spacer(minLength: 0)

                                zoomEdgeGrip(isSelected: isSelected)
                                    .gesture(
                                        DragGesture(minimumDistance: 1, coordinateSpace: .named("proTimelineCanvas"))
                                            .onChanged { val in
                                                if draggingZoomInitial?.id != seg.id || draggingZoomInitial?.mode != 1 {
                                                    onWillMutate()
                                                    draggingZoomInitial = (seg.id, 1, seg.startTime, seg.endTime)
                                                    selectedSegmentID = seg.id
                                                    selectedClipID = nil
                                                }
                                                guard let initSpan = draggingZoomInitial else { return }
                                                let bounds = VideoTimelineMapper.nonOverlappingZoomBounds(
                                                    for: seg.id,
                                                    in: zoomSegments,
                                                    totalSourceDuration: sourceDuration
                                                )
                                                let deltaT = Double(val.translation.width / max(1, trackW)) * totalOutDur
                                                var newEnd = max(min(bounds.maxEnd, initSpan.end + deltaT), initSpan.start + 0.40)

                                                if enableMagneticSnap,
                                                   let rawOut = VideoTimelineMapper.mapSourceTimeToOutput(newEnd, clips: clipSegments) {
                                                    let snappedOut = applySnap(rawOut, excludePlayhead: false, totalOutDur: totalOutDur, threshold: snapThreshold)
                                                    if activeSnapTime != nil,
                                                       let snappedSrc = VideoTimelineMapper.mapOutputTimeToSource(snappedOut, clips: clipSegments)?.sourceTime {
                                                        newEnd = max(min(bounds.maxEnd, snappedSrc), initSpan.start + 0.40)
                                                    }
                                                }

                                                seg.endTime = newEnd
                                                if let outT = VideoTimelineMapper.mapSourceTimeToOutput(newEnd, clips: clipSegments) {
                                                    currentTime = outT
                                                    dragReadout = (outT, String(format: "%.1fs (%.1fs)", newEnd, newEnd - seg.startTime))
                                                }
                                                onScrub()
                                            }
                                            .onEnded { _ in
                                                draggingZoomInitial = nil
                                                dragReadout = nil
                                                activeSnapTime = nil
                                            }
                                    )
                            }
                            .frame(width: sw, height: zoomTrackHeight - 6)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .offset(x: sx)
                        .contextMenu {
                            Button {
                                onWillMutate()
                                seg.followCursor.toggle()
                            } label: {
                                Text(uiStore.t(.followCursorLabel) + (seg.followCursor ? " ✓" : ""))
                            }
                            Button {
                                onDuplicateZoom(seg.id)
                            } label: {
                                Label(uiStore.t(.duplicateZoomBtn), systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) {
                                onDeleteZoom(seg.id)
                            } label: {
                                Label(uiStore.t(.deleteAction), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row 3: Real Audio Waveform + Live Volume & Fade Envelope Track

    private func audioWaveformTrack(
        clipRanges: [(clip: VideoClipSegment, outputStart: Double, outputEnd: Double)],
        totalOutDur: Double,
        trackW: CGFloat
    ) -> some View {
        let audioActive = hasSourceAudio && includeAudio && audioVolume > 0.001
        let emerald = Color(red: 0.14, green: 0.80, blue: 0.56)

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(palette.trackFill.opacity(0.35))

            if hasSourceAudio {
                Canvas { ctx, size in
                    let midY = size.height / 2.0
                    let safeSrcDur = max(0.1, sourceDuration)
                    let volScale = min(1.35, max(0.08, audioVolume))
                    let barStep: CGFloat = 3.0
                    let barWidth: CGFloat = 1.8

                    for entry in clipRanges {
                        let x0 = CGFloat(entry.outputStart / totalOutDur) * size.width
                        let x1 = CGFloat(entry.outputEnd / totalOutDur) * size.width
                        let clipW = max(2, x1 - x0)
                        let clipRect = CGRect(x: x0 + 1, y: 2, width: max(1, clipW - 2), height: size.height - 4)

                        ctx.fill(
                            Path(roundedRect: clipRect, cornerRadius: 5),
                            with: .color((audioActive ? emerald : palette.tertiaryText).opacity(audioActive ? 0.11 : 0.06))
                        )
                        ctx.stroke(
                            Path(roundedRect: clipRect, cornerRadius: 5),
                            with: .color((audioActive ? emerald : palette.controlBorder).opacity(audioActive ? 0.34 : 0.35)),
                            lineWidth: 0.7
                        )

                        // Center baseline
                        ctx.fill(
                            Path(CGRect(x: clipRect.minX + 2, y: midY - 0.4, width: max(0, clipRect.width - 4), height: 0.8)),
                            with: .color((audioActive ? emerald : palette.tertiaryText).opacity(0.25))
                        )

                        if !waveformPeaks.isEmpty {
                            let peakCount = waveformPeaks.count
                            var x = clipRect.minX + 3
                            while x < clipRect.maxX - 2 {
                                let localFrac = Double((x - x0) / max(1, clipW))
                                let srcT = entry.clip.sourceStart + localFrac * (entry.clip.sourceEnd - entry.clip.sourceStart)
                                let outT = entry.outputStart + localFrac * (entry.outputEnd - entry.outputStart)
                                let bucket = min(peakCount - 1, max(0, Int((srcT / safeSrcDur) * Double(peakCount - 1))))
                                let peak = Double(waveformPeaks[bucket])
                                let fadeEnv = VideoTimelineMapper.fadeOpacity(
                                    atOutputTime: outT,
                                    totalDuration: totalOutDur,
                                    fade: fadeConfig
                                )
                                let amp = min(1.0, peak * volScale * fadeEnv)
                                let barH = max(2.0, CGFloat(amp) * (size.height - 10))
                                let rect = CGRect(x: x, y: midY - barH / 2.0, width: barWidth, height: barH)
                                ctx.fill(
                                    Path(roundedRect: rect, cornerRadius: 0.9),
                                    with: .color((audioActive ? emerald : palette.tertiaryText).opacity(audioActive ? 0.82 : 0.30))
                                )
                                x += barStep
                            }
                        }
                    }

                    // Smooth audio fade-in / fade-out envelope lines
                    if audioActive {
                        if fadeConfig.fadeInDuration > 0.01 {
                            let w = min(size.width * 0.45, CGFloat(fadeConfig.fadeInDuration / totalOutDur) * size.width)
                            var p = Path()
                            p.move(to: CGPoint(x: 1, y: size.height - 3))
                            p.addLine(to: CGPoint(x: w, y: 4))
                            ctx.stroke(p, with: .color(.white.opacity(0.65)), lineWidth: 1.2)
                        }
                        if fadeConfig.fadeOutDuration > 0.01 {
                            let w = min(size.width * 0.45, CGFloat(fadeConfig.fadeOutDuration / totalOutDur) * size.width)
                            var p = Path()
                            p.move(to: CGPoint(x: size.width - w, y: 4))
                            p.addLine(to: CGPoint(x: size.width - 1, y: size.height - 3))
                            ctx.stroke(p, with: .color(.white.opacity(0.65)), lineWidth: 1.2)
                        }
                    }
                }
                .allowsHitTesting(false)

                if !audioActive {
                    Text(uiStore.t(.audioTrackMutedHint))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(palette.cardBackground.opacity(0.85), in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
            } else {
                Text(uiStore.t(.audioTrackNoAudioHint))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiaryText.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .named("proTimelineCanvas")) { pt in
            let frac = min(max(Double(pt.x / max(1, trackW)), 0), 1)
            currentTime = frac * totalOutDur
            onScrub()
        }
    }

    // MARK: - Draggable Full-Height Playhead

    private func playheadOverlay(totalOutDur: Double, trackW: CGFloat, snapThreshold: Double) -> some View {
        let playheadX = CGFloat(min(max(currentTime / totalOutDur, 0), 1)) * trackW

        return ZStack(alignment: .top) {
            // Crisp vertical playhead needle
            Rectangle()
                .fill(palette.accent)
                .frame(width: 1.8, height: totalTracksHeight - 8)
                .shadow(color: palette.accent.opacity(0.45), radius: 2)
                .offset(y: 8)
                .allowsHitTesting(false)

            // Grab-able Pentagon Cap in Ruler
            PlayheadCapShape()
                .fill(palette.accent)
                .frame(width: 12, height: 11)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .onHover { h in if h { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("proTimelineCanvas"))
                        .onChanged { val in
                            let raw = min(max(Double(val.location.x / max(1, trackW)), 0), 1) * totalOutDur
                            let snapped = applySnap(raw, excludePlayhead: true, totalOutDur: totalOutDur, threshold: snapThreshold)
                            currentTime = snapped
                            dragReadout = (snapped, formatShortTime(snapped))
                            onScrub()
                        }
                        .onEnded { _ in
                            dragReadout = nil
                            activeSnapTime = nil
                        }
                )
        }
        .offset(x: min(trackW - 11, max(-11, playheadX - 11)))
    }

    // MARK: - Helpers (Snapping, Adaptive Ruler, Filmstrip, Handles)

    private func applySnap(_ rawOut: Double, excludePlayhead: Bool, totalOutDur: Double, threshold: Double) -> Double {
        guard enableMagneticSnap else {
            activeSnapTime = nil
            return rawOut
        }
        var candidates: [Double] = [0, totalOutDur]
        if !excludePlayhead {
            candidates.append(currentTime)
        }
        for entry in VideoTimelineMapper.outputRanges(of: clipSegments) {
            candidates.append(entry.outputStart)
            candidates.append(entry.outputEnd)
        }
        for click in clickEvents {
            if let outT = VideoTimelineMapper.mapSourceTimeToOutput(click.time, clips: clipSegments) {
                candidates.append(outT)
            }
        }
        let res = VideoTimelineMapper.snapOutputTime(rawOut, candidates: candidates, thresholdSeconds: threshold)
        activeSnapTime = res.snapped ? res.time : nil
        return res.time
    }

    private func chooseMajorTickInterval(pixelsPerSecond pps: Double) -> Double {
        let intervals = [0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0]
        for step in intervals {
            if step * pps >= 58.0 {
                return step
            }
        }
        return 60.0
    }

    private func formatShortTime(_ s: Double) -> String {
        let total = max(0, s)
        let mins = Int(total) / 60
        let secs = Int(total) % 60
        let tenths = Int((total - floor(total)) * 10)
        if mins > 0 {
            return String(format: "%d:%02d.%d", mins, secs, tenths)
        }
        return String(format: "%02d.%ds", secs, tenths)
    }

    private func formatSpeed(_ spd: Double) -> String {
        abs(spd - Double(Int(spd))) < 0.01 ? "\(Int(spd))x" : String(format: "%.1fx", spd)
    }

    @ViewBuilder
    private func clipFilmstripView(for clip: VideoClipSegment, width: CGFloat, height: CGFloat) -> some View {
        let matching = filmstripFrames.filter { $0.sourceTime >= clip.sourceStart - 0.4 && $0.sourceTime <= clip.sourceEnd + 0.4 }
        let framesToShow: [CGImage] = {
            if !matching.isEmpty { return matching.map(\.image) }
            if let nearest = filmstripFrames.min(by: { abs($0.sourceTime - clip.sourceStart) < abs($1.sourceTime - clip.sourceStart) }) {
                return [nearest.image]
            }
            return []
        }()

        if framesToShow.isEmpty {
            LinearGradient(
                colors: [palette.accent.opacity(0.28), Color.blue.opacity(0.20)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width, height: height)
        } else {
            let slotCount = max(1, min(28, Int(ceil(width / 56))))
            HStack(spacing: 0) {
                ForEach(0..<slotCount, id: \.self) { i in
                    let imgIdx = min(framesToShow.count - 1, Int(Double(i) / Double(max(1, slotCount - 1)) * Double(framesToShow.count - 1)))
                    Image(decorative: framesToShow[imgIdx], scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width / CGFloat(slotCount), height: height)
                        .clipped()
                }
            }
            .frame(width: width, height: height)
        }
    }

    private func clipTrimHandle(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.accent)
                .frame(width: 9, height: height)
            RoundedRectangle(cornerRadius: 1)
                .fill(palette.accentTextOnAccent.opacity(0.85))
                .frame(width: 2, height: 14)
        }
        .shadow(color: .black.opacity(0.30), radius: 2)
    }

    private func zoomEdgeGrip(isSelected: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(isSelected ? 0.38 : 0.001))
            if isSelected {
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 1.5, height: 10)
            }
        }
        .frame(width: 8, height: zoomTrackHeight - 6)
        .contentShape(Rectangle())
        .onHover { h in if h { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
    }
}

private struct PlayheadCapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.58))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.58))
        p.closeSubpath()
        return p
    }
}
