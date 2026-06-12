#!/usr/bin/env swift
// Generates the PathPal app icon at all macOS sizes.
// Usage: swift scripts/generate-icon.swift <output-dir>
// Renders each size independently (no downscaling) so small sizes stay crisp.

import AppKit

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "PathPal/PathPal/Resources/Assets.xcassets/AppIcon.appiconset"

// (filename, pixel size) — one file per asset-catalog slot
let slots: [(name: String, px: Int)] = [
    ("icon_16", 16), ("icon_16@2x", 32),
    ("icon_32", 32), ("icon_32@2x", 64),
    ("icon_128", 128), ("icon_128@2x", 256),
    ("icon_256", 256), ("icon_256@2x", 512),
    ("icon_512", 512), ("icon_512@2x", 1024),
]

func render(px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple icon grid: content occupies 824/1024 of the canvas, radius 185.4/1024
    let inset = s * (100.0 / 1024.0)
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = s * (185.4 / 1024.0)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Drop shadow within the canvas margin (matches stock macOS icons)
    if px >= 64 {
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = s * 0.012
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        shadow.set()
        NSColor.black.setFill()
        squircle.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // Blue → purple gradient matching the onboarding branding
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.25, green: 0.48, blue: 1.00, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.58, green: 0.27, blue: 0.96, alpha: 1.0)
    )!
    gradient.draw(in: squircle, angle: -60)

    // White folder.badge.gearshape symbol, centered
    let config = NSImage.SymbolConfiguration(pointSize: s, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let aspect = symbol.size.height / symbol.size.width
        let drawW = rect.width * 0.62
        let drawH = drawW * aspect
        let drawRect = NSRect(
            x: rect.midX - drawW / 2,
            y: rect.midY - drawH / 2,
            width: drawW, height: drawH
        )
        symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for slot in slots {
    let data = render(px: slot.px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(slot.name).png")
    try! data.write(to: url)
    print("wrote \(url.path) (\(slot.px)x\(slot.px))")
}
