// Welcome and setup guide, four steps: intro → permission → shortcuts → customize.
// Shown automatically on first launch, and again from "Welcome Guide…" in the menu.

import AppKit
import ServiceManagement
import SwiftUI

final class WelcomeModel: ObservableObject {
    @Published var step = 0
    @Published var trusted = AX.trusted
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onFinish: () -> Void = {}
    private var timer: Timer?

    static let stepCount = 4

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let now = AX.trusted
            if self?.trusted != now { self?.trusted = now }
        }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { logLine("launch at login failed: \(error.localizedDescription)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// The example config shown on the last step of the guide
let exampleSnippet = """
{
  "gap": 8,
  "shortcuts": { "maximize": "ctrl+alt+m" },
  "custom": [
    { "name": "Code", "key": "ctrl+alt+1",
      "x": 0, "y": 0, "w": 0.62, "h": 1 },
    { "name": "Docs", "key": "ctrl+alt+2",
      "x": 0.62, "y": 0, "w": 0.38, "h": 1 }
  ],
  "tile": {
    "max": 6,
    "rows": { "5": [2, 3] }
  }
}
"""

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: IntroStep()
                case 1: PermissionStep(model: model)
                case 2: ShortcutsStep()
                default: CustomizeStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)

            Divider()
            HStack {
                HStack(spacing: 7) {
                    ForEach(0..<WelcomeModel.stepCount, id: \.self) { i in
                        Capsule()
                            .fill(i == model.step ? Color.accentColor : Color.primary.opacity(0.15))
                            .frame(width: i == model.step ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                if model.step > 0 {
                    Button("Back") { model.step -= 1 }
                        .buttonStyle(SecondaryButton())
                }
                Button(model.step == WelcomeModel.stepCount - 1 ? "Done" : (model.step == 0 ? "Get Started" : "Continue")) {
                    if model.step == WelcomeModel.stepCount - 1 { model.onFinish() } else { model.step += 1 }
                }
                .buttonStyle(PrimaryButton())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 640, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Step 1: intro

private struct IntroStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            AppBadge().frame(width: 84, height: 84)
            Text("Paneful")
                .font(.system(size: 30, weight: .semibold))
                .padding(.top, 20)
            Text("Window tiling for macOS that isn’t painful.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 16) {
                Feature(icon: "keyboard", title: "Keyboard tiling", detail: "Halves, quarters and thirds, with the same shortcuts as Rectangle.")
                Feature(icon: "square.grid.2x2", title: "Tile everything", detail: "One key spreads every window on the desktop into a tidy grid.")
                Feature(icon: "curlybraces", title: "One file to make it yours", detail: "Shortcuts, custom positions and tiling rules live in a single JSON file.")
            }
            .padding(.top, 34)
            .frame(maxWidth: 420, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}

private struct AppBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 14, y: 6)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white)
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.55))
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.55))
                }
            }
            .padding(19)
        }
    }
}

private struct Feature: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Step 2: permission

private struct PermissionStep: View {
    @ObservedObject var model: WelcomeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Let Paneful move windows",
                       subtitle: "macOS asks you to approve any app that arranges other apps’ windows. Paneful only reads and sets window positions and sizes. It never goes online and collects nothing.")

            HStack(spacing: 12) {
                Image(systemName: model.trusted ? "checkmark.circle.fill" : "hand.raised.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(model.trusted ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.trusted ? "Permission granted" : "Waiting for permission")
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.trusted ? "You’re all set. Continue when ready." : "Turns green once you switch it on.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.trusted {
                    Button("Open System Settings") { AX.promptForTrust(); AX.openSettings() }
                        .buttonStyle(PrimaryButton())
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 10) {
                NumberedLine(n: 1, text: "Click Open System Settings. It opens Privacy & Security → Accessibility.")
                NumberedLine(n: 2, text: "Find Paneful in the list and switch it on.")
                NumberedLine(n: 3, text: "Come back here and continue.")
            }
            .padding(.top, 24)

            Spacer(minLength: 0)
            Label("Switched on but still waiting? That entry belongs to an older build. Select Paneful, click “−” to remove it, then switch it on again. If you build from source, run scripts/setup-signing.sh once and this stops happening.", systemImage: "info.circle")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
        }
    }
}

