import SwiftUI
import AppKit

// Disambiguate the property wrapper from the newer SDK State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

@main struct Launcher {
    static func main() {
        // OpenSSH invokes this executable with the authentication prompt as its argument.
        if ProcessInfo.processInfo.environment["SSH_ASKPASS_REQUIRE"] == "force",
           ProcessInfo.processInfo.environment["DISPLAY"] == "ssht:0",
           CommandLine.arguments.count > 1 {
            if let secret = ProcessInfo.processInfo.environment["SSHT_SECRET"], !secret.isEmpty {
                print(secret)
            } else {
                let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
                let escaped = prompt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = NSAppleScript(source: "text returned of (display dialog \"\(escaped)\" with title \"SSHT · SSH 身份验证\" default answer \"\" with hidden answer buttons {\"取消\", \"确认\"} default button \"确认\")")
                var error: NSDictionary?
                guard let result = script?.executeAndReturnError(&error), error == nil else { exit(1) }
                print(result.stringValue ?? "")
            }
            exit(0)
        }
        SSHTApp.main()
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: TunnelStore?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { store?.shutdown() } }
}
@MainActor final class AppLifecycle: ObservableObject {
    let store: TunnelStore
    let interface = InterfaceState()
    init(storageDirectory: URL?) {
        store = TunnelStore(storageDirectory: storageDirectory)
    }
}
struct SSHTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var lifecycle: AppLifecycle
    private var store: TunnelStore { lifecycle.store }
    init() {
        let customDirectory = Bundle.main.object(forInfoDictionaryKey: "SSHTStorageDirectory") as? String
        _lifecycle = StateObject(wrappedValue: AppLifecycle(storageDirectory: customDirectory.map { URL(fileURLWithPath: $0) }))
    }
    var body: some Scene {
        Window("端口转发", id: "main") {
            MainView(interface: lifecycle.interface).environmentObject(store)
                .onAppear {
                    delegate.store = store
                    applyAppearance(store.preferences.appearance)
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    store.restoreRules()
                }
        }.defaultSize(width: 1120, height: 760).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("添加规则…") { NotificationCenter.default.post(name: .sshtAddRule, object: nil) }.keyboardShortcut("n") }
            CommandGroup(replacing: .appSettings) { Button("设置…") { NotificationCenter.default.post(name: .sshtSettings, object: nil) }.keyboardShortcut(",") }
            CommandGroup(after: .toolbar) { Button("查看日志") { NotificationCenter.default.post(name: .sshtLogs, object: nil) }.keyboardShortcut("l") }
        }
        MenuBarExtra("端口转发", systemImage: "arrow.left.arrow.right") {
            MenuBarView().environmentObject(store)
        }
    }
}
struct MenuBarView: View {
    @EnvironmentObject var store: TunnelStore
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("打开端口转发") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        ForEach(store.groups, id: \.self) { group in
            Menu(group) {
                Button("开启分组") { store.startGroup(group) }.disabled(!store.canStartGroup(group))
                Button("停止分组") { store.stopGroup(group) }
                    .disabled(!store.items(in: group).contains { store.state($0.id).active })
                Divider()
                ForEach(store.items(in: group)) { item in
                    Button("\(item.name) · \(store.state(item.id).status == .external ? "检查" : store.state(item.id).active ? "停止" : "启动")") {
                        if store.state(item.id).active { store.stop(item.id) } else { store.startRule(item) }
                    }
                }
            }
        }
        Divider()
        Button("全部开启") { store.startAll() }.disabled(!store.canStartAll)
        Button("全部停止") { store.stopAll() }
        Button("退出端口转发") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
extension Notification.Name {
    static let sshtAddRule = Notification.Name("ssht.addRule")
    static let sshtSettings = Notification.Name("ssht.settings")
    static let sshtLogs = Notification.Name("ssht.logs")
}

@MainActor func applyAppearance(_ appearance: AppPreferences.Appearance) {
    switch appearance {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
