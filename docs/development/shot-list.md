# Shot list

Every image in the README and the User Guide has an entry here: what it shows, how to set the screen up for it, and which doc uses it, so anyone can retake any shot identically. Shots are taken by hand on a real Mac. Docs land before the shots do, each missing image as a slot marker (see "Slot markers and adding a shot").

`scripts/check-docs.sh` reads this file, so keep to the format below. [Testing](testing.md) lists what the check enforces.

## The entry format

One entry per image: a User Guide image under `## The User Guide shots`, a README image under `## The README shots`, both below. Every `###` heading in this file is a shot id, so the guidance sections use `##` only.

```
### menu-bar-menu

- File: `user-guide/menu-bar-menu.png`
- Surface: what the shot shows, in the words of GLOSSARY.md.
- Setup: State: what is open and selected. Sample content: what is on screen. Appearance: Light. Size: the window or crop size. Taken with: how.
- Used by: [User Guide, The menu bar menu](../UserGuide.md#menu)
```

- The id is lowercase-kebab (`a-z`, `0-9` and `-`) and unique.
- `File:` is a path under `docs/images/`: `user-guide/<id>.png` for the User Guide, `readme/<id>.png` for the README. An animation is `<id>.gif`. The file name is always the id.
- `Surface:`, `Setup:` and `Used by:` follow `File:`. `Used by:` links to the doc and the section.
- Every file under `docs/images/`, at any depth and of any extension, has an entry, matched by its path.

## Slot markers and adding a shot

A shot not yet taken is a slot marker in the doc, at the place the image goes: an HTML comment on a line of its own, with a blank line before and after it, and never inside a list, a table or a note.

```
<!-- shot: menu-bar-menu -->
```

It renders as nothing on GitHub and in snapit. `scripts/check-docs.sh` lists every marker whose file is not there yet as pending, and a pending marker never fails the check. A marker that names an id missing from this file does fail it.

To add a shot:

1. Take it as the entry says and save it as the entry's `File:`, under `docs/images/`. Git does not track an empty folder, so create the folder with the first shot.
2. Replace the marker with the image reference.
   - In the User Guide the reference is a Markdown image on a line of its own, `![alt text](images/user-guide/<id>.png)`. snapit drops only such lines, so an `<img>` or `<picture>` in the User Guide would show as raw text in the window.
   - In the README it is `![alt text](docs/images/readme/<id>.png)`.
3. Run `scripts/check-docs.sh`. It fails on an image that does not exist and on a file with no entry.

The README hero is the one place where a Light and a Dark shot share a position. Its two markers, `hero-light` and `hero-dark`, wait side by side, and GitHub shows nothing for them. Once both files exist, replace the two markers with one `<picture>` on lines of its own, with a blank line before and after:

```
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/readme/hero-dark.png">
  <img src="docs/images/readme/hero-light.png" alt="snapit taking a Capture of an Area" width="800">
</picture>
```

Until both files exist the markers stay, so the README never shows a broken image.

To retake a shot, replace the file and keep the name.

## Shooting guidance

- **Tidy desktop.** A plain wallpaper, no other windows, an uncluttered menu bar, no notification banners (turn on Do Not Disturb).
- **Original sample content.** Everything on screen is made up for the purpose: no real data, and no third-party app shown by name, in a title bar, a Dock icon or a menu bar item.
- **Light appearance.** Every shot is Light, so it reads at GitHub's page width. The README hero is the one shot that also has a Dark version.
- **Windows with snapit's own Window Capture.** It keeps the window's transparent corners and leaves out its shadow, so the shot sits cleanly on the page. For a menu, an overlay or a countdown, which a Window Capture cannot take, use the macOS screenshot tool (⇧⌘5, a selection).
- **Retina, native pixels.** Take shots on a Retina display and keep them at native pixels. Crop to the surface and a little around it.
- **Default state.** The default Shortcuts, Settings at their defaults, Screen Recording allowed, Save location a tidy folder, the pointer out of the shot unless the entry puts it in.
- **Labels.** Where an entry asks for labels, add plain text with thin lines in a neutral color.
- **No personal details.** No name, account, path or folder of yours in any shot.

