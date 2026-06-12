---
name: verify-ios-simulator
description: Build, launch, and screenshot an iOS app on the simulator, then visually inspect the result to confirm a UI change actually looks right. Use when asked to verify/confirm a UI change, screenshot the simulator, check how an iOS view renders, or validate something that unit tests can't see (colors, layout, alignment, drawing).
---

# Verify on the iOS simulator

Unit tests confirm logic; they don't show you what the screen looks like. Some bugs (wrong colors, leaked fill state, misaligned glyphs, clipped views) are only visible by **running the app and looking at it**. This skill builds the app, drives it on the simulator, screenshots it, and you read the image to judge.

## Workflow

1. **Build** for the booted simulator (project-specific — match the repo's scheme):
   ```sh
   xcrun simctl list devices booted        # get the booted UDID
   xcodebuild build -scheme <Scheme> -destination 'platform=iOS Simulator,id=<UDID>' \
     [-project X.xcodeproj | -workspace X.xcworkspace]
   ```
   Find the built app: `find ~/Library/Developer/Xcode/DerivedData -name '<App>.app' -path '*Debug-iphonesimulator*' | head -1`

2. **Launch + screenshot** with the helper (install → fresh launch → settle → capture):
   ```sh
   scripts/screenshot.sh --app <App.app> [--args "<launch args>"] [--out /tmp/shot.png]
   ```
   It resolves the booted device, reads the bundle id from the app, waits until the
   frame stops changing (avoids a blank pre-render shot), and prints the PNG path.

3. **Look at it.** Read the PNG with the Read tool and check the change against intent.

4. **Iterate.** If wrong, fix the code, rebuild, and re-run `screenshot.sh` (it reinstalls and relaunches).

## Key gotchas (each one has bitten this loop)

- **Screenshot too early = blank frame.** `simctl launch` returns before the app renders. The script settles by capturing until two frames match; if you screenshot by hand, take a second shot after a beat.
- **simctl can't tap.** There's no touch command. To reach a specific screen, add a **launch argument** that deep-links to it (read in `App`/`@main` from `CommandLine.arguments`) instead of trying to navigate the UI.
- **Find the bundle id** from the build, don't guess: `/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' <App.app>/Info.plist`.
- **Terminate before relaunch** so launch args and state are fresh (the script does this).
- **Toolchain contention.** A concurrent `xcodebuild` from another project can stall or starve the build; if a run produces no output, check `pgrep -fl xcodebuild` and retry.

## Why bother when tests pass

Pixel-comparison tests that diff the *same* document against itself stay green even when a real bug shifts every pixel the same way (e.g. a text color that leaks into later runs). Running the app is the only check that catches "it compiles, tests pass, but it looks wrong."
