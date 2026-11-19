# snapit

A menu bar app for taking screenshots, marking them up quickly, and getting them out to the clipboard or disk.

## Language

### Capturing

**Capture**:
The act of grabbing screen pixels, and the image that act produces.
_Avoid_: Screenshot (in code and tickets), snap, grab

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

**Color picker**:
A tool that reads the color of a single on-screen pixel so the user can copy its value. Not the same thing as an **Annotation color**.
_Avoid_: Eyedropper, color sampler

### Editing

**Editor**:
The window where a Capture is marked up before Export.
_Avoid_: Preview, canvas window, annotator

**Annotation**:
One mark the user adds to a Capture in the Editor, such as an arrow, rectangle, text, or highlight.
_Avoid_: Shape, drawing, markup

**Annotation color**:
The color an Annotation is drawn in, chosen in the Editor. Not the same thing as the **Color picker**, which reads a pixel off the screen.
_Avoid_: Stroke color, tint, picking a color

**Redaction**:
An Annotation that hides the content beneath it (blur or pixelate) and irreversibly destroys those pixels on Export.
_Avoid_: Censor, mask, obfuscation

### Output

**Export**:
Getting the edited Capture out of snapit, by copying, saving, or dragging.
_Avoid_: Share, output, send

**Save location**:
The folder where a saved Export is written.
_Avoid_: Output folder, destination, save path

**Instant mode**:
A setting where a Capture goes straight to Export without opening the Editor.
_Avoid_: Quick mode, express mode

### App

**Onboarding**:
The first-run walkthrough that gets the permissions and shortcuts snapit needs in place.
_Avoid_: OOBE, setup wizard, welcome flow

**Shortcut**:
A global key combination that starts a Capture in a given Capture mode.
_Avoid_: Hotkey, keybinding
