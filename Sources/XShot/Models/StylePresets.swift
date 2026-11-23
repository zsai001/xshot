import AppKit
import CoreGraphics
import SwiftUI

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1.0) {
        self.r = Double((hex >> 16) & 0xFF) / 255.0
        self.g = Double((hex >> 8) & 0xFF) / 255.0
        self.b = Double(hex & 0xFF) / 255.0
        self.a = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

public struct BackgroundPreset: Identifiable, Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Equatable, Hashable, Sendable {
        case gradient
        case meshLike
        case solid
        case transparent
        case image
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var colors: [RGBAColor]
    public var angleDegrees: Double
    /// File path for macOS system wallpaper or user-picked wallpaper image (when `kind == .image`).
    public var imagePath: String?

    public init(
        id: String,
        name: String,
        kind: Kind,
        colors: [RGBAColor],
        angleDegrees: Double = 135,
        imagePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colors = colors
        self.angleDegrees = angleDegrees
        self.imagePath = imagePath
    }

    public static func imagePreset(path: String, name: String, id: String? = nil) -> BackgroundPreset {
        BackgroundPreset(
            id: id ?? "img:\(path)",
            name: name,
            kind: .image,
            colors: [RGBAColor(hex: 0x0F172A), RGBAColor(hex: 0x1E293B)],
            angleDegrees: 135,
            imagePath: path
        )
    }

    public static let curated: [BackgroundPreset] = [
        BackgroundPreset(
            id: "x-aurora",
            name: "Aurora X",
            kind: .meshLike,
            colors: [
                RGBAColor(hex: 0x0F172A),
                RGBAColor(hex: 0x1E1B4B),
                RGBAColor(hex: 0x0EA5E9),
                RGBAColor(hex: 0x8B5CF6)
            ],
            angleDegrees: 135
        ),
        BackgroundPreset(
            id: "sunset-glow",
            name: "Sunset",
            kind: .meshLike,
            colors: [
                RGBAColor(hex: 0xFF512F),
                RGBAColor(hex: 0xDD2476),
                RGBAColor(hex: 0xF59E0B),
                RGBAColor(hex: 0x7C3AED)
            ],
            angleDegrees: 125
        ),
        BackgroundPreset(
            id: "ocean-silk",
            name: "Ocean",
            kind: .meshLike,
            colors: [
                RGBAColor(hex: 0x0284C7),
                RGBAColor(hex: 0x2563EB),
                RGBAColor(hex: 0x06B6D4),
                RGBAColor(hex: 0x1E3A8A)
            ],
            angleDegrees: 140
        ),
        BackgroundPreset(
            id: "emerald-mint",
            name: "Mint",
            kind: .meshLike,
            colors: [
                RGBAColor(hex: 0x064E3B),
                RGBAColor(hex: 0x059669),
                RGBAColor(hex: 0x10B981),
                RGBAColor(hex: 0x0EA5E9)
            ],
            angleDegrees: 130
        ),
        BackgroundPreset(
            id: "mac-sequoia",
            name: "Twilight",
            kind: .meshLike,
            colors: [
                RGBAColor(hex: 0x18181B),
                RGBAColor(hex: 0x312E81),
                RGBAColor(hex: 0xEC4899),
                RGBAColor(hex: 0x3B82F6)
            ],
            angleDegrees: 150
        ),
        BackgroundPreset(
            id: "peach-cream",
            name: "Peach",
            kind: .gradient,
            colors: [
                RGBAColor(hex: 0xFDE68A),
                RGBAColor(hex: 0xFCA5A5),
                RGBAColor(hex: 0xC4B5FD)
            ],
            angleDegrees: 135
        ),
        BackgroundPreset(
            id: "obsidian",
            name: "Obsidian",
            kind: .gradient,
            colors: [
                RGBAColor(hex: 0x09090B),
                RGBAColor(hex: 0x18181B),
                RGBAColor(hex: 0x27272A)
            ],
            angleDegrees: 145
        ),
        BackgroundPreset(
            id: "silver-frost",
            name: "Frost",
            kind: .gradient,
            colors: [
                RGBAColor(hex: 0xF8FAFC),
                RGBAColor(hex: 0xE2E8F0),
                RGBAColor(hex: 0xCBD5E1)
            ],
            angleDegrees: 135
        ),
        BackgroundPreset(
            id: "pure-black",
            name: "X Black",
            kind: .solid,
            colors: [RGBAColor(hex: 0x000000)]
        ),
        BackgroundPreset(
            id: "none",
            name: "None",
            kind: .transparent,
            colors: [RGBAColor(r: 0, g: 0, b: 0, a: 0)]
        )
    ]

    public static var defaultScreenshot: BackgroundPreset { curated[0] }
    public static var defaultVideo: BackgroundPreset { curated[0] }
}

public enum AspectRatioPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "Auto"
    case wide16x9 = "16:9"
    case card4x3 = "4:3"
    case square1x1 = "1:1"
    case vertical9x16 = "9:16"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return L10n.t(.ratioAuto)
        case .wide16x9: return L10n.t(.ratio16x9)
        case .card4x3: return L10n.t(.ratio4x3)
        case .square1x1: return L10n.t(.ratio1x1)
        case .vertical9x16: return L10n.t(.ratio9x16)
        }
    }

    public var ratio: CGFloat? {
        switch self {
        case .auto: return nil
        case .wide16x9: return 16.0 / 9.0
        case .card4x3: return 4.0 / 3.0
        case .square1x1: return 1.0
        case .vertical9x16: return 9.0 / 16.0
        }
    }
}

