import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut through Carbon's RegisterEventHotKey — the one API
/// that needs no Accessibility or Input Monitoring permission. It only sees
/// its own key combination, never other keystrokes.
final class HotKey {

    static let displayString = "⌃⌥⌘I"
    static let keyEquivalent = "i"
    static let modifierFlags: NSEvent.ModifierFlags = [.control, .option, .command]

    /// False when another app already owns the combination.
    private(set) var isRegistered = false

    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let id = EventHotKeyID(signature: OSType(0x4350_5354), id: 1) // "CPST"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_I), UInt32(controlKey | optionKey | cmdKey),
                                         id, GetApplicationEventTarget(), 0, &hotKey)
        isRegistered = status == noErr
        if !isRegistered { NSLog("[capstand] could not register \(Self.displayString): \(status)") }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
