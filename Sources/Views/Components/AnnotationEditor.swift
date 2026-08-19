import SwiftUI
import AppKit

/// Gemini-style "Mark up" editor for reference images: sketch freehand,
/// arrows, circles, and place text notes in red on the image. The flattened
/// annotated image is sent to the edit model, and the app tells the model to
/// treat the red markings as instructions.
struct AnnotationEditor: View {
    let image: NSImage
    let onApply: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    enum Tool: String, CaseIterable {
        case draw, arrow, circle, text

        var icon: String {
            switch self {
            case .draw: return "pencil.and.scribble"
            case .arrow: return "arrow.up.right"
            case .circle: return "circle"
            case .text: return "textformat"
            }
        }

        var help: String {
            switch self {
            case .draw: return tr("Sketch", "手繪")
            case .arrow: return tr("Arrow", "箭頭")
            case .circle: return tr("Circle", "圈選")
            case .text: return tr("Text note", "文字")
            }
        }
    }

    enum Mark {
        case stroke([CGPoint])
        case arrow(CGPoint, CGPoint)
        case ellipse(CGRect)
        case note(String, CGPoint)
    }

    @State private var tool: Tool = .draw
    @State private var marks: [Mark] = []
    @State private var currentPoints: [CGPoint] = []
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var fitSize: CGSize = .zero
    @State private var noteText = ""
    @State private var pendingNotePoint: CGPoint?
    @State private var showNoteField = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(10)
            Divider()
            GeometryReader { geo in
                let fit = fittedSize(in: geo.size)
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                    Canvas { context, _ in
                        for mark in marks {
                            draw(mark, in: &context)
                        }
                        if let live = liveMark {
                            draw(live, in: &context)
                        }
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .contentShape(Rectangle())
                .gesture(markGesture)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .onAppear { fitSize = fit }
                .onChange(of: geo.size) { _, newSize in
                    fitSize = fittedSize(in: newSize)
                }
            }
            .background(Color.black.opacity(0.85))
            Divider()
            HStack {
                Text(tr("Mark what to change — the model follows your red markings.",
                        "標記想修改的地方——模型會依照紅色記號執行。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("Cancel", "取消")) { dismiss() }
                Button(tr("Apply markup", "套用標記")) {
                    if let data = renderAnnotatedImage() {
                        onApply(data)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(marks.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 540, idealHeight: 620)
        .alert(tr("Text note", "文字標記"), isPresented: $showNoteField) {
            TextField(tr("e.g. change this to red", "例如：把這裡改成紅色"), text: $noteText)
            Button(tr("Add", "加入")) {
                if let point = pendingNotePoint,
                   !noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    marks.append(.note(noteText, point))
                }
                noteText = ""
                pendingNotePoint = nil
            }
            Button(tr("Cancel", "取消"), role: .cancel) {
                noteText = ""
                pendingNotePoint = nil
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(Tool.allCases, id: \.self) { candidate in
                Button {
                    tool = candidate
                } label: {
                    Image(systemName: candidate.icon)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(tool == candidate ? Color.accentColor.opacity(0.2) : .clear))
                        .foregroundStyle(tool == candidate ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                .help(candidate.help)
            }
            Divider().frame(height: 18)
            Button {
                if !marks.isEmpty { marks.removeLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(marks.isEmpty)
            .help(tr("Undo", "復原"))
            Button {
                marks.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(marks.isEmpty)
            .help(tr("Clear all markings", "清除全部標記"))
            Spacer()
            Text(tr("Mark up", "標記模式"))
                .font(.headline)
        }
    }

    // MARK: Gestures

    private var liveMark: Mark? {
        switch tool {
        case .draw:
            return currentPoints.count > 1 ? .stroke(currentPoints) : nil
        case .arrow:
            if let start = dragStart, let current = dragCurrent {
                return .arrow(start, current)
            }
        case .circle:
            if let start = dragStart, let current = dragCurrent {
                return .ellipse(rect(from: start, to: current))
            }
        case .text:
            break
        }
        return nil
    }

    private var markGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch tool {
                case .draw:
                    currentPoints.append(value.location)
                case .arrow, .circle:
                    if dragStart == nil { dragStart = value.startLocation }
                    dragCurrent = value.location
                case .text:
                    break
                }
            }
            .onEnded { value in
                switch tool {
                case .draw:
                    if currentPoints.count > 1 { marks.append(.stroke(currentPoints)) }
                    currentPoints = []
                case .arrow:
                    if let start = dragStart, distance(start, value.location) > 8 {
                        marks.append(.arrow(start, value.location))
                    }
                    dragStart = nil; dragCurrent = nil
                case .circle:
                    if let start = dragStart, distance(start, value.location) > 8 {
                        marks.append(.ellipse(rect(from: start, to: value.location)))
                    }
                    dragStart = nil; dragCurrent = nil
                case .text:
                    pendingNotePoint = value.location
                    showNoteField = true
                }
            }
    }

    // MARK: Canvas drawing (view space)

    private func draw(_ mark: Mark, in context: inout GraphicsContext) {
        let red = Color(red: 1, green: 0.16, blue: 0.16)
        switch mark {
        case .stroke(let points):
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(red), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        case .arrow(let start, let end):
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            for headPoint in arrowHead(from: start, to: end, length: 12) {
                path.move(to: end)
                path.addLine(to: headPoint)
            }
            context.stroke(path, with: .color(red), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        case .ellipse(let rect):
            context.stroke(Path(ellipseIn: rect), with: .color(red), lineWidth: 3)
        case .note(let text, let point):
            context.draw(
                Text(text).font(.system(size: 15, weight: .bold)).foregroundColor(red),
                at: point, anchor: .topLeading)
        }
    }

    // MARK: Export (flatten to image pixels)

    private func renderAnnotatedImage() -> Data? {
        let pixelSize = imagePixelSize()
        guard fitSize.width > 0 else { return nil }
        let scale = pixelSize.width / fitSize.width

        let output = NSImage(size: pixelSize)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: pixelSize))

        let red = NSColor(red: 1, green: 0.16, blue: 0.16, alpha: 1)
        red.setStroke()
        red.set()

        func convert(_ point: CGPoint) -> NSPoint {
            NSPoint(x: point.x * scale, y: pixelSize.height - point.y * scale)
        }

        for mark in marks {
            let path = NSBezierPath()
            path.lineWidth = 3 * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            switch mark {
            case .stroke(let points):
                guard let first = points.first else { continue }
                path.move(to: convert(first))
                for point in points.dropFirst() { path.line(to: convert(point)) }
                path.stroke()
            case .arrow(let start, let end):
                path.move(to: convert(start))
                path.line(to: convert(end))
                for headPoint in arrowHead(from: start, to: end, length: 12) {
                    path.move(to: convert(end))
                    path.line(to: convert(headPoint))
                }
                path.stroke()
            case .ellipse(let rect):
                let converted = NSRect(x: rect.minX * scale,
                                       y: pixelSize.height - rect.maxY * scale,
                                       width: rect.width * scale,
                                       height: rect.height * scale)
                let ellipse = NSBezierPath(ovalIn: converted)
                ellipse.lineWidth = 3 * scale
                ellipse.stroke()
            case .note(let text, let point):
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 15 * scale),
                    .foregroundColor: red,
                ]
                let origin = convert(point)
                (text as NSString).draw(
                    at: NSPoint(x: origin.x, y: origin.y - 15 * scale * 1.2),
                    withAttributes: attributes)
            }
        }
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    // MARK: Helpers

    private func imagePixelSize() -> NSSize {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let pixel = imagePixelSize()
        guard pixel.width > 0, pixel.height > 0,
              container.width > 0, container.height > 0 else { return container }
        let scale = min(container.width / pixel.width, container.height / pixel.height)
        return CGSize(width: pixel.width * scale, height: pixel.height * scale)
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func arrowHead(from start: CGPoint, to end: CGPoint, length: CGFloat) -> [CGPoint] {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let spread: CGFloat = .pi / 7
        return [angle + .pi - spread, angle + .pi + spread].map { headAngle in
            CGPoint(x: end.x + cos(headAngle) * length,
                    y: end.y + sin(headAngle) * length)
        }
    }
}
