## Install snapit @VERSION@

snapit needs macOS 26 or later on Apple silicon. It is not notarized, so macOS asks you to approve it once.

1. Open `snapit-@VERSION@.dmg` and drag snapit into Applications.
2. Open snapit from Applications. macOS says it can't verify snapit. Click **Done**.
3. First open: System Settings › Privacy & Security › **Open Anyway**. Scroll down to the Security section, click **Open Anyway**, then enter your password. You do this once; the Editor that snapit starts inside its own app is never blocked separately.

## Allow Screen Recording

snapit needs Screen Recording to take a Capture.

1. Open System Settings › Privacy & Security › Screen & System Audio Recording.
2. Turn snapit on.
3. Quit snapit and open it again. macOS only applies the permission to a snapit that starts afterwards.

Each new version of snapit is a new build to macOS, so after updating, repeat the Screen Recording steps if snapit's Permission guide asks you to.

## Check the download

SHA-256 of `snapit-@VERSION@.dmg`:

```
@SHA256@
```

The hash is also attached as `snapit-@VERSION@.dmg.sha256`. To check a download, run `shasum -a 256 -c snapit-@VERSION@.dmg.sha256` in the folder that holds both files.
