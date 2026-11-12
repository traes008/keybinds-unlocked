import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Watches for every keybind's trigger and carries out its action when one happens.
final class TriggerEngine {
    private let state: AppState
    private var detectors: [(detector: DoubleTapDetector, action: Action)] = []
    private var mouseButtons: [Int64: Action] = [:]
    /// Bound buttons that are held down: their release is swallowed too, so no app sees half a click.
    private var swallowedButtons: Set<Int64> = []

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var tapMask: CGEventMask = 0
    private var permissionTimer: Timer?
    private var didPromptForPermission = false

    private var hotKeys: [EventHotKeyRef] = []
    private var armedShortcuts: [Shortcut] = []
    /// The action of each registered shortcut, in the order they were registered.
    private var shortcutActions: [Action] = []
    private var hotKeyHandlerInstalled = false

    init(state: AppState) {
        self.state = state
    }

    /// Arms what the keybinds need and disarms the rest. Safe to call repeatedly.
    func configure() {
        // Nothing fires while a shortcut or button is being recorded
        let keybinds = state.isRecording ? [] : state.keybinds

        // If two keybinds share a trigger, the first one wins
        var doubleTaps: [(key: ModifierKey, action: Action)] = []
        var buttons: [Int64: Action] = [:]
        var shortcuts: [(id: UUID, shortcut: Shortcut, action: Action)] = []
        for keybind in keybinds {
            switch keybind.trigger {
            case .doubleTap(let key):
                if !doubleTaps.contains(where: { $0.key == key }) { doubleTaps.append((key, keybind.action)) }
            case .mouseButton(let number?):
                if buttons[Int64(number)] == nil { buttons[Int64(number)] = keybind.action }
            case .shortcut(let shortcut?):
                shortcuts.append((keybind.id, shortcut, keybind.action))
            case .mouseButton(nil), .shortcut(nil):
                break
            }
        }

        detectors = doubleTaps.map {
            var detector = DoubleTapDetector()
            detector.key = $0.key
            detector.tapWindow = state.tapWindow
            return (detector, $0.action)
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
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap) // otherwise macOS keeps the switched-off tap registered
        }
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
            for index in detectors.indices
            where detectors[index].detector.flagsChanged(event.flags.rawValue, at: now, lastOtherInputAt: lastOtherInputAt) {
                fire(detectors[index].action) // outside the event callback, so typing never waits on it
            }
        case .otherMouseDown:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            guard let action = mouseButtons[button] else { return false }
            swallowedButtons.insert(button)
            fire(action)
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

    private func armHotKeys(_ shortcuts: [(id: UUID, shortcut: Shortcut, action: Action)]) {
        shortcutActions = shortcuts.map(\.action)
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
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var id = EventHotKeyID()
            let found = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if found == noErr, let userData {
                Unmanaged<TriggerEngine>.fromOpaque(userData).takeUnretainedValue().shortcutPressed(Int(id.id) - 1)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        hotKeyHandlerInstalled = status == noErr
    }

    private func shortcutPressed(_ index: Int) {
        if shortcutActions.indices.contains(index) { fire(shortcutActions[index]) }
    }

    // MARK: Action

    private typealias DockNotification = @convention(c) (CFString, Int32) -> Void

    /// Asks the Dock directly, which is instant. macOS has no public API for this, so the private
    /// function is looked up at runtime; if Apple removes it, Mission Control falls back to
    /// launching its app, which works but takes noticeably longer. The other actions have no fallback.
    private static let sendToDock: DockNotification? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: DockNotification.self)
    }()

    private func fire(_ action: Action) {
        DispatchQueue.main.async {
            if let sendToDock = Self.sendToDock {
                sendToDock(action.dockNotification as CFString, 0)
            } else if action == .missionControl {
                _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "Mission Control"])
            }
        }
    }
}
