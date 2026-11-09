import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Watches for the chosen trigger and opens Mission Control when it happens.
final class TriggerEngine {
    private let state: AppState
    private var detector = DoubleTapDetector()

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var didPromptForPermission = false

    private var hotKey: EventHotKeyRef?
    private var hotKeyHandlerInstalled = false

    init(state: AppState) {
        self.state = state
    }

    /// Arms whichever trigger is selected and disarms the other. Safe to call repeatedly.
    func configure() {
        detector.key = state.modifier
        detector.tapWindow = state.tapWindow

        if state.isRecording {
            removeTap()
            removeHotKey()
        } else if state.mode == .doubleTap {
            removeHotKey()
            armTap()
        } else {
            removeTap()
            armHotKey()
        }
        updatePermissionState()
    }

    // MARK: Double tap

    private func armTap() {
        // Without permission macOS may still hand back a tap, but a disabled one that never recovers
        guard tap == nil, AXIsProcessTrusted() else { return }

        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // Not .listenOnly: that also needs Input Monitoring, and without it comes back disabled.
        // The callback hands every event back unchanged.
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: Self.tapCallback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        tapSource = source
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        if let refcon {
            Unmanaged<TriggerEngine>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            if detector.flagsChanged(event.flags.rawValue, at: ProcessInfo.processInfo.systemUptime) {
                fire() // outside the event callback, so typing never waits on it
            }
        default:
            detector.interrupted()
        }
    }

    /// Only double tap needs Accessibility, because only it has to watch the keyboard.
    private func updatePermissionState() {
        let needed = state.mode == .doubleTap && !state.isRecording && tap == nil
        if state.needsPermission != needed { state.needsPermission = needed }

        guard needed else {
            permissionTimer?.invalidate()
            permissionTimer = nil
            return
        }
        if !didPromptForPermission {
            didPromptForPermission = true
            let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(prompt)
        }
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.configure() }
    }

    // MARK: Key shortcut

    private func armHotKey() {
        removeHotKey()
        var unavailable = false
        if let shortcut = state.shortcut {
            installHotKeyHandler()
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4B42554E), id: 1) // "KBUN"
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            hotKey = ref
            unavailable = status != noErr
        }
        if state.shortcutUnavailable != unavailable { state.shortcutUnavailable = unavailable }
    }

    private func removeHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHotKeyHandler() {
        guard !hotKeyHandlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            if let userData { Unmanaged<TriggerEngine>.fromOpaque(userData).takeUnretainedValue().fire() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        hotKeyHandlerInstalled = status == noErr
    }

    // MARK: Action

    private func fire() {
        DispatchQueue.main.async {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "Mission Control"])
        }
    }
}
