import AppKit
import SwiftUI

// MARK: - Tactile Native macOS Button Styles (Proper Inner View @State + Full Hitbox + Crisp Hover & Press)

public struct TactilePillButtonStyle: ButtonStyle {
    let background: Color
    let hoverBackground: Color
    let borderColor: Color
    let hoverBorderColor: Color?
    let cornerRadius: CGFloat

    public init(
        background: Color,
        hoverBackground: Color,
        borderColor: Color = .clear,
        hoverBorderColor: Color? = nil,
        cornerRadius: CGFloat = 8
    ) {
        self.background = background
        self.hoverBackground = hoverBackground
        self.borderColor = borderColor
        self.hoverBorderColor = hoverBorderColor
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        BodyView(
            configuration: configuration,
            background: background,
            hoverBackground: hoverBackground,
            borderColor: borderColor,
            hoverBorderColor: hoverBorderColor,
            cornerRadius: cornerRadius
        )
    }

    private struct BodyView: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let background: Color
        let hoverBackground: Color
        let borderColor: Color
        let hoverBorderColor: Color?
        let cornerRadius: CGFloat

        @State private var isHovered = false

        var body: some View {
            let activeFill = (isHovered && isEnabled) ? hoverBackground : background
            let activeBorder = (isHovered && isEnabled) ? (hoverBorderColor ?? borderColor) : borderColor
            let hasBorder = (activeBorder != .clear)

            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(activeFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(activeBorder, lineWidth: hasBorder ? 0.85 : 0)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1.0)
                .opacity(configuration.isPressed && isEnabled ? 0.85 : 1.0)
                .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}

public struct TactilePrimaryButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 8) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        BodyView(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct BodyView: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: (isHovered && isEnabled)
                                    ? [Color(red: 0.08, green: 0.72, blue: 0.96), Color(red: 0.28, green: 0.56, blue: 0.99)]
                                    : [Color(red: 0.05, green: 0.64, blue: 0.90), Color(red: 0.22, green: 0.50, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: Color(red: 0.05, green: 0.64, blue: 0.90).opacity(isHovered ? 0.38 : 0.22),
                            radius: isHovered ? 10 : 6,
                            y: 2
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1.0)
                .brightness(configuration.isPressed && isEnabled ? -0.06 : 0)
                .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.13), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

/// Tactile press-scale button style for custom-drawn cards/swatches that manage their own hover surface.
public struct TactileScaleButtonStyle: ButtonStyle {
    let pressedScale: CGFloat

    public init(pressedScale: CGFloat = 0.96) {
        self.pressedScale = pressedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

// MARK: - Pixel-Perfect Circular Rainbow Custom Color Button (Opens Native NSColorPanel)

@MainActor
public final class CustomColorPanelBridge: NSObject {
    public static let shared = CustomColorPanelBridge()
    private var onColorPicked: ((RGBAColor) -> Void)?

    public func open(initialColor: RGBAColor, onColorChanged: @escaping (RGBAColor) -> Void) {
        self.onColorPicked = onColorChanged
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initialColor.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        guard let srgb = sender.color.usingColorSpace(.sRGB) else { return }
        let rgba = RGBAColor(
            r: Double(srgb.redComponent),
            g: Double(srgb.greenComponent),
            b: Double(srgb.blueComponent),
            a: 1.0
        )
        onColorPicked?(rgba)
    }
}

public struct CustomColorWheelButton: View {
    let currentColor: RGBAColor
    let isCustomActive: Bool
    let palette: StudioPalette
    let tooltip: String
    let onColorPicked: (RGBAColor) -> Void

    @State private var isHovered = false

    public init(
        currentColor: RGBAColor,
        isCustomActive: Bool,
        palette: StudioPalette,
        tooltip: String,
        onColorPicked: @escaping (RGBAColor) -> Void
    ) {
        self.currentColor = currentColor
        self.isCustomActive = isCustomActive
        self.palette = palette
        self.tooltip = tooltip
        self.onColorPicked = onColorPicked
    }

    public var body: some View {
        Button {
            CustomColorPanelBridge.shared.open(initialColor: currentColor, onColorChanged: onColorPicked)
        } label: {
            ZStack {
                if isCustomActive {
                    Circle()
                        .strokeBorder(palette.accent, lineWidth: 2.0)
                        .frame(width: 24, height: 24)
                }

                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                            center: .center
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .fill(isCustomActive ? currentColor.swiftUIColor : palette.hudSurface)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.7)
                            )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(palette.isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.20), lineWidth: 0.8)
                    )
                    .scaleEffect(isHovered ? 1.14 : 1.0)
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.11), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isCustomActive)
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.88))
        .onHover { isHovered = $0 }
        .help(tooltip)
    }
}

