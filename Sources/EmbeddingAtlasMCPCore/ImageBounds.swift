import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Brings an image the view returned (a screenshot) inside the limits of one result: at most
/// `ToolCatalog.longestImageSide` pixels on its long side and `ToolCatalog.largestImageBytes`
/// bytes. ImageIO is the system's own; nothing is added to the package.
enum ImageBounds {

    struct Fitted: Equatable {
        var data: String
        var mimeType: String
        /// `nil` when the image was already within the limits and is passed unchanged.
        var notice: String?
    }

    /// `nil` when the data is not an image the system can read, or cannot be brought within
    /// the limits.
    static func fit(base64: String, mimeType: String) -> Fitted? {
        guard let original = Data(base64Encoded: base64),
            let source = CGImageSourceCreateWithData(original as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }

        let longSide = max(width, height)
        if longSide <= ToolCatalog.longestImageSide && original.count <= ToolCatalog.largestImageBytes {
            return Fitted(data: base64, mimeType: mimeType, notice: nil)
        }

        // PNG first: a screenshot is mostly text and flat colour. JPEG only when the PNG
        // cannot be made small enough, and then at falling quality, then at a smaller size.
        let keepsPNG = mimeType == "image/png"
        var side = min(longSide, ToolCatalog.longestImageSide)
        while side >= ToolCatalog.smallestImageSide {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                var attempts: [(type: UTType, quality: Double?)] = keepsPNG ? [(.png, nil)] : []
                attempts += [0.85, 0.7, 0.5, 0.3].map { (UTType.jpeg, $0) }
                for attempt in attempts {
                    guard let encoded = encode(image, as: attempt.type, quality: attempt.quality),
                        encoded.count <= ToolCatalog.largestImageBytes
                    else { continue }
                    let notice = Self.notice(
                        from: (width, height, original.count),
                        to: (image.width, image.height, encoded.count))
                    return Fitted(
                        data: encoded.base64EncodedString(),
                        mimeType: attempt.type == .png ? "image/png" : "image/jpeg", notice: notice)
                }
            }
            side = side * 3 / 4
        }
        return nil
    }

    static func notice(from: (Int, Int, Int), to: (Int, Int, Int)) -> String {
        "The image was reduced from \(from.0)×\(from.1) pixels, \(from.2) bytes, to "
            + "\(to.0)×\(to.1) pixels, \(to.2) bytes, to fit the limits of a result."
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { return nil }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
