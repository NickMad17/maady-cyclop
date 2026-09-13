import SwiftUI

struct NotchContentView: View {
    @ObservedObject var vm: NotchViewModel
    /// This screen's share of the panel. Everything the pointer decides is
    /// here; everything shown is in `vm`, the same on every display.
    @ObservedObject var panel: PanelState

    private var isOpen: Bool { panel.isActive }
    private var size: CGSize { panel.bodySize }
    private var topRadius: CGFloat {
        isOpen ? Theme.openTopRadius : panel.geometry.collapsedShoulderRadius
    }
    private var bottomRadius: CGFloat {
        isOpen ? Theme.openBottomRadius : panel.geometry.collapsedCornerRadius
    }
    /// Folded over a real camera the measured gap *is* the silhouette,
    /// shoulders included. Adding `2 * topRadius` on top of that painted
    /// extra black on the menu bar. Open, and on a drawn notch, the
    /// shoulders still sit outside the body — that is the flare.
    private var shapeWidth: CGFloat {
        if isOpen || !panel.geometry.isPhysical {
            return size.width + 2 * topRadius
        }
        return size.width
    }

    var body: some View {
        // The shape is wider than the body by `topRadius` on each side: that
        // slack is where the concave shoulders live, so it must not be clipped.
        ZStack(alignment: .top) {
            NotchShape(
                topRadius: topRadius,
                bottomRadius: bottomRadius
            )
            .fill(Color.black)
            .frame(width: shapeWidth, height: size.height)
            .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)

            VStack(spacing: 0) {
                header
                if isOpen {
                    content
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
        }
        .frame(width: shapeWidth, height: size.height, alignment: .top)
        .overlay(alignment: .bottom) {
            if !isOpen {
                TimerNotchBar(timer: vm.timer)
                    .padding(.horizontal, 2)
                    .offset(y: 3)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            if !isOpen, vm.behavior.opensOnClick {
                Color.clear
                    .frame(
                        width: panel.geometry.collapsedClickSize.width,
                        height: panel.geometry.collapsedClickSize.height
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { panel.notchClicked() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(Theme.openAnimation, value: isOpen)
        .animation(Theme.paneAnimation, value: vm.tab)
    }

    // MARK: - Header
    //
    // This strip sits directly on top of the menu bar. Menu bar utilities such
    // as Ice watch for clicks there with a global event monitor — a passive
    // observer that sees the click no matter which window consumes it — so
    // clicking here toggles them as a side effect. The tab switcher stays in
    // the rail below. A tap is wired only when Settings asked for a click
    // to open: hover-only keeps this row deaf, and a click to close is a
    // click outside the panel, not on this strip.

    private var header: some View {
        HStack(spacing: 0) {
            if isOpen {
                Text(vm.tab.title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, 16)
                    .id(vm.tab)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: panel.geometry.notchSize.width, height: 1)
            Spacer(minLength: 0)
            if isOpen {
                trailing
                    .padding(.trailing, 16)
                    .transition(.opacity)
            }
        }
        .frame(height: panel.geometry.notchSize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isOpen, vm.behavior.opensOnClick else { return }
            panel.notchClicked()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch vm.tab {
        case .media:
            HStack(spacing: 6) {
                if vm.media.track != nil {
                    EqualizerBars(isAnimating: vm.media.isPlaying)
                }
                Text(vm.media.sourceName ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        case .shelf:
            counter(vm.shelf.items.count)
        case .clipboard:
            counter(vm.clipboard.items.count)
        case .snippets:
            counter(vm.snippets.items.count)
        case .calendar:
            if let next = vm.calendar.next {
                Text(CalendarPane.countdown(to: next, from: vm.calendar.now))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(next.isRunning ? Color.white.opacity(0.8) : Theme.tertiary)
            }
        case .timer:
            TimerTrailing(timer: vm.timer)
        case .translate:
            // Nothing: the columns name both languages already, and the strip
            // is the one part of the panel worth not spending on a repeat.
            EmptyView()
        case .notes:
            NotesCounter(notes: vm.notes)
        case .favorites:
            counter(vm.favorites.items.count)
        case .picker:
            PickerTrailing(picker: vm.picker)
        case .teleprompter:
            EmptyView()
        case .settings:
            EmptyView()
        }
    }

    @ViewBuilder
    private func counter(_ value: Int) -> some View {
        if value > 0 {
            Text("\(value)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: - Body

    private var content: some View {
        HStack(spacing: 14) {
            if !vm.layout.leftRail.isEmpty {
                Rail(vm: vm, panel: panel, tabs: vm.layout.leftRail)
            }
            panes
            Rail(vm: vm, panel: panel, tabs: vm.layout.rightRail)
        }
        .padding(.horizontal, 14)
        // The body's height is measured from this same number, so the two
        // cannot drift apart into a rail that does not fit.
        .padding(.bottom, NotchGeometry.bodyBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.contentAnimation, value: vm.layout.items)
    }

    private var panes: some View {
        // Content is replaced in place — no travel. The rail is vertical and
        // the panes are unrelated, so a direction would only be decoration.
        ZStack {
            pane
                .id(vm.tab)
                .transition(.asymmetric(
                    insertion: .opacity
                        .combined(with: .scale(scale: 0.97))
                        .animation(Theme.paneIn),
                    removal: .opacity
                        .combined(with: .scale(scale: 1.02))
                        .animation(Theme.paneOut)
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var pane: some View {
        switch vm.tab {
        case .media:
            MediaPane(media: vm.media)
        case .shelf:
            ShelfPane(shelf: vm.shelf, isTargeted: panel.isDropTargeted)
        case .clipboard:
            ClipboardPane(clipboard: vm.clipboard, privacy: vm.privacy)
        case .calendar:
            CalendarPane(calendar: vm.calendar, privacy: vm.privacy)
        case .timer:
            TimerPane(timer: vm.timer)
        case .snippets:
            SnippetsPane(snippets: vm.snippets, privacy: vm.privacy, wantsKeyboard: $panel.wantsKeyboard)
        case .translate:
            TranslatePane(
                translator: vm.translator,
                wantsKeyboard: $panel.wantsKeyboard,
                isTargeted: panel.isDropTargeted && vm.tab == .translate
            )
        case .notes:
            NotesPane(notes: vm.notes, privacy: vm.privacy, wantsKeyboard: $panel.wantsKeyboard)
        case .favorites:
            FavoritesPane(favorites: vm.favorites, isTargeted: panel.isDropTargeted, wantsKeyboard: $panel.wantsKeyboard)
        case .picker:
            ColorPickerPane(picker: vm.picker)
        case .teleprompter:
            TeleprompterPane(prompter: vm.teleprompter, wantsKeyboard: $panel.wantsKeyboard)
        case .settings:
            SettingsPane(shelf: vm.shelf, layout: vm.layout, behavior: vm.behavior)
        }
    }
}

/// Watches the note store itself rather than reading through the view model:
/// notes are born and deleted inside the pane while this counter is on
/// screen, and the view model deliberately does not forward keystroke-driven
/// stores.
private struct NotesCounter: View {
    @ObservedObject var notes: NoteStore

    var body: some View {
        if !notes.notes.isEmpty {
            Text("\(notes.notes.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Same reason as `NotesCounter`: the timer ticks while the panel is folded,
/// and forwarding those ticks through the view model would redraw every pane.
private struct TimerTrailing: View {
    @ObservedObject var timer: TimerStore

    var body: some View {
        if timer.showsInNotch {
            Text(timer.isFinished ? localized("Done") : timer.clock)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(timer.isRunning || timer.isFinished ? Color.white.opacity(0.8) : Theme.tertiary)
                .contentTransition(.numericText())
                .animation(Theme.contentAnimation, value: timer.secondsLeft)
        }
    }
}

private struct PickerTrailing: View {
    @ObservedObject var picker: ColorPickerStore

    var body: some View {
        if let current = picker.current {
            HStack(spacing: 6) {
                Circle()
                    .fill(current.color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
                Text(current.hex)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

/// Tab switcher.
///
/// Hovering switches tabs, but only after the pointer has stopped: a pointer
/// crossing the rail on its way somewhere else is gone in a few dozen
/// milliseconds, while one that came to choose stays put. The same dwell
/// threshold is what separates "the mouse was flung across the top of the
/// screen" from "the mouse came to the notch" in `PointerWatcher`.
private struct Rail: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var panel: PanelState
    /// Which icons this rail carries — there are two rails now, one per side.
    let tabs: [NotchViewModel.Tab]

    @State private var hovered: NotchViewModel.Tab?

    /// Long enough to swallow a pass-through, short enough that a deliberate
    /// hover still feels like it answered instantly.
    private let dwell = Duration.milliseconds(150)

    var body: some View {
        VStack(spacing: NotchGeometry.railSpacing) {
            ForEach(tabs) { tab in
                Button {
                    panel.select(tab)
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: panel.geometry.railIconHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(fill(for: tab))
                        )
                        .foregroundStyle(vm.tab == tab ? Color.white : Theme.tertiary)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        // A render-time transform. Growing the frame instead
                        // would re-lay out the rail on every hover, and layout
                        // that runs on pointer movement is exactly the kind
                        // that shows up as a stutter.
                        .scaleEffect(hovered == tab ? 1.15 : 1)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        hovered = tab
                    } else if hovered == tab {
                        hovered = nil
                    }
                }
            }
        }
        .frame(width: 30)
        // Centred in the height an ordinary tab has, then that block pinned to
        // the top of whatever height this tab actually got. On the ordinary
        // tabs the two are the same and nothing moves; on the teleprompter the
        // extra 192 pt goes to the script below, and the icons stay put.
        .frame(height: panel.geometry.standardContentHeight, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Theme.contentAnimation, value: hovered)
        // Moving to another icon cancels the pending switch along with the
        // task, so only the icon actually rested on ever wins.
        .task(id: hovered) {
            guard let hovered, hovered != vm.tab else { return }
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            panel.select(hovered)
        }
    }

    private func fill(for tab: NotchViewModel.Tab) -> Color {
        if vm.tab == tab { return Theme.surfaceHover }
        return hovered == tab ? Theme.surface : .clear
    }
}
