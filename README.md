# Keybinds Unlocked

A macOS background app for keybinds that macOS doesn't offer: a double tap of a modifier key, a key combination, or a mouse button such as a side button. Each one opens Mission Control, shows the application's windows or shows the desktop.

## How it works

- **Double tap** watches modifier keys through an event tap, so it needs Accessibility permission. Every event is passed on unchanged. Other keys and clicks aren't watched: when a modifier changes, the app asks macOS how long ago one was last pressed. Any key, click or other modifier between the taps cancels it.
- **Mouse button** uses the same event tap, widened to middle and side button presses only while one is bound. A bound button's press and release are swallowed, so the app under the pointer doesn't also act on it. Left and right click can't be bound.
- **Key shortcut** uses a system hot key, which needs no permission.

Keybinds are saved as JSON under `keybinds` in the app's defaults. Settings from the single-trigger version are converted on first launch.

`KeybindsUnlocked/Trigger.swift` holds the logic and `scripts/check.sh` tests it.

## Building

Open `KeybindsUnlocked.xcodeproj` in Xcode and press Run, or:

```sh
xcodebuild -project KeybindsUnlocked.xcodeproj -target KeybindsUnlocked -configuration Release SYMROOT="$PWD/build" build
```

Signed with a free personal Apple Development certificate (set in the project), so macOS keeps the Accessibility permission across rebuilds.

Don't leave the Hammerspoon double-tap running alongside this: both would fire and cancel each other out.
