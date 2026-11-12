// Checks the trigger logic with made-up key events. Run with scripts/check.sh.
import Foundation

var failures = 0
func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    if actual == expected {
        print("ok    \(name)")
    } else {
        failures += 1
        print("FAIL  \(name): got \(actual), wanted \(expected)")
    }
}

let cmd = ModifierKey.command.mask
let shift = ModifierKey.shift.mask
let option = ModifierKey.option.mask

/// Plays flag values at the given times; returns how many double taps were recognised.
/// `otherInputAt` is when a key or mouse button was pressed, if one was.
func taps(_ events: [(UInt64, Double)], key: ModifierKey = .command, window: Double = 0.3, otherInputAt: Double? = nil) -> Int {
    var detector = DoubleTapDetector()
    detector.key = key
    detector.tapWindow = window
    return events.filter { event in
        // Like the real system: only input that has already happened is known
        let last = otherInputAt.flatMap { $0 <= event.1 ? $0 : nil } ?? -.infinity
        return detector.flagsChanged(event.0, at: event.1, lastOtherInputAt: last)
    }.count
}

// Times start at 10 so "long before" is a real moment, as it is with uptime
let quick: [(UInt64, Double)] = [(cmd, 10), (0, 10.05), (cmd, 10.15), (0, 10.2)]
check("double tap fires", taps(quick), 1)
check("second tap too late", taps([(cmd, 10), (0, 10.05), (cmd, 10.5), (0, 10.55)]), 0)
check("longer tap window accepts it", taps([(cmd, 10), (0, 10.05), (cmd, 10.5), (0, 10.55)], window: 0.6), 1)
check("first press held too long", taps([(cmd, 10), (0, 10.5), (cmd, 10.6), (0, 10.65)]), 0)
check("fires on the second press, before its release", taps([(cmd, 10), (0, 10.05), (cmd, 10.1)]), 1)
check("holding the second press doesn't fire again", taps([(cmd, 10), (0, 10.05), (cmd, 10.1), (0, 10.6)]), 1)
check("three quick taps fire once", taps(quick + [(cmd, 10.3), (0, 10.35)]), 1)
check("four quick taps fire twice", taps(quick + [(cmd, 10.3), (0, 10.35), (cmd, 10.45), (0, 10.5)]), 2)
check("another modifier cancels", taps([(cmd, 10), (0, 10.05), (cmd | shift, 10.1), (cmd, 10.15), (0, 10.2)]), 0)
check("shift held while tapping cancels", taps([(shift, 10), (shift | cmd, 10.02), (shift, 10.05), (shift | cmd, 10.1), (shift, 10.15)]), 0)
check("other key can be chosen", taps([(option, 10), (0, 10.05), (option, 10.15), (0, 10.2)], key: .option), 1)
check("command doesn't trigger option", taps(quick, key: .option), 0)

check("typing well before the taps doesn't cancel", taps(quick, otherInputAt: 9.5), 1)
check("cmd+key isn't a tap", taps(quick, otherInputAt: 10.03), 0)
check("a key press between taps cancels", taps(quick, otherInputAt: 10.1), 0)
check("a key right before the first press cancels", taps(quick, otherInputAt: 9.99), 0)
check("a key after it fired doesn't matter", taps(quick, otherInputAt: 10.17), 1)
check("cmd+C then cmd+V quickly doesn't fire", taps([(cmd, 10), (0, 10.12), (cmd, 10.25), (0, 10.4)], otherInputAt: 10.06), 0)

let recorded = Shortcut(keyCode: 46, carbonModifiers: 0x1800, display: "⌃⌥M")
check("upgrade: double tap keeps its key", Keybind.migrated(mode: "doubleTap", modifier: "option", shortcut: nil).map(\.trigger), [.doubleTap(.option)])
check("upgrade: shortcut is kept", Keybind.migrated(mode: "shortcut", modifier: "command", shortcut: recorded).map(\.trigger), [.shortcut(recorded)])
check("upgrade: shortcut mode without a shortcut falls back", Keybind.migrated(mode: "shortcut", modifier: nil, shortcut: nil).map(\.trigger), [.doubleTap(.command)])
check("first launch: double-tap command", Keybind.migrated(mode: nil, modifier: nil, shortcut: nil).map(\.trigger), [.doubleTap(.command)])

let several = [Keybind(trigger: .doubleTap(.command)), Keybind(trigger: .mouseButton(3)), Keybind(trigger: .shortcut(recorded)), Keybind(trigger: .mouseButton(nil))]
check("keybinds survive saving and loading", (try? JSONDecoder().decode([Keybind].self, from: JSONEncoder().encode(several))) ?? [], several)

let withoutAction = #"[{"id":"7E6C1B6E-58B1-4C8B-9B0B-0B1B5F0E7A11","trigger":{"mouseButton":{"_0":3}}}]"#
let loaded = try? JSONDecoder().decode([Keybind].self, from: Data(withoutAction.utf8))
check("keybind saved before actions existed still loads", loaded?.map(\.trigger), [.mouseButton(3)])
check("and it opens Mission Control, as it did", loaded?.first?.action, .missionControl)
check("a chosen action survives saving and loading",
      (try? JSONDecoder().decode([Keybind].self, from: JSONEncoder().encode([Keybind(trigger: .mouseButton(4), action: .showDesktop)])))?.first?.action, .showDesktop)

check("mouse: left click can't be bound", MouseButton.isBindable(0), false)
check("mouse: right click can't be bound", MouseButton.isBindable(1), false)
check("mouse: side button can be bound", MouseButton.isBindable(3), true)
check("mouse: middle button name", MouseButton.name(2), "Middle button")
check("mouse: first side button name", MouseButton.name(3), "Mouse button 4")

check("shortcut: ctrl+opt+M", Shortcut.make(keyCode: 46, held: [.control, .option], characters: "m"),
      Shortcut(keyCode: 46, carbonModifiers: 0x1800, display: "⌃⌥M"))
check("shortcut: plain letter refused", Shortcut.make(keyCode: 46, held: [], characters: "m"), nil)
check("shortcut: shift+letter refused", Shortcut.make(keyCode: 46, held: [.shift], characters: "M"), nil)
check("shortcut: F5 alone allowed", Shortcut.make(keyCode: 96, held: [], characters: nil)?.display, "F5")
check("shortcut: cmd+space", Shortcut.make(keyCode: 49, held: [.command], characters: " ")?.display, "⌘Space")

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
