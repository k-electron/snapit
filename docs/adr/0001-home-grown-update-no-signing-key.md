# Home-grown Update, checked by the release's SHA-256

snapit installs an **Update** with its own code, an extension of Check for Updates, rather than with Sparkle 2. It checks the downloaded DMG only against the `.sha256` file each release already publishes, plus the new bundle's identifier, version and signature validity. No signing key is used.

## Considered Options

- **Sparkle 2.** Rejected. snapit is ad-hoc signed with the hardened runtime, so library validation stops it loading Sparkle.framework without the `com.apple.security.cs.disable-library-validation` entitlement; snapit has no entitlements. An ad-hoc app can't pass Sparkle's code-signing match between builds (its designated requirement is a cdhash), so Sparkle accepts it only with an EdDSA signature: a private key held as a CI secret, which the release workflow has never needed, and whose loss ends updates for good. It also brings an appcast to publish and its own helper processes.
- **A signing key (EdDSA, or a stable self-signed certificate) for the Update.** Deferred. It would guard against someone who can publish a GitHub Release, but it adds the first CI secret. Today's trust is the same without it: an ad-hoc build approved with Open Anyway is checked by nobody either. A stable self-signed certificate may later also keep the Screen Recording grant across Updates; that is unproven and needs a prototype.

## Consequences

- snapit downloads the DMG itself, so the file carries no quarantine and the Update needs no Open Anyway. snapit's own checks are the only gate on what it installs.
- Screen Recording is still lost on every Update while releases are ad-hoc signed; the existing reset-and-ask flow covers it.
- Replacing the bundle in place in `/Applications` worked for an ad-hoc test app on macOS 27.2 with no App Management prompt; a copy first approved with Open Anyway was not tested and is a manual check.
