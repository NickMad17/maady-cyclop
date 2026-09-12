import AppKit

/// Where screenshots are kept: `~/Pictures/Cyclop`.
///
/// A screenshot taken to the clipboard exists only in memory: paste it once and
/// it is gone. The vault writes it to disk so the shelf can hold on to it.
/// The same folder is also where macOS is told to put ⌘⇧3 / ⌘⇧4, so a shot
/// taken the usual way and a shot copied to the clipboard land in one place.
/// Taking a card off the shelf, or pressing Clear, puts the file in the
/// Trash. Nothing is deleted behind the user's back.
enum ScreenshotVault {
    /// `~/Pictures/Cyclop` — findable in Finder next to Photos, and unlike
    /// Desktop or Documents it is not behind a TCC prompt.
    static let folder: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Cyclop", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Points the system's screenshot location at this folder, if it is not
    /// already there. Writing the preference is enough — killing
    /// SystemUIServer to force a reread would blink the menu bar on every
    /// launch, and the next ⌘⇧3 picks the new path without that.
    static func adoptSystemScreenshots() {
        let path = folder.path
        let domain = UserDefaults(suiteName: "com.apple.screencapture")
        guard domain?.string(forKey: "location") != path else { return }
        domain?.set(path, forKey: "location")
        domain?.set("file", forKey: "target")
        domain?.synchronize()
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = localized("yyyy-MM-dd 'at' HH.mm.ss")
        return formatter
    }()

    static func save(_ png: Data, at date: Date = Date()) -> URL? {
        let base = "\(localized("Screenshot")) \(stamp.string(from: date))"
        var url = folder.appendingPathComponent("\(base).png")
        // Two screenshots inside one second would otherwise collide.
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(attempt)).png")
            attempt += 1
        }
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("Cyclop: failed to save image: \(error.localizedDescription)")
            return nil
        }
    }

    static func reveal() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    /// What the folder holds right now — for the menu item that offers to
    /// clear it, so the offer names its price.
    static func usage() -> (files: Int, bytes: Int64) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return (0, 0) }
        let bytes = urls.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return (urls.count, bytes)
    }

    /// Whether this file lives in the vault, as opposed to a file the shelf
    /// is only holding a reference to. Only the former is ours to throw away.
    static func owns(_ url: URL) -> Bool {
        let file = url.standardizedFileURL.path
        let root = folder.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return file.hasPrefix(prefix)
    }

    /// One file, to the Trash. Refuses anything outside the vault: a card
    /// dragged in from Downloads is a reference, and deleting it from disk
    /// would be the shelf quietly destroying someone else's file.
    static func trash(_ url: URL) {
        guard owns(url) else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// To the Trash, not gone. Clearing the folder or a card is the user's
    /// own hand; the Trash keeps even that reversible.
    static func clear() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
    }
}

/// Watches the vault folder for files macOS writes there itself.
///
/// ⌘⇧3 / ⌘⇧4 never touch the pasteboard — they write a file and that is the
/// whole of it. The clipboard path cannot see those, so the shelf would stay
/// empty after the shot the user just took. A `DispatchSource` on the folder
/// sleeps until the kernel says something changed, then hands the new file
/// over. Existing files are remembered at start, so a launch does not dump
/// the whole folder onto the shelf.
@MainActor
final class ScreenshotWatcher {
    var onNewFile: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var drainWork: DispatchWorkItem?

    func start() {
        stop()
        let folder = ScreenshotVault.folder
        known = Set(Self.images(in: folder).map(\.lastPathComponent))
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleDrain() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        drainWork?.cancel()
        drainWork = nil
        source?.cancel()
        source = nil
    }

    /// The write is often a rename of a temporary file, and the name is not
    /// stable on the first event. A short wait lets the shot finish landing
    /// before we look.
    private func scheduleDrain() {
        drainWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.drain() }
        drainWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func drain() {
        let images = Self.images(in: ScreenshotVault.folder)
        let names = Set(images.map(\.lastPathComponent))
        let arrived = images.filter { !known.contains($0.lastPathComponent) }
        known = names
        for url in arrived {
            onNewFile?(url)
        }
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    private static func images(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }
}
