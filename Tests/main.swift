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
func taps(_ events: [(UInt64, Double)], key: ModifierKey = .command, window: Double = 0.3) -> Int {
    var detector = DoubleTapDetector()
    detector.key = key
    detector.tapWindow = window
    return events.filter { detector.flagsChanged($0.0, at: $0.1) }.count
}

let quick: [(UInt64, Double)] = [(cmd, 0), (0, 0.05), (cmd, 0.15), (0, 0.2)]
check("double tap fires", taps(quick), 1)
check("second tap too late", taps([(cmd, 0), (0, 0.05), (cmd, 0.5), (0, 0.55)]), 0)
check("longer tap window accepts it", taps([(cmd, 0), (0, 0.05), (cmd, 0.5), (0, 0.55)], window: 0.6), 1)
check("first press held too long", taps([(cmd, 0), (0, 0.5), (cmd, 0.6), (0, 0.65)]), 0)
check("second press held too long", taps([(cmd, 0), (0, 0.05), (cmd, 0.1), (0, 0.6)]), 0)
check("four quick taps fire twice", taps(quick + [(cmd, 0.3), (0, 0.35), (cmd, 0.45), (0, 0.5)]), 2)
check("another modifier cancels", taps([(cmd, 0), (0, 0.05), (cmd | shift, 0.1), (cmd, 0.15), (0, 0.2)]), 0)
check("shift held while tapping cancels", taps([(shift, 0), (shift | cmd, 0.02), (shift, 0.05), (shift | cmd, 0.1), (shift, 0.15)]), 0)
check("other key can be chosen", taps([(option, 0), (0, 0.05), (option, 0.15), (0, 0.2)], key: .option), 1)
check("command doesn't trigger option", taps(quick, key: .option), 0)

var interruptedDetector = DoubleTapDetector()
_ = interruptedDetector.flagsChanged(cmd, at: 0)
_ = interruptedDetector.flagsChanged(0, at: 0.05)
interruptedDetector.interrupted()
_ = interruptedDetector.flagsChanged(cmd, at: 0.1)
check("a key press between taps cancels", interruptedDetector.flagsChanged(0, at: 0.15), false)

var heldDetector = DoubleTapDetector()
_ = heldDetector.flagsChanged(cmd, at: 0)
heldDetector.interrupted() // Cmd+C
check("cmd+key isn't a tap", heldDetector.flagsChanged(0, at: 0.05), false)

check("shortcut: ctrl+opt+M", Shortcut.make(keyCode: 46, held: [.control, .option], characters: "m"),
      Shortcut(keyCode: 46, carbonModifiers: 0x1800, display: "⌃⌥M"))
check("shortcut: plain letter refused", Shortcut.make(keyCode: 46, held: [], characters: "m"), nil)
check("shortcut: shift+letter refused", Shortcut.make(keyCode: 46, held: [.shift], characters: "M"), nil)
check("shortcut: F5 alone allowed", Shortcut.make(keyCode: 96, held: [], characters: nil)?.display, "F5")
check("shortcut: cmd+space", Shortcut.make(keyCode: 49, held: [.command], characters: " ")?.display, "⌘Space")

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
