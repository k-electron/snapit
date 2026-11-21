# Building

Dependencies: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 3.x (MIT) through Swift Package Manager, pinned in `snapit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

You need Xcode 27, [rustup](https://rustup.rs) and [cbindgen](https://github.com/mozilla/cbindgen) 0.29.4 (`cargo install cbindgen --version 0.29.4 --locked`).

```sh
xcodebuild -project snapit.xcodeproj -scheme snapit -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/build/DerivedData.noindex" \
  -packageCachePath "$PWD/build/swiftpm-cache" build
```

Give `-derivedDataPath` and `-packageCachePath` absolute paths (and create `build/swiftpm-cache`): with a relative path Xcode failed to find the KeyboardShortcuts package.

Xcode builds the engine through the `Engine` target, which runs `scripts/build-engine.sh`. The script finds `cargo` itself, so no shell profile is needed. The Rust toolchain version is pinned in `rust-toolchain.toml`. Builds are ad-hoc signed.

After changing the engine's C interface, run `scripts/generate-header.sh` and commit the header.

The code is laid out in [architecture.md](architecture.md). Running the checks is in [testing.md](testing.md).
