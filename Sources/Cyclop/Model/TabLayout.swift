import Foundation

/// Which tabs sit on the rails, and in what order.
///
/// The default is everything on, in the order the app shipped with. Hiding a
/// tab takes it off the rail and stops whatever work it was doing in the
/// background — a clipboard nobody can open has no reason to poll. Settings
/// is not in this list: it is how you get back here, so it stays last on the
/// right rail and cannot be turned off.
@MainActor
final class TabLayout: ObservableObject {
    struct Item: Identifiable, Equatable {
        var id: NotchViewModel.Tab
        var visible: Bool
    }

    /// Configurable tabs, in the order they appear on the rails. Hidden ones
    /// stay in the list so turning them back on puts them where they were,
    /// not at the end.
    @Published private(set) var items: [Item]

    /// How many visible tabs the left rail will take. A seventh would still
    /// fit, but it would shrink every icon on that rail to make room — the
    /// same objection that put notes on the right in the first place.
    nonisolated static let leftCapacity = 6

    /// The order the app ships with. New tabs, added in a later build, are
    /// appended after whatever was saved — visible, so a feature is not
    /// silently missing after an update.
    static let defaultOrder: [NotchViewModel.Tab] = [
        .media, .shelf, .clipboard, .snippets, .calendar, .timer, .picker,
        .translate, .notes, .favorites, .teleprompter,
    ]

    /// First builds parked the two new tabs at the end of the saved list,
    /// which on a full rail is the last icons before Settings — easy to
    /// miss, and easy to read as "gone". This flag moves them once, after
    /// Calendar, and then leaves the user's own order alone.
    private static let placedKey = "tabs.placed.timer-picker"

    static let key = "tabs.layout"

    init() {
        items = Self.load()
    }

    var visible: [NotchViewModel.Tab] {
        items.filter(\.visible).map(\.id)
    }

    var leftRail: [NotchViewModel.Tab] {
        Array(visible.prefix(Self.leftCapacity))
    }

    var rightRail: [NotchViewModel.Tab] {
        Array(visible.dropFirst(Self.leftCapacity)) + [.settings]
    }

    func isVisible(_ tab: NotchViewModel.Tab) -> Bool {
        tab == .settings || items.contains { $0.id == tab && $0.visible }
    }

    func setVisible(_ tab: NotchViewModel.Tab, _ on: Bool) {
        guard tab != .settings, let index = items.firstIndex(where: { $0.id == tab }) else { return }
        guard items[index].visible != on else { return }
        items[index].visible = on
        persist()
    }

    func move(_ tab: NotchViewModel.Tab, to index: Int) {
        guard let current = items.firstIndex(where: { $0.id == tab }) else { return }
        let target = max(0, min(index, items.count - 1))
        guard target != current else { return }
        items.insert(items.remove(at: current), at: target)
        persist()
    }

    private func persist() {
        let records = items.map { Record(id: $0.id.rawValue, visible: $0.visible) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Saved order first, then any tab this build added that the file has
    /// never seen. Unknown ids — a tab this build no longer has — are dropped.
    private static func load() -> [Item] {
        var seen = Set<NotchViewModel.Tab>()
        var items: [Item] = []

        if let data = UserDefaults.standard.data(forKey: key),
           let records = try? JSONDecoder().decode([Record].self, from: data) {
            for record in records {
                guard let tab = NotchViewModel.Tab(rawValue: record.id), tab != .settings else { continue }
                guard seen.insert(tab).inserted else { continue }
                items.append(Item(id: tab, visible: record.visible))
            }
        }

        for tab in defaultOrder where seen.insert(tab).inserted {
            items.append(Item(id: tab, visible: true))
        }
        if !UserDefaults.standard.bool(forKey: placedKey) {
            items = placeBesideCalendar(items)
            let records = items.map { Record(id: $0.id.rawValue, visible: $0.visible) }
            if let data = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(data, forKey: key)
            }
            UserDefaults.standard.set(true, forKey: placedKey)
        }
        return items
    }

    /// Timer next to calendar, picker right after it. Both stay visible:
    /// a feature that arrives hidden is a feature that was never added.
    private static func placeBesideCalendar(_ items: [Item]) -> [Item] {
        var items = items
        func take(_ tab: NotchViewModel.Tab) -> Item {
            if let index = items.firstIndex(where: { $0.id == tab }) {
                var item = items.remove(at: index)
                item.visible = true
                return item
            }
            return Item(id: tab, visible: true)
        }
        let timer = take(.timer)
        let picker = take(.picker)
        let anchor = items.firstIndex(where: { $0.id == .calendar }).map { $0 + 1 } ?? min(5, items.count)
        items.insert(timer, at: min(anchor, items.count))
        items.insert(picker, at: min(anchor + 1, items.count))
        return items
    }

    private struct Record: Codable {
        var id: String
        var visible: Bool
    }
}
