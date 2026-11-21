# Releasing

Releases are made by pushing a tag. Tag a commit on `main` that passed CI:

```sh
git tag v1.2.3
git push origin v1.2.3
```

`.github/workflows/release.yml` runs on every `vX.Y.Z` tag, on the hosted `xcode-27` arm64 runner (macOS 27 with Xcode 27). It runs `scripts/package-release.sh`, then publishes with `gh release create`:

1. **Build.** Release configuration, with the bundle version taken from the tag (`1.2.3`) and the build number from the workflow run.
2. **Sign.** Ad-hoc (`codesign --sign -`), the Editor helper first, then the outer app, with the hardened runtime, no `--deep` and no entitlements. There is no certificate and no notarization, which is why people need Open Anyway.
3. **Verify.** `codesign --verify --deep --strict` on the app, the flags and entitlements of both bundles, and `scripts/check-bundle.sh`.
4. **DMG.** `scripts/make-dmg.sh` runs [dmgbuild](https://github.com/dmgbuild/dmgbuild) 2.x, pinned with hashes in `packaging/dmg/requirements.txt` (Dependabot's `pip` entry keeps it current). The window background, with the arrow into Applications and the line "First open: System Settings › Privacy & Security › Open Anyway", is drawn by `packaging/dmg/make-background.swift` on every build; no image is committed.
5. **Check.** `scripts/check-dmg.sh` mounts the DMG, checks its contents, layout and signatures, then detaches it.
6. **SHA-256.** `snapit-X.Y.Z.dmg.sha256` next to the DMG (`shasum -a 256 -c` works on it).
7. **Publish.** A draft GitHub Release with the DMG and the hash attached, then published. The notes (`packaging/release-notes.md`) repeat the Open Anyway and Screen Recording steps and show the hash, followed by GitHub's generated changelog.

A tag with a suffix (`v1.2.3-beta.1`) publishes as a pre-release, so "latest release" never points at it. The bundle version stays `1.2.3`; the DMG is named `snapit-1.2.3-beta.1.dmg`.

To build the same DMG locally (needs the same tools as [building](building.md), plus python3 3.11 or later; dmgbuild is installed into `build/dmg-venv` on the first run):

```sh
scripts/package-release.sh v0.1.0-beta.1   # writes build/release/
```

[manual-checks.md](manual-checks.md) lists what only a person can check on a release, such as installing from the DMG.

The workflow needs no secrets. Turning on "Immutable releases" in the repository settings locks a release's tag and assets once it is published.
