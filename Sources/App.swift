// The menu bar app: status item, menu, and applying the config to hotkeys.

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let snapper = DragSnapper()
    private let welcome = WelcomeWindowController()
    /// Shortcuts that failed to register (taken by another app), flagged in the menu
    private var takenKeys: Set<String> = []
    private var explaining = false

    private var store: ConfigStore { ConfigStore.shared }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = glyphImage([CGRect(x: 0, y: 0, width: 0.46, height: 1)], size: NSSize(width: 19, height: 14))
        statusItem.button?.toolTip = "Paneful"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        WindowManager.shared.onUntrusted = { [weak self] in self?.explainPermission() }
        store.onChange = { [weak self] in self?.applyConfig() }
        store.start()
        applyConfig()
        logLine("launch accessibility=\(AX.trusted) takenShortcuts=\(takenKeys.sorted())")

        if !UserDefaults.standard.bool(forKey: "onboarded") {
            welcome.show()
        } else if !AX.trusted {
            AX.promptForTrust()
        }
    }

    /// Re-register every hotkey after the config changes (launch, manual edit, menu toggle)
    private func applyConfig() {
        let cfg = store.config
        HotKeys.shared.reset()
        takenKeys = []
        for a in Action.allCases {
            guard let s = cfg.shortcuts[a.rawValue], let combo = KeyCombo.parse(s) else { continue }
            if !HotKeys.shared.add(combo, { WindowManager.shared.perform(a) }) { takenKeys.insert(s) }
        }
        for layout in cfg.custom {
            guard let s = layout.key, let combo = KeyCombo.parse(s) else { continue }
            if !HotKeys.shared.add(combo, { WindowManager.shared.perform(layout) }) { takenKeys.insert(s) }
        }
        snapper.setEnabled(cfg.dragSnap)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cfg = store.config

        if !AX.trusted {
            menu.addItem(item("Accessibility Permission Needed…", #selector(openAccessibility), symbol: "exclamationmark.triangle.fill"))
            menu.addItem(.separator())
        }
        var problems = cfg.warnings()
        if let e = store.parseError { problems.insert(e + " (still using the last good config)", at: 0) }
        problems += takenKeys.sorted().map { "Shortcut \(KeyCombo.parse($0)?.pretty ?? $0) is taken by another app" }
        if !problems.isEmpty {
            let head = item(problems.count == 1 ? "1 Config Problem" : "\(problems.count) Config Problems", nil, symbol: "exclamationmark.triangle")
            let sub = NSMenu()
            for p in problems {
                let it = NSMenuItem(title: p, action: nil, keyEquivalent: "")
                it.isEnabled = false
                sub.addItem(it)
            }
            sub.addItem(.separator())
            sub.addItem(item("Open Config File…", #selector(openConfig)))
            head.submenu = sub
            menu.addItem(head)
            menu.addItem(.separator())
        }

        for group in Action.groups {
            for a in group {
                let it = item(a.title, #selector(runAction(_:)), key: cfg.shortcuts[a.rawValue])
                it.image = glyphImage(a.glyphUnits)
                it.representedObject = a.rawValue
                menu.addItem(it)
            }
            menu.addItem(.separator())
        }

        if !cfg.custom.isEmpty {
            menu.addItem(.sectionHeader(title: "Custom"))
            for (i, l) in cfg.custom.enumerated() {
                let it = item(l.name, #selector(runCustom(_:)), key: l.key)
                it.image = glyphImage([l.unit])
                it.tag = i
                menu.addItem(it)
            }
            menu.addItem(.separator())
        }

        let drag = item("Snap When Dragged to Screen Edge", #selector(toggleDrag))
        drag.state = cfg.dragSnap ? .on : .off
        menu.addItem(drag)

        let gapItem = item("Window Gap", nil)
        let gapMenu = NSMenu()
        var gaps = [0, 4, 8, 12, 16]
        if !gaps.contains(Int(cfg.gap)) { gaps.append(Int(cfg.gap)); gaps.sort() }
        for g in gaps {
            let it = item(g == 0 ? "None" : "\(g) pt", #selector(setGap(_:)))
            it.tag = g
            it.state = Int(cfg.gap) == g ? .on : .off
            gapMenu.addItem(it)
        }
        gapItem.submenu = gapMenu
        menu.addItem(gapItem)

        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Edit Config File…", #selector(openConfig), symbol: "curlybraces"))
        menu.addItem(item("Example Configs", #selector(openExamples), symbol: "book"))
        menu.addItem(item("Welcome Guide…", #selector(showWelcome), symbol: "sparkles"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Paneful", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector?, key: String? = nil, symbol: String? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        if let k = key, let combo = KeyCombo.parse(k) {
            it.keyEquivalent = combo.menuEquivalent
            it.keyEquivalentModifierMask = combo.cocoaMods
        }
        if let s = symbol { it.image = NSImage(systemSymbolName: s, accessibilityDescription: nil) }
        return it
    }

    // MARK: Menu actions

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let a = Action(rawValue: raw) else { return }
        WindowManager.shared.perform(a)
    }

    @objc private func runCustom(_ sender: NSMenuItem) {
        let list = store.config.custom
        if list.indices.contains(sender.tag) { WindowManager.shared.perform(list[sender.tag]) }
    }

    @objc private func toggleDrag() { store.update { $0.dragSnap.toggle() } }
    @objc private func setGap(_ sender: NSMenuItem) { store.update { $0.gap = Double(sender.tag) } }
    @objc private func openConfig() { NSWorkspace.shared.open(ConfigStore.url) }
    @objc private func openExamples() { NSWorkspace.shared.open(URL(string: repoURL + "/tree/main/examples")!) }
    @objc private func showWelcome() { welcome.show() }
    @objc private func openAccessibility() { AX.promptForTrust(); AX.openSettings() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// A shortcut was pressed without the permission: say why instead of just beeping
    private func explainPermission() {
        logLine("action blocked: no accessibility permission")
        guard !explaining else { return }
        explaining = true
        defer { explaining = false }
        let alert = NSAlert()
        alert.messageText = "Paneful needs the Accessibility permission"
        alert.informativeText = "Without it, Paneful can't move other apps' windows.\n\nIf Paneful is already switched on in the list but nothing happens, that entry belongs to an older build: select it, click “−” to remove it, then switch it on again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { AX.openSettings() }
    }
}