public enum WindowChromeStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "None"
    case macOSDark = "Dark"
    case macOSLight = "Light"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return L10n.t(.chromeNone)
        case .macOSDark: return L10n.t(.chromeDark)
        case .macOSLight: return L10n.t(.chromeLight)
        }
    }
}

public enum MultiImageLayoutMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case horizontal
    case vertical
    case grid2x2
    case bentoHero

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .horizontal: return L10n.t(.collageHorizontal)
        case .vertical: return L10n.t(.collageVertical)
        case .grid2x2: return L10n.t(.collageGrid)
        case .bentoHero: return L10n.t(.collageBento)
        }
    }
}

public enum MultiImageFitMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fit
    case fill

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fit: return L10n.t(.collageFitContain)
        case .fill: return L10n.t(.collageFitFill)
        }
    }
}

public enum WatermarkPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft
    case bottomCenter
    case tiled

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bottomRight: return L10n.t(.ksPosBottomRight)
        case .bottomLeft: return L10n.t(.ksPosBottomLeft)
        case .topRight: return L10n.t(.ksPosTopRight)
        case .topLeft: return L10n.t(.ksPosTopLeft)
        case .bottomCenter: return L10n.t(.ksPosBottomCenter)
        case .tiled: return L10n.t(.watermarkPosTiled)
        }
    }
}

public enum WatermarkVisualStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case glassPill
    case minimalText
    case badgeAccent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .glassPill: return L10n.t(.watermarkStyleGlass)
        case .minimalText: return L10n.t(.watermarkStyleMinimal)
        case .badgeAccent: return L10n.t(.watermarkStyleBadge)
        }
    }
}

public struct WatermarkConfig: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var text: String
    public var position: WatermarkPosition
    public var visualStyle: WatermarkVisualStyle
    public var opacity: Double       // 0.15...1.0
    public var scale: Double         // 0.65...1.80
    public var showBrandGlyph: Bool

    public init(
        enabled: Bool = false,
        text: String = "@XShot",
        position: WatermarkPosition = .bottomRight,
        visualStyle: WatermarkVisualStyle = .glassPill,
        opacity: Double = 0.85,
        scale: Double = 1.0,
        showBrandGlyph: Bool = true
    ) {
        self.enabled = enabled
        self.text = text
        self.position = position
        self.visualStyle = visualStyle
        self.opacity = opacity
        self.scale = scale
        self.showBrandGlyph = showBrandGlyph
    }

    public var isEffectivelyVisible: Bool {
        enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && opacity > 0.02
    }

    public static let `default` = WatermarkConfig()
}

public enum WebcamPiPShape: String, CaseIterable, Identifiable, Codable, Sendable {
    case circle
    case roundedRect
    case vertical

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .circle: return L10n.t(.webcamShapeCircle)
        case .roundedRect: return L10n.t(.webcamShapeRounded)
        case .vertical: return L10n.t(.webcamShapeVertical)
        }
    }

    /// Width-to-height ratio of the PiP bubble frame.
    public var aspectRatio: CGFloat {
        switch self {
        case .circle: return 1.0
        case .roundedRect: return 4.0 / 3.0
        case .vertical: return 3.0 / 4.0
        }
    }
}

public enum WebcamPiPCorner: String, CaseIterable, Identifiable, Codable, Sendable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bottomLeft: return L10n.t(.ksPosBottomLeft)
        case .bottomRight: return L10n.t(.ksPosBottomRight)
        case .topLeft: return L10n.t(.ksPosTopLeft)
        case .topRight: return L10n.t(.ksPosTopRight)
        }
    }
}

