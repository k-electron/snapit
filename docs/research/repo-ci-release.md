# Repo layout, CI and DMG release pipeline

Research for [#5](https://github.com/k-electron/snapit/issues/5), part of the v1 map [#1](https://github.com/k-electron/snapit/issues/1). Sources checked on 2026-11-19. The Swift↔Rust bridge itself (C ABI + cbindgen, one `staticlib`, linked by an Xcode Run Script phase) comes from [#2](https://github.com/k-electron/snapit/issues/2) on branch `research/swift-rust-bridge`. This doc gives that bridge a home in the repo and a pipeline around it.

## Question

What repo layout, build and release pipeline should snapit use? Cover: Xcode project vs SwiftPM-first layout next to a Cargo workspace; GitHub Actions on macOS 26 / Apple Silicon runners; Google OSV-Scanner and Dependabot for both Cargo and Swift; ad-hoc code signing for an app that is not notarized; reputable open-source tooling to build a DMG with an install-instructions window; and versioning and tagging that drive GitHub Releases.

## Answer

**Commit one Xcode project, using buildable folders, at the repo root. Put a root Cargo virtual workspace next to it, with the engine in `engine/`. Pin the Rust toolchain in `rust-toolchain.toml`. CI runs on GitHub's `macos-26` arm64 image, plus OSV-Scanner on Ubuntu. Dependabot covers `cargo`, `swift` (it now reads `Package.resolved` inside `.xcodeproj`), `rust-toolchain`, `github-actions` and `pip`. Releases trigger on a pushed `vX.Y.Z` tag. The workflow builds with `CODE_SIGN_IDENTITY=-` (ad-hoc), packages the app with dmgbuild 2.x (no Finder, already moved off the deprecated `hdiutil`), and publishes with `gh release create` as a draft. The draft goes live only once the DMG and its SHA-256 are attached.**

The biggest finding is not about tooling. **Ad-hoc signing ties macOS privacy grants to one exact build.** Each update would make users grant Screen Recording again (see [Signing](#ad-hoc-signing-for-an-app-that-is-not-notarized)). A stable self-signed certificate probably fixes that at no cost, but a prototype has to confirm it before the spec locks.

## 1. Xcode project vs SwiftPM-first

- **SwiftPM can't produce the app.** A package product is a library, an executable or a plugin ([PackageDescription `Product`](https://developer.apple.com/documentation/packagedescription/product)). A menu bar `.app` with an Info.plist, entitlements and an asset catalog needs an Xcode app target.
- **Merge noise is no longer the reason to avoid a committed `.xcodeproj`.** Since Xcode 16, *buildable folders* "only record the folder path into the project file without enumerating the contained files", which "minimizes diffs … and avoids source control conflicts" ([Xcode 16 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes)). That removes the main argument for a project generator.
- **Dependabot can now read Xcode-managed packages.** As of 2026-03-31, "Dependabot can now detect and update Swift package dependencies in Xcode projects" that use `.xcodeproj` bundles, even without a `Package.swift`. It discovers `Package.resolved` in `.xcodeproj` and `.xcworkspace` layouts and reads version rules from `project.pbxproj` ([GitHub changelog](https://github.blog/changelog/2026-03-31-dependabot-now-supports-xcode-projects-using-swiftpm-with-xcodeproj-manifests)). Xcode keeps that file at `snapit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, and Apple says to commit it ([Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)).
- **Generators would hide that file.** XcodeGen (MIT, active, release 2.47.0 on 2026-11-17, [repo](https://github.com/yonaskolb/XcodeGen)) and Tuist ([repo](https://github.com/tuist/tuist)) are healthy. But a generated `.xcodeproj` is usually not committed, so Dependabot and OSV-Scanner would have no `Package.resolved` to read. Not recommended.
- **Local packages are optional.** Apple supports splitting code into local Swift packages that live inside the project ([Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)). Use one only if a module needs `swift test` on its own. Don't name its folder `Packages/`: the repo's current `.gitignore` ignores `Packages/`.

**Decision: an Xcode-project-first layout with a committed `.xcodeproj` that uses buildable folders. No `Package.swift` and no generator.**

### Rust next to it

- `aarch64-apple-darwin` is Tier 1. rustc honours `MACOSX_DEPLOYMENT_TARGET`, so set it to `26.0` to match the app ([rustc apple-darwin](https://doc.rust-lang.org/rustc/platform-support/apple-darwin.html)).
- Per [#2](https://github.com/k-electron/snapit/issues/2), one `staticlib` is linked by a Run Script phase that runs `cargo build`. The phase must declare its inputs and outputs. Xcode otherwise "runs your script every time" ([Running custom scripts during a build](https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build)). With `ENABLE_USER_SCRIPT_SANDBOXING` on, the build system sandboxes scripts "to disallow undeclared input/output dependencies" ([Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)). Declare the outputs, or turn the setting off for that target.
- Pin the toolchain in `rust-toolchain.toml`. Dependabot's `rust-toolchain` ecosystem bumps `channel = "1.xx"` values ([Dependabot ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories)). The runner image already has rustup 1.29.2 and Rust 1.99.1 ([macos-26 arm64 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)), so rustup only has to fetch the pinned version.
- Put a virtual workspace (`Cargo.toml` + `Cargo.lock`) at the repo root with `members = ["engine"]`. Then `cargo fmt/clippy/test` run from the root, a second crate can be added later, and Dependabot and OSV-Scanner find one lockfile at `/`. Add `/target/` to `.gitignore`; today it lists only `build/`, `.build/` and `DerivedData/`.

## 2. GitHub Actions runners

- **Runner labels.** `macos-26` (alias `macos-latest`, also `macos-26-xlarge`) is **macOS 26 on arm64**. `macos-26-intel` / `-large` are x64, so avoid them. A separate **`xcode-27` preview image** (arm64) exists ([runner-images README](https://github.com/actions/runner-images)). Since 2026-09-16 that preview runs on macOS 27 ([runner-images#14404](https://github.com/actions/runner-images/issues/14404)).
- **Xcode on `macos-26`.** The default is Xcode 26.6 (build 17F113), with 26.0.1 to 26.5 also installed. The newest SDK is `macosx26.5` ([image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)). The `xcode-27` image ships 27.0, 27.1 (default) and 27.2 with the `macosx27.2` SDK ([xcode-27 readme](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)). Pin one explicitly with `sudo xcode-select -s /Applications/Xcode_XX.app`.
- **Image churn.** GitHub keeps "at most 2 GA images and 1 beta" at a time, and `-latest` labels move over 1–2 months. macOS 14 images were retired on 2026-11-02 ([README](https://github.com/actions/runner-images)). Use the explicit `macos-26` / `xcode-27` labels rather than `macos-latest`.
- **Cost while the repo is private.** Standard runners are free for public repos. Private repos get $12 of included compute a month, and macOS costs **$0.062/min** against Linux's $0.006 ([Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)). That is roughly 190 macOS minutes a month (my arithmetic). Until the repo goes public, run the macOS job only on PRs to `main` and on tags, use `concurrency` with `cancel-in-progress`, and keep OSV-Scanner on Ubuntu, which its reusable workflow already defaults to (`runs-on: ubuntu-latest`, [osv-scanner-reusable.yml](https://github.com/google/osv-scanner-action/blob/main/.github/workflows/osv-scanner-reusable.yml)).
- **Pinning actions.** GitHub recommends pinning to a full commit SHA. It also describes a newer workflow lockfile (`.github/workflows/actions.lock`, generated by the `gh actions-lock` extension) as "the strongest protection available" ([Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use), [Workflow dependency lockfiles](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles)). The docs give no availability or plan details for the lockfile, so start with SHA pins kept fresh by Dependabot's `github-actions` ecosystem.

## 3. Dependabot and OSV-Scanner

### Dependabot

| Ecosystem | `package-ecosystem` | Version updates | Security updates | Private repo |
|---|---|---|---|---|
| Rust crates | `cargo` | yes | yes | yes |
| Swift packages (incl. `.xcodeproj`) | `swift` (v5, v6) | yes | yes | yes, git registries only |
| Rust toolchain | `rust-toolchain` | yes | — | — |
| Workflow actions | `github-actions` | yes | yes | yes |
| dmgbuild pin | `pip` | yes | yes | yes |

Source: [Dependabot supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories). Swift notes from that page: "Non-declarative manifests are not supported", and "Swift registries are not supported" (only git).

- Use `groups` to batch PRs. A default 3-day `cooldown` applies to version updates (not security updates), and `cargo` and `swift` also accept per-semver cooldowns ([options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference)).
- **Repo setting needed.** Dependabot *alerts* and security updates must be enabled by an admin ([About Dependabot alerts](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts)). On 2026-11-19, `GET /repos/k-electron/snapit/vulnerability-alerts` returned 404, so they are off. `dependabot.yml` version updates work without that setting.

### OSV-Scanner

- **Health.** [google/osv-scanner](https://github.com/google/osv-scanner) is Apache-2.0 with about 11.5k stars. It ships monthly releases (v2.5.0 on 2026-08-07 through v2.7.1 on 2026-11-09), and the action tracks them (v2.7.1, 2026-11-11, [google/osv-scanner-action](https://github.com/google/osv-scanner-action)).
- **Cargo.** `Cargo.lock` is supported ([supported lockfiles](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/)).
- **Swift.** The docs table doesn't list Swift yet. But v2.4.0 (2026-06-18) "Enable[d] the `swift/packageresolved` plugin by default to support SwiftURL vulnerability scans" ([v2.4.0 release notes](https://github.com/google/osv-scanner/releases/tag/v2.4.0)). The plugin matches any file named `Package.resolved` ([osv-scalibr extractor](https://pkg.go.dev/github.com/google/osv-scalibr/extractor/filesystem/language/swift/packageresolved)), so the default `--recursive ./` scan should reach the one inside `snapit.xcodeproj/`. Confirm that on the first real run.
- **Wiring.** Use the two reusable workflows, `osv-scanner-reusable.yml` (scheduled + push) and `osv-scanner-reusable-pr.yml` (fails only on *new* vulnerabilities). Both need `actions: read`, `security-events: write`, `contents: read`. Inputs: `scan-args`, `upload-sarif`, `fail-on-vuln` ([OSV-Scanner GitHub Action docs](https://google.github.io/osv-scanner/github-action/)).
- **Private-repo catch.** SARIF upload goes to Code Scanning. "For private and internal repositories, code scanning is available when GitHub Code Security features are enabled" ([Uploading a SARIF file](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)). **Set `upload-sarif: false` while private** and read results from the job log. Flip it to `true` when the repo goes public.
- OSV.dev imports the RustSec Advisory Database and covers both crates.io and SwiftURL ([OSV.dev data sources](https://google.github.io/osv.dev/data/)), so a separate `cargo audit` isn't needed. [cargo-deny](https://github.com/EmbarkStudios/cargo-deny) (Apache-2.0, release 0.21.0 on 2026-11-16) is an optional extra for enforcing an MIT-compatible **licence** allowlist on crates. That is a different job from vulnerability scanning.

## 4. Ad-hoc signing for an app that is not notarized

- **Signing is mandatory, identity is not.** On Apple silicon "any executable must be signed before it's allowed to run … a simple ad-hoc signature is sufficient." The linker signs automatically, and tools that modify a binary after linking (`strip`, `install_name_tool`) need a re-sign. "Binaries signed this way cannot pass through Gatekeeper" ([macOS 11 Universal Apps release notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes)).
- **How.** `codesign -s -` performs ad-hoc signing, which "does not use an identity at all, and identifies exactly one instance of code" (`man 1 codesign`, macOS 27.2). In Xcode this is *Sign to Run Locally* (`CODE_SIGN_IDENTITY = "-"`) ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)). Sign inside-out and never use `--deep` when signing ([Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)). With the engine linked statically (#2) there is a single Mach-O, so the app needs one `codesign` call. Verify with `codesign --verify --strict`.
- **What users do.** Since macOS Sequoia, "users will no longer be able to Control-click to override" Gatekeeper. They go to System Settings › Privacy & Security instead ([Apple Developer news, 2024-08-06](https://developer.apple.com/news/?id=saqachfa)). The steps are Privacy & Security › Security › **Open** › **Open Anyway** › password. The button "is available for about an hour after you try to open the app" ([Apple Support: Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)).
- **⚠️ Privacy grants do not survive updates with ad-hoc signing.** macOS records an app's *designated requirement* (DR) when the user grants a privacy permission, and checks each later version against it. "Ad hoc signed code … has a DR but it's tied to that specific version of the code … macOS can't track this authorization across versions of your app" ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)). For snapit, **every release would make users grant Screen Recording again.**
  - **Likely fix: a stable self-signed code-signing certificate.** It's free, kept as a CI secret, and signs with an explicit DR such as `designated => identifier "<bundle id>" and certificate leaf = H"<sha1>"`. The requirement language supports hash pins on the leaf certificate, and for self-signed code "the leaf and root refer to the same single certificate". Ad-hoc code, by contrast, has "no certificates at all" ([Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)). Gatekeeper still blocks the app because it isn't notarized, so the "Open Anyway" flow is the same. **Unverified:** whether the Screen Recording grant then persists across builds. Prototype before locking.

## 5. DMG with an install-instructions window

`hdiutil` is on its way out. On macOS 27 its man page carries a deprecation notice: "diskutil image is the preferred interface. New features and formats (e.g. ASIF) are available exclusively through diskutil image" (`man hdiutil`, macOS 27.2). That rules out tools that drive `hdiutil` or Finder.

| Tool | Licence | Health (2026-11-19) | Custom background / layout | Headless CI | Notes |
|---|---|---|---|---|---|
| **[dmgbuild](https://github.com/dmgbuild/dmgbuild)** | MIT | v2.0.0 on 2026-11-16; CI on `macos-15`, `macos-26`, `xcode-27` | Yes: `background` image, `icon_locations`, `window_rect`, `icon_size`, `symlinks` for `/Applications` ([settings](https://dmgbuild.readthedocs.io/en/latest/settings/)) | Yes: writes `.DS_Store` itself "without relying on Finder" ([README](https://github.com/dmgbuild/dmgbuild)) | 2.0 replaced `hdiutil` with `diskutil` and defaults to `ULFO`. Needs macOS 14+ ([v2.0.0 notes](https://github.com/dmgbuild/dmgbuild/releases/tag/v2.0.0)) |
| [create-dmg/create-dmg](https://github.com/create-dmg/create-dmg) (shell) | MIT | v1.3.0 on 2026-07-02, 47 open issues | Yes, via Finder AppleScript | Only with `--skip-jenkins`, which skips the "Finder-prettifying AppleScript", i.e. the layout ([README](https://github.com/create-dmg/create-dmg)) | Built on `hdiutil` |
| [sindresorhus/create-dmg](https://github.com/sindresorhus/create-dmg) (Node) | MIT | v8.1.0 on 2026-03-21 | **No** custom background: fixed design, options cover only title, signing and filename ([README](https://github.com/sindresorhus/create-dmg)) | Yes | Depends on `appdmg` ([node-appdmg](https://github.com/LinusU/node-appdmg)), whose last release was 2023-02-03 |

**Decision: dmgbuild 2.x**, pinned in `packaging/dmg/requirements.txt` with `--require-hashes` so Dependabot `pip` and OSV-Scanner both cover it. The "install-instructions window" is the DMG's Finder window. Its background image shows the app icon → arrow → Applications, plus a short caption on first launch: *"macOS will say it can't verify snapit. Open System Settings › Privacy & Security and click Open Anyway."* Build the background as a Retina-ready multi-resolution TIFF with `tiffutil -cathidpicheck bg.png bg@2x.png -out bg.tiff` (`man tiffutil`). Repeat the same three steps in the release notes and README. Gatekeeper blocks the app before any of its own UI can run, so Onboarding (#9) can't carry this message.

## 6. Versioning, tagging and GitHub Releases

- **Version format.** `CFBundleShortVersionString` must be "three period-separated integers" (`Major.Minor.Patch`, digits and periods only) ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring)). `CFBundleVersion` takes one to three integers ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)). Use SemVer tags `vX.Y.Z`. CI derives `MARKETING_VERSION=X.Y.Z` from the tag and `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`. A pre-release tag such as `v1.0.0-beta.1` keeps the bundle version at `1.0.0` and is published with `--prerelease`.
- **Publishing.** Use `gh release create "$TAG" --draft --verify-tag --generate-notes snapit-X.Y.Z.dmg SHA256SUMS.txt`, with `--prerelease` when the tag has a `-` suffix ([gh manual](https://cli.github.com/manual/gh_release_create)). The GitHub CLI is preinstalled on the runner (2.103.3, [image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)), so no third-party release action is needed. The job needs `permissions: contents: write`.
- **Immutable releases.** Turn on the repo setting. A published release then locks its tag and assets, and an attestation is generated automatically. GitHub recommends "create the release as a draft, attach all assets, publish" ([Immutable releases](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases)). Optional once public: `actions/attest@v4` build provenance, which users check with `gh attestation verify` ([Using artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)).
- **"Check for Updates".** `GET /repos/{owner}/{repo}/releases/latest` returns "the most recent non-prerelease, non-draft release", so pre-releases never reach users ([REST: releases](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)). Unauthenticated calls are limited to 60/hour per IP ([REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)), which is plenty for a manual menu item. The endpoint only works without a token once the repo is public, and the first release makes it public anyway.

## Recommended layout

```
snapit/
├── LICENSE                         # MIT
├── README.md                       # install + "Open Anyway" steps
├── GLOSSARY.md
├── Cargo.toml                      # virtual workspace: members = ["engine"]
├── Cargo.lock                      # committed (app, not library)
├── rust-toolchain.toml             # channel = "1.xx", targets = ["aarch64-apple-darwin"]
├── engine/                         # Rust engine crate (staticlib + rlib)
│   ├── Cargo.toml
│   ├── cbindgen.toml
│   ├── include/snapit_engine.h     # generated, committed; CI fails on drift (#2)
│   ├── include/module.modulemap
│   └── src/
├── snapit.xcodeproj/               # committed; buildable folders
│   └── project.xcworkspace/xcshareddata/swiftpm/Package.resolved   # committed
├── snapit/                         # app target (buildable folder): Swift/SwiftUI, Assets, Info.plist, entitlements
├── snapitTests/
├── scripts/
│   ├── build-engine.sh             # called by the Xcode Run Script phase and CI
│   └── make-dmg.sh                 # dmgbuild wrapper
├── packaging/dmg/
│   ├── settings.py                 # dmgbuild settings
│   ├── background.tiff             # 1x+2x, includes the Open Anyway caption
│   └── requirements.txt            # dmgbuild==2.x with hashes
├── docs/{adr,research,agents}/
└── .github/
    ├── dependabot.yml
    └── workflows/
        ├── ci.yml                  # PR + main: Rust + Xcode build/test
        ├── osv-scanner.yml         # schedule + push + PR (reusable workflows)
        └── release.yml             # on tag v*.*.*
```

## Pipeline sketch

Illustrative only. Pin every `uses:` to a full SHA in the real files.

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: cargo
    directory: "/"
    schedule: { interval: weekly }
    groups: { rust: { patterns: ["*"] } }
  - package-ecosystem: swift
    directory: "/"                     # finds Package.resolved inside snapit.xcodeproj (verify)
    schedule: { interval: weekly }
  - package-ecosystem: rust-toolchain
    directory: "/"
    schedule: { interval: weekly }
  - package-ecosystem: github-actions
    directory: "/"
    schedule: { interval: weekly }
    groups: { actions: { patterns: ["*"] } }
  - package-ecosystem: pip
    directory: "/packaging/dmg"
    schedule: { interval: monthly }
```

```yaml
# .github/workflows/ci.yml
on:
  pull_request: { branches: [main] }
  push: { branches: [main] }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
permissions: { contents: read }
jobs:
  rust:                               # cheap: Linux runner for fmt/clippy/test of pure-Rust code
    runs-on: ubuntu-latest
    steps: [checkout, "cargo fmt --check", "cargo clippy -- -D warnings", "cargo test",
            "regenerate cbindgen header; git diff --exit-code"]
  app:
    runs-on: macos-26                 # arm64; or xcode-27 once GA (open question)
    env: { MACOSX_DEPLOYMENT_TARGET: "26.0" }
    steps: [checkout, "sudo xcode-select -s /Applications/Xcode_26.6.app",
            "xcodebuild -project snapit.xcodeproj -scheme snapit -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- test"]
```

```yaml
# .github/workflows/osv-scanner.yml
on:
  schedule: [{ cron: "30 12 * * 1" }]
  push: { branches: [main] }
  pull_request: { branches: [main] }
permissions: { actions: read, security-events: write, contents: read }
jobs:
  scan-scheduled:
    if: github.event_name != 'pull_request'
    uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@<sha> # v2.7.1
    with: { upload-sarif: false }     # true once the repo is public
  scan-pr:
    if: github.event_name == 'pull_request'
    uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable-pr.yml@<sha> # v2.7.1
    with: { upload-sarif: false }
```

```yaml
# .github/workflows/release.yml
on: { push: { tags: ["v*.*.*"] } }
permissions: { contents: write }
jobs:
  osv-gate:                           # refuse to ship with known vulns
    uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@<sha>
    with: { upload-sarif: false, fail-on-vuln: true }
    permissions: { actions: read, security-events: write, contents: read }
  build:
    needs: osv-gate
    runs-on: macos-26
    steps:
      - checkout
      - VERSION=${GITHUB_REF_NAME#v}; MARKETING=${VERSION%%-*}
      - xcodebuild -project snapit.xcodeproj -scheme snapit -configuration Release
          MARKETING_VERSION=$MARKETING CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER
          CODE_SIGN_IDENTITY=-   # or the self-signed identity, see open question
          -derivedDataPath build build
      - codesign --verify --strict --verbose=2 build/.../snapit.app
      - check Info.plist CFBundleShortVersionString == $MARKETING
      - pip install --require-hashes -r packaging/dmg/requirements.txt
      - dmgbuild -s packaging/dmg/settings.py -D app=build/.../snapit.app "snapit" "snapit-$VERSION.dmg"
      - shasum -a 256 snapit-$VERSION.dmg > SHA256SUMS.txt
      - gh release create "$GITHUB_REF_NAME" --draft --verify-tag --generate-notes
          $( [[ $VERSION == *-* ]] && echo --prerelease ) snapit-$VERSION.dmg SHA256SUMS.txt
      - gh release edit "$GITHUB_REF_NAME" --draft=false   # immutable from here
```

## Open questions surfaced

1. **Ad-hoc vs self-signed identity.** With ad-hoc signing, every update re-prompts for Screen Recording (TN3127). Prototype a self-signed certificate with an explicit DR and confirm the TCC grant survives a rebuild. Also decide where its private key lives (a GitHub Actions secret, imported into a temporary keychain). This affects Onboarding (#9) and Capture (#3).
2. **`macos-26` (GA, Xcode 26.6) vs `xcode-27` (preview, Xcode 27.x on macOS 27).** "Latest Swift and SwiftUI standards" pulls towards Xcode 27, but that image is still a preview with possible queueing. CI should match the Xcode the developer uses locally.
3. **How the DMG window looks.** The background artwork and caption wording are already listed under "Not yet specified" on the map. This doc only fixes the mechanism.
4. **Verify on first run.** Check that Dependabot `swift` with `directory: "/"` and OSV-Scanner's recursive scan both pick up `snapit.xcodeproj/.../Package.resolved`. Neither source names the exact path.
5. **Workflow dependency lockfile** (`actions.lock`). Availability and Dependabot support aren't documented yet, so SHA pinning stays until they are.

## Sources

- GitHub: [runner-images README](https://github.com/actions/runner-images) · [macos-26 arm64 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) · [xcode-27 arm64 image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) · [runner-images#14404](https://github.com/actions/runner-images/issues/14404) · [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) · [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use) · [Workflow dependency lockfiles](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles)
- Dependabot: [Supported ecosystems](https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories) · [Options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference) · [Xcode project support changelog](https://github.blog/changelog/2026-03-31-dependabot-now-supports-xcode-projects-using-swiftpm-with-xcodeproj-manifests) · [About Dependabot alerts](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts)
- OSV-Scanner: [repo](https://github.com/google/osv-scanner) · [v2.4.0 release](https://github.com/google/osv-scanner/releases/tag/v2.4.0) · [supported lockfiles](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/) · [GitHub Action docs](https://google.github.io/osv-scanner/github-action/) · [osv-scanner-action](https://github.com/google/osv-scanner-action) · [OSV.dev data sources](https://google.github.io/osv.dev/data/) · [swift/packageresolved extractor](https://pkg.go.dev/github.com/google/osv-scalibr/extractor/filesystem/language/swift/packageresolved) · [SARIF upload availability](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)
- Apple: [macOS 11 Universal Apps release notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes) · [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) · [Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html) · [Creating distribution-signed code](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) · [Sequoia runtime protection news](https://developer.apple.com/news/?id=saqachfa) · [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) · [Xcode 16 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes) · [Running custom scripts during a build](https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build) · [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference) · [Local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages) · [Adding package dependencies](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) · [PackageDescription Product](https://developer.apple.com/documentation/packagedescription/product) · [CFBundleShortVersionString](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring) · [CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion) · local man pages `codesign(1)`, `hdiutil(1)`, `tiffutil(1)` on macOS 27.2
- Rust: [rustc apple-darwin platform support](https://doc.rust-lang.org/rustc/platform-support/apple-darwin.html)
- DMG tools: [dmgbuild](https://github.com/dmgbuild/dmgbuild) · [dmgbuild v2.0.0](https://github.com/dmgbuild/dmgbuild/releases/tag/v2.0.0) · [dmgbuild settings](https://dmgbuild.readthedocs.io/en/latest/settings/) · [create-dmg/create-dmg](https://github.com/create-dmg/create-dmg) · [sindresorhus/create-dmg](https://github.com/sindresorhus/create-dmg) · [node-appdmg](https://github.com/LinusU/node-appdmg)
- Releases: [gh release create](https://cli.github.com/manual/gh_release_create) · [REST: latest release](https://docs.github.com/en/rest/releases/releases#get-the-latest-release) · [REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) · [Immutable releases](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases) · [Artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
- Tool health: [XcodeGen](https://github.com/yonaskolb/XcodeGen) · [Tuist](https://github.com/tuist/tuist) · [cargo-deny](https://github.com/EmbarkStudios/cargo-deny)
