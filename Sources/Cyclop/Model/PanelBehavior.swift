import Foundation

/// How the folded notch opens and how the open panel folds away.
///
/// The two sides are independent: open on a click and close when the pointer
/// leaves is a real combination, and the old "hover does both" is just the
/// default pair. Hidden behind Settings so a passing pointer can stop being
/// a decision without teaching a second gesture to everyone else.
@MainActor
final class PanelBehavior: ObservableObject {
    enum Open: String {
        case hover, click
    }

    enum Close: String {
        case leave, click
    }

    @Published private(set) var open: Open
    @Published private(set) var close: Close

    private static let openKey = "panel.open"
    private static let closeKey = "panel.close"

    var opensOnHover: Bool { open == .hover }
    var opensOnClick: Bool { open == .click }
    var closesOnLeave: Bool { close == .leave }
    var closesOnClick: Bool { close == .click }

    init() {
        let defaults = UserDefaults.standard
        open = Open(rawValue: defaults.string(forKey: Self.openKey) ?? "") ?? .hover
        close = Close(rawValue: defaults.string(forKey: Self.closeKey) ?? "") ?? .leave
    }

    func setOpen(_ value: Open) {
        guard open != value else { return }
        open = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.openKey)
    }

    func setClose(_ value: Close) {
        guard close != value else { return }
        close = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.closeKey)
    }
}