public struct WebcamPiPConfig: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var shape: WebcamPiPShape
    public var corner: WebcamPiPCorner
    /// Relative diameter / width fraction of the canvas shorter edge (`0.14...0.38`).
    public var sizeFraction: Double
    public var mirrored: Bool
    public var showBorder: Bool

    public init(
        enabled: Bool = true,
        shape: WebcamPiPShape = .circle,
        corner: WebcamPiPCorner = .bottomLeft,
        sizeFraction: Double = 0.22,
        mirrored: Bool = true,
        showBorder: Bool = true
    ) {
        self.enabled = enabled
        self.shape = shape
        self.corner = corner
        self.sizeFraction = sizeFraction
        self.mirrored = mirrored
        self.showBorder = showBorder
    }

    /// Computes exact PiP frame rect in **bottom-left CoreImage/CG canvas coordinates**.
    public func frameRectCI(in canvasSize: CGSize) -> CGRect {
        let clampedFrac = CGFloat(min(max(sizeFraction, 0.12), 0.42))
        let baseDim = min(canvasSize.width, canvasSize.height) * clampedFrac
        let w: CGFloat
        let h: CGFloat
        switch shape {
        case .circle:
            w = baseDim
            h = baseDim
        case .roundedRect:
            w = baseDim * 1.18
            h = w / shape.aspectRatio
        case .vertical:
            h = baseDim * 1.12
            w = h * shape.aspectRatio
        }
        let margin = max(18.0, min(canvasSize.width, canvasSize.height) * 0.036)
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .bottomLeft:
            x = margin
            y = margin
        case .bottomRight:
            x = canvasSize.width - w - margin
            y = margin
        case .topLeft:
            x = margin
            y = canvasSize.height - h - margin
        case .topRight:
            x = canvasSize.width - w - margin
            y = canvasSize.height - h - margin
        }
        return CGRect(x: x.rounded(), y: y.rounded(), width: max(24, w.rounded()), height: max(24, h.rounded()))
    }

    public func cornerRadius(for rect: CGRect) -> CGFloat {
        switch shape {
        case .circle:
            return min(rect.width, rect.height) / 2.0
        case .roundedRect:
            return min(rect.width, rect.height) * 0.18
        case .vertical:
            return min(rect.width, rect.height) * 0.22
        }
    }

    public static let `default` = WebcamPiPConfig()
}

public struct BeautifyStyle: Codable, Equatable, Sendable {
    public var background: BackgroundPreset
    public var padding: CGFloat          // fraction of shorter edge or pixel base (0...220 in design pts)
    public var cornerRadius: CGFloat     // 0...48
    public var shadowRadius: CGFloat     // 0...80
    public var shadowOpacity: CGFloat    // 0...0.85
    public var aspectRatio: AspectRatioPreset
    public var windowChrome: WindowChromeStyle
    public var windowTitle: String
    public var insetStroke: Bool
    public var watermark: WatermarkConfig

    public init(
        background: BackgroundPreset = .defaultScreenshot,
        padding: CGFloat = 64,
        cornerRadius: CGFloat = 18,
        shadowRadius: CGFloat = 36,
        shadowOpacity: CGFloat = 0.48,
        aspectRatio: AspectRatioPreset = .auto,
        windowChrome: WindowChromeStyle = .none,
        windowTitle: String = "",
        insetStroke: Bool = true,
        watermark: WatermarkConfig = .default
    ) {
        self.background = background
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
        self.aspectRatio = aspectRatio
        self.windowChrome = windowChrome
        self.windowTitle = windowTitle
        self.insetStroke = insetStroke
        self.watermark = watermark
    }

    public static var defaultScreenshot: BeautifyStyle {
        BeautifyStyle(
            background: .defaultScreenshot,
            padding: 64,
            cornerRadius: 18,
            shadowRadius: 36,
            shadowOpacity: 0.45,
            aspectRatio: .auto,
            windowChrome: .none,
            insetStroke: true
        )
    }

    public static var defaultVideo: BeautifyStyle {
        BeautifyStyle(
            background: .defaultVideo,
            padding: 56,
            cornerRadius: 20,
            shadowRadius: 42,
            shadowOpacity: 0.50,
            aspectRatio: .wide16x9,
            windowChrome: .none,
            insetStroke: true
        )
    }
}

