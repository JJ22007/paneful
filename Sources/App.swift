// The menu bar app: status item, menu, and applying the config to hotkeys.

import AppKit
import ServiceManagement

/// English or Simplified Chinese, following the system language. Used for the messages people
/// see when something goes wrong; the rest of the interface is English.
func L(_ en: String, _ zh: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let snapper = DragSnapper()
    private let welcome = WelcomeWindowController()
    /// Shortcuts that failed to register (taken by another app), flagged in the menu
    private var takenKeys: Set<String> = []
    private var explaining = false
    private var wasTrusted = AX.trusted

    private var store: ConfigStore { ConfigStore.shared }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = menuBarIcon()
        statusItem.button?.toolTip = "Paneful"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        WindowManager.shared.onUntrusted = { [weak self] in self?.explainPermission() }
        store.onChange = { [weak self] in self?.applyConfig() }
        store.start()
        applyConfig()
        CLI.startServer()
        logLine("launch accessibility=\(AX.trusted) adhoc=\(AX.adHocSigned) takenShortcuts=\(takenKeys.sorted())")
        updateStatusIcon()
        // The permission can disappear while Paneful runs (a rebuild, or the user switching it off).
        // Dim the icon so it is obvious, instead of shortcuts silently doing nothing.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateStatusIcon() }

        if !UserDefaults.standard.bool(forKey: "onboarded") {
            welcome.show()
        } else if !AX.trusted {
            AX.promptForTrust()
        }
    }

    private func updateStatusIcon() {
        let now = AX.trusted
        if now != wasTrusted { logLine("accessibility changed: \(now)"); wasTrusted = now }
        statusItem.button?.appearsDisabled = !now
        statusItem.button?.toolTip = now ? "Paneful" : L("Paneful: Accessibility permission needed", "Paneful:需要辅助功能权限")
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
            menu.addItem(item(L("Accessibility Permission Needed…", "需要辅助功能权限…"), #selector(openAccessibility), symbol: "exclamationmark.triangle.fill"))
            menu.addItem(.separator())
        }
        var problems = cfg.warnings()
        if let e = store.parseError { problems.insert(e + " (still using the last good config)", at: 0) }
        problems += takenKeys.sorted().map {
            L("Shortcut \(KeyCombo.parse($0)?.pretty ?? $0) is taken by another app", "快捷键 \(KeyCombo.parse($0)?.pretty ?? $0) 已被其他 App 占用")
        }
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
            if #available(macOS 14, *) {
                menu.addItem(.sectionHeader(title: "Custom"))
            } else {
                let header = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }
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
    @objc private func openAccessibility() { explaining = false; explainPermission(force: true) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Couldn't change Launch at Login", "无法更改「登录时打开」")
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// A shortcut was pressed without the permission: say why instead of just beeping
    private func explainPermission(force: Bool = false) {
        if !force { logLine("action blocked: no accessibility permission") }
        guard !explaining else { return }
        explaining = true
        defer { explaining = false }
        let alert = NSAlert()
        alert.messageText = L("Paneful needs the Accessibility permission", "Paneful 需要辅助功能权限")
        var text = L("Without it, Paneful can't move other apps' windows. Paneful uses it only to read and set window positions.",
                     "没有这个权限,Paneful 无法移动其他 App 的窗口。Paneful 只用它来读取和设置窗口位置。")
        text += "\n\n" + L("If Paneful is already switched on in the list but nothing happens, that entry belongs to an older build: select it, click “−” to remove it, then add Paneful again.",
                            "如果列表里 Paneful 已经是打开的,但仍然没反应,说明那一条属于旧的构建:选中它,点「−」删掉,再重新添加 Paneful。")
        if AX.adHocSigned {
            text += "\n\n" + L("This copy is ad-hoc signed, so macOS forgets the permission every time it is rebuilt. Run scripts/setup-signing.sh once in the source folder to stop that.",
                                "这一份是临时签名(ad-hoc)构建的,每次重新编译 macOS 都会忘掉这个权限。在源码目录里运行一次 scripts/setup-signing.sh 就不会再这样。")
        }
        alert.informativeText = text
        alert.addButton(withTitle: L("Open System Settings", "打开系统设置"))
        alert.addButton(withTitle: L("Later", "稍后"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { AX.promptForTrust(); AX.openSettings() }
    }
}
