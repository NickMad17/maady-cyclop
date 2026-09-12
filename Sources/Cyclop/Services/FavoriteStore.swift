import AppKit
import SwiftUI

/// A handful of colours, not a picker.
///
/// A free colour on a card this small is a colour you cannot name twice, and
/// the file would then hold hex that nobody edits by hand. These eight are the
/// Finder tag set plus pink — enough to tell "music" from "video" at a glance,
/// and each one is a word in `favorites.json`.
enum FavoriteTint: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var id: String { rawValue }

    /// Finder-adjacent, a little brighter: the panel is black, and a folder
    /// painted in the system tag colours disappeared into it.
    var color: Color {
        switch self {
        case .red:    return Color(red: 1.00, green: 0.38, blue: 0.36)
        case .orange: return Color(red: 1.00, green: 0.62, blue: 0.22)
        case .yellow: return Color(red: 0.98, green: 0.84, blue: 0.26)
        case .green:  return Color(red: 0.38, green: 0.82, blue: 0.45)
        case .blue:   return Color(red: 0.35, green: 0.68, blue: 0.99)
        case .purple: return Color(red: 0.72, green: 0.48, blue: 0.98)
        case .pink:   return Color(red: 0.98, green: 0.47, blue: 0.72)
        case .gray:   return Color(red: 0.66, green: 0.68, blue: 0.71)
        }
    }

    var title: String {
        switch self {
        case .red:    return localized("Red")
        case .orange: return localized("Orange")
        case .yellow: return localized("Yellow")
        case .green:  return localized("Green")
        case .blue:   return localized("Blue")
        case .purple: return localized("Purple")
        case .pink:   return localized("Pink")
        case .gray:   return localized("Gray")
        }
    }
}

/// A folder kept for opening, not for holding.
///
/// The shelf is a queue: a file lands, is dragged out, and is gone. This list
/// is the opposite — the same handful of folders, reached for every day, which
/// is why they used to live as aliases on the Desktop. The notch is closer
/// than the Desktop, and a click here does what a double-click did there.
struct FavoriteFolder: Identifiable, Equatable {
    /// The path is identity: two aliases to the same folder are one folder.
    var id: String { path }
    /// Optional name. Without one the row shows the folder's own name, which
    /// is usually what was on the alias anyway.
    var label: String = ""
    var path: String
    /// Default is Finder blue. Painted on the symbol, not on the real folder
    /// icon: `icon(forFile:)` is always that same blue, and asking for it
    /// would raise TCC for Desktop the moment the tab opened.
    var tint: FavoriteTint = .blue
    /// True after a visit to the tab found nothing at the path. Kept, not
    /// swept: a curated list that deletes itself when a folder is renamed is
    /// worse than a dimmed card with a cross on it.
    var isMissing: Bool = false

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// The name shown on the card. A hand-given label wins; otherwise the
    /// last path component, which is what Finder itself would print.
    var name: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url.lastPathComponent : trimmed
    }
}

/// Across a row, or under it. Both are a line; they just face different ways.
enum FavoriteDividerAxis: String, Equatable {
    case horizontal, vertical
}

/// One slot in the favorites list: a folder, or a line that splits groups.
enum FavoriteEntry: Identifiable, Equatable {
    case folder(FavoriteFolder)
    case divider(UUID, FavoriteDividerAxis)

    var id: String {
        switch self {
        case .folder(let folder): return "folder.\(folder.path)"
        case .divider(let uuid, _): return "divider.\(uuid.uuidString)"
        }
    }

    var folder: FavoriteFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    var dividerID: UUID? {
        if case .divider(let uuid, _) = self { return uuid }
        return nil
    }
}

/// A hand-kept list of folders worth opening without hunting for them.
///
/// Lives in a file so it can be edited from outside the app, the same way
/// snippets can. The copy in memory is only as fresh as the last visit to
/// the tab; writing over it blind would silently undo a hand edit.
@MainActor
final class FavoriteStore: ObservableObject {
    @Published private(set) var entries: [FavoriteEntry] = []
    /// Folders only — the header counter, and anything that used to read
    /// `items` as "how many shortcuts". Dividers are not shortcuts.
    var items: [FavoriteFolder] { entries.compactMap(\.folder) }
    /// True when the file exists but cannot be parsed — a hand edit left it
    /// broken. Writing is then forbidden: "could not read" and "read as it
    /// is" are different answers, and only the second makes writing back safe.
    @Published private(set) var fileBroken = false

    /// `~/Library/Application Support/Cyclop/favorites.json`. A plain array of
    /// folder objects and `{"kind": "divider"}` rows. `axis` is `"vertical"`
    /// or omitted (a horizontal line, which is what older files already are).
    /// `label` and `tint` may be left out on a folder — missing tint is blue,
    /// the Finder default.
    static let file = Support.file("favorites.json")

