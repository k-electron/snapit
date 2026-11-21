# Get started

## <a id="overview"></a>Overview <!-- icon: sparkles -->

snapit is a menu bar app for taking a Capture, marking it up and getting it onto the clipboard or into a file. It does nothing, and costs nothing, until you ask it to.

1. Press a Shortcut, or choose an item in the snapit menu, to take a Capture of an [Area](#capture-area), a [Window](#capture-window) or a [Screen](#capture-screen).
2. The [Editor](#editor) opens at once. Mark the Capture up with [tools](#tools).
3. [Export](#export) it: Copy, Save or drag it out.

The most recent Capture stays available as the [Last Capture](#last-capture). snapit goes online only when you choose [Check for Updates…](#updates).

Use the list on the left to move between sections, or the search field above it.

## <a id="install"></a>Install and Open Anyway <!-- icon: square.and.arrow.down -->

snapit comes as one disk image (a DMG) with one app inside.

1. Open the DMG. Its window shows snapit, an arrow and the Applications folder.
2. Drag snapit onto Applications, then eject the DMG.
3. Open snapit from Applications. macOS says it can't verify snapit.
4. Open System Settings › Privacy & Security, click **Open Anyway** and enter your password.
5. Open snapit again. It starts in the menu bar and [Onboarding](#onboarding) opens.

> snapit is not notarized, so macOS blocks it the first time. Every update is a new build and needs **Open Anyway** again. See [After an update](#after-an-update).

You approve snapit once, and you grant the one permission it needs once, to snapit itself: the Editor inside the app is part of snapit.

If you opened snapit straight from the DMG, it offers to [move itself to Applications](#move-to-applications).

## <a id="move-to-applications"></a>Move to Applications <!-- icon: folder -->

snapit checks where it runs from every time it launches.

- **From the DMG.** The window "Move snapit to Applications" explains that Open at Login and updates need snapit in Applications. **Move to Applications** copies it, relaunches it from there and ejects the DMG. **Not Now** keeps running it from where it is.
- **A copy already in Applications.** The window says the snapit already in Applications is replaced.
- **macOS runs it from a temporary location** (a copy in Applications that macOS has moved aside). snapit fixes this in place and relaunches once. You do nothing.

If the move fails, the window stays open and says why. Nothing in Applications changes.

## <a id="onboarding"></a>Onboarding <!-- icon: hand.wave -->

Onboarding opens on the first launch and has six steps. **Continue** and **Back** move between them.

| Step | What you do |
|---|---|
| Welcome | Shows where snapit lives in the menu bar. |
| Screen Recording | Follow the animated [Permission guide](#screen-recording). |
| Save location | Choose the folder a saved Capture goes into. Downloads is the default. |
| Shortcuts | See the default [Shortcuts](#shortcuts) and record others. A flag means macOS uses those keys too. |
| Open at Login | A switch, on by default. See [Open at Login](#launch-at-login). |
| Done | "Try it: press ⌃⌥⌘4", and a link that opens this User Guide. |

Close Onboarding at any step. It comes back at that step the next time snapit launches or you press a Shortcut, and never again once you finish it.

## <a id="screen-recording"></a>Screen Recording <!-- icon: record.circle -->

Screen Recording is the one permission snapit needs, and the only one it asks for in Onboarding. macOS lists it under System Settings › Privacy & Security › Screen Recording.

The Permission guide shows a simplified, animated drawing of that screen with snapit's switch being turned on.

1. macOS shows its own message. Choose **Open System Settings**.
2. Turn snapit on in the Screen Recording list.
3. macOS offers **Quit & Reopen**. Choose it. snapit relaunches and Onboarding resumes where you left off.

Other ways it goes:

- **You chose Later** on the relaunch. Click back into snapit's window: the guide shows a **Relaunch snapit** button. Use it when you are ready.
- **You chose Don't Allow.** macOS won't ask again. The guide switches to the System Settings version of the animation. Its **Open System Settings** button opens Privacy & Security › Screen Recording directly.
- **You press a Capture Shortcut, or choose a Capture in the menu, while Screen Recording is off.** snapit shows the Permission guide instead of failing silently, and takes no Capture.

snapit looks at the permission when its window becomes active, never on a timer.

After an update the permission is lost: see [After an update](#after-an-update). For the occasional notices macOS itself shows, see [periodic notices](#screen-recording-notices).

## <a id="screen-recording-notices"></a>Periodic Screen Recording notices <!-- icon: bell -->

macOS may occasionally ask again whether an app that can record your screen should keep that access, or tell you that an app has accessed your screen. These are macOS's own messages, shown for any app with Screen Recording. snapit can't turn them off.

If macOS asks, keep snapit allowed. If you turned Screen Recording off by mistake, turn snapit back on in System Settings › Privacy & Security › Screen Recording; the next Capture Shortcut shows the [Permission guide](#screen-recording) if it is off.

# Take a Capture

## <a id="menu"></a>The menu bar menu <!-- icon: filemenu.and.selection -->

Click snapit's icon in the menu bar. The menu has, top to bottom:

| Item | What it does |
|---|---|
| Capture Area | Starts an [Area Capture](#capture-area). Shortcut ⌃⌥⌘4. |
| Capture Window | Starts a [Window Capture](#capture-window). Shortcut ⌃⌥⌘5. |
| Capture Screen | Takes a [Screen Capture](#capture-screen). Shortcut ⌃⌥⌘3. |
| Pick Color | Starts the [Color picker](#color-picker). No Shortcut until you record one. |
| Reopen Last Capture | Opens the [Last Capture](#last-capture) in the Editor. Greyed out when there is none. |
| Settings… | Opens [Settings](#settings). ⌘, |
| User Guide | Opens this guide. |
| Check for Updates… | [Asks GitHub](#updates) whether a newer snapit is out. |
| Quit snapit | [Quits](#quitting) snapit. |

The menu shows each Shortcut next to its item, as you have set it.

## <a id="shortcuts"></a>Shortcuts <!-- icon: command -->

A Shortcut is a key combination that starts a Capture from any app.

| Shortcut | Default |
|---|---|
| Area | ⌃⌥⌘4 |
| Window | ⌃⌥⌘5 |
| Screen | ⌃⌥⌘3 |
| Pick Color | none |

To change one, open [Settings](#settings) › Shortcuts, click its recorder and press the keys you want. **Delete** clears it, **Esc** cancels. A change works at once, with no relaunch.

- Recording a combination another snapit Shortcut has removes it from that one.
- A combination macOS also uses carries a flag, "macOS also uses this key combination". It is still accepted.
- Some keys are refused with a beep and a hint, because every app depends on them: ⌘ with a letter or number alone, ⌥ or ⌥⇧ alone, and ⇧ alone.

To use ⌘⇧3, ⌘⇧4 or ⌘⇧5, first [free them from macOS](#free-system-shortcuts).

## <a id="free-system-shortcuts"></a>Free ⌘⇧3, ⌘⇧4 and ⌘⇧5 <!-- icon: keyboard -->

macOS keeps ⌘⇧3, ⌘⇧4 and ⌘⇧5 for its own screenshots. To use them for snapit:

1. In snapit's Settings › Shortcuts, click **Open Keyboard Shortcuts in System Settings…**. System Settings opens on Keyboard.
2. Click **Keyboard Shortcuts…**.
3. Choose **Screenshots** in the sidebar.
4. Turn off the shortcuts that use ⇧⌘3, ⇧⌘4 and ⇧⌘5.
5. Back in snapit's Settings › Shortcuts, record the key combination you want for Area, Window or Screen.

Until you turn them off, macOS uses those keys first, and snapit flags them while you record.

## <a id="capture-area"></a>Area Capture <!-- icon: viewfinder -->

Press ⌃⌥⌘4, or choose Capture Area.

- The screen freezes under a full-screen crosshair, with a loupe next to your pointer to place the Area precisely.
- The window under the pointer is highlighted, and everything outside the Area is dimmed.
- Drag to select an Area. It stays on the display where you started dragging.
- Click a highlighted window to use that window as the Area.
- **Esc** cancels. Nothing is captured.

What happens when you let go depends on Settings › Capturing › After selecting an Area:

- **Show Action bar** (the default) keeps the Area on screen with eight handles and the [Action bar](#action-bar).
- **Capture on release** takes the Capture the moment you let go of the mouse. Clicking a highlighted window captures it straight away.

The Capture is at the display's native pixels and in its color space. The mouse pointer is not in it. The [Editor](#editor) opens right away.

## <a id="capture-window"></a>Window Capture <!-- icon: macwindow -->

Press ⌃⌥⌘5, or choose Capture Window.

1. Move the pointer over a window. It is outlined and the rest of the screen is dimmed.
2. Click it. snapit captures exactly that window, including any part that other windows cover.
3. **Esc** cancels.

There is no crosshair, no loupe and no Action bar. A Window Capture keeps the window's transparent corners and leaves out its shadow.

## <a id="capture-screen"></a>Screen Capture <!-- icon: display -->

Press ⌃⌥⌘3, or choose Capture Screen. snapit captures the whole display under your pointer at once, at its native pixels. The [Editor](#editor) opens.

## <a id="action-bar"></a>The Action bar <!-- icon: slider.horizontal.below.rectangle -->

With After selecting an Area set to Show Action bar, the Action bar floats beside the Area, below it or wherever it fits. It offers:

| Button | What it does |
|---|---|
| Capture | Takes the Capture of the Area (Enter). |
| Timer slider | Chooses 1 to 10 seconds for a [Timed Capture](#timed-capture). |
| Capture in N s | Starts the [Timed Capture](#timed-capture). |
| Pick Color | Opens the [Color picker](#color-picker) (P). |
| Cancel | Ends the Area Capture (Esc). |

Without the buttons:

- **Enter**, or a double-click inside the Area, captures it.
- **Esc** cancels.
- Drag any of the eight **handles** to resize the Area, even past the opposite edge. Drag inside it to move it. Drag outside it to draw a new Area.
- Rest the pointer on a button for its tooltip.

## <a id="timed-capture"></a>Timed Capture <!-- icon: timer -->

A Timed Capture takes a Capture of your Area after a countdown, while the rest of the desktop stays usable. Use it to catch a menu or a tooltip.

1. Choose an Area and set the timer slider (1 to 10 s). snapit remembers the value.
2. Click **Capture in N s**. The overlay goes away and you have your desktop back.
3. A thin border marks the Area and a small badge shows the seconds left with a ✕. Clicks pass through the border to the apps beneath.
4. At zero snapit takes a fresh Capture of the screen as it is at that moment. Its own border and badge are not in it.

To cancel, click the ✕ or press the Area Shortcut again. The Editor opens when the Capture is taken.

## <a id="color-picker"></a>Color picker <!-- icon: eyedropper.halffull -->

The Color picker reads the color of one pixel on your screen and copies its value. It is not the [Eyedropper](#annotation-color), which takes an Annotation color from a Capture.

Open it from the Action bar's **Pick Color** button, the **P** key while the Action bar shows, the menu's Pick Color, or its Shortcut (unassigned until you record one in [Settings](#shortcuts)).

- A large loupe outlines the exact pixel being sampled, with a swatch and its `#RRGGBB` value.
- The **arrow keys** nudge the sampled pixel by one device pixel. Hold ⇧ to move ten.
- **Click** or **Enter** copies the hex value, in upper case, to the clipboard and shows a brief "Copied #…" toast.
- **Esc** returns to the Action bar, or cancels when you opened the picker from the menu or its Shortcut.

# Mark up and export

## <a id="editor"></a>The Editor <!-- icon: pencil.and.scribble -->

The Editor opens straight after every Capture.

- **Left toolbar:** the Annotation [tools](#tools).
- **Top left:** [Annotation color](#annotation-color), the width and text size, and Outline or Solid for Rectangle and Oval.
- **Top right:** Undo, Redo and Delete Annotation, then the drag-out thumbnail, Copy and Save (see [Export](#export)).
- **Far right:** Delete Capture (see [Delete Capture](#delete-and-prompts)).

Every button has a tooltip. snapit remembers your last Annotation color, width and fill.

While an Editor is open, snapit shows in the Dock and in Cmd-Tab. Both go when the last Editor closes. Taking a new Capture while an Editor is open gives you a second Editor, so you can work on several Captures.

## <a id="tools"></a>Tools <!-- icon: wrench.and.screwdriver -->

Pick a tool on the left toolbar, or press its key.

| Tool | Key | What it does |
|---|---|---|
| Select | V | Click an Annotation to select it, drag to move it, drag a handle to resize it. |
| Arrow | A | Drag from the tail to the point. |
| Rectangle | R | Drag a box. Outline or Solid fill. |
| Oval | O | Drag an oval. Outline or Solid fill. |
| Text | T | Click where the text starts and type. Click away, or press Esc, to finish. Click a Text to edit it. |
| Highlighter | H | Drag a translucent marker stroke. |
| Redaction | X | Drag a box. It pixelates what lies beneath it in bold blocks. |
| Crop | C | Drag a crop rectangle, adjust its handles, then press Enter or **Apply Crop**. Esc cancels. |

- **Redaction** is what you see is what you get: the preview is the same pixelate the Export uses. On Export the pixels beneath it are destroyed for good, so the hidden content can't be recovered from the file.
- **Crop** fixes a loose Area. It is one Undo step.
- While you type a Text, tool keys and ⌫ are typing, and ⌘Z takes the typing back first.

## <a id="annotation-color"></a>Annotation color and width <!-- icon: paintpalette -->

- **Swatches:** Red, Orange, Yellow, Green, Blue, Purple, Black and White. A click sets the color of the selected Annotation and of the ones you draw next.
- **Eyedropper:** takes the Annotation color from a pixel of the Capture, never from the screen. Click its button, then click in the Capture. Esc, or another tool, ends it.
- **Color wheel:** opens the macOS color panel, to choose any color.
- **Width and text size:** three presets in one control. Lines (Arrow, Rectangle and Oval outlines) are 3, 5 or 8 pt, the Highlighter is 14, 22 or 34 pt, and Text is 14, 20 or 32 pt.
- **Outline or Solid:** for Rectangle and Oval, a box to frame something or a fill to block it out.

Every button's whole area is clickable, and the Editor accepts the first click on any control even when it is a background window, except Delete Capture (see [Delete Capture](#delete-and-prompts)).

## <a id="undo-and-keys"></a>Undo, Redo and keys <!-- icon: arrow.uturn.backward -->

| Key | What it does |
|---|---|
| ⌘Z | Undo |
| ⇧⌘Z | Redo |
| ⌫ | Delete Annotation: removes the selected Annotation. The tooltip says "Delete Annotation (⌫)". |
| ⌘C | Copy |
| ⌘S | Save |
| Esc | Finishes a Text being typed, ends the Eyedropper, cancels a Crop, and otherwise closes the Editor. |
| V A R O T H X C | Select, Arrow, Rectangle, Oval, Text, Highlighter, Redaction, Crop |

Undo and Redo also have buttons at the top right.

## <a id="export"></a>Export <!-- icon: square.and.arrow.up -->

Exporting gets the edited Capture out of snapit. The order is crop, Redactions, Annotations, then the PNG.

- **Copy (⌘C)** puts a PNG on the clipboard. Paste it anywhere.
- **Save (⌘S)** writes a PNG into your Save location with no dialog. Choose the folder in [Settings](#settings) › General. Files are named `snapit-YYYYMMDD-HHMMSS.png` from the time of the Capture, for example `snapit-20261119-155058.png`. A clash adds `-2`, `-3` and so on.
- **Drag-out:** drag the thumbnail at the top right into Finder or another app. The file has the same name a Save would give it.

Exports are at the display's native pixels, tagged at 144 dpi on a Retina display. To share smaller images, turn on **Export at standard resolution (1x)** in Settings › Export.

By default the Editor closes after Copy and after Save. Turn either off with **Close the Editor after Copy** and **Close the Editor after Save** in Settings › Editor. PNG is the only format.

If a Save can't write into the Save location, the Editor stays open and shows the [folder Permission guide](#folder-permission).

## <a id="folder-permission"></a>Save location access <!-- icon: lock.folder -->

If a Save fails because of folder access, the Editor stays open, so nothing is lost, and the **folder Permission guide** opens.

- **macOS is refusing access** (for example to Desktop, Documents or Downloads): the guide shows System Settings › Privacy & Security › Files & Folders with snapit's switch turned on. **Open System Settings** opens it. Turn the switch on, then choose **Try again**.
- **The folder can't be written to** (read-only, missing, an unplugged drive or a full disk): the guide says why, and does not offer Open System Settings.
- **Choose another folder** picks a new Save location and saves there at once.
- If a Save fails after the Editor was handed the Capture and closed, a window says "Your Capture was not saved" and offers **Choose another folder**.

## <a id="last-capture"></a>The Last Capture <!-- icon: clock.arrow.circlepath -->

snapit keeps your most recent Capture, with its Annotations, crop and Undo history, as the **Last Capture**.

- Closing its Editor never loses it, and closing it never asks a question.
- Choose **Reopen Last Capture** in the menu to bring it back where you left off. The item is greyed out when there is no Last Capture. If the stored Capture is damaged, snapit says "That Capture couldn't be reopened."
- A new Capture replaces the Last Capture. snapit keeps only one.
- **Quitting snapit removes it.**

## <a id="delete-and-prompts"></a>Delete Capture and closing Editors <!-- icon: trash -->

- **Delete Capture** (the far right button) closes that Editor and removes the Capture immediately, with no confirmation.
- When an Editor is in the background, the **first click** on Delete Capture only brings it forward, so you never delete by accident. Click it again to delete.
- Closing an Editor whose Capture is **not** the Last Capture, and has edits you never Exported, asks once: "Discard this Capture?" **Cancel** (Esc) keeps it, **Discard** (⌘D) closes it. Copying, saving or dragging out counts as Exporting.
- With such an Editor open, quitting brings it forward first and asks "Quit snapit?". **Discard and Quit** quits.

# snapit itself

## <a id="settings"></a>Settings <!-- icon: gearshape -->

Open Settings from the menu (⌘,). It is one scrolling page.

| Section | What it holds |
|---|---|
| General | **Open at Login**, and the **Save location** with **Choose…**. |
| Capturing | **After selecting an Area:** Show Action bar (the default) or Capture on release. |
| Editor | **Close the Editor after Copy** and **Close the Editor after Save**, both on by default. |
| Shortcuts | Recorders for Area, Window, Screen and Pick Color, and a button that opens macOS's Keyboard settings. See [Shortcuts](#shortcuts). |
| Export | **Export at standard resolution (1x)**, off by default. |
| About | The version, and **Check for Updates…**. |

Changes take effect at once. The Save location starts as `~/Downloads`.

## <a id="launch-at-login"></a>Open at Login <!-- icon: power -->

**Open at Login** in Settings › General starts snapit when you log in. It is on by default for a copy that runs from Applications, and Onboarding offers it as a switch. From a build folder or the DMG, snapit registers nothing.

If macOS needs your approval first, Settings says so and offers **Open Login Items**. Turning the switch off removes snapit from your login items, and it stays off across relaunches. It also survives updates.

## <a id="updates"></a>Check for Updates <!-- icon: arrow.triangle.2.circlepath -->

snapit contacts GitHub only when you click **Check for Updates…**, in the menu or in Settings › About. It makes no other network calls.

- **A newer release:** the window shows the new version, its notes and a **Download** button that opens the release page in your browser.
- **Up to date, or GitHub can't be reached:** the window gives one line.

Every release is on [GitHub](https://github.com/k-electron/snapit/releases).

To update, download the new DMG, quit snapit, drag the new snapit onto Applications and replace the old one. Then see [After an update](#after-an-update).

## <a id="after-an-update"></a>After an update <!-- icon: exclamationmark.arrow.triangle.2.circlepath -->

Every update is a new build, so macOS treats it as a new app twice:

1. **Open Anyway again.** Open the new snapit, then System Settings › Privacy & Security › **Open Anyway**.
2. **Screen Recording again.** snapit shows only the Screen Recording [Permission guide](#screen-recording), "snapit needs Screen Recording turned back on". It clears its own old entry and asks macOS afresh, so you turn on the new entry and choose **Quit & Reopen**.

If snapit could not clear its old entry, the guide says so and tells you to select snapit in the Screen Recording list, press − to remove it, choose **Relaunch snapit** and allow Screen Recording when macOS asks.

## <a id="quitting"></a>Quitting <!-- icon: xmark.circle -->

- **Quit snapit** in the menu quits everything. With an Editor holding edits you never Exported, snapit brings it forward and asks first.
- Closing the last window (an Editor, Settings or this guide) does not quit snapit. It leaves snapit in the menu bar and the Dock icon goes.
- Quitting removes the [Last Capture](#last-capture).
- With Open at Login on, snapit starts again at your next login.
