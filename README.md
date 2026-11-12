<img src="icon.png" width="96" alt="">

# Keybinds Unlocked

A small Mac app for keybinds that macOS doesn't offer: double-tap a modifier key, press a mouse side button or use a key shortcut to open Mission Control, show the current app's windows or show the desktop.

Website: https://traes008.github.io/keybinds-unlocked/

## What it does

- **Any number of keybinds,** each with its own action: Mission Control, Application Windows or Show Desktop.
- **Double tap** of Command, Option, Control, Shift or Fn. Any key, click or other modifier between the taps cancels it, so shortcuts like ⌘C don't set it off. It fires on the second press, so it feels as fast as a built-in shortcut.
- **Mouse button:** the middle button or a side button. The press is taken over, so the app under the pointer doesn't also act on it. Left and right click can't be bound.
- **Key shortcut:** any combination you record.
- **Stays cheap:** it only wakes when a modifier key or a bound mouse button is pressed.

## Install

There is no ready-made download yet, so you build it yourself. You need a Mac with [Xcode](https://apps.apple.com/app/xcode/id497799835) (free).

1. Download this repository (the green **Code** button, then **Download ZIP**) or clone it.
2. Open `KeybindsUnlocked.xcodeproj` in Xcode.
3. Click the project in the sidebar, pick the **KeybindsUnlocked** target, open **Signing & Capabilities** and choose your own team. A free Apple account works; add it under Xcode → Settings → Accounts.
4. Choose **Product → Archive**, or just press Run to try it.
5. Move the built app to your Applications folder and open it.
6. Allow it under System Settings → Privacy & Security → Accessibility when asked.

Signing with your own team matters: macOS then recognises new builds as the same app and keeps the permission.

The app has no menu bar icon. Open it again to reach its settings, including **Open at Login**.

## How it works

- **Double tap** watches modifier keys through an event tap, which needs Accessibility permission. Every event is passed on unchanged. Other keys and clicks aren't watched: when a modifier changes, the app asks macOS how long ago one was last pressed.
- **Mouse button** uses the same event tap, widened to middle and side button presses only while one is bound.
- **Key shortcut** uses a system hot key, which needs no permission.
- **Actions** are sent straight to the Dock through a private macOS function that is looked up at runtime. If Apple removes it, Mission Control falls back to launching its app and the other actions stop working.

`KeybindsUnlocked/Trigger.swift` holds the logic, and `scripts/check.sh` runs the checks in `Tests/main.swift`. `scripts/make-icon.swift` draws the app icon, and `index.html` is the website.

## Licence

MIT, see [LICENSE](LICENSE).
