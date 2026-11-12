<img src="icon.png" width="96" alt="">

# Keybinds Unlocked

Keybinds macOS doesn't offer, like double-tap ⌘ for Mission Control or a mouse side button for Show Desktop.

https://traes008.github.io/keybinds-unlocked/

- Triggers: double tap of a modifier key, a mouse button, or a key shortcut.
- Actions: Mission Control, Application Windows, Show Desktop.
- Add as many as you want.

## Install

1. [Download KeybindsUnlocked.zip](https://traes008.github.io/keybinds-unlocked/KeybindsUnlocked.zip), unzip it and move the app to Applications.
2. Open it. macOS blocks it because it isn't signed by Apple: go to System Settings → Privacy & Security and click **Open Anyway**.
3. Allow it under Privacy & Security → Accessibility.

No menu bar icon. Open the app again for its settings.

Or build it yourself: open `KeybindsUnlocked.xcodeproj` in Xcode, pick your own team under Signing & Capabilities, and run.

## Notes

- A bound mouse button is taken over, so other apps don't see it.
- `scripts/check.sh` runs the logic tests. Start reading at `KeybindsUnlocked/Trigger.swift`.

MIT licence.
