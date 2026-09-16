# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Capstand** — a macOS menu bar app (AppKit, SwiftPM, macOS 14+) that opens a chromeless window showing an iPhone's screen whenever the phone is plugged in over USB, so it can be recorded (OBS, QuickTime screen recording). Display only: no remote control, no built-in recording. The directory is `iosdisplay`; the product, bundle (`com.fintonlabs.capstand`) and GitHub repo (`justynroberts/capstand`) are all Capstand.

## Commands

```bash
make help          # list targets
make build         # debug build of the bare binary
make app           # universal (arm64 + x86_64) release build → signed Capstand.app (Developer ID if in keychain, else ad-hoc)
make run           # build app and launch it
make install       # copy to /Applications and launch
make devices       # list capture devices the way the app sees them (needs phone plugged in, unlocked, trusted)
make release VERSION=x.y.z      # sign, notarise, tag, publish GitHub release
make release-dry VERSION=x.y.z  # everything except tag/publish
```

No test suite. Verify capture changes with a real phone: `make run`, plug in, watch `log stream --predicate 'process == "Capstand"'` (all app logs are `NSLog("[capstand] …")`).

Test from the `.app`, not `swift run`: camera permission (TCC) is tied to bundle ID + signature, so the bare binary can't get it reliably.

## How capture works

The QuickTime mechanism, all public API (`DeviceWatcher.swift`):

1. `CMIOObjectSetPropertyData(kCMIOHardwarePropertyAllowScreenCaptureDevices = 1)` — iOS screens are hidden from capture apps until a process opts in. The `DiscoverySession` must be created **after** this.
2. The phone then appears (seconds later) as an `AVCaptureDevice` of type `.external`, media type `.muxed` (video + audio), manufacturer Apple. Hot-plug is tracked by KVO on the discovery session plus `wasConnected/wasDisconnected` notifications, diffed by `uniqueID`.
3. `ScreenWindowController` — one per device: `AVCaptureSession` → `AVCaptureVideoPreviewLayer` (in `ScreenView`) and `AVCaptureAudioPreviewOutput` (capture mutes the phone, so this is the only way to hear it). Stream size comes from the video input port's format description; `formatDescriptionDidChangeNotification` fires on stream start and rotation, and the window re-fits keeping its long edge.

Access is gated on camera permission (`AVCaptureDevice.requestAccess(for: .video)`) — macOS treats the phone screen as a camera. Hardened runtime needs both entitlements in `Assets/Capstand.entitlements`.

## Structure worth knowing

- `AppDelegate` owns everything. The status-bar menu and each window's right-click menu are the *same* builder (`menuNeedsUpdate`), rebuilt on every open.
- `Settings` (UserDefaults) holds global window prefs — stacking level (`.floating` / `.normal` / just above desktop icons), frame style, titanium finish, Dynamic Island, shadow, appearance — applied to all windows. Size presets act on all windows too. Window frames persist per device via `saveFrame(usingName: "screen-<uniqueID>")` (not `setFrameAutosaveName`, which clashes when a device reconnects before the old window deallocates).
- **Show/hide:** the global hotkey ⌃⌥⌘I (`HotKey.swift`) is registered with Carbon's `RegisterEventHotKey`, which needs no Accessibility permission. It toggles every phone window. Hiding keeps the capture session running and sets the audio preview volume to 0, because restarting an iPhone capture takes a second or two. Only unplugging stops the session (`hide(stopCapture: true)`). `wantsVisible` stops a fade-out that finishes late from hiding a window that has since been shown again.
- **Frames:** `FrameRenderer.layout` (`Frames.swift`) is a pure function from style + stream size to a `FrameLayout`: a canvas plus screen, bezel, button and island rects, all in one unit system with a bottom-left origin. The window's aspect ratio and every size preset use `canvas`, not the bare stream; `ScreenView.layout()` just scales and draws it. The iPhone frame is drawn with CAShapeLayers, not images, so there's no licence to worry about. In landscape the phone is turned anticlockwise, which puts the Dynamic Island on the left. Custom frames are PNGs whose screen is either transparent or one flat colour. For a flat-colour screen, `punchSolidScreen` flood-fills from the centre and makes those pixels transparent. The image is copied to `~/Library/Application Support/Capstand/Frames/custom.png`. The screen area is found by scanning outward from the centre along three rows and three columns, and the image is stored in portrait with a landscape version generated from it.
- **Stock mockup sites (pngtree etc.):** they block automated fetches, need a login to download, and their licences don't allow bundling the images into the app. Don't try to scrape them. `Assets/Frames/` holds CC0 frames from Pomme Plate (github.com/ephread/PommePlate). `bundle.sh` copies them to `Contents/Resources/Frames`, and each one gets its own Frame menu item (`FrameStyle.bundled` plus `Settings.bundledFrame`, which stores the file name). To add a frame, drop a PNG into `Assets/Frames`. `ImageFrame.load` cuts out and measures each image once per launch and caches the result.

## Self-update

`Update/` is ported from `~/work/murmur` (proven there). `Updater` checks `api.github.com/repos/justynroberts/capstand/releases/latest` on launch and every 6h, alerts once per version, and never installs unprompted (it would drop the screen mid-recording). `UpdateInstaller` downloads the `.dmg` asset, requires the same Developer ID **Team ID** as the running app (so local ad-hoc builds refuse to self-update), swaps the bundle in place and relaunches.

The contract with `scripts/release.sh`: tag `v<version>`, asset `Capstand-<version>.dmg`, notarised and stapled. `release.sh` rewrites `VERSION=` in `scripts/bundle.sh` — that line is the single source of the version. Notarisation uses keychain profile `notarytool` (override with `NOTARY_KEYCHAIN_PROFILE`).

## Website

`docs/` is the GitHub Pages site (https://justynroberts.github.io/capstand/, served from `main` `/docs`). It's a single static `index.html` with no build step; the design is recorded in `DESIGN.md`. Its download buttons link straight to `releases/download/vX/Capstand-X.dmg`. `release.sh` rewrites those links and the `.dl-ver` spans, and commits the change with the version bump. Don't hand-edit the version numbers.

## Gotchas

- Release builds are universal: `swift build --arch arm64 --arch x86_64` writes to `.build/apple/Products/Release/`, not `.build/release/`. `bundle.sh release` reads that path, and `release.sh` refuses to ship if `lipo -archs` doesn't show both architectures.
- Never use `Bundle.module` — it bakes this machine's `.build` path in and crashes elsewhere. The Bricolage font is excluded from SwiftPM resources and copied by `bundle.sh`; `Fonts.register()` finds it by hand. `release.sh` smoke-tests the built app with `.build` moved aside.
- `main.swift` wraps app startup in `MainActor.assumeIsolated` because `AppDelegate` is `@MainActor`.
- "Open at Login" (`SMAppService.mainApp`) and self-update both expect the app in `/Applications` (`make install`).
- UI follows the `house-style` skill as far as a native window allows; choices are in `DESIGN.md`.
