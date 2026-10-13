import SwiftUI
import AppKit
import ServiceManagement

struct PreferencesSheet: View {
    @EnvironmentObject var store: TunnelStore
    @Environment(\.dismiss) var dismiss
    @ViewState private var loginEnabled = SMAppService.mainApp.status == .enabled
    @ViewState private var changingLogin = false
    @ViewState private var error: String?
    @ViewState private var clearingLogs = false
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "设置", close: { dismiss() }, textClose: true).frame(height: 63)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSection("启动与运行") {
                        VStack(spacing: 0) {
                            preferenceRow("登录时启动", subtitle: "登录 Mac 后自动打开端口转发。") {
                                Toggle("登录时启动", isOn: Binding(get: { loginEnabled }, set: changeLogin)).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(changingLogin)
                            }
                            Hairline()
                            preferenceRow("启动后恢复转发", subtitle: "恢复上次退出时仍在运行的规则。") {
                                Toggle("启动后恢复转发", isOn: $store.preferences.restoreOnLaunch).labelsHidden().toggleStyle(.switch).controlSize(.small)
                            }
                            Hairline()
                            preferenceRow("关闭窗口后在菜单栏运行", subtitle: "关闭窗口不退出应用，转发继续运行。") {
                                Text("始终开启").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                            }
                        }.settingsGroup()
                    }
                    settingsSection("外观") {
                        HStack {
                            Text("应用外观").font(.system(size: 13))
                            Spacer()
                            Picker("应用外观", selection: $store.preferences.appearance) { ForEach(AppPreferences.Appearance.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 290)
                        }.padding(.horizontal, 16).frame(height: 42).settingsGroup()
                    }
                    settingsSection("日志") {
                        VStack(spacing: 0) {
                            preferenceRow("记录连接日志", subtitle: "记录连接状态与错误，便于排查转发问题。") {
                                Toggle("记录连接日志", isOn: $store.preferences.recordLogs).labelsHidden().toggleStyle(.switch).controlSize(.small)
                            }
                            Hairline()
                            preferenceRow("保留时间") {
                                Picker("保留时间", selection: $store.preferences.retentionDays) { ForEach([1, 7, 30], id: \.self) { Text("\($0) 天").tag($0) } }.labelsHidden().frame(width: 136)
                            }
                            Hairline()
                            preferenceRow("日志文件", subtitle: "过期日志会自动清理。") {
                                HStack(spacing: 8) {
                                    Button("打开日志文件夹") {
                                        do { try FileManager.default.createDirectory(at: store.logsDirectory, withIntermediateDirectories: true); NSWorkspace.shared.open(store.logsDirectory) }
                                        catch { self.error = error.localizedDescription }
                                    }.buttonStyle(FlatButtonStyle(height: 34))
                                    Button("清空日志…") { clearingLogs = true }.buttonStyle(FlatButtonStyle(height: 34))
                                }
                            }
                        }.settingsGroup()
                    }
                    if let error { Text(error).font(.system(size: 11)).foregroundStyle(UITheme.danger) }
                    if SMAppService.mainApp.status == .requiresApproval {
                        Button("在系统设置中批准登录启动") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(.link).font(.system(size: 11))
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }.frame(maxHeight: .infinity)
            Hairline()
            HStack {
                Text("设置更改后自动保存").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(FlatButtonStyle(height: 34)).keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 24).frame(height: 63)
        }.frame(width: 560, height: 620).background(UITheme.canvas).foregroundStyle(UITheme.text).tint(UITheme.accent)
            .alert("清空所有连接日志？", isPresented: $clearingLogs) {
                Button("取消", role: .cancel) {}
                Button("清空日志", role: .destructive) { store.clearLogs() }
            } message: { Text("当前日志和已保存的日志文件将被删除，转发规则不受影响。") }
    }
    func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 13, weight: .semibold)); content() }
    }
    func preferenceRow<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(UITheme.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control()
        }.padding(.horizontal, 16).frame(height: 44)
    }
    func changeLogin(_ value: Bool) {
        changingLogin = true
        defer { changingLogin = false }
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            error = nil
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; self.error = "无法更改登录启动：\(error.localizedDescription)" }
    }
}
private extension View {
    func settingsGroup() -> some View {
        background(UITheme.canvas, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UITheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct LogsSheet: View {
    @EnvironmentObject var store: TunnelStore
    @Environment(\.dismiss) var dismiss
    let selectedRule: UUID?
    @ViewState private var saved = ""
    @ViewState private var showHistory = false
    @ViewState private var showCommand = false
    var current: String {
        if let selectedRule { return store.state(selectedRule).log }
        return store.ruleItems.map { "\($0.name)\n\(store.state($0.id).log)" }.joined(separator: "\n")
    }
    var command: String {
        guard let item = store.ruleItems.first(where: { $0.id == selectedRule }), let profile = store.sessionProfile(for: item) else { return "请先选择一条规则。" }
        do { return SSHCommand.display(try SSHCommand.arguments(profile, socket: "/tmp/ssht-preview.sock")) }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "连接日志") { dismiss() }
            Hairline()
            HStack(spacing: 16) {
                Toggle("历史日志", isOn: $showHistory).toggleStyle(.checkbox)
                Toggle("SSH 命令", isOn: $showCommand).toggleStyle(.checkbox)
                Spacer()
                if let item = store.ruleItems.first(where: { $0.id == selectedRule }) { Text(item.name).lineLimit(1).foregroundStyle(UITheme.secondary) }
            }.font(.system(size: 12)).padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showCommand { Text(command).foregroundStyle(UITheme.accent) }
                    Text((showHistory ? saved : current).isEmpty ? "暂无连接日志。启动转发后，状态和错误信息会显示在这里。" : (showHistory ? saved : current))
                }.font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(20)
            }.frame(maxHeight: .infinity).background(UITheme.sidebar)
            Hairline()
            HStack {
                Text(store.preferences.recordLogs ? "日志保留 \(store.preferences.retentionDays) 天" : "日志仅在当前会话显示").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 24).frame(height: 63)
        }.frame(width: 680, height: 560).background(UITheme.canvas).foregroundStyle(UITheme.text).tint(UITheme.accent)
            .onAppear { saved = store.savedLog() }
            .onChange(of: store.logsRevision) { _, _ in if showHistory { saved = store.savedLog() } }
            .onChange(of: showHistory) { _, enabled in if enabled { saved = store.savedLog() } }
    }
}
