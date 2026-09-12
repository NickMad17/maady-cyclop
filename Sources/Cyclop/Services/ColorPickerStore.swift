import AppKit
import SwiftUI

/// A colour under the cursor, kept as the hex a paste is expecting.
///
/// The system loupe (`NSColorSampler`) is the pick: it is the same gesture
/// Digital Color Meter made a window for, without the window. The panel folds
/// first so the loupe is not sampling its own black.
@MainActor
final class ColorPickerStore: ObservableObject {
    struct Swatch: Identifiable, Equatable {
        var hex: String
        var id: String { hex }
        var color: Color { Color(nsColor: NSColor(hex: hex) ?? .white) }
    }

    @Published private(set) var current: Swatch?
    @Published private(set) var recents: [Swatch] = []
    @Published private(set) var justCopied = false

    /// Raised before the loupe appears, so the panel can get out of the way.
    var onPickStarted: (() -> Void)?

    private var sampler: NSColorSampler?
    private let defaults = UserDefaults.standard
    private static let recentsKey = "picker.recents"
    private static let limit = 6

    init() {
        if let saved = defaults.array(forKey: Self.recentsKey) as? [String] {
            recents = saved.map { Swatch(hex: $0) }
            current = recents.first
        }
    }

    func pick() {
        onPickStarted?()
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            DispatchQueue.main.async {
                self?.sampler = nil
                guard let color else { return }
                self?.capture(color)
            }
        }
    }

    func copy(_ swatch: Swatch) {
        current = swatch
        write(swatch.hex)
        remember(swatch)
        flashCopied()
    }

    private func capture(_ color: NSColor) {
        guard let hex = color.hexString else { return }
        let swatch = Swatch(hex: hex)
        current = swatch
        remember(swatch)
        write(hex)
        flashCopied()
    }

    private func remember(_ swatch: Swatch) {
        recents.removeAll { $0.hex == swatch.hex }
        recents.insert(swatch, at: 0)
        if recents.count > Self.limit { recents = Array(recents.prefix(Self.limit)) }
        defaults.set(recents.map(\.hex), forKey: Self.recentsKey)
    }

    private func write(_ hex: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
    }

    private func flashCopied() {
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.justCopied = false
        }
    }
}

extension NSColor {
    /// sRGB hex, the string CSS and design tools paste. Display P3 is
    /// converted rather than emitted as a different alphabet: a hex that
    /// only some apps understand is a hex that fails on the next paste.
    var hexString: String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
