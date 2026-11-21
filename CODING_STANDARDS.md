# Coding standards

Read at review time. These rules are judgement calls a reviewer applies to a diff. Anything a script can check belongs in `scripts/test.sh` instead.

## Engineering priorities

Rank every trade-off: **correctness**, then **safety**, then **stability**, then **performance**. Performance matters and ranks fourth.

snapit stays small, light and fast through ordinary good engineering. Features and UX are built in full and are never shaped to fit a performance number. For each resource the app uses (CPU, memory, GPU, disk, file handles, anything else), ask:

1. **Justified:** does the feature set need it?
2. **Proportionate:** does what snapit's own process holds add up to what the running feature requires?
3. **Released:** does it return to the process's own baseline when the flow ends?
4. **Well chosen:** is the algorithm the best on correctness, then safety, then stability, then performance?

Resource review is a reading of the code against these four questions. Tests cover behaviour and release (clean-up after each flow), measured against the process's own baseline and the feature's own size, with generous margins, and pass the same way on every machine.

## Tests

- **Real input paths.** A test of UI behaviour drives the same path a person does: real or synthetic events through the window, not a direct call to the handler. For example, a first click on a background window is only proven by an event, because AppKit makes the window key before the action runs.
- **Outside behaviour.** Assert on what a user or the OS can observe: files and their pixels, pasteboard contents, processes, windows, the Dock. Never assert on private state.
- **Isolation.** Test mode uses a private pasteboard and temporary folders. The real clipboard, `~/Downloads`, the real Save location and the real cache stay untouched.
- **Clean-up.** Every run removes what it created: files, LaunchServices registrations, defaults domains and permission entries. Reset permission entries (`tccutil`) while the app is still installed, because `tccutil` needs the bundle to resolve its identifier. Only then delete the app.

## Language

- **Vocabulary.** UI copy, code, comments and docs use the terms in `GLOSSARY.md` (Capture, Area, Editor, Annotation, Export, Last Capture, and so on), and avoid the synonyms it lists.
- **Positive statements.** Docs, UI copy and comments describe what snapit does. When a feature or topic is dropped, its mentions are removed outright, with no note that it was dropped and no statement that snapit lacks it.

## Design

- **Hit areas.** Every control is clickable across its whole visible shape.
- **Tooltips.** Every button has a hover tooltip.
- **Look.** Chrome follows the macOS Liquid Glass design language.
