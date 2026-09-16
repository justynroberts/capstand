import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Where everything sits for one frame style and stream size, in a single
/// unit system (stream pixels, or image pixels for a custom frame), origin
/// bottom-left. The window's aspect ratio is `canvas`; ScreenView scales it.
struct FrameLayout {
    var canvas: CGSize
    var screen: CGRect
    var screenRadius: CGFloat = 0

    // Drawn iPhone bezel only.
    var body: CGRect?
    var bodyRadius: CGFloat = 0
    var rail: CGFloat = 0
    var buttons: [CGRect] = []
    var island: CGRect?

    // Custom image frame only, drawn over the screen.
    var image: CGImage?
}

enum FrameRenderer {

    static func layout(for style: FrameStyle, video: CGSize, island: Bool) -> FrameLayout {
        let short = min(video.width, video.height)
        let landscape = video.width > video.height
        let plain = FrameLayout(canvas: video, screen: CGRect(origin: .zero, size: video))

        switch style {
        case .none:
            return plain

        case .rounded:
            var layout = plain
            layout.screenRadius = short * 0.15
            return layout

        case .iphone:
            return drawnPhone(video: video, short: short, landscape: landscape, island: island)

        case .bundled, .custom:
            let url = style == .custom ? ImageFrame.customURL : ImageFrame.bundled(named: Settings.bundledFrame)?.url
            guard let url, let frame = ImageFrame.load(url, landscape: landscape) else {
                return layout(for: .rounded, video: video, island: island)
            }
            return FrameLayout(canvas: CGSize(width: frame.image.width, height: frame.image.height),
                               screen: frame.screen,
                               screenRadius: min(frame.screen.width, frame.screen.height) * 0.12,
                               image: frame.image)
        }
    }

    /// Proportions of a current Pro iPhone, relative to the display's short edge.
    /// Landscape turns the phone anticlockwise: its top (and Dynamic Island) goes left.
    private static func drawnPhone(video: CGSize, short s: CGFloat, landscape: Bool, island: Bool) -> FrameLayout {
        let pad = s * 0.05          // rail + black border around the display
        let rail = s * 0.016
        let buttonDepth = s * 0.012 // how far the buttons stand proud of the rail

        let bodySize = CGSize(width: video.width + pad * 2, height: video.height + pad * 2)
        let canvas = landscape
            ? CGSize(width: bodySize.width, height: bodySize.height + buttonDepth * 2)
            : CGSize(width: bodySize.width + buttonDepth * 2, height: bodySize.height)
        let body = CGRect(origin: landscape ? CGPoint(x: 0, y: buttonDepth) : CGPoint(x: buttonDepth, y: 0),
                          size: bodySize)
        let screen = body.insetBy(dx: pad, dy: pad)
        let screenRadius = s * 0.15

        var layout = FrameLayout(canvas: canvas, screen: screen, screenRadius: screenRadius,
                                 body: body, bodyRadius: screenRadius + pad, rail: rail)

        // Fractions of the phone's length, measured from its top.
        let leftSide: [(CGFloat, CGFloat)] = [(0.19, 0.235), (0.28, 0.35), (0.375, 0.445)]  // action, volume up, down
        let rightSide: [(CGFloat, CGFloat)] = [(0.30, 0.42)]                                  // side button
        let length = max(body.width, body.height)
        let thickness = buttonDepth + rail

        func button(_ span: (CGFloat, CGFloat), onLeft: Bool) -> CGRect {
            let extent = length * (span.1 - span.0)
            if landscape {
                // Phone's left side faces down, right side faces up.
                return CGRect(x: body.minX + length * span.0,
                              y: onLeft ? 0 : body.maxY - rail,
                              width: extent, height: thickness)
            }
            return CGRect(x: onLeft ? 0 : body.maxX - rail,
                          y: body.maxY - length * span.1,
                          width: thickness, height: extent)
        }
        layout.buttons = leftSide.map { button($0, onLeft: true) } + rightSide.map { button($0, onLeft: false) }

        if island {
            let long = s * 0.31, narrow = s * 0.092, inset = s * 0.03
            layout.island = landscape
                ? CGRect(x: screen.minX + inset, y: screen.midY - long / 2, width: narrow, height: long)
                : CGRect(x: screen.midX - long / 2, y: screen.maxY - inset - narrow, width: long, height: narrow)
        }
        return layout
    }
}

/// A frame drawn from a PNG of a front-on phone whose screen is transparent or
/// one flat colour: either shipped in the app (CC0 Pomme Plate mockups, in
/// Assets/Frames) or imported by the user into Application Support, where it
/// survives rebuilds and self-updates.
enum ImageFrame {

    struct Bundled {
        /// File name without extension; what Settings.bundledFrame stores.
        let name: String
        let url: URL
        /// "iPhone X-XS-11 Pro Space Gray" reads as "iPhone X/XS/11 Pro Space Gray".
        var title: String { name.replacingOccurrences(of: "-", with: "/") }
    }

