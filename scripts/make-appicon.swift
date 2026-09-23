// Draws the MacDevClean application icon and writes a complete
// AppIcon.appiconset.
//
// The artwork is original: a storage stack whose top layer has been cleared,
// over a rounded gradient tile. Nothing here is traced from Apple artwork, a
// vendor logo, or the interface mockup.
//
// Usage: swift scripts/make-appicon.swift <path-to-AppIcon.appiconset>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("usage: make-appicon.swift <AppIcon.appiconset path>\n".utf8))
    exit(2)
}
let destination = URL(fileURLWithPath: arguments[1])

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1)
    -> CGColor
{
    CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [
            CGFloat(red / 255), CGFloat(green / 255), CGFloat(blue / 255), CGFloat(alpha),
        ])!
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(
        roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
        transform: nil)
}

func drawIcon(size: Int) -> CGImage? {
    let side = CGFloat(size)
    guard
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    context.interpolationQuality = .high
    context.setShouldAntialias(true)

    // The tile. Inset so the icon has the breathing room macOS expects.
    let inset = side * 0.08
    let tile = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let tilePath = roundedPath(tile, radius: tile.width * 0.2237)

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(38, 70, 116), color(22, 38, 64)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    context.restoreGState()

    // Three storage layers. The top one is shorter and brighter: what the
    // product does is clear a layer, not empty the disk.
    let layerHeight = tile.height * 0.135
    let spacing = tile.height * 0.055
    let fullWidth = tile.width * 0.62
    let left = tile.midX - fullWidth / 2
    let bottom = tile.midY - (layerHeight * 1.5 + spacing)

    let widths: [CGFloat] = [fullWidth, fullWidth, fullWidth * 0.42]
    let fills = [color(122, 162, 214), color(150, 189, 236), color(126, 231, 196)]

    for index in 0..<3 {
        let rect = CGRect(
            x: left,
            y: bottom + CGFloat(index) * (layerHeight + spacing),
            width: widths[index],
            height: layerHeight)
        context.addPath(roundedPath(rect, radius: layerHeight * 0.32))
        context.setFillColor(fills[index])
        context.fillPath()
    }

    // The space the cleared layer used to occupy, drawn as an outline so the
    // icon says "reclaimable", not "deleted".
    let ghost = CGRect(
        x: left + widths[2] + tile.width * 0.035,
        y: bottom + 2 * (layerHeight + spacing),
        width: fullWidth - widths[2] - tile.width * 0.035,
        height: layerHeight)
    context.addPath(roundedPath(ghost, radius: layerHeight * 0.32))
    context.setStrokeColor(color(126, 231, 196, 0.55))
    context.setLineWidth(max(1, side * 0.012))
    context.strokePath()

    guard let image = context.makeImage() else { return nil }
    return image
}

func write(_ image: CGImage, to url: URL) throws {
    guard
        let output = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw NSError(domain: "make-appicon", code: 1)
    }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else {
        throw NSError(domain: "make-appicon", code: 2)
    }
}

struct Entry {
    let idiom = "mac"
    let size: Int
    let scale: Int
    var pixels: Int { size * scale }
    var filename: String {
        scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    }
}

let entries = [16, 32, 128, 256, 512].flatMap { size in
    [Entry(size: size, scale: 1), Entry(size: size, scale: 2)]
}

try FileManager.default.createDirectory(
    at: destination, withIntermediateDirectories: true)

var rendered: [Int: CGImage] = [:]
for entry in entries {
    let image: CGImage
    if let existing = rendered[entry.pixels] {
        image = existing
    } else {
        guard let drawn = drawIcon(size: entry.pixels) else {
            FileHandle.standardError.write(Data("failed to draw \(entry.pixels)\n".utf8))
            exit(1)
        }
        rendered[entry.pixels] = drawn
        image = drawn
    }
    try write(image, to: destination.appendingPathComponent(entry.filename))
}

let images = entries.map { entry in
    [
        "idiom": entry.idiom,
        "size": "\(entry.size)x\(entry.size)",
        "scale": "\(entry.scale)x",
        "filename": entry.filename,
    ]
}
let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let data = try JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: destination.appendingPathComponent("Contents.json"))

print("wrote \(entries.count) icon files to \(destination.path)")