private struct NumberedLine: View {
    let n: Int, text: String
    var body: some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            Text(text).font(.system(size: 13))
        }
    }
}

// MARK: - Step 3: shortcuts

private struct ShortcutsStep: View {
    private struct Card: Identifiable {
        let id = UUID()
        let title: String, units: [CGRect], keys: [String]
    }

    private func pretty(_ a: Action) -> String {
        let s = ConfigStore.shared.config.shortcuts[a.rawValue] ?? a.defaultShortcut
        return KeyCombo.parse(s)?.pretty ?? "not set"
    }

    private var cards: [Card] {
        [
            Card(title: "Left / right half", units: Action.leftHalf.glyphUnits, keys: [pretty(.leftHalf), pretty(.rightHalf)]),
            Card(title: "Maximize", units: Action.maximize.glyphUnits, keys: [pretty(.maximize)]),
            Card(title: "Tile everything", units: Action.tileAll.glyphUnits, keys: [pretty(.tileAll)]),
            Card(title: "Corners", units: Action.topLeft.glyphUnits, keys: [pretty(.topLeft), pretty(.topRight), pretty(.bottomLeft), pretty(.bottomRight)]),
            Card(title: "Thirds", units: Action.centerThird.glyphUnits, keys: [pretty(.firstThird), pretty(.centerThird), pretty(.lastThird)]),
            Card(title: "Restore", units: Action.restore.glyphUnits, keys: [pretty(.restore)]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "The only keys you need",
                       subtitle: "Click the window you want to move, then press a shortcut. Every action is also in the menu bar icon.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(cards) { c in
                    VStack(alignment: .leading, spacing: 10) {
                        LayoutGlyph(units: c.units).frame(width: 54, height: 36)
                        Text(c.title).font(.system(size: 13, weight: .semibold))
                        FlowKeys(keys: c.keys)
                    }
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
                }
            }
            .padding(.top, 22)
            Spacer(minLength: 0)
            Label("Press \(pretty(.leftHalf)) again to cycle the width: 1/2 → 2/3 → 1/3.", systemImage: "lightbulb")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
    }
}

private struct FlowKeys: View {
    let keys: [String]
    var body: some View {
        // Up to four key caps, two per row
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(stride(from: 0, to: keys.count, by: 2)), id: \.self) { i in
                HStack(spacing: 4) {
                    ForEach(keys[i..<min(i + 2, keys.count)], id: \.self) { KeyCap(text: $0) }
                }
            }
        }
    }
}

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Step 4: customize

private struct CustomizeStep: View {
    @ObservedObject var model: WelcomeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Make it yours",
                       subtitle: "Every setting lives in one JSON file. Save it and the change applies right away. No restart.")

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("~/.config/paneful/config.json")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    Divider()
                    Text(exampleSnippet)
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .frame(width: 336)

                VStack(alignment: .leading, spacing: 13) {
                    Explain(key: "shortcuts", text: "Rebind any action")
                    Explain(key: "custom", text: "Positions as screen fractions")
                    Explain(key: "tile", text: "Windows per row when tiling")
                    Explain(key: "gap", text: "Space between windows")

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Open Config File") { NSWorkspace.shared.open(ConfigStore.url) }
                            .buttonStyle(SecondaryButton())
                        Button("More Examples") { NSWorkspace.shared.open(URL(string: repoURL + "/tree/main/examples")!) }
                            .buttonStyle(SecondaryButton())
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text("Want more? Paneful is about 1,500 lines of Swift with no dependencies. Fork it, hand the repo to your AI coding agent, and say what you want.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12))
                    .fixedSize()
            }
            .padding(.bottom, 16)
        }
    }
}

private struct Explain: View {
    let key: String, text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.accentColor)
            Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared pieces

private struct StepHeader: View {
    let title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08)))
    }
}

// MARK: - Window

final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = WelcomeModel()

    func show() {
        model.trusted = AX.trusted
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        if window == nil {
            model.step = 0
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView(model: model))
            w.delegate = self
            w.center()
            window = w
            model.onFinish = { [weak self] in self?.window?.close() }
        }
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        UserDefaults.standard.set(true, forKey: "onboarded")
        window = nil
    }
}
