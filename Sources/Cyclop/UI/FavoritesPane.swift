import SwiftUI

struct FavoritesPane: View {
    @ObservedObject var favorites: FavoriteStore
    var isTargeted: Bool
    @Binding var wantsKeyboard: Bool
    /// Off by default: the tab is for opening folders, and colour dots plus
    /// reorder arrows on every hover made a glance at the list feel like
    /// editing it. The pencil turns that on for as long as it is needed.
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            if favorites.fileBroken { brokenNotice }
            if favorites.entries.isEmpty {
                dropHint
            } else {
                grid
            }
        }
        .padding(.top, 2)
        .onAppear { favorites.refreshFromDisk() }
        .onChange(of: favorites.items.isEmpty) { _, empty in
            if empty { isEditing = false }
        }
        .animation(Theme.contentAnimation, value: isEditing)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            if !favorites.items.isEmpty {
                Button { isEditing.toggle() } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isEditing ? .white : Theme.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isEditing ? Theme.surfaceHover : .clear)
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .help(localized(isEditing ? "Done" : "Edit"))
            }
            if isEditing, favorites.items.count >= 2 {
                Button { favorites.addDivider(.vertical) } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .help(localized("Add a vertical divider"))
                Button { favorites.addDivider(.horizontal) } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .help(localized("Add a horizontal divider"))
            }
            Spacer(minLength: 0)
            Button { favorites.pick() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .help(localized("Add folders"))
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
    }

    /// The refusal to write over a broken file is only honest if it is said
    /// out loud: a log line is where refusals go to be unread.
    private var brokenNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.yellow.opacity(0.85))
            Text("favorites.json is broken — click to open; nothing is overwritten")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { FavoriteStore.reveal() }
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                isTargeted ? Color.white.opacity(0.6) : Theme.hairline,
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? Theme.surface : .clear)
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20, weight: .light))
                    Text("Drop folders here, or add with +")
                        .font(.system(size: 10))
                }
                .foregroundStyle(isTargeted ? .white : Theme.tertiary)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Theme.contentAnimation, value: isTargeted)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sections) { section in
                    if let divider = section.hDivider {
                        FavoriteHDivider(
                            id: divider,
                            favorites: favorites,
                            isEditing: isEditing
                        )
                    }
                    if !section.items.isEmpty {
                        FavoriteWrap(spacing: 8, lineSpacing: 8) {
                            ForEach(section.items) { item in
                                switch item {
                                case .folder(let folder):
                                    FavoriteCard(
                                        item: folder,
                                        favorites: favorites,
                                        isEditing: isEditing,
                                        wantsKeyboard: $wantsKeyboard
                                    )
                                case .vDivider(let id):
                                    FavoriteVDivider(
                                        id: id,
                                        favorites: favorites,
                                        isEditing: isEditing
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
            .animation(Theme.contentAnimation, value: favorites.entries)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.white.opacity(0.45) : .clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
                .animation(Theme.contentAnimation, value: isTargeted)
        )
    }

    /// Horizontal lines start a new row of cards. Vertical lines sit in the
    /// row, between the cards they split. A line with nothing next to it still
    /// shows in edit mode, so adding one is not a disappearing act.
    private var sections: [FavoriteSection] {
        var result: [FavoriteSection] = [FavoriteSection(id: "head", hDivider: nil, items: [])]
        for entry in favorites.entries {
            switch entry {
            case .folder(let folder):
                result[result.count - 1].items.append(.folder(folder))
            case .divider(let id, .horizontal):
                result.append(FavoriteSection(id: id.uuidString, hDivider: id, items: []))
            case .divider(let id, .vertical):
                result[result.count - 1].items.append(.vDivider(id))
            }
        }
        return result.filter { section in
            if !section.items.isEmpty { return true }
            return isEditing && section.hDivider != nil
        }
    }
}

private struct FavoriteSection: Identifiable {
    let id: String
    var hDivider: UUID?
    var items: [FavoriteInline]
}

private enum FavoriteInline: Identifiable {
    case folder(FavoriteFolder)
    case vDivider(UUID)

    var id: String {
        switch self {
        case .folder(let folder): return "folder.\(folder.path)"
        case .vDivider(let id): return "vdiv.\(id.uuidString)"
        }
    }
}

/// Cards are a fixed 86pt; a vertical line is much thinner. Adaptive grid
/// would give the line a whole column. This wrap keeps each view's own width
/// and only starts a new line when the row is full.
private struct FavoriteWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        frames(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let placed = frames(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (subview, frame) in zip(subviews, placed.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Placed {
        var size: CGSize
        var frames: [CGRect]
    }

    private func frames(proposal: ProposedViewSize, subviews: Subviews) -> Placed {
        let limit = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        let width = limit.isFinite ? limit : maxX
        return Placed(size: CGSize(width: width, height: y + rowHeight), frames: frames)
    }
}

/// A full-width hairline under a row. In edit mode it grows just enough
/// for the same arrows and cross the cards have, so moving a line is the
/// same act as moving a folder.
private struct FavoriteHDivider: View {
    let id: UUID
    @ObservedObject var favorites: FavoriteStore
    let isEditing: Bool

    private var index: Int {
        favorites.entries.firstIndex(where: { $0.dividerID == id }) ?? 0
    }
    private var isLast: Bool { index >= favorites.entries.count - 1 }

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                Button { favorites.moveDivider(id, to: index - 1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(index == 0 ? Theme.tertiary : Theme.secondary)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
            }
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(height: 1)
            if isEditing {
                Button { favorites.moveDivider(id, to: index + 1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isLast ? Theme.tertiary : Theme.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                Button { favorites.removeDivider(id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .help(localized("Remove"))
            }
        }
        .frame(height: isEditing ? 16 : 8)
        .padding(.vertical, 2)
    }
}

/// A line between two cards in a row. Same height as a card, so it reads as
/// a split of that row rather than a stray mark in the margin.
private struct FavoriteVDivider: View {
    let id: UUID
    @ObservedObject var favorites: FavoriteStore
    let isEditing: Bool

    private var index: Int {
        favorites.entries.firstIndex(where: { $0.dividerID == id }) ?? 0
    }
    private var isLast: Bool { index >= favorites.entries.count - 1 }

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                VStack(spacing: 2) {
                    Button { favorites.moveDivider(id, to: index - 1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(index == 0 ? Theme.tertiary : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    Button { favorites.moveDivider(id, to: index + 1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isLast ? Theme.tertiary : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }
            }
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 1, height: isEditing ? 56 : 48)
            if isEditing {
                Button { favorites.removeDivider(id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .help(localized("Remove"))
            }
        }
        .frame(width: isEditing ? 28 : 10, height: 92)
    }
}

private struct FavoriteCard: View {
    let item: FavoriteFolder
    @ObservedObject var favorites: FavoriteStore
    /// Pane-level: colour, order and the cross exist only while this is on.
    let isEditing: Bool
    @Binding var wantsKeyboard: Bool
    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var index: Int { favorites.entries.firstIndex(where: { $0.folder?.path == item.path }) ?? 0 }
    private var isLast: Bool { index >= favorites.entries.count - 1 }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(item.tint.color)
                .frame(width: 40, height: 40)
                .opacity(item.isMissing ? 0.4 : 1)
                .overlay(alignment: .bottom) {
                    if isEditing, !renaming { palette }
                }

            if renaming {
                TextField(localized("Name"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit { commit() }
                    .frame(height: 24)
            } else {
                Text(item.name)
                    .font(.system(size: 9))
                    .foregroundStyle(item.isMissing ? Theme.tertiary : Theme.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 24, alignment: .top)
                    .onTapGesture {
                        if isEditing { beginRenaming() }
                    }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 86, height: 92)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardFill)
        )
        .overlay(alignment: .topTrailing) {
            if isEditing, !renaming {
                Button { favorites.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help(localized("Remove"))
            }
        }
        .overlay(alignment: .topLeading) {
            if isEditing, !renaming, favorites.entries.count > 1 {
                HStack(spacing: 0) {
                    Button { favorites.move(item, to: index - 1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(index == 0 ? Theme.tertiary : Theme.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    Button { favorites.move(item, to: index + 1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isLast ? Theme.tertiary : Theme.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }
                .padding(4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { if !isEditing { favorites.open(item) } }
        .contextMenu {
            if isEditing {
                Button("Rename") { beginRenaming() }
                Menu {
                    ForEach(FavoriteTint.allCases) { tint in
                        Button(tint.title) { favorites.setTint(item, tint) }
                    }
                } label: {
                    Text("Color")
                }
                Divider()
            }
            Button("Open") { favorites.open(item) }
            Button("Show in Finder") { favorites.reveal(item) }
            if isEditing {
                Divider()
                Button("Remove") { favorites.remove(item) }
            }
        }
        .opacity(item.isMissing ? 0.85 : 1)
        .help(item.isMissing ? localized("Folder is missing") : item.path)
        .animation(Theme.contentAnimation, value: hovering)
        .animation(Theme.contentAnimation, value: item.tint)
        .animation(Theme.contentAnimation, value: renaming)
        .onKeyPress(.escape) {
            guard renaming else { return .ignored }
            cancel()
            return .handled
        }
        .onChange(of: focused) { _, now in
            if renaming, !now { commit() }
        }
        .onChange(of: isEditing) { _, on in
            if !on, renaming { commit() }
        }
        .onDisappear { if renaming { commit() } }
    }

    private var cardFill: Color {
        let base = item.tint.color
        if renaming || (isEditing && hovering) { return base.opacity(0.22) }
        if isEditing { return base.opacity(0.16) }
        return hovering ? base.opacity(0.18) : base.opacity(0.12)
    }

    /// Eight dots, one per tint. They sit on the folder rather than under the
    /// name: the name is what the card is for, and covering it to pick a
    /// colour would be painting over the label you just came to read.
    private var palette: some View {
        HStack(spacing: 2) {
            ForEach(FavoriteTint.allCases) { tint in
                Button { favorites.setTint(item, tint) } label: {
                    Circle()
                        .fill(tint.color)
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(item.tint == tint ? 0.95 : 0.25),
                                    lineWidth: item.tint == tint ? 1.2 : 0.5
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(tint.title)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
        )
    }

    private func beginRenaming() {
        draft = item.label.isEmpty ? item.name : item.label
        renaming = true
        focused = true
        wantsKeyboard = true
    }

    private func cancel() {
        renaming = false
        focused = false
    }

    private func commit() {
        guard renaming else { return }
        renaming = false
        focused = false
        // Clearing the field puts the folder's own name back, rather than
        // leaving a blank card: a name you cannot read is not a name.
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        favorites.setLabel(item, trimmed == item.url.lastPathComponent ? "" : trimmed)
    }
}