    enum ImportError: LocalizedError {
        case unreadable, noScreen
        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file could not be read as an image."
            case .noScreen: return "Capstand couldn't find the screen in that image. Use a front-on phone PNG whose screen is transparent or a single flat colour."
            }
        }
    }

    struct Oriented {
        let image: CGImage
        let screen: CGRect
    }

    static var customURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Capstand/Frames/custom.png")
    }

    static var customExists: Bool { FileManager.default.fileExists(atPath: customURL.path) }

    /// Shipped frames, sorted by name. bundle.sh copies Assets/Frames into
    /// Contents/Resources/Frames; the bare binary reads the source tree.
    static let bundled: [Bundled] = {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/Frames")
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Frames"), source].compactMap { $0 }
        guard let folder = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "png" }
            .map { Bundled(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name < $1.name }
    }()

    static func bundled(named name: String?) -> Bundled? {
        bundled.first { $0.name == name } ?? bundled.first
    }

    private static var cache: [URL: (portrait: Oriented, landscape: Oriented)] = [:]

    /// Loads, cuts out and measures a frame once; later calls are free.
    static func load(_ url: URL, landscape: Bool) -> Oriented? {
        if cache[url] == nil, let image = loadImage(url), let prepared = prepare(normalised(image)) {
            cache[url] = prepared
        }
        return landscape ? cache[url]?.landscape : cache[url]?.portrait
    }

    /// Validates, normalises and copies the image into place as the custom frame.
    static func importImage(from source: URL) throws {
        guard let loaded = loadImage(source) else { throw ImportError.unreadable }
        let image = normalised(loaded)
        guard let prepared = prepare(image) else { throw ImportError.noScreen }

        try FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(customURL as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ImportError.unreadable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.unreadable }
        cache[customURL] = prepared
    }

    /// Portrait, with a flat-colour screen cut out. Flat mockups (Pomme Plate,
    /// most clip art) paint the screen instead of leaving it transparent.
    private static func normalised(_ image: CGImage) -> CGImage {
        var image = image
        if image.width > image.height, let turned = rotate(image, clockwise: true) { image = turned }
        return punchSolidScreen(image) ?? image
    }

    private static func prepare(_ portrait: CGImage) -> (portrait: Oriented, landscape: Oriented)? {
        guard let screen = detectScreen(portrait),
              let turned = rotate(portrait, clockwise: false),
              let turnedScreen = detectScreen(turned)
        else { return nil }
        return (Oriented(image: portrait, screen: screen), Oriented(image: turned, screen: turnedScreen))
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The transparent hole around the image centre, found by walking out along
    /// three rows and three columns (so a Dynamic Island on the centre line
    /// doesn't cut the screen short). Bottom-left origin, image pixels.
    private static func detectScreen(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        guard let pixels = rgba(image) else { return nil }

        // Row 0 of the buffer is the top of the image.
        func clear(_ x: Int, _ row: Int) -> Bool { pixels[(row * w + x) * 4 + 3] < 128 }
        guard clear(w / 2, h / 2) else { return nil }

        var left = w, right = 0, top = h, bottom = 0
        for row in [h * 3 / 10, h / 2, h * 7 / 10] where clear(w / 2, row) {
            var x = w / 2; while x > 0 && clear(x - 1, row) { x -= 1 }; left = min(left, x)
            x = w / 2; while x < w - 1 && clear(x + 1, row) { x += 1 }; right = max(right, x)
        }
        for column in [w * 3 / 10, w / 2, w * 7 / 10] where clear(column, h / 2) {
            var y = h / 2; while y > 0 && clear(column, y - 1) { y -= 1 }; top = min(top, y)
            y = h / 2; while y < h - 1 && clear(column, y + 1) { y += 1 }; bottom = max(bottom, y)
        }

        // Running into the image edge means nothing encloses the centre.
        guard left > 0, right < w - 1, top > 0, bottom < h - 1,
              (right - left) * (bottom - top) > w * h / 4
        else { return nil }
        return CGRect(x: left, y: h - 1 - bottom, width: right - left + 1, height: bottom - top + 1)
    }

    /// If the centre pixel is opaque, flood-fills outward over pixels of that
    /// colour and makes them transparent — following the screen's real rounded
    /// corners. Returns nil when the centre is already transparent. A fill that
    /// leaks to the image edge is caught later by detectScreen.
    private static func punchSolidScreen(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard var pixels = rgba(image) else { return nil }
        let centre = (h / 2 * w + w / 2) * 4
        guard pixels[centre + 3] > 250 else { return nil }
        let target = (pixels[centre], pixels[centre + 1], pixels[centre + 2])

        func matches(_ i: Int) -> Bool {
            pixels[i + 3] > 250
                && abs(Int(pixels[i]) - Int(target.0)) <= 10
                && abs(Int(pixels[i + 1]) - Int(target.1)) <= 10
                && abs(Int(pixels[i + 2]) - Int(target.2)) <= 10
        }

        var stack = [w / 2 + h / 2 * w]
        while let index = stack.popLast() {
            let i = index * 4
            guard matches(i) else { continue }
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            let x = index % w, row = index / w
            if x > 0 { stack.append(index - 1) }
            if x < w - 1 { stack.append(index + 1) }
            if row > 0 { stack.append(index - w) }
            if row < h - 1 { stack.append(index + w) }
        }

        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage()
        }
    }

    /// Premultiplied RGBA, row 0 at the top of the image.
    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Anticlockwise puts the phone's top on the left, matching the drawn frame.
    private static func rotate(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if clockwise {
            context.translateBy(x: 0, y: CGFloat(w))
            context.rotate(by: -.pi / 2)
        } else {
            context.translateBy(x: CGFloat(h), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