// MARK: - Shared Wallpaper Picker Section (Curated Gradients + macOS System Wallpapers + Custom Local Image)

public struct WallpaperPickerSection: View {
    @Binding var selectedBackground: BackgroundPreset
    let palette: StudioPalette
    @ObservedObject private var uiStore = ThemeLocaleStore.shared

    @State private var activeTab: Int = 0 // 0 = Curated Gradients, 1 = macOS System Wallpapers
    @State private var systemWallpapers: [BackgroundPreset] = []
    @State private var loadedSystemWallpapers = false

    public init(selectedBackground: Binding<BackgroundPreset>, palette: StudioPalette) {
        self._selectedBackground = selectedBackground
        self.palette = palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Sleek 2-tab pill switcher: Gradients vs macOS System Wallpapers
            HStack(spacing: 4) {
                tabButton(title: uiStore.t(.wallpaperTabGradients), icon: "sparkles", tab: 0)
                tabButton(title: uiStore.t(.wallpaperTabSystem), icon: "photo.on.rectangle.angled", tab: 1)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.trackFill)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
            )

            if activeTab == 0 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(BackgroundPreset.curated) { preset in
                        WallpaperSwatchButton(
                            preset: preset,
                            isSelected: selectedBackground.id == preset.id,
                            palette: palette,
                            height: 35
                        ) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                selectedBackground = preset
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    if !loadedSystemWallpapers {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(uiStore.t(.wallpaperLoadingSystem))
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 82)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                                ForEach(systemWallpapers) { preset in
                                    SystemWallpaperSwatchButton(
                                        preset: preset,
                                        isDesktop: preset.id.hasPrefix("sys-desktop:"),
                                        isSelected: selectedBackground.imagePath == preset.imagePath && selectedBackground.kind == .image,
                                        palette: palette
                                    ) {
                                        withAnimation(.easeOut(duration: 0.14)) {
                                            selectedBackground = preset
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(height: 132)
                    }

                    Button {
                        if let picked = SystemWallpaperManager.pickCustomWallpaperPreset() {
                            withAnimation(.easeOut(duration: 0.14)) {
                                selectedBackground = picked
                            }
                            if !systemWallpapers.contains(where: { $0.imagePath == picked.imagePath }) {
                                systemWallpapers.insert(picked, at: min(1, systemWallpapers.count))
                            }
                        }
                    } label: {
                        Label(uiStore.t(.wallpaperPickLocal), systemImage: "folder.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.controlFill,
                        hoverBackground: palette.controlHoverFill,
                        borderColor: palette.controlBorder,
                        hoverBorderColor: palette.accentBorder,
                        cornerRadius: 8
                    ))
                }
            }
        }
        .onAppear {
            if selectedBackground.kind == .image {
                activeTab = 1
            }
            loadSystemWallpapersIfNeeded()
        }
        .onChange(of: activeTab) { _, tab in
            if tab == 1 {
                loadSystemWallpapersIfNeeded()
            }
        }
    }

    private func loadSystemWallpapersIfNeeded() {
        let desktopTitle = uiStore.t(.wallpaperDesktopName)
        if !loadedSystemWallpapers,
           let instant = SystemWallpaperManager.shared.cachedDiscoveredWallpapers(desktopLabel: desktopTitle) {
            self.systemWallpapers = instant
            self.loadedSystemWallpapers = true
            return
        }
        guard !loadedSystemWallpapers else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let discovered = SystemWallpaperManager.shared.discoverSystemWallpapers(desktopLabel: desktopTitle)
            DispatchQueue.main.async {
                self.systemWallpapers = discovered
                self.loadedSystemWallpapers = true
            }
        }
    }

    private func tabButton(title: String, icon: String, tab: Int) -> some View {
        let isSelected = (activeTab == tab)
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                activeTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isSelected ? palette.accentSoftFill : .clear,
            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
            borderColor: isSelected ? palette.accentBorder : .clear,
            cornerRadius: 6
        ))
    }
}