## The Sample Capture

The Annotation and Editor shots share one Sample Capture, an Area Capture of an original page, "Harbour Café, weekly specials": a heading, three short lines of text, a small illustration of a boat and a solid color block. Build it in a plain window with no app name visible, and capture it about 1200 pixels wide. Keep it the same across shots, so a reader sees the same page being marked up.

## The User Guide shots

### install-dmg-window

- File: `user-guide/install-dmg-window.png`
- Surface: The disk image window: snapit, an arrow and the Applications folder.
- Setup: State: The DMG is open in Finder, icon view, with no other Finder window. Sample content: none beyond what the state needs. Appearance: Light. Size: the DMG window at its own size. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Install and Open Anyway](../UserGuide.md#install)

### install-open-anyway

- File: `user-guide/install-open-anyway.png`
- Surface: System Settings > Privacy & Security with the Open Anyway button for snapit.
- Setup: State: System Settings is open on Privacy & Security after macOS blocked snapit once; the Open Anyway button is visible. Sample content: none beyond what the state needs. Appearance: Light. Size: System Settings at its own size, cropped to the Security section. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Install and Open Anyway](../UserGuide.md#install)

### move-to-applications-offer

- File: `user-guide/move-to-applications-offer.png`
- Surface: The window "Move snapit to Applications".
- Setup: State: snapit was opened straight from the mounted DMG. Sample content: none beyond what the state needs. Appearance: Light. Size: the window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Move to Applications](../UserGuide.md#move-to-applications)

### onboarding-welcome

- File: `user-guide/onboarding-welcome.png`
- Surface: Onboarding, the Welcome step, showing where snapit lives in the menu bar.
- Setup: State: First launch; Welcome is the current step. Sample content: none beyond what the state needs. Appearance: Light. Size: the Onboarding window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Onboarding](../UserGuide.md#onboarding)

### onboarding-shortcuts

- File: `user-guide/onboarding-shortcuts.png`
- Surface: Onboarding, the Shortcuts step, with the default Shortcuts in their recorders.
- Setup: State: Onboarding on the Shortcuts step; the default Shortcuts. Sample content: none beyond what the state needs. Appearance: Light. Size: the Onboarding window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Onboarding](../UserGuide.md#onboarding)

### onboarding-done

- File: `user-guide/onboarding-done.png`
- Surface: Onboarding, the Done step, with "Try it: press ⌃⌥⌘4" and the link that opens the User Guide.
- Setup: State: Onboarding on the last step. Sample content: none beyond what the state needs. Appearance: Light. Size: the Onboarding window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Onboarding](../UserGuide.md#onboarding)

### permission-guide-screen-recording

- File: `user-guide/permission-guide-screen-recording.png`
- Surface: The Screen Recording Permission guide in Onboarding: the animated drawing of System Settings with snapit's switch turned on.
- Setup: State: Onboarding on the Screen Recording step with the permission not yet granted; freeze the animation on the frame where the switch is on. Sample content: none beyond what the state needs. Appearance: Light. Size: the Onboarding window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Screen Recording](../UserGuide.md#screen-recording)

### permission-guide-screen-recording-denied

- File: `user-guide/permission-guide-screen-recording-denied.png`
- Surface: The Screen Recording Permission guide after Don't Allow: the System Settings version with its Open System Settings button.
- Setup: State: Screen Recording was refused at macOS's message; the guide shows the System Settings variant. Sample content: none beyond what the state needs. Appearance: Light. Size: the guide window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Screen Recording](../UserGuide.md#screen-recording)

### screen-recording-notice-macos

- File: `user-guide/screen-recording-notice-macos.png`
- Surface: One of macOS's periodic notices about an app that can record the screen, naming snapit.
- Setup: State: snapit has Screen Recording; macOS shows its own notice. Sample content: none beyond what the state needs. Appearance: Light. Size: the notice at its own size, with a little desktop around it. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Periodic Screen Recording notices](../UserGuide.md#screen-recording-notices)

### menu-bar-menu

- File: `user-guide/menu-bar-menu.png`
- Surface: The snapit menu open under its menu bar icon, every item visible.
- Setup: State: snapit running with a Last Capture, so Reopen Last Capture is not greyed out; the default Shortcuts. Sample content: none beyond what the state needs. Appearance: Light. Size: the menu and its icon, about 480 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, The menu bar menu](../UserGuide.md#menu)

### settings-shortcuts

- File: `user-guide/settings-shortcuts.png`
- Surface: Settings, the Shortcuts section: recorders for Area, Window, Screen and Pick Color, and the Keyboard settings button.
- Setup: State: Settings scrolled to Shortcuts; the default Shortcuts, Pick Color empty. Sample content: none beyond what the state needs. Appearance: Light. Size: the Settings window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Shortcuts](../UserGuide.md#shortcuts)

### system-settings-screenshot-shortcuts

- File: `user-guide/system-settings-screenshot-shortcuts.png`
- Surface: System Settings > Keyboard > Keyboard Shortcuts > Screenshots, with the ⇧⌘3, ⇧⌘4 and ⇧⌘5 shortcuts turned off.
- Setup: State: The Screenshots list is open and the shortcuts for ⇧⌘3, ⇧⌘4 and ⇧⌘5 are off. Sample content: none beyond what the state needs. Appearance: Light. Size: the Keyboard Shortcuts sheet at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Free ⌘⇧3, ⌘⇧4 and ⌘⇧5](../UserGuide.md#free-system-shortcuts)

### area-overlay

- File: `user-guide/area-overlay.png`
- Surface: The Area overlay: the crosshair, the loupe by the pointer and the dimmed screen around a selected Area.
- Setup: State: An Area Capture in progress with an Area selected over the sample page; the Action bar is not shown yet (drag, hold the mouse down). Sample content: an original made-up page (see the Sample Capture) on the display. Appearance: Light. Size: one display; crop to the Area and its surroundings, about 900 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Area Capture](../UserGuide.md#capture-area)

### area-window-highlight

- File: `user-guide/area-window-highlight.png`
- Surface: The Area overlay highlighting the window under the pointer.
- Setup: State: An Area Capture in progress; the pointer rests over one tidy window with nothing else on the desktop. Sample content: an original made-up page in a window (no app name visible). Appearance: Light. Size: one display; crop to the window and its surroundings. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Area Capture](../UserGuide.md#capture-area)

### window-capture-highlight

- File: `user-guide/window-capture-highlight.png`
- Surface: Window Capture: one window outlined, the rest of the screen dimmed, no crosshair, no loupe.
- Setup: State: A Window Capture in progress; the pointer is over one tidy window. Sample content: an original made-up page in a window (no app name visible). Appearance: Light. Size: one display; crop to the window and its surroundings. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Window Capture](../UserGuide.md#capture-window)

### screen-capture-editor

- File: `user-guide/screen-capture-editor.png`
- Surface: A Screen Capture in the Editor, the whole display visible in the canvas.
- Setup: State: A Screen Capture of a tidy desktop has just been taken; the Editor is open with no Annotations. Sample content: a tidy desktop with one original made-up window. Appearance: Light. Size: the Editor at its opening size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Screen Capture](../UserGuide.md#capture-screen)

### action-bar

- File: `user-guide/action-bar.png`
- Surface: The Action bar beside a selected Area: Capture, the Timer slider, Capture in N s, Pick Color and Cancel, with the Area's eight handles.
- Setup: State: An Area is selected with After selecting an Area set to Show Action bar; the Timer slider at 5. Sample content: the Sample Capture's page behind the Area. Appearance: Light. Size: crop to the Area and its Action bar, about 800 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, The Action bar](../UserGuide.md#action-bar)

### timed-capture-countdown

- File: `user-guide/timed-capture-countdown.png`
- Surface: A Timed Capture counting down: the thin border around the Area and the badge with the seconds left and the ✕.
- Setup: State: A Timed Capture started with the Timer slider at 5; the countdown shows 3. Sample content: an original made-up page behind the border. Appearance: Light. Size: crop to the Area and the badge. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Timed Capture](../UserGuide.md#timed-capture)

### color-picker-loupe

- File: `user-guide/color-picker-loupe.png`
- Surface: The Color picker: the large loupe outlining one pixel, with its swatch and #RRGGBB value.
- Setup: State: The Color picker is open over a flat, saturated area of the sample page. Sample content: an original made-up page with a solid colour block. Appearance: Light. Size: crop to the loupe, about 400 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Color picker](../UserGuide.md#color-picker)

### color-picker-toast

- File: `user-guide/color-picker-toast.png`
- Surface: The "Copied #…" toast after a click in the Color picker.
- Setup: State: A click has just copied the value; the toast is showing. Sample content: an original made-up page with a solid colour block. Appearance: Light. Size: crop to the toast and the pixel it names. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Color picker](../UserGuide.md#color-picker)

### editor-toolbar-labelled

- File: `user-guide/editor-toolbar-labelled.png`
- Surface: The Editor with its toolbar labelled: the tools on the left, Annotation color, width and fill at the top left, Undo, Redo, Delete Annotation, drag-out thumbnail, Copy and Save at the top right, Delete Capture at the far right.
- Setup: State: The Editor open on the Sample Capture, no Annotations, Select tool active; add the labels afterwards, plain text with thin lines. Sample content: the Sample Capture. Appearance: Light. Size: the Editor at its opening size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, The Editor](../UserGuide.md#editor)

### annotation-arrow

- File: `user-guide/annotation-arrow.png`
- Surface: An Arrow Annotation on a Capture.
- Setup: State: The Arrow tool; one Arrow pointing at the heading of the sample page, red, the middle width. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Capture area of the Editor, about 700 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Tools](../UserGuide.md#tools)

### annotation-rectangle

- File: `user-guide/annotation-rectangle.png`
- Surface: A Rectangle Annotation, outline, on a Capture.
- Setup: State: The Rectangle tool with Outline; one Rectangle around the illustration, red, the middle width. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Capture area of the Editor, about 700 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Tools](../UserGuide.md#tools)

### annotation-oval

- File: `user-guide/annotation-oval.png`
- Surface: An Oval Annotation, outline, on a Capture.
- Setup: State: The Oval tool with Outline; one Oval around one line of text, red, the middle width. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Capture area of the Editor, about 700 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Tools](../UserGuide.md#tools)

### annotation-text

- File: `user-guide/annotation-text.png`
- Surface: A Text Annotation on a Capture.
- Setup: State: The Text tool; one Text of a few made-up words ("Start here") by the heading, red, the middle size. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Capture area of the Editor, about 700 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Tools](../UserGuide.md#tools)

### annotation-highlighter

- File: `user-guide/annotation-highlighter.png`
- Surface: A Highlighter Annotation over a line of text.
- Setup: State: The Highlighter tool; one stroke over a line of the sample page, yellow, the middle width. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Capture area of the Editor, about 700 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Tools](../UserGuide.md#tools)

### redaction

- File: `user-guide/redaction.png`
- Surface: A Redaction pixelating part of a Capture.
- Setup: State: The Redaction tool; one Redaction over a made-up line of text (a fake reference number). Sample content: the Sample Capture. Appearance: Light. Size: crop to the Capture area of the Editor, about 700 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Tools](../UserGuide.md#tools)

### crop-handles

- File: `user-guide/crop-handles.png`
- Surface: The Crop tool with its crop rectangle and handles, and the Apply Crop button.
- Setup: State: The Crop tool; a crop rectangle drawn inside the Capture, not yet applied. Sample content: the Sample Capture. Appearance: Light. Size: the Editor at its opening size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Tools](../UserGuide.md#tools)

### annotation-color-swatches

- File: `user-guide/annotation-color-swatches.png`
- Surface: The Annotation color swatches (Red, Orange, Yellow, Green, Blue, Purple, Black, White) and the color wheel.
- Setup: State: The Editor with one Annotation selected; Blue chosen. Sample content: the Sample Capture. Appearance: Light. Size: crop to the controls at the top left, about 600 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Annotation color and width](../UserGuide.md#annotation-color)

### annotation-eyedropper

- File: `user-guide/annotation-eyedropper.png`
- Surface: The Eyedropper active over a Capture, about to take a color from a pixel of the Capture.
- Setup: State: The Eyedropper button is on; the pointer is over a coloured part of the sample page. Sample content: the Sample Capture. Appearance: Light. Size: the Editor at its opening size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Annotation color and width](../UserGuide.md#annotation-color)

### annotation-width-presets

- File: `user-guide/annotation-width-presets.png`
- Surface: The width and text size control with its three presets.
- Setup: State: The Rectangle tool active, so the Line presets 3, 5 and 8 pt show; the middle preset chosen. Sample content: the Sample Capture. Appearance: Light. Size: crop to the control, about 300 pt wide. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Annotation color and width](../UserGuide.md#annotation-color)

### export-copy

- File: `user-guide/export-copy.png`
- Surface: Copy in the Editor: the Copy button, and the Capture pasted into a document.
- Setup: State: An Annotated Sample Capture; Copy pressed; then pasted into a plain, empty document. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Copy button and the pasted result side by side. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Export](../UserGuide.md#export)

### export-save

- File: `user-guide/export-save.png`
- Surface: Save in the Editor: the Save button, and the saved file in Finder with its snapit-YYYYMMDD-HHMMSS.png name.
- Setup: State: An Annotated Sample Capture; Save pressed with the Save location set to a tidy folder; the folder open in Finder. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Save button and the Finder window. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Export](../UserGuide.md#export)

### export-drag-out

- File: `user-guide/export-drag-out.png`
- Surface: Drag-out: the thumbnail at the top right of the Editor being dragged toward a Finder folder.
- Setup: State: An Annotated Sample Capture; the thumbnail mid-drag over a tidy Finder window. Sample content: the Sample Capture. Appearance: Light. Size: crop to the thumbnail and the Finder window. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, Export](../UserGuide.md#export)

### permission-guide-folder

- File: `user-guide/permission-guide-folder.png`
- Surface: The folder Permission guide after a Save could not write: System Settings > Privacy & Security > Files & Folders with snapit's switch turned on, and Open System Settings and Try again.
- Setup: State: A Save into a folder macOS refuses (Documents, with access removed beforehand); the Editor stays open behind the guide. Sample content: the Sample Capture. Appearance: Light. Size: the guide at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Save location access](../UserGuide.md#folder-permission)

### menu-reopen-last-capture

- File: `user-guide/menu-reopen-last-capture.png`
- Surface: The snapit menu with Reopen Last Capture highlighted.
- Setup: State: A Last Capture exists (an Editor was closed); the menu is open with the pointer on Reopen Last Capture. Sample content: none beyond what the state needs. Appearance: Light. Size: the menu and its icon, about 480 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [User Guide, The Last Capture](../UserGuide.md#last-capture)

### discard-capture-prompt

- File: `user-guide/discard-capture-prompt.png`
- Surface: The "Discard this Capture?" question with Cancel and Discard.
- Setup: State: An Editor holding an Annotated Capture that is not the Last Capture is being closed. Sample content: the Sample Capture. Appearance: Light. Size: the prompt at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Delete Capture and closing Editors](../UserGuide.md#delete-and-prompts)

### settings-window

- File: `user-guide/settings-window.png`
- Surface: The Settings window, one page: General, Capturing, Editor, Shortcuts, Export, About.
- Setup: State: Settings at its default values, scrolled to the top. Sample content: none beyond what the state needs. Appearance: Light. Size: the window at its own size (tall enough to show every section, or two shots joined). Taken with: snapit's own Window Capture.
- Used by: [User Guide, Settings](../UserGuide.md#settings)

### update-window-newer-release

- File: `user-guide/update-window-newer-release.png`
- Surface: The Update window for a newer release: the new version, its notes, Download, and the Open Anyway and Screen Recording reminder.
- Setup: State: Check for Updates finds a newer release (use a made-up release note of a few lines). Sample content: none beyond what the state needs. Appearance: Light. Size: the window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Check for Updates](../UserGuide.md#updates)

### update-window-up-to-date

- File: `user-guide/update-window-up-to-date.png`
- Surface: The one-line window when snapit is up to date.
- Setup: State: Check for Updates finds no newer release. Sample content: none beyond what the state needs. Appearance: Light. Size: the window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, Check for Updates](../UserGuide.md#updates)

### permission-guide-after-update

- File: `user-guide/permission-guide-after-update.png`
- Surface: The Screen Recording Permission guide after an update: "snapit needs Screen Recording turned back on".
- Setup: State: A newer build whose Screen Recording entry is lost; the guide is on its own. Sample content: none beyond what the state needs. Appearance: Light. Size: the guide window at its own size. Taken with: snapit's own Window Capture.
- Used by: [User Guide, After an update](../UserGuide.md#after-an-update)

## The README shots

The hero is two shots, Light and Dark, and its two markers become one `<picture>` (see "Slot markers and adding a shot"). The demo is a GIF of about 5 MB or less. Every other image is Light.

### hero-light

- File: `readme/hero-light.png`
- Surface: The Editor holding the Sample Capture with an Arrow and a Redaction, on a tidy desktop, with the Area it was taken from still outlined behind it.
- Setup: State: The Editor is open on the Sample Capture with one Arrow at the heading and one Redaction over a made-up reference number. Sample content: the Sample Capture. Appearance: Light. Size: one display's tidy desktop, about 1600 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because the shot holds more than one window.
- Used by: [README, the hero](../../README.md#snapit)

### hero-dark

- File: `readme/hero-dark.png`
- Surface: The same scene as `hero-light`, in the Dark appearance.
- Setup: State: As `hero-light`, retaken with macOS set to Dark, with the same positions. Sample content: the Sample Capture. Appearance: Dark. Size: as `hero-light`. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because the shot holds more than one window.
- Used by: [README, the hero](../../README.md#snapit)

### demo

- File: `readme/demo.gif`
- Surface: An animation: an Area drag, the Action bar, the Editor with an Arrow and a Redaction, then ⌘C.
- Setup: State: The Sample Capture's page is open in a window on a tidy desktop. Drag an Area over the page, press Enter on the Action bar's Capture, draw an Arrow at the heading and a Redaction over the reference number, press ⌘C. Sample content: the Sample Capture. Appearance: Light. Size: cropped to the page and the Editor, about 900 pt wide, 15 seconds at most, and about 5 MB or less. Taken with: the macOS screenshot tool (⇧⌘5, record a selection), converted to a GIF.
- Used by: [README, the top](../../README.md#snapit)

### tour-area

- File: `readme/tour-area.png`
- Surface: The Area overlay: an Area selected over the sample page, with the screen dimmed around it and its handles.
- Setup: State: An Area Capture in progress with an Area selected; the Action bar is not shown yet (drag, hold the mouse down). Sample content: the Sample Capture's page on the display. Appearance: Light. Size: crop to the Area and its surroundings, about 900 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [README, Area, Window and Screen Capture](../../README.md#area-window-and-screen-capture)

### tour-window

- File: `readme/tour-window.png`
- Surface: The Window Capture's outline over one window, with the rest of the screen dimmed.
- Setup: State: A Window Capture in progress; the pointer is over one tidy window. Sample content: an original made-up page in a window (no app name visible). Appearance: Light. Size: one display; crop to the window and its surroundings. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [README, Area, Window and Screen Capture](../../README.md#area-window-and-screen-capture)

### tour-screen

- File: `readme/tour-screen.png`
- Surface: A Screen Capture of a tidy desktop, open in the Editor.
- Setup: State: A Screen Capture of a tidy desktop has just been taken; the Editor is open with no Annotations. Sample content: a tidy desktop with one original made-up window. Appearance: Light. Size: the Editor at its opening size. Taken with: snapit's own Window Capture.
- Used by: [README, Area, Window and Screen Capture](../../README.md#area-window-and-screen-capture)

### tour-action-bar

- File: `readme/tour-action-bar.png`
- Surface: The Action bar beside a selected Area.
- Setup: State: An Area is selected with After selecting an Area set to Show Action bar; the Timer slider at 5. Sample content: the Sample Capture's page behind the Area. Appearance: Light. Size: crop to the Area and its Action bar, about 800 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [README, The Action bar](../../README.md#the-action-bar)

### tour-timed-capture

- File: `readme/tour-timed-capture.png`
- Surface: A Timed Capture counting down: the thin border around the Area and the badge with the seconds left.
- Setup: State: A Timed Capture started with the Timer slider at 5; the countdown shows 3. Sample content: an original made-up page behind the border. Appearance: Light. Size: crop to the Area and the badge. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [README, Timed Capture](../../README.md#timed-capture)

### tour-color-picker

- File: `readme/tour-color-picker.png`
- Surface: The Color picker's loupe outlining one pixel, with its swatch and `#RRGGBB` value.
- Setup: State: The Color picker is open over a flat, saturated area of the sample page. Sample content: an original made-up page with a solid color block. Appearance: Light. Size: crop to the loupe, about 400 pt wide. Taken with: the macOS screenshot tool (⇧⌘5, a selection), because snapit's own Capture would freeze or hide this surface.
- Used by: [README, Color picker](../../README.md#color-picker)

### tour-editor-tools

- File: `readme/tour-editor-tools.png`
- Surface: The Editor with its toolbar of tools and its Annotation colors, on the Sample Capture.
- Setup: State: The Editor open on the Sample Capture, no Annotations, Select tool active. Sample content: the Sample Capture. Appearance: Light. Size: the Editor at its opening size. Taken with: snapit's own Window Capture.
- Used by: [README, Editor tools](../../README.md#editor-tools)

### tour-redaction

- File: `readme/tour-redaction.png`
- Surface: A Redaction over a made-up line of text.
- Setup: State: The Redaction tool; one Redaction over a made-up line of text (a fake reference number). Sample content: the Sample Capture. Appearance: Light. Size: crop to the Capture area of the Editor, about 700 pt wide. Taken with: snapit's own Window Capture.
- Used by: [README, Redaction](../../README.md#redaction)

### tour-export

- File: `readme/tour-export.png`
- Surface: Copy, Save and drag-out: the Editor's top right with Copy, Save and the drag-out thumbnail, beside the saved file in a Finder window.
- Setup: State: An Annotated Sample Capture; Save pressed with the Save location set to a tidy folder, and that folder open in Finder. Sample content: the Sample Capture. Appearance: Light. Size: crop to the Editor's top right and the Finder window. Taken with: snapit's own Window Capture.
- Used by: [README, Copy, Save and drag-out](../../README.md#copy-save-and-drag-out)
