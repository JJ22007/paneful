// Shortcuts: parse strings like "ctrl+alt+left" into global hotkeys the system can register.
// Uses Carbon's RegisterEventHotKey, which needs no extra permission.

import AppKit
import Carbon.HIToolbox

struct KeyCombo {
    let code: UInt32
    let carbonMods: UInt32
    let cocoaMods: NSEvent.ModifierFlags
    let menuEquivalent: String  // shown by NSMenuItem
    let pretty: String          // e.g. ⌃⌥←

    /// Key name → (virtual key code, menu character, display symbol)
    static let keys: [String: (Int, String, String)] = {
        var t: [String: (Int, String, String)] = [
            "left": (kVK_LeftArrow, "\u{F702}", "←"), "right": (kVK_RightArrow, "\u{F703}", "→"),
            "up": (kVK_UpArrow, "\u{F700}", "↑"), "down": (kVK_DownArrow, "\u{F701}", "↓"),
            "return": (kVK_Return, "\r", "↩"), "enter": (kVK_Return, "\r", "↩"),
            "delete": (kVK_Delete, "\u{8}", "⌫"), "backspace": (kVK_Delete, "\u{8}", "⌫"),
            "space": (kVK_Space, " ", "␣"), "tab": (kVK_Tab, "\t", "⇥"), "escape": (kVK_Escape, "\u{1B}", "⎋"),
            "-": (kVK_ANSI_Minus, "-", "-"), "=": (kVK_ANSI_Equal, "=", "="),
            "[": (kVK_ANSI_LeftBracket, "[", "["), "]": (kVK_ANSI_RightBracket, "]", "]"),
            ";": (kVK_ANSI_Semicolon, ";", ";"), "'": (kVK_ANSI_Quote, "'", "'"),
            ",": (kVK_ANSI_Comma, ",", ","), ".": (kVK_ANSI_Period, ".", "."),
            "/": (kVK_ANSI_Slash, "/", "/"), "\\": (kVK_ANSI_Backslash, "\\", "\\"), "`": (kVK_ANSI_Grave, "`", "`"),
        ]
        let letters: [(String, Int)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
            ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19),
            ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29), ("o", 31),
            ("u", 32), ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        for (name, code) in letters { t[name] = (code, name, name.uppercased()) }
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, code) in fkeys.enumerated() {
            t["f\(i + 1)"] = (code, String(UnicodeScalar(UInt32(NSF1FunctionKey + i))!), "F\(i + 1)")
        }
        return t
    }()

    /// Parse "ctrl+alt+left". Modifiers: ctrl / alt (opt) / shift / cmd. At least one modifier is required.
    static func parse(_ s: String) -> KeyCombo? {
        let raw = s.lowercased().replacingOccurrences(of: " ", with: "")
        // Allow "ctrl+alt+=" and "ctrl+alt++"
        var parts = raw.split(separator: "+", omittingEmptySubsequences: true).map(String.init)
        if raw.hasSuffix("++") || raw == "+" { parts.append("=") }
        guard let keyName = parts.popLast(), let key = keys[keyName] else { return nil }
        var carbon: UInt32 = 0
        var cocoa: NSEvent.ModifierFlags = []
        for m in parts {
            switch m {
            case "ctrl", "control": carbon |= UInt32(controlKey); cocoa.insert(.control)
            case "alt", "opt", "option": carbon |= UInt32(optionKey); cocoa.insert(.option)
            case "shift": carbon |= UInt32(shiftKey); cocoa.insert(.shift)
            case "cmd", "command": carbon |= UInt32(cmdKey); cocoa.insert(.command)
            default: return nil
            }
        }
        guard carbon != 0 else { return nil }
        let symbols = (cocoa.contains(.control) ? "⌃" : "") + (cocoa.contains(.option) ? "⌥" : "")
            + (cocoa.contains(.shift) ? "⇧" : "") + (cocoa.contains(.command) ? "⌘" : "")
        return KeyCombo(code: UInt32(key.0), carbonMods: carbon, cocoaMods: cocoa, menuEquivalent: key.1, pretty: symbols + key.2)
    }
}

final class HotKeys {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef] = []
    fileprivate var handlers: [UInt32: () -> Void] = [:]
    private var installed = false
    private var nextID: UInt32 = 1

    /// Unregister every hotkey (called before reloading the config)
    func reset() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        handlers = [:]
    }

    /// Register a global hotkey. Returns false when another app already owns the combination.
    @discardableResult
    func add(_ combo: KeyCombo, _ handler: @escaping () -> Void) -> Bool {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                if let h = HotKeys.shared.handlers[hk.id] { DispatchQueue.main.async(execute: h) }
                return noErr
            }, 1, &spec, nil, nil)
        }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.code, combo.carbonMods, EventHotKeyID(signature: 0x4650_4E47, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let r = ref else { return false }
        refs.append(r)
        handlers[id] = handler
        return true
    }
}
