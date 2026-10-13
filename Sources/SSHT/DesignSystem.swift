import SwiftUI
import AppKit

// Raw colors and measurements from Figma frame 2:844.
enum UITheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let text = adaptive(0x25262a, 0xe8e9ec)
    static let secondary = adaptive(0x767980, 0x9b9ea7)
    static let muted = adaptive(0x96999f, 0x868a94)
    static let canvas = adaptive(0xffffff, 0x1d1e22)
    static let toolbar = adaptive(0xf6f6f7, 0x26272d)
    static let sidebar = adaptive(0xfafafb, 0x222329)
    static let border = adaptive(0xe5e6e9, 0x383a43)
    static let inputBorder = adaptive(0xd5d7dc, 0x454853)
    static let selection = adaptive(0xedf5ff, 0x1b3351)
    static let accent = Color(red: 0, green: 122 / 255, blue: 1)
    static let green = adaptive(0x24854c, 0x65cc8a)
    static let danger = adaptive(0xc64343, 0xff8686)
}

struct FigmaIcon: View {
    let name: String
    @Environment(\.colorScheme) private var scheme
    static let sizes: [String: CGFloat] = ["square":14,"plus":14,"settings":18,"search":13,"arrow-active":16,"arrow":16,"status-active":6,"status-idle":6,"info":13,"laptop":14,"server":14,"lock":13,"trash":16,"terminal":12,"close":12,"laptop-modal":15,"server-modal":15,"chevrons":12]
    static var images: [String: NSImage] = {
        var images = [String: NSImage]()
        for name in sizes.keys {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("Figma/\(name).png")
            if let url = bundled, let image = NSImage(contentsOf: url) { images[name] = image }
            else if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Figma"), let image = NSImage(contentsOf: url) { images[name] = image }
        }
        return images
    }()
    var body: some View {
        if let image = Self.images[name] {
            Image(nsImage: image).resizable().renderingMode(scheme == .dark && !name.hasPrefix("status") ? .template : .original)
                .frame(width: Self.sizes[name] ?? 14, height: Self.sizes[name] ?? 14)
                .foregroundStyle(name == "plus" ? Color.white : name == "arrow-active" ? UITheme.accent : UITheme.secondary)
                .accessibilityHidden(true)
        }
    }
}
struct FlatButtonStyle: ButtonStyle {
    var primary = false
    var height: CGFloat = 32
    var horizontalPadding: CGFloat = 12
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fixedSize(horizontal: true, vertical: false).font(.system(size: 12, weight: .medium))
            .foregroundStyle(primary ? Color.white : UITheme.text)
            .padding(.horizontal, horizontalPadding).frame(height: height)
            .background(primary ? UITheme.accent : UITheme.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? UITheme.accent : UITheme.inputBorder, lineWidth: 1))
            .opacity(enabled ? configuration.isPressed ? 0.7 : 1 : 0.45)
    }
}
struct UIField: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var monospaced = false
    var height: CGFloat = 32
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(UITheme.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .foregroundStyle(UITheme.text).padding(.horizontal, 10).frame(height: height)
                .background(enabled ? UITheme.canvas : UITheme.toolbar, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.inputBorder, lineWidth: 1))
                .accessibilityLabel(title)
        }
    }
}
struct SectionLabel: View {
    let title: String
    let icon: String
    var body: some View { HStack(spacing: 6) { FigmaIcon(name: icon); Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(UITheme.text) } }
}
struct RuleStatus: View {
    let state: TunnelState
    var body: some View {
        HStack(spacing: 5) {
            if state.status == .connected || state.status == .external { FigmaIcon(name: "status-active") }
            else if state.status == .connecting || state.status == .stopping { Circle().fill(Color.orange).frame(width: 6, height: 6) }
            else if state.status == .occupied { Circle().fill(Color.orange).frame(width: 6, height: 6) }
            else if state.status == .failed { Circle().fill(UITheme.danger).frame(width: 6, height: 6) }
            else { FigmaIcon(name: "status-idle") }
            Text(state.status == .connected ? "运行中" : state.status == .idle ? "已停止" : state.status.rawValue)
                .font(.system(size: 11)).foregroundStyle(state.status == .connected || state.status == .external ? UITheme.green : state.status == .failed ? UITheme.danger : UITheme.secondary)
        }.fixedSize()
    }
}
struct Hairline: View {
    var body: some View { Rectangle().fill(UITheme.border).frame(height: 1) }
}
struct ProtocolControl: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("协议").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
            HStack(spacing: 3) {
                Text("TCP").font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).frame(height: 26)
                    .background(UITheme.toolbar, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(UITheme.inputBorder, lineWidth: 1))
                Text("UDP").font(.system(size: 12)).foregroundStyle(UITheme.secondary).frame(maxWidth: .infinity).help("OpenSSH 不支持 UDP 端口转发")
            }.padding(3).frame(height: 32).background(UITheme.canvas, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.inputBorder, lineWidth: 1))
                .accessibilityElement(children: .ignore).accessibilityLabel("协议 TCP；OpenSSH 不支持 UDP")
        }
    }
}

// Use standalone AppKit window buttons in the Figma toolbar slot. The original
// titlebar buttons stay owned by AppKit; hiding them avoids duplicate controls.
struct WindowControls: NSViewRepresentable {
    final class ControlsView: NSView {
        private weak var configuredWindow: NSWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            for view in subviews { view.removeFromSuperview() }
            // Scale an independent child, leaving SwiftUI layout coordinates intact.
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 52, height: 12))
            container.bounds = NSRect(x: 0, y: 0, width: 52 * 14 / 12, height: 14)
            addSubview(container)
            let controls: [(NSWindow.ButtonType, Selector, String)] = [
                (.closeButton, #selector(NSWindow.performClose(_:)), "关闭窗口"),
                (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:)), "最小化窗口"),
                (.zoomButton, #selector(NSWindow.toggleFullScreen(_:)), "全屏窗口")
            ]
            for (index, entry) in controls.enumerated() {
                window.standardWindowButton(entry.0)?.isHidden = true
                guard let button = NSWindow.standardWindowButton(entry.0, for: window.styleMask) else { continue }
                button.target = window
                button.action = entry.1
                button.frame = NSRect(x: CGFloat(index) * 20 * 14 / 12, y: 0, width: 14, height: 14)
                button.setAccessibilityLabel(entry.2)
                container.addSubview(button)
            }
        }
    }
    func makeNSView(context: Context) -> ControlsView { ControlsView() }
    func updateNSView(_ nsView: ControlsView, context: Context) {}
}
