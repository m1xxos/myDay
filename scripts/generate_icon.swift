import Foundation
import AppKit
import CoreGraphics

func renderMasterIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let scale = size / 1024.0

    // 1. Shadow for the squircle
    let squircleInset = 100.0 * scale
    let squircleRect = CGRect(
        x: squircleInset,
        y: squircleInset,
        width: size - (squircleInset * 2),
        height: size - (squircleInset * 2)
    )
    let cornerRadius = 185.0 * scale

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -24 * scale),
        blur: 36 * scale,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
    )

    let squirclePath = CGPath(
        roundedRect: squircleRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Draw Squircle Gradient Background
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Base background gradient: Deep Space Dark (Indigo -> Violet -> Obsidian)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.12, green: 0.08, blue: 0.28, alpha: 1.0), // Top indigo/violet
        CGColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1.0), // Mid dark
        CGColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0)  // Deep obsidian
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
            end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
            options: []
        )
    }

    // Radial Neon Bloom under the center star
    let bloomColors = [
        CGColor(red: 0.45, green: 0.18, blue: 0.95, alpha: 0.45), // Glowing Purple
        CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.15),  // Neon Cyan
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    ] as CFArray
    let bloomLocations: [CGFloat] = [0.0, 0.5, 1.0]
    if let bloomGradient = CGGradient(colorsSpace: colorSpace, colors: bloomColors, locations: bloomLocations) {
        ctx.drawRadialGradient(
            bloomGradient,
            startCenter: CGPoint(x: size / 2, y: size / 2),
            startRadius: 0,
            endCenter: CGPoint(x: size / 2, y: size / 2),
            endRadius: 280 * scale,
            options: []
        )
    }

    // 3. 24-Hour Timelapse Orbit Ring
    let center = CGPoint(x: size / 2, y: size / 2)
    let orbitRadius = 220.0 * scale
    let orbitRect = CGRect(
        x: center.x - orbitRadius,
        y: center.y - orbitRadius,
        width: orbitRadius * 2,
        height: orbitRadius * 2
    )

    ctx.saveGState()
    ctx.setLineWidth(14.0 * scale)
    ctx.setLineCap(.round)

    // Soft glow for orbit
    ctx.setShadow(
        offset: .zero,
        blur: 16 * scale,
        color: CGColor(red: 0.47, green: 0.16, blue: 0.82, alpha: 0.8)
    )

    // Draw circular arc representing 24h cycle (from -140 deg to 140 deg)
    let orbitPath = CGMutablePath()
    orbitPath.addArc(
        center: center,
        radius: orbitRadius,
        startAngle: CGFloat(-Double.pi * 0.75),
        endAngle: CGFloat(Double.pi * 0.75),
        clockwise: false
    )
    ctx.addPath(orbitPath)
    ctx.setStrokeColor(CGColor(red: 0.55, green: 0.25, blue: 0.95, alpha: 0.9))
    ctx.strokePath()
    ctx.restoreGState()

    // Micro Timelapse ticks on the orbit ring
    for i in 0..<12 {
        let angle = CGFloat(Double.pi * 2.0 * Double(i) / 12.0)
        let dotRadius = 4.0 * scale
        let dotX = center.x + (orbitRadius) * cos(angle)
        let dotY = center.y + (orbitRadius) * sin(angle)
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: i % 3 == 0 ? 0.9 : 0.4))
        ctx.fillEllipse(in: CGRect(x: dotX - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    }

    // 4. Central Radiant AI Sparkle Star (✦)
    func drawSparkle(at pt: CGPoint, radius: CGFloat, waist: CGFloat, color: CGColor, glowColor: CGColor, glowBlur: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: glowBlur, color: glowColor)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: pt.x, y: pt.y + radius))
        path.addQuadCurve(to: CGPoint(x: pt.x + radius, y: pt.y), control: CGPoint(x: pt.x + waist, y: pt.y + waist))
        path.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y - radius), control: CGPoint(x: pt.x + waist, y: pt.y - waist))
        path.addQuadCurve(to: CGPoint(x: pt.x - radius, y: pt.y), control: CGPoint(x: pt.x - waist, y: pt.y - waist))
        path.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y + radius), control: CGPoint(x: pt.x - waist, y: pt.y + waist))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Main Star
    drawSparkle(
        at: center,
        radius: 120 * scale,
        waist: 26 * scale,
        color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        glowColor: CGColor(red: 0.45, green: 0.25, blue: 1.0, alpha: 0.9),
        glowBlur: 24 * scale
    )

    // Inner highlight star core
    drawSparkle(
        at: center,
        radius: 50 * scale,
        waist: 12 * scale,
        color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        glowColor: CGColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 0.9),
        glowBlur: 14 * scale
    )

    // Secondary Accent Stars
    drawSparkle(
        at: CGPoint(x: center.x + 130 * scale, y: center.y + 120 * scale),
        radius: 36 * scale,
        waist: 8 * scale,
        color: CGColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 0.95),
        glowColor: CGColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.8),
        glowBlur: 12 * scale
    )

    drawSparkle(
        at: CGPoint(x: center.x - 120 * scale, y: center.y - 110 * scale),
        radius: 28 * scale,
        waist: 6 * scale,
        color: CGColor(red: 0.9, green: 0.45, blue: 1.0, alpha: 0.9),
        glowColor: CGColor(red: 0.8, green: 0.3, blue: 1.0, alpha: 0.7),
        glowBlur: 10 * scale
    )

    // 5. Delicate Glass Rim Highlight along squircle border
    ctx.setLineWidth(2.5 * scale)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.22))
    ctx.addPath(squirclePath)
    ctx.strokePath()

    ctx.restoreGState()

    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, targetSize: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetSize,
        pixelsHigh: targetSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: targetSize, height: targetSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
        from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: url)
    }
}

let fm = FileManager.default
let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconsetDir)
try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

print("🎨 Rendering master 1024x1024 MyDay icon...")
let master = renderMasterIcon(size: 1024)

let iconSizes: [(name: String, px: Int)] = [
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

for item in iconSizes {
    let fileURL = iconsetDir.appendingPathComponent(item.name)
    savePNG(image: master, targetSize: item.px, to: fileURL)
}

print("📦 Packaging into AppIcon.icns via iconutil...")
let resourcesDir = URL(fileURLWithPath: "Resources")
try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "AppIcon.iconset", "-o", icnsURL.path]
try? task.run()
task.waitUntilExit()

try? fm.removeItem(at: iconsetDir)
print("✅ Generated: \(icnsURL.path)")
