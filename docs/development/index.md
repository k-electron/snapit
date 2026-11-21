# Developing snapit

The starting point for contributors. The vocabulary (Capture, Editor, Annotation, Export and so on) is in [GLOSSARY.md](../../GLOSSARY.md), the rules reviews apply are in [CODING_STANDARDS.md](../../CODING_STANDARDS.md), and the Markdown in this repo is checked by `scripts/check-docs.sh`.

## The docs

- [Architecture](architecture.md): the repo's layout, so you can find code by feature.
- [Building](building.md): the toolchain, the build command and regenerating the C header.
- [Testing](testing.md): `scripts/test.sh` and its stages, the scripted whole-app run, test mode, and how to add a flow, a fixture, a test-mode command or an engine test.
- [Releasing](releasing.md): the tag-to-DMG pipeline and the local packaging command.
- [Manual checks](manual-checks.md): what only a person can check, such as installing from the DMG.
- [Research](../research): the notes behind the v1 decisions: [the menu bar shell](../research/menu-bar-shell.md), [the repo, CI and release pipeline](../research/repo-ci-release.md), [ScreenCaptureKit](../research/screencapturekit.md) and [the Swift and Rust bridge](../research/swift-rust-bridge.md).

## Specs and research issues

Specs live in GitHub Issues.

- [snapit v1 spec (#13)](https://github.com/k-electron/snapit/issues/13), written from [the map (#1)](https://github.com/k-electron/snapit/issues/1) and its research issues:
  - [#2](https://github.com/k-electron/snapit/issues/2) how Swift calls the Rust engine, and how both ship in one app
  - [#3](https://github.com/k-electron/snapit/issues/3) ScreenCaptureKit on macOS 26 for Area, Window and Screen Captures
  - [#4](https://github.com/k-electron/snapit/issues/4) a menu bar app with zero idle CPU and low memory
  - [#5](https://github.com/k-electron/snapit/issues/5) the repo, CI and DMG release pipeline
  - [#6](https://github.com/k-electron/snapit/issues/6) what the Rust engine owns, and whether it beats the native frameworks
  - [#7](https://github.com/k-electron/snapit/issues/7) the Area overlay and Color picker
  - [#8](https://github.com/k-electron/snapit/issues/8) the Editor
  - [#9](https://github.com/k-electron/snapit/issues/9) Onboarding and the default Shortcuts
  - [#10](https://github.com/k-electron/snapit/issues/10) Settings and Export
  - [#12](https://github.com/k-electron/snapit/issues/12) launch at login for ad-hoc-signed builds

New specs come from `/to-spec`. Decision records come from `/domain-modeling`, which creates `docs/adr/` when the first one is written.
