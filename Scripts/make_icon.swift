import AppKit
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func renderIcon(pixels: Int, to path: String) -> Bool {
    let size = CGFloat(pixels)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }

    let cornerRadius = size * (185.0 / 1024.0)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let rounded = CGPath(roundedRect: rect,
                         cornerWidth: cornerRadius,
                         cornerHeight: cornerRadius,
                         transform: nil)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.addPath(rounded)
    ctx.fillPath()

    let fontSize = size * 0.38
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        .kern: -(fontSize * 0.03)
    ]
    let string = NSAttributedString(string: ".MD", attributes: attrs)

    let line = CTLineCreateWithAttributedString(string)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let textHeight = ascent + descent

    let x = (size - width) / 2.0
    let y = (size - textHeight) / 2.0 + descent

    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)

    guard let cgImage = ctx.makeImage() else { return false }

    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(dest, cgImage, nil)
    return CGImageDestinationFinalize(dest)
}

let outputs: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
for (px, name) in outputs {
    let p = "\(dir)/\(name)"
    if renderIcon(pixels: px, to: p) {
        print("wrote \(p) (\(px)x\(px))")
    } else {
        FileHandle.standardError.write("failed at \(name)\n".data(using: .utf8)!)
        exit(1)
    }
}
