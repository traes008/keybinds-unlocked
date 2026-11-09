import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Open Mission Control with") {
                Picker("Trigger", selection: $state.mode) {
                    Text("Double-tap a key").tag(TriggerMode.doubleTap)
                    Text("Key shortcut").tag(TriggerMode.shortcut)
                }
                .pickerStyle(.segmented)

                if state.mode == .doubleTap {
                    Picker("Key", selection: $state.modifier) {
                        ForEach(ModifierKey.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Tap speed") {
                        HStack {
                            Text("Quick").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $state.tapWindow, in: 0.15...0.6)
                            Text("Relaxed").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    LabeledContent("Shortcut") { ShortcutField(state: state) }
                    if state.shortcutUnavailable {
                        Text("Another app or macOS is already using that shortcut.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if state.needsPermission {
                Section("Permission needed") {
                    Text("Double-tap detection needs Accessibility access to notice key presses. It only watches, and never changes what you type.")
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
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
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

/// Click, then press the keys you want.
struct ShortcutField: View {
    @ObservedObject var state: AppState
    @State private var monitor: Any?

    var body: some View {
        Button(state.isRecording ? "Press keys… (Esc cancels)" : state.shortcut?.display ?? "Click to record") {
            state.isRecording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        state.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop() // Esc on its own cancels
                return nil
            }
            var held: Shortcut.Held = []
            if event.modifierFlags.contains(.control) { held.insert(.control) }
            if event.modifierFlags.contains(.option) { held.insert(.option) }
            if event.modifierFlags.contains(.shift) { held.insert(.shift) }
            if event.modifierFlags.contains(.command) { held.insert(.command) }
            if let shortcut = Shortcut.make(keyCode: UInt32(event.keyCode), held: held,
                                            characters: event.charactersIgnoringModifiers) {
                state.shortcut = shortcut
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if state.isRecording { state.isRecording = false }
    }
}
