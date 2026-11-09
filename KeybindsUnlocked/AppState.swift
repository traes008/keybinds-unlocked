import Foundation

/// What the user chose, saved between launches, plus what the settings window needs to show.
final class AppState: ObservableObject {
    private enum Key {
        static let mode = "mode", modifier = "modifier", tapWindow = "tapWindow", shortcut = "shortcut"
    }

    /// Called after anything that changes how the trigger should be armed.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    @Published var mode: TriggerMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode); onChange?() }
    }
    @Published var modifier: ModifierKey {
        didSet { defaults.set(modifier.rawValue, forKey: Key.modifier); onChange?() }
    }
    @Published var tapWindow: Double {
        didSet { defaults.set(tapWindow, forKey: Key.tapWindow); onChange?() }
    }
    @Published var shortcut: Shortcut? {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: Key.shortcut); onChange?() }
    }
    /// True while the settings window is capturing a new shortcut, so the old one can't fire.
    @Published var isRecording = false {
        didSet { onChange?() }
    }

    @Published var needsPermission = false
    @Published var shortcutUnavailable = false

    init() {
        mode = TriggerMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .doubleTap
        modifier = ModifierKey(rawValue: defaults.string(forKey: Key.modifier) ?? "") ?? .command
        tapWindow = defaults.object(forKey: Key.tapWindow) as? Double ?? 0.3
        shortcut = defaults.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    var summary: String {
        switch mode {
        case .doubleTap: return "Double-tap \(modifier.symbol) opens Mission Control"
        case .shortcut: return shortcut.map { "\($0.display) opens Mission Control" } ?? "No shortcut set"
        }
    }
}
