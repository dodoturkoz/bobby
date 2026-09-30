import Carbon
import Foundation

final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (() -> Void)?

    static let choices: [(id: String, label: String, key: UInt32, modifiers: UInt32)] = [
        ("controlOptionB", "⌃⌥B", UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey)),
        ("controlOptionSpace", "⌃⌥Space", UInt32(kVK_Space), UInt32(controlKey | optionKey)),
        ("optionB", "⌥B", UInt32(kVK_ANSI_B), UInt32(optionKey)),
        ("commandShiftB", "⌘⇧B", UInt32(kVK_ANSI_B), UInt32(cmdKey | shiftKey))
    ]

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(pointer).takeUnretainedValue()
            shortcut.onTrigger?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func register(_ choice: String) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        let selected = Self.choices.first(where: { $0.id == choice }) ?? Self.choices[0]
        let id = EventHotKeyID(signature: OSType(0x424F4259), id: 1)
        return RegisterEventHotKey(selected.key, selected.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
