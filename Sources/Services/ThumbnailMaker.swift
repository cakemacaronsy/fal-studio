import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

/// Makes small JPEG thumbnails for gallery cards.
nonisolated enum ThumbnailMaker {
    static func imageThumbnail(from data: Data, maxPixel: Int = 480) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return encodeJPEG(cgImage)
    }

    static func videoThumbnail(url: URL, maxPixel: Int = 480) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return encodeJPEG(result.image)
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let destData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(destData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return destData as Data
    }
}
