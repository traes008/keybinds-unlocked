import Foundation

/// What the user chose, saved between launches, plus what the settings window needs to show.
final class AppState: ObservableObject {
    private enum Key {
        static let keybinds = "keybinds", tapWindow = "tapWindow"
        // From the version that had a single trigger
        static let mode = "mode", modifier = "modifier", shortcut = "shortcut"
    }

    /// Called after anything that changes how the keybinds should be armed.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    @Published var keybinds: [Keybind] {
        didSet { defaults.set(try? JSONEncoder().encode(keybinds), forKey: Key.keybinds); onChange?() }
    }
    @Published var tapWindow: Double {
        didSet { defaults.set(tapWindow, forKey: Key.tapWindow); onChange?() }
    }
    /// The keybind whose shortcut or mouse button is being captured. Nothing fires meanwhile.
    @Published var recordingID: UUID? {
        didSet { onChange?() }
    }

    @Published var needsPermission = false
    /// Key shortcuts that another app or macOS already uses.
    @Published var unavailableShortcuts: Set<UUID> = []

    var isRecording: Bool { recordingID != nil }

    init() {
        tapWindow = defaults.object(forKey: Key.tapWindow) as? Double ?? 0.3
        if let saved = defaults.data(forKey: Key.keybinds).flatMap({ try? JSONDecoder().decode([Keybind].self, from: $0) }) {
            keybinds = saved
        } else {
            let shortcut = defaults.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            keybinds = Keybind.migrated(mode: defaults.string(forKey: Key.mode),
                                        modifier: defaults.string(forKey: Key.modifier), shortcut: shortcut)
        }
    }
}
