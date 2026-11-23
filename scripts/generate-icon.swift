#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let iconsetPath = CommandLine.arguments[1]
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    let s = CGFloat(pixelSize)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS Big Sur / Sequoia squircle inset (~8.5% margin)
    let inset = s * 0.085
    let card = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = card.width * 0.225
    let cardPath = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.04, color: CGColor(gray: 0, alpha: 0.42))
    ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.07, blue: 0.13, alpha: 1))
    ctx.addPath(cardPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Rich dark cosmic gradient + cyan/violet glow inside squircle
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()

    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(srgbRed: 0.05, green: 0.08, blue: 0.16, alpha: 1),
            CGColor(srgbRed: 0.10, green: 0.12, blue: 0.28, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: card.minX, y: card.maxY), end: CGPoint(x: card.maxX, y: card.minY), options: [])

    let orb1 = CGGradient(
        colorsSpace: cs,
        colors: [CGColor(srgbRed: 0.06, green: 0.78, blue: 0.98, alpha: 0.55), CGColor(srgbRed: 0.06, green: 0.78, blue: 0.98, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(orb1, startCenter: CGPoint(x: card.minX + card.width * 0.24, y: card.maxY - card.height * 0.22), startRadius: 0, endCenter: CGPoint(x: card.minX + card.width * 0.24, y: card.maxY - card.height * 0.22), endRadius: card.width * 0.65, options: [])

    let orb2 = CGGradient(
        colorsSpace: cs,
        colors: [CGColor(srgbRed: 0.58, green: 0.25, blue: 0.96, alpha: 0.58), CGColor(srgbRed: 0.58, green: 0.25, blue: 0.96, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(orb2, startCenter: CGPoint(x: card.maxX - card.width * 0.2, y: card.minY + card.height * 0.22), startRadius: 0, endCenter: CGPoint(x: card.maxX - card.width * 0.2, y: card.minY + card.height * 0.22), endRadius: card.width * 0.65, options: [])

    // Center viewfinder lens ring + sleek X crop frame
    let cx = s / 2
    let cy = s / 2
    let ringR = card.width * 0.30
    let ringRect = CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)

    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.setLineWidth(s * 0.042)
    ctx.strokeEllipse(in: ringRect)

    // Recording red jewel dot top-right of card
    let dotR = card.width * 0.068
    let dotRect = CGRect(x: card.maxX - card.width * 0.22 - dotR, y: card.maxY - card.height * 0.22 - dotR, width: dotR * 2, height: dotR * 2)
    ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.25, blue: 0.37, alpha: 1))
    ctx.fillEllipse(in: dotRect)

    // Crisp inner cyan core lens
    let innerR = card.width * 0.115
    let innerRect = CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2)
    let coreGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(srgbRed: 0.22, green: 0.85, blue: 1.0, alpha: 1),
            CGColor(srgbRed: 0.55, green: 0.36, blue: 0.98, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.addEllipse(in: innerRect)
    ctx.clip()
    ctx.drawLinearGradient(coreGrad, start: CGPoint(x: innerRect.minX, y: innerRect.maxY), end: CGPoint(x: innerRect.maxX, y: innerRect.minY), options: [])
    ctx.restoreGState()

    // Subtle glass top highlight border
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(max(1, s * 0.014))
    ctx.addPath(cardPath)
    ctx.strokePath()

    ctx.restoreGState()
    return ctx.makeImage()!
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    let img = renderIcon(pixelSize: px)
    let rep = NSBitmapImageRep(cgImage: img)
    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    }
}
