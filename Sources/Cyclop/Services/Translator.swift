import AppKit
import Translation

/// Apple's on-device translator, driven from the panel.
///
/// The session is not ours to create: `translationTask` hands one over and owns
/// its lifetime, so everything here is about deciding *what* to translate and
/// holding the result. `TranslatePane` supplies the session.
@MainActor
final class Translator: ObservableObject {
    static let russian = Locale.Language(identifier: "ru")
    static let english = Locale.Language(identifier: "en")

    /// Both ends are always named. Leaving the source to the framework looks
    /// tempting, but its identifier is a separate asset that is not installed
    /// either — auto-detection fails with `unableToIdentifyLanguage`, and the
    /// translation that follows hangs instead of returning an error.
    struct Route: Equatable {
        var source: Locale.Language
        var target: Locale.Language
    }

    /// Keyed by the pane's debounced task. The counter is what makes a retry of
    /// unchanged text a new request rather than a no-op.
    struct Request: Equatable {
        var text: String
        var attempt: Int
    }

    @Published var input = ""
    @Published private(set) var output = ""
    @Published private(set) var failure: String?
    /// The failure is a missing language pack, which is a thing the user can
    /// go and fix — so the pane offers the button that takes them there.
    @Published private(set) var needsDownload = false
    /// OCR is in flight. The pane stays quiet rather than flashing a status:
    /// the recognized text lands in `input` and the usual translation follows.
    @Published private(set) var isReadingImage = false

    private var attempt = 0
    private var readTask: Task<Void, Never>?

    var request: Request { Request(text: input, attempt: attempt) }
    var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    var route: Route { Self.route(for: trimmed) }

    /// Russian goes out to English, everything else comes in to Russian.
    ///
    /// Decided by script rather than by language detection: a single word is
    /// far too short to identify reliably, and "привет" comes back as Bulgarian
    /// often enough to matter.
    static func route(for text: String) -> Route {
        let cyrillic = text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        return cyrillic
            ? Route(source: russian, target: english)
            : Route(source: english, target: russian)
    }

    func retry() {
        attempt += 1
    }

    func clear() {
        output = ""
        failure = nil
        needsDownload = false
    }

    func reset() {
        readTask?.cancel()
        isReadingImage = false
        input = ""
        clear()
    }

    /// A screenshot or any other picture: read the words, then translate them
    /// the same way typed text is translated. Replaces whatever was in the
    /// field — a new picture is a new source, not an appendix.
    func ingest(image: NSImage) {
        readTask?.cancel()
        input = ""
        clear()
        isReadingImage = true
        readTask = Task { [weak self] in
            let text = await ImageTextReader.read(image)
            guard let self, !Task.isCancelled else { return }
            isReadingImage = false
            // Typed over the empty field while Vision was working: keep it.
            guard input.isEmpty else { return }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                failure = localized("No text on this image.")
                return
            }
            input = trimmed
        }
    }

    /// ⌘V / the photo button: an image on the pasteboard becomes a source.
    /// Text wins when both are present, so an ordinary copy still pastes.
    @discardableResult
    func ingestPasteboardImage() -> Bool {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        guard let image = Self.image(from: pasteboard) else { return false }
        ingest(image: image)
        return true
    }

    static func image(from pasteboard: NSPasteboard) -> NSImage? {
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
            return image
        }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
            return image
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            return urls.lazy.filter(ImageTextReader.isImageFile).compactMap { NSImage(contentsOf: $0) }.first
        }
        return pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
    }

    func run(_ session: TranslationSession) async {
        let text = trimmed
        guard !text.isEmpty else { clear(); return }
        guard let source = session.sourceLanguage, let target = session.targetLanguage else { return }

        // No language pack ships installed. `prepareTranslation()` is what asks
        // for one, but it blocks until its system prompt is answered — and that
        // prompt has nowhere to appear over a borderless panel of an app that
        // never activates, so it would hang forever. Check instead, and send
        // the user to the one place that can actually install it.
        let status = await LanguageAvailability().status(from: source, to: target)
        guard status == .installed else {
            output = ""
            needsDownload = status == .supported
            failure = needsDownload
                ? localized("The %@ → %@ language pack is not installed.", Self.name(source), Self.name(target))
                : localized("macOS does not translate this pair of languages.")
            return
        }

        do {
            let response = try await session.translate(text)
            guard !Task.isCancelled else { return }
            output = response.targetText
            failure = nil
            needsDownload = false
        } catch {
            guard !Task.isCancelled else { return }
            output = ""
            needsDownload = false
            failure = error.localizedDescription
        }
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }

    /// "Русский", "English" — for the column headers. Named in the language the
    /// panel itself is in, not in the system's: those two can differ, and a
    /// column headed in one language above a button worded in another reads as
    /// a mistake.
    static func name(_ language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier,
              let name = Locale(identifier: appLanguage).localizedString(forLanguageCode: code) else {
            return language.languageCode?.identifier.uppercased() ?? "?"
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Short code for the header badge — "EN → RU" reads at a glance where a
    /// spelled-out name would not fit in the strip.
    static func code(_ language: Locale.Language) -> String {
        language.languageCode?.identifier.uppercased() ?? "?"
    }

    /// System Settings → General → Language & Region, which is where the
    /// "Translation Languages…" button lives.
    static func openLanguageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
