import Foundation

// The trigger logic. Pure Swift with no system calls, so scripts/check.sh can test it directly.

/// What sets a keybind off. A shortcut or mouse button is nil until one has been recorded.
enum Trigger: Codable, Equatable {
    case doubleTap(ModifierKey)
    case shortcut(Shortcut?)
    case mouseButton(Int?)
}

/// One way of opening Mission Control. There can be any number of them.
struct Keybind: Codable, Equatable, Identifiable {
    var id = UUID()
    var trigger: Trigger

    /// The keybinds for someone coming from the version that had a single trigger.
    static func migrated(mode: String?, modifier: String?, shortcut: Shortcut?) -> [Keybind] {
        if mode == "shortcut", let shortcut {
            return [Keybind(trigger: .shortcut(shortcut))]
        }
        return [Keybind(trigger: .doubleTap(ModifierKey(rawValue: modifier ?? "") ?? .command))]
    }
}

/// Mouse buttons by their system number: 0 is left, 1 is right, 2 is the middle button, and the
/// side buttons follow.
enum MouseButton {
    /// Left and right can't be bound: that would stop you clicking.
    static func isBindable(_ number: Int) -> Bool {
        number >= 2
    }

    /// Named the way mice and their software count them, starting at 1.
    static func name(_ number: Int) -> String {
        number == 2 ? "Middle button" : "Mouse button \(number + 1)"
    }
}

/// A modifier key that can be double-tapped. `mask` is its bit in a CGEvent's flags (either side of the keyboard).
enum ModifierKey: String, CaseIterable, Identifiable, Codable {
    case command, option, control, shift, function

    var id: String { rawValue }

    var mask: UInt64 {
        switch self {
        case .command: return 0x100000
        case .option: return 0x80000
        case .control: return 0x40000
        case .shift: return 0x20000
        case .function: return 0x800000
        }
    }

    var title: String {
        switch self {
        case .command: return "Command ⌘"
        case .option: return "Option ⌥"
        case .control: return "Control ⌃"
        case .shift: return "Shift ⇧"
        case .function: return "Fn"
        }
    }

    static let allMasks: UInt64 = allCases.reduce(0) { $0 | $1.mask }
}

/// Recognises two quick, bare taps of one modifier. Any key, click or other modifier in between
/// (⌘C, ⌘-click, ...) cancels it.
struct DoubleTapDetector {
    var key: ModifierKey = .command
    /// Max seconds between releasing the first tap and pressing the second.
    var tapWindow: TimeInterval = 0.3
    /// Holding the key longer than this isn't a tap.
    var maxTapLength: TimeInterval = 0.3

    /// A key or click this close before the first press also cancels. The press is timed when it
    /// reaches the app, slightly after it happened, so this keeps a key pressed right after it
    /// from slipping through.
    private static let inputMargin: TimeInterval = 0.03

    private var isDown = false
    private var isClean = false
    private var tapStartedAt: TimeInterval = 0
    private var lastTapAt: TimeInterval = -.infinity

    /// Feed every modifier change, with the time a key or mouse button was last pressed.
    /// Returns true when this change completes a double tap. That is the second press, not its
    /// release: waiting for the release feels sluggish.
    mutating func flagsChanged(_ flags: UInt64, at now: TimeInterval, lastOtherInputAt: TimeInterval) -> Bool {
        let keyHeld = flags & key.mask != 0
        let otherHeld = flags & (ModifierKey.allMasks & ~key.mask) != 0
        let interrupted = lastOtherInputAt > tapStartedAt - Self.inputMargin

        if keyHeld && !isDown {
            isDown = true
            if !otherHeld && !interrupted && now - lastTapAt <= tapWindow {
                lastTapAt = -.infinity
                isClean = false // this press is used up, so its release doesn't start a new double tap
                return true
            }
            tapStartedAt = now
            isClean = !otherHeld
        } else if !keyHeld && isDown {
            isDown = false
            let isTap = isClean && !otherHeld && !interrupted && now - tapStartedAt <= maxTapLength
            lastTapAt = isTap ? now : -.infinity
        } else {
            // Another modifier changed
            isClean = false
            lastTapAt = -.infinity
        }
        return false
    }
}

/// A recorded key combination, using the Carbon key code and modifier values that hot keys need.
struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    struct Held: OptionSet {
        let rawValue: Int
        static let control = Held(rawValue: 1)
        static let option = Held(rawValue: 2)
        static let shift = Held(rawValue: 4)
        static let command = Held(rawValue: 8)
    }

    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let namedKeys: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    /// Builds a shortcut from a key press, or nil if it isn't usable. A plain letter or Shift+letter
    /// would stop you typing it, so it needs ⌘, ⌥ or ⌃. Function keys work on their own.
    static func make(keyCode: UInt32, held: Held, characters: String?) -> Shortcut? {
        let function = functionKeys[keyCode]
        guard function != nil || !held.isDisjoint(with: [.control, .option, .command]) else { return nil }
        guard let name = function ?? namedKeys[keyCode] ?? characters?.uppercased(), !name.isEmpty else { return nil }

        var carbon: UInt32 = 0
        var symbols = ""
        if held.contains(.control) { carbon |= 0x1000; symbols += "⌃" }
        if held.contains(.option) { carbon |= 0x800; symbols += "⌥" }
        if held.contains(.shift) { carbon |= 0x200; symbols += "⇧" }
        if held.contains(.command) { carbon |= 0x100; symbols += "⌘" }
        return Shortcut(keyCode: keyCode, carbonModifiers: carbon, display: symbols + name)
    }
}
