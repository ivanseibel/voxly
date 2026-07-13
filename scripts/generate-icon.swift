import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [16, 32, 128, 256, 512, 1024]
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for size in sizes {
    let dimension = size * 2
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: dimension,
        height: dimension,
        bitsPerComponent: 8,
        bytesPerRow: dimension * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Unable to create icon context") }

    context.setFillColor(CGColor(red: 0.055, green: 0.09, blue: 0.12, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))

    let inset = CGFloat(dimension) * 0.08
    let tile = CGRect(x: inset, y: inset, width: CGFloat(dimension) - inset * 2, height: CGFloat(dimension) - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: CGFloat(dimension) * 0.22, cornerHeight: CGFloat(dimension) * 0.22, transform: nil)
    context.addPath(tilePath)
    context.clip()

    let gradientColors = [
        CGColor(red: 0.07, green: 0.42, blue: 0.48, alpha: 1),
        CGColor(red: 0.18, green: 0.73, blue: 0.67, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(dimension)), end: CGPoint(x: CGFloat(dimension), y: 0), options: [])

    let bubble = CGRect(x: CGFloat(dimension) * 0.20, y: CGFloat(dimension) * 0.25, width: CGFloat(dimension) * 0.60, height: CGFloat(dimension) * 0.46)
    let bubblePath = CGPath(roundedRect: bubble, cornerWidth: CGFloat(dimension) * 0.12, cornerHeight: CGFloat(dimension) * 0.12, transform: nil)
    context.setFillColor(CGColor(red: 0.97, green: 0.99, blue: 0.95, alpha: 1))
    context.addPath(bubblePath)
    context.fillPath()

    context.move(to: CGPoint(x: CGFloat(dimension) * 0.35, y: CGFloat(dimension) * 0.27))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.30, y: CGFloat(dimension) * 0.16))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.49, y: CGFloat(dimension) * 0.27))
    context.closePath()
    context.setFillColor(CGColor(red: 0.97, green: 0.99, blue: 0.95, alpha: 1))
    context.fillPath()

    context.setStrokeColor(CGColor(red: 0.07, green: 0.42, blue: 0.48, alpha: 1))
    context.setLineWidth(CGFloat(dimension) * 0.035)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: CGFloat(dimension) * 0.32, y: CGFloat(dimension) * 0.48))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.39, y: CGFloat(dimension) * 0.48))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.43, y: CGFloat(dimension) * 0.39))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.48, y: CGFloat(dimension) * 0.57))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.53, y: CGFloat(dimension) * 0.43))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.59, y: CGFloat(dimension) * 0.48))
    context.addLine(to: CGPoint(x: CGFloat(dimension) * 0.68, y: CGFloat(dimension) * 0.48))
    context.strokePath()

    guard let image = context.makeImage() else { fatalError("Unable to create icon image") }
    let fileURL = outputDirectory.appendingPathComponent("icon_\(size)x\(size)@2x.png")
    guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Unable to create PNG destination") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write PNG") }
}
