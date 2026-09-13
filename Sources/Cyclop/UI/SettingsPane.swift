import SwiftUI
import ServiceManagement

/// What used to live in the status bar menu, minus the two items that belong
/// there: opening the panel and hiding its contents are both things people
/// reach for in a hurry, often without wanting to open the panel at all — the
/// rest is configuration, read rarely, and reads better as a tab like any
/// other than as a menu that grows a new row per feature.
struct SettingsPane: View {
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var layout: TabLayout
    @ObservedObject var behavior: PanelBehavior

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var saveClipboardImages = NotchViewModel.saveClipboardImagesEnabled
    @State private var allDisplays = NotchGeometry.showsOnAllDisplays
    @State private var screenshotUsage: (files: Int, bytes: Int64) = (0, 0)
    @State private var expanded: Set<String> = SettingsPane.loadExpanded()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                section("general", localized("General")) {
                    toggleRow(
                        symbol: "arrow.forward.to.line",
                        title: localized("Launch at Login"),
                        isOn: launchAtLoginBinding
                    )
                    choiceRow(
                        symbol: "hand.tap",
                        title: localized("Open"),
                        left: localized("On hover"),
                        right: localized("On click"),
                        isLeft: behavior.opensOnHover,
                        pickLeft: { behavior.setOpen(.hover) },
                        pickRight: { behavior.setOpen(.click) }
                    )
                    choiceRow(
                        symbol: "arrow.uturn.left",
                        title: localized("Close"),
                        left: localized("On leave"),
                        right: localized("Click outside"),
                        isLeft: behavior.closesOnLeave,
                        pickLeft: { behavior.setClose(.leave) },
                        pickRight: { behavior.setClose(.click) }
                    )
                }

                section("tabs", localized("Tabs")) {
                    Text("The first six that are on sit on the left. The rest go to the right.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                    ForEach(Array(layout.items.enumerated()), id: \.element.id) { index, item in
                        tabRow(item, index: index)
                    }
                    pinnedSettingsRow
                }

                section("displays", localized("Displays")) {
                    toggleRow(
                        symbol: "display.2",
                        title: localized("Show on All Displays"),
                        isOn: allDisplaysBinding
                    )
                }

                section("screenshots", localized("Screenshots")) {
                    toggleRow(
                        symbol: "photo.on.rectangle",
                        title: localized("Save Clipboard Screenshots"),
                        isOn: saveClipboardImagesBinding
                    )
                    actionRow(symbol: "folder", title: localized("Show Screenshots Folder")) {
                        ScreenshotVault.reveal()
                    }
                    actionRow(
                        symbol: "trash",
                        title: clearTitle,
                        disabled: screenshotUsage.files == 0
                    ) {
                        ScreenshotVault.clear()
                        shelf.load()
                        // The files were just deleted, so the cards have to go
                        // with them. Safe to look here: the vault lives in the
                        // app's own folder, which macOS does not guard.
                        shelf.refreshFromDisk()
                        refreshUsage()
                    }
                }

                section("snippets", localized("Snippets")) {
                    actionRow(symbol: "doc.text", title: localized("Show Snippets File")) {
                        SnippetStore.reveal()
                    }
                }

                section("favorites", localized("Favorites")) {
                    actionRow(symbol: "folder", title: localized("Show Favorites File")) {
                        FavoriteStore.reveal()
                    }
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Live state, not a snapshot taken once at launch: System Settings can
        // flip Launch at Login from outside, and the folder can empty or fill
        // between visits to this tab (#11 taught the same lesson for the menu
        // this replaces).
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            saveClipboardImages = NotchViewModel.saveClipboardImagesEnabled
            allDisplays = NotchGeometry.showsOnAllDisplays
            refreshUsage()
        }
    }

    private var clearTitle: String {
        guard screenshotUsage.files > 0 else { return localized("Clear Screenshots Folder") }
        let size = ByteCountFormatter.string(fromByteCount: screenshotUsage.bytes, countStyle: .file)
        return localized("Clear Screenshots Folder (%@)", size)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { wants in
                do {
                    if wants {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Cyclop: launch-at-login failed: \(error.localizedDescription)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    private var saveClipboardImagesBinding: Binding<Bool> {
        Binding(
            get: { saveClipboardImages },
            set: { wants in
                saveClipboardImages = wants
                UserDefaults.standard.set(wants, forKey: NotchViewModel.saveClipboardImagesKey)
            }
        )
    }

    /// Turning this off folds the panel back to one screen — the notched one
    /// if this Mac has a notch, the main display otherwise. The panels are
    /// rebuilt on the spot, so the switch is its own confirmation.
    private var allDisplaysBinding: Binding<Bool> {
        Binding(
            get: { allDisplays },
            set: { wants in
                allDisplays = wants
                NotchGeometry.showsOnAllDisplays = wants
            }
        )
    }

    /// Off the main thread: walking the folder takes as long as the folder is
    /// big, and this is the thread the whole panel lives on (#11).
    private func refreshUsage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let usage = ScreenshotVault.usage()
            DispatchQueue.main.async { screenshotUsage = usage }
        }
    }

    // MARK: - Rows

    private static let expandedKey = "settings.expanded"
    private static let defaultExpanded: Set<String> = ["general", "tabs"]

    private static func loadExpanded() -> Set<String> {
        if let saved = UserDefaults.standard.array(forKey: expandedKey) as? [String] {
            return Set(saved)
        }
        return defaultExpanded
    }

    private func toggleSection(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
        UserDefaults.standard.set(Array(expanded), forKey: Self.expandedKey)
    }

    @ViewBuilder
    private func section<Rows: View>(_ id: String, _ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        let isOpen = expanded.contains(id)
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(Theme.contentAnimation) { toggleSection(id) }
            } label: {
                HStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 8)
                .frame(height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(spacing: 1) {
                    rows()
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surface)
                )
            }
        }
    }

    private func tabRow(_ item: TabLayout.Item, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.id.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.visible ? Theme.secondary : Theme.tertiary)
                .frame(width: 16)
            Text(item.id.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(item.visible ? .white : Theme.secondary)
            Spacer(minLength: 6)
            Button { layout.move(item.id, to: index - 1) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(index == 0 ? Theme.tertiary : Theme.secondary)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            Button { layout.move(item.id, to: index + 1) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(index >= layout.items.count - 1 ? Theme.tertiary : Theme.secondary)
            }
            .buttonStyle(.plain)
            .disabled(index >= layout.items.count - 1)
            Toggle("", isOn: Binding(
                get: { item.visible },
                set: { layout.setVisible(item.id, $0) }
            ))
            .toggleStyle(NotchToggleStyle())
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .opacity(item.visible ? 1 : 0.7)
    }

    /// Settings itself is how this list is reached, so it is not a row that
    /// can be turned off or dragged past the others — it would be a switch
    /// that hides the switch.
    private var pinnedSettingsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: NotchViewModel.Tab.settings.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 16)
            Text(NotchViewModel.Tab.settings.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            Text("Always visible")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }

    private func choiceRow(
        symbol: String,
        title: String,
        left: String,
        right: String,
        isLeft: Bool,
        pickLeft: @escaping () -> Void,
        pickRight: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                choiceChip(left, selected: isLeft, action: pickLeft)
                choiceChip(right, selected: !isLeft, action: pickRight)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
    }

    private func choiceChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? .white : Theme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? Theme.surfaceHover : Theme.surface)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(symbol: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(NotchToggleStyle())
                .labelsHidden()
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }

    private func actionRow(
        symbol: String,
        title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}
