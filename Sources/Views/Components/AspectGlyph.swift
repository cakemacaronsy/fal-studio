import AppKit

/// Small template images showing the shape of an aspect ratio, used as icons
/// in the Aspect dropdown so the output orientation is visible at a glance.
enum AspectGlyph {
    private static var cache: [String: NSImage] = [:]
    private static let canvas = NSSize(width: 22, height: 15)

    static func image(for ratio: String) -> NSImage {
        if let cached = cache[ratio] { return cached }
        let image = draw(ratio: ratio)
        cache[ratio] = image
        return image
    }

    private static func draw(ratio: String) -> NSImage {
        let parts = ratio.split(separator: ":").compactMap { Double($0) }
        let isProportional = parts.count == 2 && parts[0] > 0 && parts[1] > 0

        let image = NSImage(size: canvas, flipped: false) { _ in
            let rect: NSRect
            if isProportional {
                let (w, h) = (parts[0], parts[1])
                // Fit the ratio inside the canvas with 1.5pt padding.
                let maxW = canvas.width - 3, maxH = canvas.height - 3
                var boxW = maxW, boxH = maxW * h / w
                if boxH > maxH {
                    boxH = maxH
                    boxW = maxH * w / h
                }
                rect = NSRect(x: (canvas.width - boxW) / 2,
                              y: (canvas.height - boxH) / 2,
                              width: boxW, height: boxH)
            } else {
                // "auto" / "adaptive": dashed square.
                let side = canvas.height - 3
                rect = NSRect(x: (canvas.width - side) / 2, y: 1.5, width: side, height: side)
            }
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.2
            if !isProportional {
                path.setLineDash([2.5, 2], count: 2, phase: 0)
            }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true  // tints with menu text in light/dark
        return image
    }
}
