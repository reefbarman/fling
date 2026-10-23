import AppKit
import Foundation

/// Custom target icons, stored as small PNGs next to `config.json` in
/// `~/Library/Application Support/Fling/Icons/`.
enum TargetIconStore {
    private static let pixelSize = 256
    private static let cache = NSCache<NSString, NSImage>()

    static func directoryURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("Fling/Icons", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func image(named fileName: String) -> NSImage? {
        let key = fileName as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = try? directoryURL().appendingPathComponent(fileName),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Rasterises `image` into a square PNG and returns its new file name. Names are unique per
    /// import, so cached images never go stale.
    static func importImage(_ image: NSImage, circular: Bool = false) throws -> String {
        guard let data = pngData(for: image, circular: circular) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let fileName = "icon-\(UUID().uuidString.lowercased()).png"
        try data.write(to: directoryURL().appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    /// Deletes icon files no target references any more.
    static func removeUnreferenced(keeping referenced: Set<String>) {
        guard let directory = try? directoryURL(),
            let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else {
            return
        }
        for file in files where file.hasPrefix("icon-") && !referenced.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            cache.removeObject(forKey: file as NSString)
        }
    }

    /// Loads an image file, or an app's icon when given an `.app` bundle.
    static func loadImage(from url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "app" {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(contentsOf: url)
    }

    private static func pngData(for image: NSImage, circular: Bool) -> Data? {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSize,
                pixelsHigh: pixelSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return nil
        }

        let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        let source = image.size
        guard source.width > 0, source.height > 0 else { return nil }

        // Circular crops fill the square (photos); others fit inside it (logos).
        let scale =
            circular
            ? max(canvas.width / source.width, canvas.height / source.height)
            : min(canvas.width / source.width, canvas.height / source.height)
        let drawSize = NSSize(width: source.width * scale, height: source.height * scale)
        let drawRect = NSRect(
            x: (canvas.width - drawSize.width) / 2,
            y: (canvas.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        if circular {
            NSBezierPath(ovalIn: canvas).addClip()
        }
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
