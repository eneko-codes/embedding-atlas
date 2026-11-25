import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Invented pictures for the image tests: noise, so that a PNG of one is large.
enum Pictures {

    static func png(width: Int, height: Int, noise: Bool = false) -> String {
        var generator = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = noise ? UInt8.random(in: 0...255, using: &generator) : 200
            pixels[index] = value
            pixels[index + 1] = noise ? UInt8.random(in: 0...255, using: &generator) : 120
            pixels[index + 2] = noise ? UInt8.random(in: 0...255, using: &generator) : 40
            pixels[index + 3] = 255
        }
        let image = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return (output as Data).base64EncodedString()
    }
}
