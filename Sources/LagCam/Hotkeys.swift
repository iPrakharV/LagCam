import Carbon.HIToolbox

/// System-wide ⌃⌥ hotkeys via Carbon. Works while Meet/Zoom is focused and,
/// unlike event taps, needs no Accessibility permission.
final class HotkeyManager {
    enum Key: UInt32 {
        case one, two, three, four, d, r

        var keyCode: UInt32 {
            switch self {
            case .one: return UInt32(kVK_ANSI_1)
            case .two: return UInt32(kVK_ANSI_2)
            case .three: return UInt32(kVK_ANSI_3)
            case .four: return UInt32(kVK_ANSI_4)
            case .d: return UInt32(kVK_ANSI_D)
            case .r: return UInt32(kVK_ANSI_R)
            }
        }
    }

    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4C_41_47_43 // 'LAGC'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.actions[hotKeyID.id]?()
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Registers ⌃⌥ + key.
    func register(_ key: Key, action: @escaping () -> Void) {
        let id = EventHotKeyID(signature: Self.signature, id: key.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            key.keyCode, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
            actions[key.rawValue] = action
        }
    }
}
