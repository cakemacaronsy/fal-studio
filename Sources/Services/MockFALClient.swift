import Foundation
import CoreGraphics
import CoreText
import AVFoundation
import UniformTypeIdentifiers
import ImageIO

/// Zero-credit stand-in for FALClient: renders a gradient placeholder image,
/// or writes a short gradient mp4 for video models. Enabled via the Settings
/// "Mock mode" toggle or the FAL_STUDIO_MOCK=1 environment variable.
nonisolated struct MockFALClient: FALClientProtocol {
    func generate(endpoint: String,
                  queued: Bool,
                  payload: [String: JSONValue],
                  onUpdate: @escaping @Sendable (_ status: String?, _ requestID: String?) -> Void)
        async throws -> [MediaFile] {
        let prompt = payload["prompt"]?.stringValue ?? ""
        onUpdate(queued ? "IN_QUEUE" : "GENERATING", queued ? "mock-\(UUID().uuidString.prefix(8))" : nil)
        try await Task.sleep(for: .seconds(1))
        if queued {
            onUpdate("IN_PROGRESS", nil)
            try await Task.sleep(for: .seconds(2))
        } else {
            try await Task.sleep(for: .seconds(1))
        }
        let isVideo = endpoint.contains("video")
        if isVideo {
            let data = try Self.makeVideo(prompt: prompt)
            return [MediaFile(data: data, fileExtension: "mp4")]
        }
        let count = payload["num_images"]?.intValue ?? 1
        return try (0..<count).map { index in
            MediaFile(data: try Self.makeImage(prompt: prompt, variant: index), fileExtension: "png")
        }
    }

    func generateText(model: String, systemPrompt: String, prompt: String) async throws -> String {
        try await Task.sleep(for: .seconds(1))
        return "[MOCK improved via \(model)] \(prompt) — detailed subject, balanced composition, cinematic lighting, 50mm lens."
    }

    // MARK: Placeholder image

    private static func hueSeed(_ text: String) -> Double {
        Double(abs(text.hashValue % 360)) / 360.0
    }

    private static func drawFrame(in ctx: CGContext, size: CGSize, prompt: String,
                                  variant: Int, phase: Double) {
        let seed = hueSeed(prompt) + Double(variant) * 0.13 + phase * 0.2
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        func color(_ offset: Double) -> CGColor {
            let h = (seed + offset).truncatingRemainder(dividingBy: 1.0)
            // cheap HSV→RGB, s=0.55 v=0.9
            let i = Int(h * 6), f = h * 6 - Double(i)
            let v = 0.9, s = 0.55
            let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
            let rgb: [Double]
            switch i % 6 {
            case 0: rgb = [v, t, p]; case 1: rgb = [q, v, p]; case 2: rgb = [p, v, t]
            case 3: rgb = [p, q, v]; case 4: rgb = [t, p, v]; default: rgb = [v, p, q]
            }
            return CGColor(colorSpace: colorSpace, components: [rgb[0], rgb[1], rgb[2], 1])!
        }
        let gradient = CGGradient(colorsSpace: colorSpace,
                                  colors: [color(0), color(0.35)] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient,
                               start: .zero,
                               end: CGPoint(x: size.width, y: size.height),
                               options: [])
        // Prompt excerpt + MOCK label
        let text = "MOCK · \(prompt.prefix(48))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: CTFont(.system, size: 20),
            .foregroundColor: CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.92])!,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = CGPoint(x: 24, y: 28)
        CTLineDraw(line, ctx)
    }

    static func makeImage(prompt: String, variant: Int) throws -> Data {
        let size = CGSize(width: 1024, height: 576)
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        drawFrame(in: ctx, size: size, prompt: prompt, variant: variant, phase: 0)
        guard let image = ctx.makeImage() else { throw FALError.badResponse("mock render failed") }
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    // MARK: Placeholder video (2 s shifting gradient, H.264)

    static func makeVideo(prompt: String) throws -> Data {
        let size = CGSize(width: 640, height: 360)
        let fps = 12, seconds = 2
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("falstudio-mock-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(fps * seconds) {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let pool = adaptor.pixelBufferPool else { throw FALError.badResponse("mock video pool") }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else { throw FALError.badResponse("mock video buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            drawFrame(in: ctx, size: size, prompt: prompt, variant: 0,
                      phase: Double(frame) / Double(fps * seconds))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            throw FALError.badResponse("mock video writer: \(writer.error?.localizedDescription ?? "failed")")
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try Data(contentsOf: tempURL)
    }
}
