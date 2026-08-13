import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares dropped reference images for upload: downscale to a sane size and
/// re-encode, so a 12 MP photo doesn't become a 15 MB base64 request body.
nonisolated enum ImageEncoding {
    struct EncodedImage: Sendable {
        let data: Data
        let mime: String   // image/jpeg or image/png

        var dataURI: String {
            "data:\(mime);base64,\(data.base64EncodedString())"
        }
    }

    enum EncodingError: Error, LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            if case .unreadable(let name) = self { return "Could not read image: \(name)" }
            return nil
        }
    }

    /// Load an image file, downscale to longest edge `maxPixel`, and encode
    /// JPEG (or PNG when the source has an alpha channel).
    static func encodeForUpload(fileURL: URL, maxPixel: Int = 2048) throws -> EncodedImage {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw EncodingError.unreadable(fileURL.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw EncodingError.unreadable(fileURL.lastPathComponent)
        }
        let hasAlpha: Bool
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let type: UTType = hasAlpha ? .png : .jpeg
        let destData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(destData, type.identifier as CFString, 1, nil) else {
            throw EncodingError.unreadable(fileURL.lastPathComponent)
        }
        let destOptions: [CFString: Any] = hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(dest, cgImage, destOptions as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw EncodingError.unreadable(fileURL.lastPathComponent)
        }
        return EncodedImage(data: destData as Data, mime: hasAlpha ? "image/png" : "image/jpeg")
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    static func mime(forData data: Data) -> String {
        // PNG magic number: 0x89 'P' 'N' 'G'
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
    }

    static func dataURI(_ data: Data) -> String {
        "data:\(mime(forData: data));base64,\(data.base64EncodedString())"
    }
}
