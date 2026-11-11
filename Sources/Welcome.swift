// 欢迎与配置引导:四步 —— 欢迎 → 授权 → 快捷键 → 定制。
// 第一次启动时自动出现,之后可以从菜单栏的「欢迎与教程…」再打开。

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
        } catch { logLine("开机启动设置失败:\(error.localizedDescription)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// 欢迎页最后一步展示的示例配置
let exampleSnippet = """
{
  "gap": 8,
  "shortcuts": { "maximize": "ctrl+alt+m" },
  "custom": [
    { "name": "写代码", "key": "ctrl+alt+1",
      "x": 0, "y": 0, "w": 0.62, "h": 1 },
    { "name": "看文档", "key": "ctrl+alt+2",
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
                    Button("上一步") { model.step -= 1 }
                        .buttonStyle(SecondaryButton())
                }
                Button(model.step == WelcomeModel.stepCount - 1 ? "完成" : (model.step == 0 ? "开始" : "继续")) {
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

// MARK: - 第 1 步:欢迎

private struct IntroStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            AppBadge().frame(width: 84, height: 84)
            Text("分屏 Fenping")
                .font(.system(size: 30, weight: .semibold))
                .padding(.top, 20)
            Text("一个你能完全读懂、也能完全改写的 macOS 分屏工具。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 16) {
                Feature(icon: "keyboard", title: "键盘分屏", detail: "半屏、四分之一、三分之一,快捷键与 Rectangle 一致。")
                Feature(icon: "square.grid.2x2", title: "一键排列", detail: "按一下,桌面上所有窗口自动铺开,按数量选布局。")
                Feature(icon: "curlybraces", title: "一个文件定制一切", detail: "快捷键、自定义位置、排列规则都在一份 JSON 里,保存即生效。")
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

// MARK: - 第 2 步:授权

private struct PermissionStep: View {
    @ObservedObject var model: WelcomeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "允许 Fenping 移动窗口",
                       subtitle: "macOS 要求你亲自授权,App 才能调整别的 App 的窗口。Fenping 只用它来读取和设置窗口的位置与大小,不联网、不收集任何数据。")

            HStack(spacing: 12) {
                Image(systemName: model.trusted ? "checkmark.circle.fill" : "hand.raised.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(model.trusted ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.trusted ? "已授权" : "等待授权")
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.trusted ? "一切就绪,可以继续了。" : "打开后这里会自动变成「已授权」。")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.trusted {
                    Button("打开系统设置") { AX.promptForTrust(); AX.openSettings() }
                        .buttonStyle(PrimaryButton())
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 10) {
                NumberedLine(n: 1, text: "点「打开系统设置」,进入 隐私与安全性 → 辅助功能")
                NumberedLine(n: 2, text: "找到 Fenping,打开右边的开关")
                NumberedLine(n: 3, text: "回到这里继续")
            }
            .padding(.top, 24)

            Spacer(minLength: 0)
            Label("开关已经开着却仍显示「等待授权」?那是旧版本留下的记录:选中 Fenping 点「−」删除,再重新打开开关。自己从源码编译后常会遇到。", systemImage: "info.circle")
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

// MARK: - 第 3 步:快捷键

private struct ShortcutsStep: View {
    private struct Card: Identifiable {
        let id = UUID()
        let title: String, units: [CGRect], keys: [String]
    }

    private func pretty(_ a: Action) -> String {
        let s = ConfigStore.shared.config.shortcuts[a.rawValue] ?? a.defaultShortcut
        return KeyCombo.parse(s)?.pretty ?? "未设置"
    }

    private var cards: [Card] {
        [
            Card(title: "左 / 右半屏", units: Action.leftHalf.glyphUnits, keys: [pretty(.leftHalf), pretty(.rightHalf)]),
            Card(title: "最大化", units: Action.maximize.glyphUnits, keys: [pretty(.maximize)]),
            Card(title: "一键排列", units: Action.tileAll.glyphUnits, keys: [pretty(.tileAll)]),
            Card(title: "四个角", units: Action.topLeft.glyphUnits, keys: [pretty(.topLeft), pretty(.topRight), pretty(.bottomLeft), pretty(.bottomRight)]),
            Card(title: "三分之一", units: Action.centerThird.glyphUnits, keys: [pretty(.firstThird), pretty(.centerThird), pretty(.lastThird)]),
            Card(title: "还原", units: Action.restore.glyphUnits, keys: [pretty(.restore)]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "记住这几个键就够了",
                       subtitle: "先点一下想移动的窗口,再按快捷键。全部动作也都在菜单栏图标里。")
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
            Label("连按 \(pretty(.leftHalf)):宽度在 1/2 → 2/3 → 1/3 之间切换。", systemImage: "lightbulb")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
    }
}

private struct FlowKeys: View {
    let keys: [String]
    var body: some View {
        // 最多四个键帽,两行排开
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

// MARK: - 第 4 步:定制

private struct CustomizeStep: View {
    @ObservedObject var model: WelcomeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "把它变成你自己的",
                       subtitle: "所有设置都在一份 JSON 里。改完保存,立即生效,不用重启。")

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("~/.config/fenping/config.json")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    Divider()
                    Text(exampleSnippet)
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .frame(width: 336)

                VStack(alignment: .leading, spacing: 13) {
                    Explain(key: "shortcuts", text: "改掉任何一个快捷键")
                    Explain(key: "custom", text: "你自己的位置,用 0~1 的屏幕比例描述")
                    Explain(key: "tile", text: "一键排列时,几个窗口怎么分行")
                    Explain(key: "gap", text: "窗口之间留多少空隙")

                    VStack(alignment: .leading, spacing: 8) {
                        Button("打开配置文件") { NSWorkspace.shared.open(ConfigStore.url) }
                            .buttonStyle(SecondaryButton())
                        Button("查看更多示例") { NSWorkspace.shared.open(URL(string: repoURL + "/tree/main/examples")!) }
                            .buttonStyle(SecondaryButton())
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text("想改得更彻底?整个 App 是约一千五百行、没有依赖的 Swift。Fork 之后把仓库交给你的 AI 编程助手,告诉它你想要什么。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("开机启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
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

// MARK: - 公共部件

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

// MARK: - 窗口

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
