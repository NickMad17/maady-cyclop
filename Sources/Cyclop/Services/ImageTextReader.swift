import AppKit
import Vision

/// On-device OCR for a picture dropped onto the translate tab.
///
/// Vision is the same stack Live Text uses: no network, no permission, and
/// nothing leaves the machine. The translator then sees ordinary text and
/// does not need to know a picture was involved.
enum ImageTextReader {
    static let fileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp",
    ]

    static func isImageFile(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    @MainActor
    static func read(_ image: NSImage) async -> String? {
        guard let cgImage = rasterize(image) else { return nil }
        return await Task.detached { recognize(cgImage) }.value
    }

    /// Shrinks a huge screenshot before OCR: a 5× retina capture is more
    /// pixels than the recognizer needs, and the extra ones only cost time
    /// on the panel's one thread that is allowed to hitch.
    @MainActor
    private static func rasterize(_ image: NSImage) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let maxSide: CGFloat = 2048
        let scale = min(1, maxSide / max(size.width, size.height))
        let pixels = NSSize(
            width: max(1, (size.width * scale).rounded(.down)),
            height: max(1, (size.height * scale).rounded(.down))
        )
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width),
            pixelsHigh: Int(pixels.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    nonisolated private static func recognize(_ cgImage: CGImage) -> String? {
        var result: String?
        let request = VNRecognizeTextRequest { request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            result = lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = ["en-US", "ru-RU"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return result
    }
}
