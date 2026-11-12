import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @StateObject private var recorder: Recorder
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    init(state: AppState) {
        self.state = state
        _recorder = StateObject(wrappedValue: Recorder(state: state))
    }

    private var usedModifiers: [ModifierKey] {
        state.keybinds.compactMap { if case .doubleTap(let key) = $0.trigger { return key } else { return nil } }
    }

    var body: some View {
        Form {
            Section("Keybinds") {
                if state.keybinds.isEmpty {
                    Text("No keybinds yet.").foregroundStyle(.secondary)
                }
                ForEach($state.keybinds) { $keybind in
                    KeybindRow(keybind: $keybind, state: state, recorder: recorder)
                }
                Menu("Add Keybind") {
                    Button("Double-tap a key") {
                        add(.doubleTap(ModifierKey.allCases.first { !usedModifiers.contains($0) } ?? .command))
                    }
                    Button("Key shortcut") { add(.shortcut(nil)) }
                    Button("Mouse button") { add(.mouseButton(nil)) }
                }
                .fixedSize()
            }

            if !usedModifiers.isEmpty {
                Section {
                    LabeledContent("Double-tap speed") {
                        HStack {
                            Text("Quick").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $state.tapWindow, in: 0.15...0.6)
                            Text("Relaxed").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if state.needsPermission {
                Section("Permission needed") {
                    Text("Double taps and mouse buttons need Accessibility access to notice those presses. Typing is never changed.")
                        .font(.callout)
                    Button("Open Accessibility Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }

            Section {
                Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                Button("Quit Keybinds Unlocked") { NSApp.terminate(nil) }
            } footer: {
                Text("Runs in the background. Open the app again to get back here.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear(perform: recorder.stop)
    }

    /// A new shortcut or mouse button starts recording straight away.
    private func add(_ trigger: Trigger) {
        let keybind = Keybind(trigger: trigger)
        state.keybinds.append(keybind)
        recorder.start(keybind)
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Keybinds Unlocked: could not change Open at Login: \(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct KeybindRow: View {
    @Binding var keybind: Keybind
    @ObservedObject var state: AppState
    let recorder: Recorder

    private var isRecording: Bool { state.recordingID == keybind.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                switch keybind.trigger {
                case .doubleTap(let key):
                    Text("Double-tap")
                    Picker("Key", selection: Binding(get: { key }, set: { keybind.trigger = .doubleTap($0) })) {
                        ForEach(ModifierKey.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                case .shortcut(let shortcut):
                    Text("Key shortcut")
                    Button(isRecording ? "Press keys… (Esc cancels)" : shortcut?.display ?? "Click to record") {
                        recorder.toggle(keybind)
                    }
                case .mouseButton(let number):
                    Button(isRecording ? "Press a button… (Esc cancels)" : number.map(MouseButton.name) ?? "Click to record") {
                        recorder.toggle(keybind)
                    }
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("Action", selection: $keybind.action) {
                    ForEach(Action.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button {
                    if isRecording { recorder.stop() }
                    state.keybinds.removeAll { $0.id == keybind.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this keybind")
            }
            if state.unavailableShortcuts.contains(keybind.id) {
                Text("Another app or macOS is already using that shortcut.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// Captures the next key combination or mouse button for one keybind at a time.
final class Recorder: ObservableObject {
    private let state: AppState
    private var monitors: [Any] = []

    init(state: AppState) {
        self.state = state
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    func toggle(_ keybind: Keybind) {
        if state.recordingID == keybind.id {
            stop()
        } else {
            start(keybind)
        }
    }

    func start(_ keybind: Keybind) {
        stop()
        let id = keybind.id
        switch keybind.trigger {
        case .doubleTap:
            return
        case .shortcut:
            monitors = [NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, !self.isEscape(event) else { return nil }
                var held: Shortcut.Held = []
                if event.modifierFlags.contains(.control) { held.insert(.control) }
                if event.modifierFlags.contains(.option) { held.insert(.option) }
                if event.modifierFlags.contains(.shift) { held.insert(.shift) }
                if event.modifierFlags.contains(.command) { held.insert(.command) }
                if let shortcut = Shortcut.make(keyCode: UInt32(event.keyCode), held: held,
                                                characters: event.charactersIgnoringModifiers) {
                    self.finish(.shortcut(shortcut), for: id)
                }
                return nil
            } as Any]
        case .mouseButton:
            let record: (NSEvent) -> Void = { [weak self] event in
                if MouseButton.isBindable(event.buttonNumber) { self?.finish(.mouseButton(event.buttonNumber), for: id) }
            }
            monitors = [
                NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .keyDown]) { [weak self] event in
                    if event.type == .keyDown {
                        return self?.isEscape(event) == false ? event : nil
                    }
                    record(event)
                    return nil
                } as Any,
                // So the button can be pressed anywhere, not only over this window
                NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown, handler: record) as Any,
            ]
        }
        state.recordingID = id
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if state.recordingID != nil { state.recordingID = nil }
    }

    /// Esc on its own cancels the recording.
    private func isEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
        stop()
        return true
    }

    private func finish(_ trigger: Trigger, for id: UUID) {
        if let index = state.keybinds.firstIndex(where: { $0.id == id }) {
            state.keybinds[index].trigger = trigger
        }
        stop()
    }
}
