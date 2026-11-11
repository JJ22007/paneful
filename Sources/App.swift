// 菜单栏 App:状态栏图标、菜单、把配置应用到热键上。

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let snapper = DragSnapper()
    private let welcome = WelcomeWindowController()
    /// 注册失败(被别的 App 占用)的快捷键,用于在菜单里标出来
    private var takenKeys: Set<String> = []
    private var explaining = false

    private var store: ConfigStore { ConfigStore.shared }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = glyphImage([CGRect(x: 0, y: 0, width: 0.46, height: 1)], size: NSSize(width: 19, height: 14))
        statusItem.button?.toolTip = "分屏 Fenping"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        WindowManager.shared.onUntrusted = { [weak self] in self?.explainPermission() }
        store.onChange = { [weak self] in self?.applyConfig() }
        store.start()
        applyConfig()
        logLine("启动 辅助功能权限=\(AX.trusted) 被占用的快捷键=\(takenKeys.sorted())")

        if !UserDefaults.standard.bool(forKey: "onboarded") {
            welcome.show()
        } else if !AX.trusted {
            AX.promptForTrust()
        }
    }

    /// 配置变了(启动、手动编辑、菜单里改设置)之后重新注册热键
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

    // MARK: 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cfg = store.config

        if !AX.trusted {
            menu.addItem(item("需要开启「辅助功能」权限…", #selector(openAccessibility), symbol: "exclamationmark.triangle.fill"))
            menu.addItem(.separator())
        }
        var problems = cfg.warnings()
        if let e = store.parseError { problems.insert(e + "(仍在使用上一份配置)", at: 0) }
        problems += takenKeys.sorted().map { "快捷键 \(KeyCombo.parse($0)?.pretty ?? $0) 已被别的 App 占用" }
        if !problems.isEmpty {
            let head = item("配置有 \(problems.count) 处问题", nil, symbol: "exclamationmark.triangle")
            let sub = NSMenu()
            for p in problems {
                let it = NSMenuItem(title: p, action: nil, keyEquivalent: "")
                it.isEnabled = false
                sub.addItem(it)
            }
            sub.addItem(.separator())
            sub.addItem(item("打开配置文件…", #selector(openConfig)))
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
            menu.addItem(.sectionHeader(title: "自定义"))
            for (i, l) in cfg.custom.enumerated() {
                let it = item(l.name, #selector(runCustom(_:)), key: l.key)
                it.image = glyphImage([l.unit])
                it.tag = i
                menu.addItem(it)
            }
            menu.addItem(.separator())
        }

        let drag = item("拖到屏幕边缘吸附", #selector(toggleDrag))
        drag.state = cfg.dragSnap ? .on : .off
        menu.addItem(drag)

        let gapItem = item("窗口间距", nil)
        let gapMenu = NSMenu()
        var gaps = [0, 4, 8, 12, 16]
        if !gaps.contains(Int(cfg.gap)) { gaps.append(Int(cfg.gap)); gaps.sort() }
        for g in gaps {
            let it = item(g == 0 ? "无" : "\(g) pt", #selector(setGap(_:)))
            it.tag = g
            it.state = Int(cfg.gap) == g ? .on : .off
            gapMenu.addItem(it)
        }
        gapItem.submenu = gapMenu
        menu.addItem(gapItem)

        let login = item("开机自动启动", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("编辑配置文件…", #selector(openConfig), symbol: "curlybraces"))
        menu.addItem(item("配置示例", #selector(openExamples), symbol: "book"))
        menu.addItem(item("欢迎与教程…", #selector(showWelcome), symbol: "sparkles"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出分屏", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    // MARK: 菜单动作

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
            alert.messageText = "无法修改开机启动"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// 没权限时按了快捷键:明确告诉用户原因,而不是只响一声
    private func explainPermission() {
        logLine("动作被拦下:没有辅助功能权限")
        guard !explaining else { return }
        explaining = true
        defer { explaining = false }
        let alert = NSAlert()
        alert.messageText = "分屏还没有「辅助功能」权限"
        alert.informativeText = "没有这个权限就不能移动别的 App 的窗口。\n\n如果列表里 Fenping 已经是打开的但仍然无效,说明那是旧版本的授权:选中它点「−」删掉,再重新打开开关。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { AX.openSettings() }
    }
}