// MARK: - Tactile Wallpaper Swatches (Curated + Async System Image Swatch)

public struct WallpaperSwatchButton: View {
    let preset: BackgroundPreset
    let isSelected: Bool
    let palette: StudioPalette
    let height: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    public init(
        preset: BackgroundPreset,
        isSelected: Bool,
        palette: StudioPalette,
        height: CGFloat = 36,
        action: @escaping () -> Void
    ) {
        self.preset = preset
        self.isSelected = isSelected
        self.palette = palette
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                swatchFill
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.68), radius: 2)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? palette.accent : (isHovered ? palette.primaryText.opacity(0.45) : palette.controlBorder),
                        lineWidth: isSelected ? 2.2 : 0.9
                    )
            )
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.93))
        .onHover { isHovered = $0 }
        .help(preset.name)
    }

    @ViewBuilder
    private var swatchFill: some View {
        switch preset.kind {
        case .transparent:
            ZStack {
                palette.controlFill
                Image(systemName: "checkerboard.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
            }
        case .solid:
            (preset.colors.first?.swiftUIColor ?? .black)
        case .gradient, .meshLike, .image:
            LinearGradient(
                colors: preset.colors.map(\.swiftUIColor),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct SystemWallpaperSwatchButton: View {
    let preset: BackgroundPreset
    let isDesktop: Bool
    let isSelected: Bool
    let palette: StudioPalette
    let action: () -> Void

    @State private var thumbCG: CGImage?
    @State private var isHovered = false

    private var displayedThumb: CGImage? {
        if let thumbCG { return thumbCG }
        if let path = preset.imagePath {
            return SystemWallpaperManager.shared.cachedThumbnail(forPath: path, maxPixelSize: 180)
        }
        return nil
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let cg = displayedThumb {
                    Image(decorative: cg, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 40, maxHeight: 40)
                        .clipped()
                } else {
                    palette.controlFill
                }

                if isDesktop {
                    VStack {
                        HStack {
                            Image(systemName: "display")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(3)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white, palette.accent)
                        .shadow(color: .black.opacity(0.55), radius: 2)
                }
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? palette.accent : (isHovered ? palette.primaryText.opacity(0.45) : palette.controlBorder),
                        lineWidth: isSelected ? 2.2 : 0.9
                    )
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.94))
        .onHover { isHovered = $0 }
        .help(preset.name)
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        guard displayedThumb == nil, let path = preset.imagePath else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = SystemWallpaperManager.shared.thumbnail(forPath: path, maxPixelSize: 180)
            DispatchQueue.main.async {
                self.thumbCG = img
            }
        }
    }
}

public struct AspectRatioMiniIcon: View {
    let ratio: AspectRatioPreset
    let color: Color

    public init(ratio: AspectRatioPreset, color: Color) {
        self.ratio = ratio
        self.color = color
    }

    public var body: some View {
        let dims: (CGFloat, CGFloat) = {
            switch ratio {
            case .auto: return (12, 9)
            case .wide16x9: return (14, 8)
            case .card4x3: return (12, 9)
            case .square1x1: return (10, 10)
            case .vertical9x16: return (7, 12)
            }
        }()
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(color, lineWidth: 1.3)
            .frame(width: dims.0, height: dims.1)
    }
}

// MARK: - 120Hz GPU Live Background View (Zero-Allocation Native Metal Shaders + Cached System Wallpaper Image)

public struct LiveBeautifyBackgroundView: View {
    let preset: BackgroundPreset
    @State private var loadedImagePath: String?
    @State private var loadedCGImage: CGImage?

    public init(preset: BackgroundPreset) {
        self.preset = preset
    }

    public var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)

            switch preset.kind {
            case .transparent:
                Canvas { ctx, size in
                    let cell: CGFloat = 12
                    let cols = Int(ceil(size.width / cell))
                    let rows = Int(ceil(size.height / cell))
                    for r in 0..<rows {
                        for c in 0..<cols {
                            let isEven = (r + c) % 2 == 0
                            ctx.fill(
                                Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)),
                                with: .color(isEven ? Color.gray.opacity(0.18) : Color.gray.opacity(0.08))
                            )
                        }
                    }
                }

            case .solid:
                (preset.colors.first?.swiftUIColor ?? .black)

            case .gradient:
                let stops = preset.colors.isEmpty
                    ? [Color(red: 0.06, green: 0.09, blue: 0.16), Color(red: 0.12, green: 0.16, blue: 0.23)]
                    : preset.colors.map(\.swiftUIColor)
                let rad = preset.angleDegrees * .pi / 180.0
                let dx = cos(rad) * 0.5
                let dy = sin(rad) * 0.5
                LinearGradient(
                    colors: stops,
                    startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 + dy),
                    endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 - dy)
                )

            case .meshLike:
                ZStack {
                    let baseColors = Array(preset.colors.prefix(2)).map(\.swiftUIColor)
                    LinearGradient(
                        colors: baseColors.count >= 2 ? baseColors : [Color(red: 0.06, green: 0.09, blue: 0.16), Color(red: 0.12, green: 0.11, blue: 0.29)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )

                    let anchors: [(UnitPoint, CGFloat)] = [
                        (UnitPoint(x: 0.18, y: 0.78), 0.72),
                        (UnitPoint(x: 0.84, y: 0.22), 0.78),
                        (UnitPoint(x: 0.82, y: 0.82), 0.58),
                        (UnitPoint(x: 0.20, y: 0.16), 0.62)
                    ]
                    let maxDim = max(w, h)
                    ForEach(Array(preset.colors.enumerated()), id: \.offset) { idx, c in
                        let anchor = anchors[idx % anchors.count]
                        RadialGradient(
                            colors: [c.swiftUIColor.opacity(0.62), c.swiftUIColor.opacity(0.0)],
                            center: anchor.0,
                            startRadius: 0,
                            endRadius: maxDim * anchor.1
                        )
                    }
                }

            case .image:
                let activeCG: CGImage? = (loadedImagePath == preset.imagePath ? loadedCGImage : nil)
                    ?? preset.imagePath.flatMap { SystemWallpaperManager.shared.cachedPreviewImage(forPath: $0, maxPixelSize: 1920) }
                    ?? preset.imagePath.flatMap { SystemWallpaperManager.shared.cachedThumbnail(forPath: $0, maxPixelSize: 180) }
                if let cg = activeCG {
                    Image(decorative: cg, scale: 1.0, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.09, green: 0.11, blue: 0.16), Color(red: 0.15, green: 0.18, blue: 0.26)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .onAppear { loadWallpaperImageIfNeeded() }
        .onChange(of: preset.imagePath) { _, _ in loadWallpaperImageIfNeeded() }
    }

    private func loadWallpaperImageIfNeeded() {
        guard preset.kind == .image, let path = preset.imagePath else { return }
        if loadedImagePath == path && loadedCGImage != nil { return }
        if let cached = SystemWallpaperManager.shared.cachedPreviewImage(forPath: path, maxPixelSize: 1920) {
            self.loadedImagePath = path
            self.loadedCGImage = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = SystemWallpaperManager.shared.previewImage(forPath: path, maxPixelSize: 1920)
            DispatchQueue.main.async {
                if self.preset.imagePath == path {
                    self.loadedImagePath = path
                    self.loadedCGImage = img
                }
            }
        }
    }
}

