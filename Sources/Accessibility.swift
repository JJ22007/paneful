// A thin wrapper over the macOS Accessibility API: find windows, read frames, set frames.
// This is the only part of the app that needs the Accessibility permission.

import AppKit
import ApplicationServices

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Show the system prompt that asks for the permission
    static func promptForTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &v) == .success, let w = v else { return nil }
        return (w as! AXUIElement)
    }

    static func frame(of w: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    static func setFrame(_ r: CGRect, of w: AXUIElement) {
        // Some apps (Chrome, Electron) animate slowly while AXEnhancedUserInterface is on; switch it off briefly
        var pid: pid_t = 0
        AXUIElementGetPid(w, &pid)
        let appEl = AXUIElementCreateApplication(pid)
        var enh: CFTypeRef?
        let hadEnhanced = AXUIElementCopyAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, &enh) == .success && (enh as? Bool) == true
        if hadEnhanced { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }

        var pt = r.origin, sz = r.size
        let pv = AXValueCreate(.cgPoint, &pt)!, sv = AXValueCreate(.cgSize, &sz)!
        // Size → position → size: across displays the first resize can be clamped by the old screen
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)

        if hadEnhanced { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    static func setOrigin(_ p: CGPoint, of w: AXUIElement) {
        var pt = p
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pt)!)
    }

    /// Every visible standard window on the current desktop, front to back
    static func windowsFrontToBack() -> [(window: AXUIElement, frame: CGRect)] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var cache: [pid_t: [(window: AXUIElement, frame: CGRect)]] = [:]
        var result: [(window: AXUIElement, frame: CGRect)] = []
        let me = getpid()
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b), rect.width > 120, rect.height > 120 else { continue }
            if cache[pid] == nil { cache[pid] = standardWindows(pid) }
            if let i = cache[pid]!.firstIndex(where: { nearlyEqual($0.frame, rect, tol: 2) }) {
                result.append(cache[pid]!.remove(at: i))
            }
        }
        return result
    }

    private static func standardWindows(_ pid: pid_t) -> [(window: AXUIElement, frame: CGRect)] {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.5)  // don't let a hung app stall us
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &v) == .success,
              let wins = v as? [AXUIElement] else { return [] }
        func attr(_ w: AXUIElement, _ name: String) -> CFTypeRef? {
            var x: CFTypeRef?
            return AXUIElementCopyAttributeValue(w, name as CFString, &x) == .success ? x : nil
        }
        return wins.compactMap { w in
            guard (attr(w, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                  (attr(w, kAXMinimizedAttribute) as? Bool) != true,
                  (attr(w, "AXFullScreen") as? Bool) != true,
                  let f = frame(of: w) else { return nil }
            return (w, f)
        }
    }
}

/// Append a line to ~/Library/Logs/Paneful.log, for troubleshooting
func logLine(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Paneful.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}
