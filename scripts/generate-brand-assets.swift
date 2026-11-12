#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Draws a clean, minimalist, sculpted Blacksmith Anvil macOS icon — no outlines, no rainbow color mixes.
func renderAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size / 1024.0
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    ctx.saveGState()

    // 1. macOS squircle (824x824 inside 1024x1024)
    let pad = 100.0 * s
    let rect = CGRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
    let radius = 185.0 * s
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft macOS drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 28 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.setFillColor(CGColor(red: 0.07, green: 0.075, blue: 0.085, alpha: 1.0))
    ctx.addPath(bgPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Pure matte carbon background (subtle vertical tonal depth, single charcoal family)
    let bgColors = [
        CGColor(red: 0.125, green: 0.130, blue: 0.145, alpha: 1.0),
        CGColor(red: 0.070, green: 0.073, blue: 0.082, alpha: 1.0)
    ] as CFArray
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: size * 0.5, y: size - pad),
        end: CGPoint(x: size * 0.5, y: pad),
        options: []
    )

    // 2. Centered, bold, geometric-industrial Anvil (NO stroke/outline, clean solid bevel planes)
    // Coordinates in 1024x1024 space (y=0 at bottom, y=1024 at top)
    // Centered around y = 500, x = 512
    let anvil = CGMutablePath()
    // Base foot (bottom)
    anvil.move(to: CGPoint(x: 310 * s, y: 310 * s))
    anvil.addLine(to: CGPoint(x: 726 * s, y: 310 * s))
    // Right foot chamfer up
    anvil.addLine(to: CGPoint(x: 696 * s, y: 362 * s))
    // Right waist curve up to heel overhang
    anvil.addQuadCurve(to: CGPoint(x: 616 * s, y: 492 * s), control: CGPoint(x: 598 * s, y: 416 * s))
    // Heel underside out to right
    anvil.addLine(to: CGPoint(x: 760 * s, y: 492 * s))
    // Heel vertical face up to top table
    anvil.addLine(to: CGPoint(x: 760 * s, y: 586 * s))
    // Top flat working face across to the step
    anvil.addLine(to: CGPoint(x: 418 * s, y: 586 * s))
    // Slight step drop to the horn
    anvil.addLine(to: CGPoint(x: 404 * s, y: 564 * s))
    // Horn top edge extending left to tip
    anvil.addLine(to: CGPoint(x: 224 * s, y: 556 * s))
    // Horn underside sweeping smoothly back to left waist
    anvil.addQuadCurve(to: CGPoint(x: 422 * s, y: 472 * s), control: CGPoint(x: 300 * s, y: 482 * s))
    // Left waist curve down to left foot chamfer
    anvil.addQuadCurve(to: CGPoint(x: 340 * s, y: 362 * s), control: CGPoint(x: 434 * s, y: 412 * s))
    anvil.closeSubpath()

    // Soft grounding shadow directly beneath the anvil
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16 * s), blur: 32 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    ctx.setFillColor(CGColor(red: 0.85, green: 0.87, blue: 0.90, alpha: 1.0))
    ctx.addPath(anvil)
    ctx.fillPath()
    ctx.restoreGState()

    // Fill anvil with clean brushed steel / warm titanium vertical gradient (no outline)
    ctx.saveGState()
    ctx.addPath(anvil)
    ctx.clip()
    let anvilColors = [
        CGColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0), // Crisp top table highlight
        CGColor(red: 0.76, green: 0.79, blue: 0.84, alpha: 1.0), // Mid body steel
        CGColor(red: 0.54, green: 0.57, blue: 0.63, alpha: 1.0)  // Lower forged base
    ] as CFArray
    let anvilGrad = CGGradient(colorsSpace: colorSpace, colors: anvilColors, locations: [0.0, 0.48, 1.0])!
    ctx.drawLinearGradient(
        anvilGrad,
        start: CGPoint(x: 512 * s, y: 586 * s),
        end: CGPoint(x: 512 * s, y: 310 * s),
        options: []
    )

    // Subtle geometric facet plane on the lower waist/foot to give sculptural depth without any stroke
    let lowerFacet = CGMutablePath()
    lowerFacet.move(to: CGPoint(x: 310 * s, y: 310 * s))
    lowerFacet.addLine(to: CGPoint(x: 726 * s, y: 310 * s))
    lowerFacet.addLine(to: CGPoint(x: 696 * s, y: 362 * s))
    lowerFacet.addLine(to: CGPoint(x: 340 * s, y: 362 * s))
    lowerFacet.closeSubpath()
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.14))
    ctx.addPath(lowerFacet)
    ctx.fillPath()

    // Hardy hole (clean dark square punch on the upper right face, iconic anvil detail)
    let hardyRect = CGRect(x: 668 * s, y: 530 * s, width: 34 * s, height: 24 * s)
    let hardyPath = CGPath(roundedRect: hardyRect, cornerWidth: 5 * s, cornerHeight: 5 * s, transform: nil)
    ctx.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 0.75))
    ctx.addPath(hardyPath)
    ctx.fillPath()

    ctx.restoreGState()

    // Subtle squircle inner rim (neutral white 8% opacity, standard macOS icon finish)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
    ctx.setLineWidth(3 * s)
    ctx.addPath(bgPath)
    ctx.strokePath()

    ctx.restoreGState()
    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixelSize: Int) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "LoopsmithIcon", code: 1)
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LoopsmithIcon", code: 2)
    }
    try data.write(to: url)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let brandDir = root.appendingPathComponent("brand", isDirectory: true)
try fm.createDirectory(at: brandDir, withIntermediateDirectories: true)

let master = renderAppIcon(size: 1024)
try writePNG(master, to: brandDir.appendingPathComponent("AppIcon-1024.png"), pixelSize: 1024)

let icnsURL = brandDir.appendingPathComponent("AppIcon.icns")
let icnsSizes = [16, 32, 64, 128, 256, 512, 1024]
if let dest = CGImageDestinationCreateWithURL(icnsURL as CFURL, "com.apple.icns" as CFString, icnsSizes.count, nil) {
    for px in icnsSizes {
        let icon = renderAppIcon(size: CGFloat(px))
        if let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            CGImageDestinationAddImage(dest, cgImage, nil)
        }
    }
    CGImageDestinationFinalize(dest)
}
print("Generated \(icnsURL.path) and brand/AppIcon-1024.png")
