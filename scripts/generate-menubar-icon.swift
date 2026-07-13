import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let dimension = 36
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: dimension,
    height: dimension,
    bitsPerComponent: 8,
    bytesPerRow: dimension * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Unable to create menu bar icon context") }

context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(2.5)
context.setLineCap(.round)
context.setLineJoin(.round)

let bubble = CGRect(x: 5, y: 9, width: 26, height: 18)
context.addPath(CGPath(roundedRect: bubble, cornerWidth: 7, cornerHeight: 7, transform: nil))
context.strokePath()

context.move(to: CGPoint(x: 11, y: 10))
context.addLine(to: CGPoint(x: 8, y: 5))
context.addLine(to: CGPoint(x: 16, y: 10))
context.strokePath()

context.move(to: CGPoint(x: 10, y: 18))
context.addLine(to: CGPoint(x: 13, y: 18))
context.addLine(to: CGPoint(x: 15, y: 14))
context.addLine(to: CGPoint(x: 18, y: 22))
context.addLine(to: CGPoint(x: 21, y: 16))
context.addLine(to: CGPoint(x: 24, y: 18))
context.addLine(to: CGPoint(x: 27, y: 18))
context.strokePath()

guard let image = context.makeImage() else { fatalError("Unable to create menu bar icon image") }
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Unable to create PNG destination") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write menu bar icon") }
