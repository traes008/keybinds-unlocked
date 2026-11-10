import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Watches for every keybind's trigger and opens Mission Control when one happens.
final class TriggerEngine {
    private let state: AppState
    private var detectors: [DoubleTapDetector] = []
    private var mouseButtons: Set<Int64> = []
    /// Bound buttons that are held down: their release is swallowed too, so no app sees half a click.
    private var swallowedButtons: Set<Int64> = []

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var tapMask: CGEventMask = 0
    private var permissionTimer: Timer?
    private var didPromptForPermission = false

    private var hotKeys: [EventHotKeyRef] = []
    private var armedShortcuts: [Shortcut] = []
    private var hotKeyHandlerInstalled = false

    init(state: AppState) {
        self.state = state
    }

    /// Arms what the keybinds need and disarms the rest. Safe to call repeatedly.
    func configure() {
        // Nothing fires while a shortcut or button is being recorded
        let keybinds = state.isRecording ? [] : state.keybinds

        var modifiers: [ModifierKey] = []
        var buttons: Set<Int64> = []
        var shortcuts: [(id: UUID, shortcut: Shortcut)] = []
        for keybind in keybinds {
            switch keybind.trigger {
            case .doubleTap(let key): if !modifiers.contains(key) { modifiers.append(key) }
            case .mouseButton(let number?): buttons.insert(Int64(number))
            case .shortcut(let shortcut?): shortcuts.append((keybind.id, shortcut))
            case .mouseButton(nil), .shortcut(nil): break
            }
        }

        detectors = modifiers.map {
            var detector = DoubleTapDetector()
            detector.key = $0
            detector.tapWindow = state.tapWindow
            return detector
        }
        mouseButtons = buttons

        // Only what is bound, so the app isn't woken by (or in the path of) ordinary typing and clicks
        var mask: CGEventMask = 0
        if !detectors.isEmpty { mask |= CGEventMask(1) << CGEventType.flagsChanged.rawValue }
        if !buttons.isEmpty {
            mask |= CGEventMask(1) << CGEventType.otherMouseDown.rawValue | CGEventMask(1) << CGEventType.otherMouseUp.rawValue
        }
        armTap(mask)
        armHotKeys(shortcuts)
        updatePermissionState(needsTap: mask != 0)
    }

    // MARK: Double tap and mouse buttons

    private func armTap(_ mask: CGEventMask) {
        if tap != nil && mask == tapMask { return }
        removeTap()
        // Without permission macOS may still hand back a tap, but a disabled one that never recovers
        guard mask != 0, AXIsProcessTrusted() else { return }

        // Not .listenOnly: that also needs Input Monitoring, and without it comes back disabled.
        // The callback hands every event back unchanged, except presses of a bound mouse button.
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: Self.tapCallback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        tapSource = source
        tapMask = mask
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        tapMask = 0
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        if let refcon, Unmanaged<TriggerEngine>.fromOpaque(refcon).takeUnretainedValue().handle(type, event) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// Returns true to swallow the event, so no other app sees it.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let now = ProcessInfo.processInfo.systemUptime
            let lastOtherInputAt = now - Self.secondsSinceOtherInput()
            var fired = false
            for index in detectors.indices
            where detectors[index].flagsChanged(event.flags.rawValue, at: now, lastOtherInputAt: lastOtherInputAt) {
                fired = true
            }
            if fired { fire() } // outside the event callback, so typing never waits on it
        case .otherMouseDown:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard mouseButtons.contains(button) else { return false }
            swallowedButtons.insert(button)
            fire()
            return true
        case .otherMouseUp:
            return swallowedButtons.remove(event.getIntegerValueField(.mouseEventButtonNumber)) != nil
        default:
            break
        }
        return false
    }

    /// How long ago a key or mouse button was last pressed. Asking the system when needed means
    /// those events don't have to be watched.
    private static func secondsSinceOtherInput() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
    }

    /// Double taps and mouse buttons need Accessibility, because they have to watch input. Key shortcuts don't.
    private func updatePermissionState(needsTap: Bool) {
        let needed = needsTap && tap == nil
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

    // MARK: Key shortcuts

    private func armHotKeys(_ shortcuts: [(id: UUID, shortcut: Shortcut)]) {
        // Unchanged shortcuts stay registered: this runs on every settings change
        guard shortcuts.map(\.shortcut) != armedShortcuts else { return }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        armedShortcuts = shortcuts.map(\.shortcut)

        var unavailable: Set<UUID> = []
        for (index, entry) in shortcuts.enumerated() {
            installHotKeyHandler()
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4B42554E), id: UInt32(index + 1)) // "KBUN"
            let status = RegisterEventHotKey(entry.shortcut.keyCode, entry.shortcut.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys.append(ref)
            } else {
                unavailable.insert(entry.id)
            }
        }
        if state.unavailableShortcuts != unavailable { state.unavailableShortcuts = unavailable }
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

    private typealias DockNotification = @convention(c) (CFString, Int32) -> Void

    /// Asks the Dock directly, which is instant. macOS has no public API for this, so the private
    /// function is looked up at runtime; if Apple removes it, `fire` falls back to launching the
    /// Mission Control app, which works but takes noticeably longer.
    private static let sendToDock: DockNotification? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: DockNotification.self)
    }()

    private func fire() {
        DispatchQueue.main.async {
            if let sendToDock = Self.sendToDock {
                sendToDock("com.apple.expose.awake" as CFString, 0)
            } else {
                _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "Mission Control"])
            }
        }
    }
}
