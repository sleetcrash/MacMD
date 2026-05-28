import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Produce a 1280x640 GitHub social preview card from docs/screenshot.png.
// The screenshot is scaled to fit inside the card with padding, centered on a
// black background that matches the app's aesthetic.

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("usage: make_social_preview.swift <input.png> <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("could not read \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

let cardW: CGFloat = 1280
let cardH: CGFloat = 640
let padding: CGFloat = 40

let srcW = CGFloat(image.width)
let srcH = CGFloat(image.height)
let maxW = cardW - padding * 2
let maxH = cardH - padding * 2
let scale = min(maxW / srcW, maxH / srcH)
let drawW = srcW * scale
let drawH = srcH * scale
let drawX = (cardW - drawW) / 2
let drawY = (cardH - drawH) / 2

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(cardW),
    height: Int(cardH),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("could not create bitmap context\n".data(using: .utf8)!)
    exit(1)
}

ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: cardW, height: cardH))

ctx.interpolationQuality = .high
ctx.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("could not open output\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
if !CGImageDestinationFinalize(dest) {
    FileHandle.standardError.write("could not write output\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outputPath) (\(Int(cardW))x\(Int(cardH)))")