    /// Re-read on every visit to the tab. The file is edited from outside the
    /// app, so the only sensible moment to trust what is in memory is the
    /// moment before it is shown.
    func reload() {
        guard let data = try? Data(contentsOf: Self.file) else {
            entries = []
            fileBroken = false
            return
        }
        do {
            let records = try JSONDecoder().decode([Record].self, from: data)
            entries = records.map(\.entry)
            fileBroken = false
        } catch {
            fileBroken = true
            NSLog("Cyclop: favorites.json is not readable: \(error.localizedDescription)")
        }
    }

    /// Called when the tab comes into view, and only then.
    ///
    /// This is where the disk is finally touched: missing folders are marked,
    /// real icons arrive. If a permission prompt is coming — a folder kept in
    /// Desktop, Documents or Downloads — it comes here, with the cards in
    /// front of the person being asked, which is the difference between a
    /// question and an interruption.
    func refreshFromDisk() {
        guard !entries.isEmpty else { return }
        for index in entries.indices {
            guard case .folder(var folder) = entries[index] else { continue }
            folder.isMissing = Self.isGone(folder.url)
            entries[index] = .folder(folder)
        }
    }

    /// Whether the folder is actually gone, as opposed to merely out of reach.
    ///
    /// `fileExists` answers false to both, and the difference matters: a card
    /// whose folder was deleted should look missing, while one the app was
    /// just refused access to should stay exactly where it is. Treating them
    /// alike meant a single "Don't Allow" would dim every Desktop shortcut
    /// with the folders still sitting there.
    private static func isGone(_ url: URL) -> Bool {
        do {
            return try !url.checkResourceIsReachable()
        } catch let error as NSError {
            return error.code == NSFileReadNoSuchFileError
        }
    }

    /// Adds folders and writes the file.
    ///
    /// Re-reads first, because the file is also edited by hand and the copy in
    /// memory is only as fresh as the last visit to the tab. Writing over it
    /// blind would silently undo whatever was added in an editor meanwhile.
    /// Files are ignored: this list is folders, and a file dropped here is
    /// almost always meant for the shelf, which is one tab away.
    func add(_ urls: [URL]) {
        let folders = urls.filter(Self.isFolder)
        guard !folders.isEmpty else { return }
        reload()
        guard !fileBroken else {
            NSLog("Cyclop: refusing to write over an unreadable favorites.json")
            return
        }
        for url in folders {
            let path = url.standardizedFileURL.path
            guard !entries.contains(where: { $0.folder?.path == path }) else { continue }
            entries.append(.folder(FavoriteFolder(path: path)))
        }
        persist()
    }

