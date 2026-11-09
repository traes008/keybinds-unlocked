# Keybinds Unlocked

A macOS background app that opens Mission Control when you double-tap a modifier key or press a key combination of your choice.

## How it works

- **Double tap** watches the keyboard through an event tap, so it needs Accessibility permission. Every event is passed on unchanged. Any key, click or other modifier between the taps cancels it.
- **Key shortcut** uses a system hot key, which needs no permission.

`KeybindsUnlocked/Trigger.swift` holds the logic and `scripts/check.sh` tests it.

## Building

Open `KeybindsUnlocked.xcodeproj` in Xcode and press Run, or:

```sh
xcodebuild -project KeybindsUnlocked.xcodeproj -target KeybindsUnlocked -configuration Release SYMROOT="$PWD/build" build
```

Signed with a free personal Apple Development certificate (set in the project), so macOS keeps the Accessibility permission across rebuilds.

Don't leave the Hammerspoon double-tap running alongside this: both would fire and cancel each other out.
