#!/usr/bin/env swift
//
// Renders the app icon and writes an .icns.
//
// The icon is drawn here instead of being checked in as a binary so it stays
// sharp at every size, stays in version control as readable code, and matches
// the in-app AppMark exactly.
//
// Usage: swift Scripts/make_icon.swift <output.icns>

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.icns"

// The same accent the UI uses (Design.accent).
let accent = NSColor(srgbRed: 0.98, green: 0.45, blue: 0.20, alpha: 1)
let accentDark = NSColor(srgbRed: 0.85, green: 0.33, blue: 0.12, alpha: 1)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.055
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.2237

    // macOS icons sit in a rounded "squircle"-ish frame with a subtle shadow.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
    shadow.set()

    let frame = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [accent, accentDark])!
    gradient.draw(in: frame, angle: -60)

    NSGraphicsContext.current?.saveGraphicsState()
    frame.addClip()

    // A soft diagonal highlight, the way a real Mac icon catches light.
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.28),
        NSColor.white.withAlphaComponent(0.0)
    ])!
    highlight.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2),
                   angle: 90)

    // The "H" mark: two stems and a crossbar, drawn as one path.
    let insetX = body.width * 0.255
    let stemWidth = body.width * 0.105
    let top = body.maxY - body.height * 0.265
    let bottom = body.minY + body.height * 0.265
    let crossbarTop = body.midY + body.height * 0.055
    let crossbarBottom = body.midY - body.height * 0.055

    let mark = NSBezierPath()
    // Left stem
    mark.appendRoundedRect(NSRect(x: body.minX + insetX, y: bottom,
                                  width: stemWidth, height: top - bottom),
                           xRadius: stemWidth / 2, yRadius: stemWidth / 2)
    // Right stem
    mark.appendRoundedRect(NSRect(x: body.maxX - insetX - stemWidth, y: bottom,
                                  width: stemWidth, height: top - bottom),
                           xRadius: stemWidth / 2, yRadius: stemWidth / 2)
    // Crossbar
    mark.appendRoundedRect(NSRect(x: body.minX + insetX, y: crossbarBottom,
                                  width: body.width - insetX * 2, height: crossbarTop - crossbarBottom),
                           xRadius: stemWidth / 2, yRadius: stemWidth / 2)

    NSColor.white.setFill()
    mark.fill()

    NSGraphicsContext.current?.restoreGraphicsState()
    return image
}

func png(from image: NSImage, pixels: Int) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    // Re-render at an exact pixel size; tiffRepresentation follows the point size.
    if let exact = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: pixels,
                                    pixelsHigh: pixels,
                                    bitsPerSample: 8,
                                    samplesPerPixel: 4,
                                    hasAlpha: true,
                                    isPlanar: false,
                                    colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0,
                                    bitsPerPixel: 0) {
        exact.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: exact)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        if let context = NSGraphicsContext.current {
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                       from: .zero, operation: .sourceOver, fraction: 1)
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        return exact.representation(using: .png, properties: [:])
    }
    return rep.representation(using: .png, properties: [:])
}

// The icon sizes macOS expects in an .icns.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

// The .iconset must be a *sibling* of the directory holding the PNGs, not a
// child of it: moving a directory into itself fails, and that error is what
// left the shipped app with an empty AppIcon.icns.
let workRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("hfh-icon-\(UUID().uuidString)", isDirectory: true)
let iconset = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: workRoot)
    try? FileManager.default.removeItem(at: iconset)
}

for variant in variants {
    let image = drawIcon(size: CGFloat(variant.pixels))
    guard let data = png(from: image, pixels: variant.pixels) else {
        FileHandle.standardError.write("failed to render \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputPath]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("icon written to \(outputPath)")
} else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
