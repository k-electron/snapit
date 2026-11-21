<p align="center">
  <img src="Shared/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="snapit app icon" width="128" height="128">
</p>

# snapit

**A brilliantly simple macOS menu bar app: take a screenshot, mark it up, and get it onto the clipboard or into a file.**

[![Latest release](https://img.shields.io/github/v/release/k-electron/snapit)](https://github.com/k-electron/snapit/releases/latest)
[![CI](https://github.com/k-electron/snapit/actions/workflows/ci.yml/badge.svg)](https://github.com/k-electron/snapit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/k-electron/snapit)](LICENSE)

**[Download snapit from Releases](https://github.com/k-electron/snapit/releases/latest)** · macOS 26 or later, Apple silicon · [install steps](#download-and-install)

<!-- shot: hero-light -->

<!-- shot: hero-dark -->

<!-- shot: demo -->

snapit lives in the menu bar and does nothing, and costs nothing, until you ask. Drag an Area, add an Arrow and a Redaction, press ⌘C, and the marked-up screenshot is on your clipboard.

## What it does

### Area, Window and Screen Capture

Take a Capture of an Area you drag, of exactly one Window, or of a whole Screen, each from its own Shortcut.

<!-- shot: tour-area -->

<!-- shot: tour-window -->

<!-- shot: tour-screen -->

### The Action bar

After you select an Area, the Action bar floats beside it: Capture, a Timed Capture, the Color picker and Cancel.

<!-- shot: tour-action-bar -->

### Timed Capture

Set a countdown of 1 to 10 seconds and get your desktop back. A thin border marks the Area, and snapit takes the Capture when the badge reaches zero. Use it to catch a menu or a tooltip.

<!-- shot: tour-timed-capture -->

### Color picker

A loupe outlines one pixel of your screen. Click, and its `#RRGGBB` value is on the clipboard.

<!-- shot: tour-color-picker -->

### Editor tools

Every Capture opens in the Editor with Select, Arrow, Rectangle, Oval, Text, Highlighter, Redaction and Crop, in eight Annotation colors and three widths, with Undo and Redo.

<!-- shot: tour-editor-tools -->

### Redaction

A Redaction pixelates what lies beneath it, and destroys those pixels for good when you Export, so the hidden content can't be recovered from the file.

<!-- shot: tour-redaction -->

### Copy, Save and drag-out

Copy puts a PNG on the clipboard, Save writes one into your Save location, and the thumbnail drags into Finder or any app.

<!-- shot: tour-export -->

## Requirements

macOS 26 or later, on a Mac with Apple silicon.

## Download and install

1. Download the disk image (DMG) from the [latest release](https://github.com/k-electron/snapit/releases/latest).
2. Open it and drag snapit onto Applications.
3. Open snapit from Applications. snapit is ad-hoc signed, so macOS asks you to confirm it once.
4. Open System Settings › Privacy & Security, click **Open Anyway** and enter your password. Open snapit again.
5. Onboarding opens and takes you through the Screen Recording permission, the Save location and the Shortcuts.

## Quick start

The default Shortcuts work from any app:

| Shortcut | Capture |
|---|---|
| ⌃⌥⌘4 | Area |
| ⌃⌥⌘5 | Window |
| ⌃⌥⌘3 | Screen |

Take your first Capture:

1. Press ⌃⌥⌘4 and drag over part of your screen.
2. Press Enter, or click **Capture** in the Action bar. The Editor opens.
3. Mark it up with the tools on the left.
4. Press ⌘C to copy it, or ⌘S to save it.

## Privacy

snapit makes one network request: Check for Updates, and only when you click it. It talks to GitHub to ask whether a newer release exists. It collects nothing and sends nothing else.

## More

- [User Guide](docs/UserGuide.md): every flow, from install to Settings.
- [Contributing](CONTRIBUTING.md)
- [Technical index](docs/development/index.md): architecture, building, testing and releasing.
- [License](LICENSE): MIT.