    /// A drop from Finder usually already knows it is a directory. Asking the
    /// disk is the fallback, and it is what raises TCC for Desktop — fine
    /// here: the person just handed us that folder, so the dialog arrives
    /// with the pane in front of them. Packages (.app) are directories too,
    /// and opening one would launch it; those stay out.
    private static func isFolder(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "app" { return false }
        if url.hasDirectoryPath { return true }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return false
        }
        return isDir.boolValue
    }

    func remove(_ folder: FavoriteFolder) {
        entries.removeAll { $0.folder?.path == folder.path }
        persist()
    }

    func removeDivider(_ id: UUID) {
        entries.removeAll { $0.dividerID == id }
        persist()
    }

    /// A line between groups. Dropped in the middle so two folders become
    /// two blocks in one click — a line under everything divides nothing.
    func addDivider(_ axis: FavoriteDividerAxis) {
        reload()
        guard !fileBroken else {
            NSLog("Cyclop: refusing to write over an unreadable favorites.json")
            return
        }
        let divider = FavoriteEntry.divider(UUID(), axis)
        let index = max(1, entries.count / 2)
        if index >= entries.count {
            entries.append(divider)
        } else {
            entries.insert(divider, at: index)
        }
        persist()
    }

    /// Moves a folder to another position and writes the new order.
    ///
    /// The order is the file's order, so rearranging a card is a real edit
    /// and not a view-only arrangement — the one reached for most often is
    /// meant to end up first and stay there.
    func move(_ folder: FavoriteFolder, to index: Int) {
        guard let current = entries.firstIndex(where: { $0.folder?.path == folder.path }) else { return }
        move(from: current, to: index)
    }

    func moveDivider(_ id: UUID, to index: Int) {
        guard let current = entries.firstIndex(where: { $0.dividerID == id }) else { return }
        move(from: current, to: index)
    }

    private func move(from current: Int, to index: Int) {
        let target = max(0, min(index, entries.count - 1))
        guard target != current else { return }
        entries.insert(entries.remove(at: current), at: target)
        persist()
    }

    /// Painted in place: a colour is not a new folder, and re-reading the
    /// file to apply one would flash the grid under the pointer that just
    /// chose it.
    func setTint(_ folder: FavoriteFolder, _ tint: FavoriteTint) {
        guard let index = entries.firstIndex(where: { $0.folder?.path == folder.path }) else { return }
        guard var folder = entries[index].folder, folder.tint != tint else { return }
        folder.tint = tint
        entries[index] = .folder(folder)
        persist()
    }

    /// An empty label is a real value — it means "use the folder's name" —
    /// and is written as a missing key, the same way snippets write an
    /// unnamed row.
    func setLabel(_ folder: FavoriteFolder, _ label: String) {
        guard let index = entries.firstIndex(where: { $0.folder?.path == folder.path }) else { return }
        guard var folder = entries[index].folder else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard folder.label != trimmed else { return }
        folder.label = trimmed
        entries[index] = .folder(folder)
        persist()
    }

    func open(_ folder: FavoriteFolder) {
        NSWorkspace.shared.open(folder.url)
    }

    /// Selects the folder in its parent, the way Finder's "Show in Enclosing
    /// Folder" does — useful when the card is missing and the question is
    /// where it went, not what is inside.
    func reveal(_ folder: FavoriteFolder) {
        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
    }

    /// Pretty-printed, and slashes left alone: the file is meant to be opened
    /// and edited by hand, and `\/` in every path would be the app making that
    /// harder for its own convenience.
    private func persist() {
        guard !fileBroken else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let records = entries.map(Record.init)
        do {
            try encoder.encode(records).write(to: Self.file, options: .atomic)
        } catch {
            NSLog("Cyclop: cannot write favorites.json: \(error.localizedDescription)")
        }
    }

    /// Selecting a file that is not on disk yet is a silent no-op for Finder —
    /// nothing opens, nothing errors. Before the first folder is added there
    /// is nothing to select, so an empty list is written first: the same
    /// state `reload()` already treats as a valid, empty file.
    static func reveal() {
        if !FileManager.default.fileExists(atPath: file.path) {
            try? Data("[]".utf8).write(to: file)
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// An Open panel, because dragging is how folders arrive from the Desktop
    /// and a button is how they arrive from anywhere else.
    ///
    /// The app is `.accessory`, so a panel shown as-is never becomes key and
    /// sits behind whatever the user was in. A brief trip to `.regular` is
    /// the documented way a menu-bar app shows an Open panel; the Dock icon
    /// that flashes is the price, and it is gone the moment the panel is.
    func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = localized("Add")
        panel.message = localized("Choose folders to keep in the notch")
        panel.level = .floating

        let previous = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            NSApp.setActivationPolicy(previous)
            guard response == .OK else { return }
            Task { @MainActor in
                self?.add(panel.urls)
            }
        }
    }

    /// What the file actually holds. A folder is `{path, label?, tint?}`; a
    /// divider is `{"kind": "divider"}`, with `"axis": "vertical"` when the
    /// line stands between cards. Older files have no `kind` and are folders,
    /// and no `axis` and are horizontal — a missing key must not turn a list
    /// of shortcuts into an unreadable file.
    private struct Record: Codable {
        var kind: String?
        var id: String?
        var axis: String?
        var label: String = ""
        var path: String?
        var tint: FavoriteTint = .blue

        private enum CodingKeys: String, CodingKey { case kind, id, axis, label, path, tint }

        var entry: FavoriteEntry {
            if kind == "divider" {
                let uuid = id.flatMap(UUID.init(uuidString:)) ?? UUID()
                let axis: FavoriteDividerAxis = self.axis == "vertical" ? .vertical : .horizontal
                return .divider(uuid, axis)
            }
            return .folder(FavoriteFolder(label: label, path: path ?? "", tint: tint))
        }

        init(_ entry: FavoriteEntry) {
            switch entry {
            case .folder(let folder):
                label = folder.label
                path = folder.path
                tint = folder.tint
            case .divider(let uuid, let axis):
                kind = "divider"
                id = uuid.uuidString
                self.axis = axis == .vertical ? "vertical" : nil
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(String.self, forKey: .kind)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            axis = try container.decodeIfPresent(String.self, forKey: .axis)
            label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
            path = try container.decodeIfPresent(String.self, forKey: .path)
            if let raw = try container.decodeIfPresent(String.self, forKey: .tint) {
                tint = FavoriteTint(rawValue: raw) ?? .blue
            } else {
                tint = .blue
            }
            if kind != "divider", path == nil {
                throw DecodingError.keyNotFound(
                    CodingKeys.path,
                    .init(codingPath: container.codingPath, debugDescription: "folder without path")
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if kind == "divider" {
                try container.encode("divider", forKey: .kind)
                if let id { try container.encode(id, forKey: .id) }
                if let axis { try container.encode(axis, forKey: .axis) }
                return
            }
            if !label.isEmpty { try container.encode(label, forKey: .label) }
            try container.encode(path ?? "", forKey: .path)
            if tint != .blue { try container.encode(tint.rawValue, forKey: .tint) }
        }
    }
}