public enum VideoExportPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case xOptimal1080p60
    case xPremium1440p60
    case xUltra4K60
    case gifSmooth

    public var id: String { rawValue }

    public var title: String {
        shortTitle
    }

    public var shortTitle: String {
        switch self {
        case .xOptimal1080p60: return L10n.t(.export1080pShort)
        case .xPremium1440p60: return L10n.t(.export2KShort)
        case .xUltra4K60: return L10n.t(.export4KShort)
        case .gifSmooth: return L10n.t(.exportGIFShort)
        }
    }

    public var maxLongEdge: Int {
        switch self {
        case .xOptimal1080p60: return 1920
        case .xPremium1440p60: return 2560
        case .xUltra4K60: return 3840
        case .gifSmooth: return 960
        }
    }

    public var fps: Int {
        switch self {
        case .xOptimal1080p60, .xPremium1440p60, .xUltra4K60: return 60
        case .gifSmooth: return 24
        }
    }

    public var targetBitrate: Int {
        switch self {
        case .xOptimal1080p60: return 18_000_000 // 18 Mbps — keeps UI text razor sharp after X transcode
        case .xPremium1440p60: return 28_000_000 // 28 Mbps
        case .xUltra4K60: return 42_000_000      // 42 Mbps
        case .gifSmooth: return 0
        }
    }

    public var isGIF: Bool {
        self == .gifSmooth
    }
}

public enum KeystrokeVisualStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case macKeycapDark
    case macKeycapLight
    case minimalGlass
    case neonAccent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .macKeycapDark: return L10n.t(.ksStyleDark)
        case .macKeycapLight: return L10n.t(.ksStyleLight)
        case .minimalGlass: return L10n.t(.ksStyleMinimal)
        case .neonAccent: return L10n.t(.ksStyleNeon)
        }
    }
}

public enum KeystrokePosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight
    case custom

    public var id: String { rawValue }

    public static let presetCases: [KeystrokePosition] = [
        .topLeft, .topCenter, .topRight,
        .bottomLeft, .bottomCenter, .bottomRight
    ]

    public var displayName: String {
        switch self {
        case .topLeft: return L10n.t(.ksPosTopLeft)
        case .topCenter: return L10n.t(.ksPosTopCenter)
        case .topRight: return L10n.t(.ksPosTopRight)
        case .bottomLeft: return L10n.t(.ksPosBottomLeft)
        case .bottomCenter: return L10n.t(.ksPosBottomCenter)
        case .bottomRight: return L10n.t(.ksPosBottomRight)
        case .custom: return L10n.t(.ksPosCustom)
        }
    }

    /// Default normalized (x, y) center in top-left canvas space [0...1] for each preset.
    public var normalizedAnchor: (x: Double, y: Double) {
        switch self {
        case .topLeft: return (0.14, 0.08)
        case .topCenter: return (0.50, 0.08)
        case .topRight: return (0.86, 0.08)
        case .bottomLeft: return (0.14, 0.91)
        case .bottomCenter: return (0.50, 0.91)
        case .bottomRight: return (0.86, 0.91)
        case .custom: return (0.50, 0.91)
        }
    }
}

public enum KeystrokeFilterMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case shortcutsOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return L10n.t(.ksFilterAll)
        case .shortcutsOnly: return L10n.t(.ksFilterShortcutsOnly)
        }
    }
}

public struct KeystrokeStyleConfig: Codable, Equatable, Sendable {
    public var visualStyle: KeystrokeVisualStyle
    public var position: KeystrokePosition
    /// Normalized [0, 1] center X (0 = left, 1 = right) when `position == .custom`
    public var customX: Double
    /// Normalized [0, 1] center Y (0 = top, 1 = bottom) when `position == .custom`
    public var customY: Double
    public var sizeScale: Double
    public var filterMode: KeystrokeFilterMode

    public init(
        visualStyle: KeystrokeVisualStyle = .macKeycapDark,
        position: KeystrokePosition = .bottomCenter,
        customX: Double = 0.50,
        customY: Double = 0.91,
        sizeScale: Double = 1.0,
        filterMode: KeystrokeFilterMode = .all
    ) {
        self.visualStyle = visualStyle
        self.position = position
        self.customX = customX
        self.customY = customY
        self.sizeScale = sizeScale
        self.filterMode = filterMode
    }

    /// Effective normalized center (top-left origin) used by interactive preview drag overlay.
    public var effectiveNormalizedCenter: (x: Double, y: Double) {
        if position == .custom {
            return (min(max(customX, 0.04), 0.96), min(max(customY, 0.04), 0.96))
        }
        return position.normalizedAnchor
    }

    public mutating func applyPresetPosition(_ preset: KeystrokePosition) {
        self.position = preset
        let anchor = preset.normalizedAnchor
        self.customX = anchor.x
        self.customY = anchor.y
    }

    public static let `default` = KeystrokeStyleConfig()
}