// MARK: - 120Hz Live macOS Window Titlebar View (1:1 match with ScreenshotRenderer.drawWindowChromeBar)

public struct LiveWindowChromeView: View {
    let style: WindowChromeStyle
    let title: String
    let height: CGFloat

    public init(style: WindowChromeStyle, title: String, height: CGFloat) {
        self.style = style
        self.title = title
        self.height = height
    }

    public var body: some View {
        let isDark = (style == .macOSDark)
        let dotDiameter = max(6, height * 0.34)
        let dotSpacing = dotDiameter * 0.65

        ZStack {
            Rectangle()
                .fill(isDark ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(red: 0.94, green: 0.94, blue: 0.96))

            HStack(spacing: dotSpacing) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: dotDiameter, height: dotDiameter)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: dotDiameter, height: dotDiameter)
                Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: dotDiameter, height: dotDiameter)
                Spacer()
            }
            .padding(.leading, height * 0.45 - dotDiameter / 2)

            if !title.isEmpty {
                Text(title)
                    .font(.system(size: max(9, height * 0.38), weight: .medium))
                    .foregroundStyle(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
                    .lineLimit(1)
            }

            VStack {
                Spacer()
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Shared Reusable Custom Watermark / Creator Signature Card & 120Hz Live Preview Overlay

public struct WatermarkInspectorCard: View {
    @Binding var config: WatermarkConfig
    let palette: StudioPalette
    let onSaveAsDefault: (() -> Void)?

    @ObservedObject private var uiStore = ThemeLocaleStore.shared

    public init(
        config: Binding<WatermarkConfig>,
        palette: StudioPalette,
        onSaveAsDefault: (() -> Void)? = nil
    ) {
        self._config = config
        self.palette = palette
        self.onSaveAsDefault = onSaveAsDefault
    }

    public var body: some View {
        let roseTint = Color(red: 0.94, green: 0.36, blue: 0.64)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "signature")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(roseTint)
                Text(uiStore.t(.watermarkCardTitle))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.enabled },
                    set: { newVal in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            config.enabled = newVal
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if config.enabled {
                TextField(uiStore.t(.watermarkTextPlaceholder), text: $config.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                // 3 Visual Styles
                HStack(spacing: 4) {
                    ForEach(WatermarkVisualStyle.allCases) { style in
                        let isSelected = (config.visualStyle == style)
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                config.visualStyle = style
                            }
                        } label: {
                            Text(style.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .lineLimit(1)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? palette.accentSoftFill : .clear,
                            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
                            borderColor: isSelected ? palette.accentBorder : .clear,
                            cornerRadius: 6
                        ))
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.trackFill)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                )

                // 6 Positions (4 corners + bottom center + diagonal tiled)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                    ForEach(WatermarkPosition.allCases) { pos in
                        let isSelected = (config.position == pos)
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                config.position = pos
                            }
                        } label: {
                            Text(pos.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? roseTint : palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 25)
                                .lineLimit(1)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? roseTint.opacity(palette.isDark ? 0.22 : 0.14) : palette.controlFill,
                            hoverBackground: isSelected ? roseTint.opacity(palette.isDark ? 0.30 : 0.20) : palette.controlHoverFill,
                            borderColor: isSelected ? roseTint.opacity(0.65) : palette.controlBorder,
                            cornerRadius: 6
                        ))
                    }
                }

                // Opacity & Scale Sliders
                VStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(uiStore.t(.watermarkOpacityLabel))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text("\(Int((config.opacity * 100).rounded()))%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.accent)
                        }
                        Slider(value: $config.opacity, in: 0.15...1.0)
                            .tint(roseTint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(uiStore.t(.watermarkScaleLabel))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text(String(format: "%.2fx", config.scale))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.accent)
                        }
                        Slider(value: $config.scale, in: 0.65...1.80)
                            .tint(roseTint)
                    }
                }

                HStack(spacing: 8) {
                    Toggle(uiStore.t(.watermarkBrandGlyph), isOn: $config.showBrandGlyph)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if let onSaveAsDefault {
                        Button(action: onSaveAsDefault) {
                            Text(uiStore.t(.watermarkSaveDefaultBtn))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(roseTint)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: roseTint.opacity(0.14),
                            hoverBackground: roseTint.opacity(0.24),
                            borderColor: roseTint.opacity(0.45),
                            cornerRadius: 6
                        ))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                .shadow(color: .black.opacity(palette.isDark ? 0 : 0.04), radius: 4, y: 1)
        )
    }
}

