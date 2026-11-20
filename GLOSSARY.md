# snapit

A menu bar app for taking screenshots, marking them up quickly, and getting them out to the clipboard or disk.

## Language

### Capturing

**Capture**:
The act of grabbing screen pixels, and the image that act produces.
_Avoid_: Screenshot (in code and tickets), snap, grab

**Last Capture**:
The most recently taken Capture, kept with its Annotations so the Editor can reopen it after it closes. Taking a new Capture replaces it.
_Avoid_: Recent capture, history, draft

**Capture mode**:
Which part of the screen a Capture takes: **Area**, **Window**, or **Screen**.
_Avoid_: Capture type, region mode

**Area**:
A Capture mode where the user drags a rectangle over any part of the screen.
_Avoid_: Region, selection, rect

**Window**:
A Capture mode that takes exactly one app window.

**Screen**:
A Capture mode that takes one whole display.
_Avoid_: Full screen, fullscreen, display capture

**Action bar**:
The floating bar shown beside a selected Area, offering Capture, **Timed Capture**, the **Color picker**, and Cancel.
_Avoid_: Toolbar, HUD, popover

**Timed Capture**:
A Capture of a chosen Area taken after a countdown, while the rest of the desktop stays usable.
_Avoid_: Delayed capture, self-timer, timer capture

**Color picker**:
A tool that reads the color of a single on-screen pixel so the user can copy its value. Not the same thing as an **Annotation color**.
_Avoid_: Color sampler

### Editing

**Editor**:
The window where a Capture is marked up before Export.
_Avoid_: Preview, canvas window, annotator

**Annotation**:
One mark the user adds to a Capture in the Editor, such as an arrow, rectangle, oval, text, or highlight.
_Avoid_: Shape, drawing, markup

**Annotation color**:
The color an Annotation is drawn in, chosen in the Editor. Not the same thing as the **Color picker**, which reads a pixel off the screen.
_Avoid_: Stroke color, tint

**Eyedropper**:
The Editor control that takes the **Annotation color** from a pixel of the Capture, never from the screen. Not the same thing as the **Color picker**.
_Avoid_: Color picker (for this control)

**Redaction**:
An Annotation that hides the content beneath it by pixelating it, and irreversibly destroys those pixels on Export.
_Avoid_: Censor, mask, obfuscation

### Output

**Export**:
Getting the edited Capture out of snapit, by copying, saving, or dragging.
_Avoid_: Share, output, send

**Save location**:
The folder where a saved Export is written.
_Avoid_: Output folder, destination, save path

### App

**Onboarding**:
The first-run walkthrough that gets the permissions and shortcuts snapit needs in place.
_Avoid_: OOBE, setup wizard, welcome flow

**Permission guide**:
A screen that shows, with a short animation, how to grant one permission snapit needs. It is a step of Onboarding (Screen Recording), and it also appears on its own whenever that permission later goes missing, and, as the folder guide, when a Save cannot write to the **Save location**. Not the same thing as a permission prompt, which is macOS's own dialog.
_Avoid_: Permission screen, permission prompt, setup step

**User Guide**:
The help that ships inside snapit and walks through every flow the user can take.
_Avoid_: Manual, docs, help pages, README

**Shortcut**:
A global key combination that starts a Capture in a given Capture mode.
_Avoid_: Hotkey, keybinding
