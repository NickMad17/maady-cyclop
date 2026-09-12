# MaadyCyclop

*English · [Русский](README.ru.md)*

The MacBook notch as a working panel: hover to open music, a file shelf, clipboard, meetings and the rest. Move away and it is just the notch again.

![The MaadyCyclop panel](docs/panel.png)

## Download

**[MaadyCyclop for macOS](https://github.com/NickMad17/maady-cyclop/releases/latest)** — the `.dmg` on the release page, macOS 15 or newer.

Works on a Mac without a notch too: the panel appears at the top centre of the screen.

## Install

1. Open the `.dmg`.
2. Drag **MaadyCyclop** into **Applications**.
3. Open it from Applications.

The first launch will be blocked: macOS says the app cannot be verified. That is expected. Allow it once:

**System Settings → Privacy & Security** → **Open Anyway** near the bottom.

Or in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/MaadyCyclop.app
```

To update, drop the new `.dmg` over the old app. You do not have to allow it again.

## How to use

Hover the notch to open the panel. Move away to close it. Tabs switch if the pointer rests on an icon, not if it just passes through.

The menu bar icon opens the panel, turns on launch at login, and quits.

Dragging files toward the notch opens the shelf by itself.

| Tab | What it does |
|---|---|
| **Music** | Artwork, track, pause, scrub, next. Whatever is playing on the Mac — a player or a browser tab. Nothing to configure in the browser |
| **Shelf** | Drop a file on the notch and it stays as a card until you take it. Cards can be copied or removed. Screenshots (⌘⇧3 / ⌘⇧4, or a copy, including from an iPhone) land here and in `~/Pictures/MaadyCyclop` by themselves. No setup on a new Mac |
| **Clipboard** | The last 40 copies. A click puts one back. Password-manager secrets are skipped |
| **Snippets** | Things you retype: email, phone, address. A click copies |
| **Calendar** | The next meeting and a join button (Zoom, Meet, Teams, …) if the event has a link |
| **Translate** | Type on the left, translation on the right, offline. The first time, download languages in Settings → General → Language & Region → Translation Languages… |
| **Teleprompter** | Text scrolls next to the camera. The panel stays open while it runs |
| **Notes** | Jot and leave. Blank notes clear themselves |

## Permissions

Day to day — **none**. No Screen Recording, no Accessibility, nothing in the browser.

Calendar asks only if you press the button on that tab. Skip the tab and it never asks.

Opening the shelf with a file from Downloads, Documents or Desktop may prompt for that folder. Refusing is fine: the card stays, without a preview.

## Good to know

- iPhone screenshots travel through Universal Clipboard: same Apple ID, Wi‑Fi, Bluetooth, Handoff, devices nearby.
- Shelf cards are links. Move the original file and the card goes. Screenshots do not: they live in `~/Pictures/MaadyCyclop` until you clear the folder in Settings.
- The join-call button appears only if the link is in the event itself.
- The menu bar can hide panel contents — useful on a shared-screen call.

## For developers

Build and run:

```bash
git clone https://github.com/NickMad17/maady-cyclop.git
cd maady-cyclop
./Scripts/bundle.sh
open build/MaadyCyclop.app
```

Disk image: `./Scripts/dmg.sh`. Release: bump `Scripts/version`, write `docs/releases/<version>.md`, then `./Scripts/release.sh`.

Needs macOS 15 and Swift 6 (Command Line Tools are enough). Licence: MIT.
