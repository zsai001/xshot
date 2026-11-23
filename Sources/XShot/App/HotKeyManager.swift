import AppKit
import Carbon
import Foundation

public struct HotKeyBinding: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public var displayLabel: String {
        var result = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { result += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { result += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { result += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    public static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
             kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12:
            return true
        default:
            return false
        }
    }

    public static func isModifierOnlyKey(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    /// Validates an AppKit keyDown event and turns it into a valid global shortcut binding.
    /// Requires at least one of Command / Control / Option (unless using F1–F12).
    public static func from(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> HotKeyBinding? {
        let code = UInt32(keyCode)
        guard !isModifierOnlyKey(code) else { return nil }
        guard Int(code) != kVK_Escape else { return nil }

        let mods = carbonModifiers(from: modifierFlags)
        let hasPrimaryMod = (mods & UInt32(cmdKey | optionKey | controlKey)) != 0
        guard hasPrimaryMod || isFunctionKey(code) else { return nil }
        return HotKeyBinding(keyCode: code, carbonModifiers: mods)
    }

    public static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return "#\(keyCode)"
        }
    }
}

public enum GlobalHotKeyAction: UInt32, CaseIterable, Identifiable, Codable, Sendable {
    case captureArea = 1       // ⇧⌘2
    case captureWindow = 2     // ⇧⌘6
    case captureScroll = 7     // ⇧⌘5
    case extractTextArea = 6   // ⇧⌘0
    case beautifyClipboard = 5 // ⇧⌘9
    case recordArea = 3        // ⇧⌘7
    case stopRecording = 4     // ⇧⌘8

    public var id: UInt32 { rawValue }

    public var defaultBinding: HotKeyBinding {
        let cmdShift = UInt32(cmdKey | shiftKey)
        switch self {
        case .captureArea: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: cmdShift)
        case .captureWindow: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_6), carbonModifiers: cmdShift)
        case .captureScroll: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: cmdShift)
        case .extractTextArea: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_0), carbonModifiers: cmdShift)
        case .beautifyClipboard: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_9), carbonModifiers: cmdShift)
        case .recordArea: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_7), carbonModifiers: cmdShift)
        case .stopRecording: return HotKeyBinding(keyCode: UInt32(kVK_ANSI_8), carbonModifiers: cmdShift)
        }
    }

    public var shortcutLabel: String {
        defaultBinding.displayLabel
    }

    public var title: String {
        switch self {
        case .captureArea: return L10n.t(.hkAreaShot)
        case .captureWindow: return L10n.t(.hkWindowShot)
        case .captureScroll: return L10n.t(.hkScrollShot)
        case .recordArea: return L10n.t(.hkRecordArea)
        case .stopRecording: return L10n.t(.hkStopRecord)
        case .beautifyClipboard: return L10n.t(.hkClipboardBeautify)
        case .extractTextArea: return L10n.t(.hkExtractText)
        }
    }
}

public enum HotKeyUpdateResult: Equatable, Sendable {
    case updated(HotKeyBinding)
    case conflict(GlobalHotKeyAction)
}

/// Carbon RegisterEventHotKey manager — works reliably system-wide without needing Accessibility permissions,
/// supports live user customization with UserDefaults persistence and conflict detection.
public final class HotKeyManager {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let registerWithSystem: Bool

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var onTrigger: ((GlobalHotKeyAction) -> Void)?
    private var isSuspended: Bool = false

    public private(set) var bindings: [GlobalHotKeyAction: HotKeyBinding] = [:]

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "xshot.customHotKeys.v1",
        registerWithSystem: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.registerWithSystem = registerWithSystem
        self.bindings = Self.loadBindings(from: userDefaults, key: storageKey)
    }

    deinit {
        unregisterAll()
    }

    public func binding(for action: GlobalHotKeyAction) -> HotKeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    public func label(for action: GlobalHotKeyAction) -> String {
        binding(for: action).displayLabel
    }

    public func isCustomized(_ action: GlobalHotKeyAction) -> Bool {
        binding(for: action) != action.defaultBinding
    }

    public var hasAnyCustomization: Bool {
        GlobalHotKeyAction.allCases.contains { isCustomized($0) }
    }

    public func registerDefaults(onTrigger: @escaping (GlobalHotKeyAction) -> Void) {
        self.onTrigger = onTrigger
        reregisterActiveBindings()
    }

    @discardableResult
    public func updateBinding(_ newBinding: HotKeyBinding, for action: GlobalHotKeyAction) -> HotKeyUpdateResult {
        for other in GlobalHotKeyAction.allCases where other != action {
            if binding(for: other) == newBinding {
                return .conflict(other)
            }
        }
        bindings[action] = newBinding
        saveBindings()
        reregisterActiveBindings()
        return .updated(newBinding)
    }

    public func resetBinding(for action: GlobalHotKeyAction) {
        bindings[action] = action.defaultBinding
        saveBindings()
        reregisterActiveBindings()
    }

    public func resetAllToDefaults() {
        for action in GlobalHotKeyAction.allCases {
            bindings[action] = action.defaultBinding
        }
        userDefaults.removeObject(forKey: storageKey)
        reregisterActiveBindings()
    }

    /// Temporarily suspends system-wide Carbon triggers while the user is recording a new shortcut in Settings.
    public func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended {
            unregisterHotKeysOnly()
        } else {
            reregisterActiveBindings()
        }
    }

    private func reregisterActiveBindings() {
        guard registerWithSystem else { return }
        unregisterAll()
        guard !isSuspended, onTrigger != nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let userData, let eventRef else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr, let action = GlobalHotKeyAction(rawValue: hotKeyID.id) {
                    DispatchQueue.main.async {
                        manager.onTrigger?(action)
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else { return }

        let signature: OSType = 0x58534854 // 'XSHT'
        for action in GlobalHotKeyAction.allCases {
            let b = binding(for: action)
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: action.rawValue)
            let regStatus = RegisterEventHotKey(
                b.keyCode,
                b.carbonModifiers,
                hkID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if regStatus == noErr, let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    private func unregisterHotKeysOnly() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    public func unregisterAll() {
        unregisterHotKeysOnly()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    private func saveBindings() {
        let rawMap = Dictionary(uniqueKeysWithValues: bindings.map { (String($0.key.rawValue), $0.value) })
        if let data = try? JSONEncoder().encode(rawMap) {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    private static func loadBindings(from defaults: UserDefaults, key: String) -> [GlobalHotKeyAction: HotKeyBinding] {
        var result: [GlobalHotKeyAction: HotKeyBinding] = [:]
        for action in GlobalHotKeyAction.allCases {
            result[action] = action.defaultBinding
        }
        guard let data = defaults.data(forKey: key),
              let rawMap = try? JSONDecoder().decode([String: HotKeyBinding].self, from: data) else {
            return result
        }
        for (rawID, binding) in rawMap {
            if let id = UInt32(rawID), let action = GlobalHotKeyAction(rawValue: id) {
                result[action] = binding
            }
        }
        return result
    }
}