/// 120Hz GPU Live Watermark Overlay for ScreenshotEditorView matching `ScreenshotRenderer.drawWatermark` proportions.
public struct LiveWatermarkOverlay: View {
    let config: WatermarkConfig
    let targetRect: CGRect
    let canvasPixelSize: CGSize

    public init(config: WatermarkConfig, targetRect: CGRect, canvasPixelSize: CGSize) {
        self.config = config
        self.targetRect = targetRect
        self.canvasPixelSize = canvasPixelSize
    }

    public var body: some View {
        let trimmed = config.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.isEffectivelyVisible, !trimmed.isEmpty {
            let displayScale = targetRect.width / max(1, canvasPixelSize.width)
            let shortEdgePx = min(canvasPixelSize.width, canvasPixelSize.height)
            let designScale = max(0.85, shortEdgePx / 760.0) * CGFloat(min(max(config.scale, 0.55), 2.2))
            let fontSize = max(9.0, max(13.0, 15.5 * designScale) * displayScale)
            let displayText = config.showBrandGlyph ? "✦  \(trimmed)" : trimmed

            Group {
                if config.position == .tiled {
                    Canvas { ctx, size in
                        let resolved = ctx.resolve(
                            Text(displayText)
                                .font(.system(size: fontSize, weight: .semibold))
                                .foregroundColor(.white.opacity(config.opacity * 0.44))
                        )
                        let measured = resolved.measure(in: size)
                        let tileW = max(90, measured.width + 110 * designScale * displayScale)
                        let tileH = max(58, measured.height + 90 * designScale * displayScale)
                        let diag = hypot(size.width, size.height)

                        ctx.translateBy(x: size.width / 2, y: size.height / 2)
                        ctx.rotate(by: .degrees(-26))
                        var row = 0
                        var y = -diag / 2
                        while y < diag / 2 {
                            let xOff = (row % 2 == 0) ? 0 : tileW * 0.5
                            var x = -diag / 2 - tileW + xOff
                            while x < diag / 2 + tileW {
                                ctx.draw(resolved, at: CGPoint(x: x, y: y), anchor: .topLeading)
                                x += tileW
                            }
                            y += tileH
                            row += 1
                        }
                    }
                    .frame(width: targetRect.width, height: targetRect.height)
                    .clipped()
                    .position(x: targetRect.midX, y: targetRect.midY)
                } else {
                    let margin = max(8.0, max(16.0, shortEdgePx * 0.028) * displayScale)
                    let padX = (config.visualStyle == .minimalText ? 4.0 : 12.0) * designScale * displayScale
                    let padY = (config.visualStyle == .minimalText ? 2.5 : 6.0) * designScale * displayScale
                    let badge = Text(displayText)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, max(4, padX))
                        .padding(.vertical, max(2, padY))
                        .background {
                            switch config.visualStyle {
                            case .glassPill:
                                Capsule()
                                    .fill(Color(red: 0.06, green: 0.07, blue: 0.11).opacity(0.72))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.9))
                                    .shadow(color: .black.opacity(0.40), radius: 6, y: 2)
                            case .badgeAccent:
                                RoundedRectangle(cornerRadius: max(5, 9 * designScale * displayScale), style: .continuous)
                                    .fill(Color(red: 0.05, green: 0.09, blue: 0.16).opacity(0.86))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: max(5, 9 * designScale * displayScale), style: .continuous)
                                            .strokeBorder(Color(red: 0.12, green: 0.72, blue: 1.0).opacity(0.78), lineWidth: 1.1)
                                    )
                                    .shadow(color: Color(red: 0.06, green: 0.56, blue: 0.94).opacity(0.38), radius: 7, y: 2)
                            case .minimalText:
                                Color.clear
                            }
                        }
                        .shadow(color: config.visualStyle == .minimalText ? .black.opacity(0.65) : .clear, radius: 4, y: 1)
                        .opacity(config.opacity)

                    let alignment: Alignment = {
                        switch config.position {
                        case .bottomRight: return .bottomTrailing
                        case .bottomLeft: return .bottomLeading
                        case .topRight: return .topTrailing
                        case .topLeft: return .topLeading
                        case .bottomCenter: return .bottom
                        case .tiled: return .bottomTrailing
                        }
                    }()

                    ZStack(alignment: alignment) {
                        Color.clear
                        badge.padding(margin)
                    }
                    .frame(width: targetRect.width, height: targetRect.height)
                    .clipped()
                    .position(x: targetRect.midX, y: targetRect.midY)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
