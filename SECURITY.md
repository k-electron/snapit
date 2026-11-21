# Security policy

## Report a vulnerability privately

snapit takes reports through GitHub's private vulnerability reporting, so a report stays between you and the maintainer until a fix is out.

[Report a vulnerability](https://github.com/k-electron/snapit/security/advisories/new)

Please do not open a public issue or pull request for a vulnerability.

## What to include

- The snapit version (Settings › About shows it), the macOS version and the Mac model.
- What the vulnerability is and what it lets someone do.
- The steps to reproduce it, with a sample Capture or file if one is needed.
- The impact you expect, and a suggested fix if you have one.

The maintainer replies in the report, works on a fix with you there, and credits you in the advisory if you wish.

## Supported versions

The latest release receives security fixes. Updating is one click on [Check for Updates](docs/UserGuide.md#updates).

## snapit's network surface

snapit contacts GitHub only when you click **Check for Updates…**, in the menu or in Settings › About, to ask whether a newer release exists. It makes no other network request, and a Capture never leaves your Mac unless you Export it yourself. See [Check for Updates](docs/UserGuide.md#updates) in the User Guide.

`scripts/check-network.sh` runs in the repo's checks and keeps that code to one file, which the [testing doc](docs/development/testing.md) describes.
