import SwiftUI
import AppKit

struct SheetHeader: View {
    let title: String
    let close: () -> Void
    var textClose = false
    var body: some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(action: close) {
                Group {
                    if textClose { Text("×").font(.system(size: 16, weight: .medium)).foregroundStyle(UITheme.secondary) }
                    else { FigmaIcon(name: "close") }
                }.frame(width: 28, height: 28)
            }.buttonStyle(.plain)
                .background(UITheme.toolbar, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.inputBorder, lineWidth: 1)).accessibilityLabel("关闭")
        }.padding(.horizontal, 24).frame(height: 56)
    }
}
struct AddRuleSheet: View {
    @EnvironmentObject var store: TunnelStore
    @Environment(\.dismiss) var dismiss
    let added: (UUID) -> Void
    @ViewState private var rule = ForwardRule(name: "")
    @ViewState private var configPath = "~/.ssh/config"
    @ViewState private var configHosts = [String]()
    @ViewState private var selectedHost = ""
    @ViewState private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "添加规则") { dismiss() }
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    UIField(title: "规则名称", text: $rule.name, placeholder: "例如：开发服务器 · 备用", height: 36)
                    RuleGroupField(group: $rule.group).environmentObject(store)
                    HStack(alignment: .bottom, spacing: 12) {
                        ProtocolControl()
                        VStack(alignment: .leading, spacing: 7) {
                            Text("转发方式").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                            Picker("转发方式", selection: $rule.kind) { ForEach(ForwardKind.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(height: 32)
                        }.frame(width: 145)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: rule.kind == .remote ? "远端监听" : "本地监听", icon: "laptop-modal")
                        HStack(spacing: 12) {
                            UIField(title: "监听地址", text: $rule.bindAddress, monospaced: true, height: 36)
                            UIField(title: "监听端口", text: $rule.listenPort, monospaced: true, height: 36).frame(width: 154)
                        }
                        Text("仅允许本机访问；使用 0.0.0.0 将监听所有网络接口。").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                    }
                    Hairline()
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "转发目标", icon: "server-modal")
                        if rule.kind == .socks {
                            Text("SOCKS4 / SOCKS5，目标由使用代理的应用决定。").font(.system(size: 12)).foregroundStyle(UITheme.secondary)
                        } else {
                            HStack(spacing: 12) {
                                UIField(title: "目标主机", text: $rule.targetHost, monospaced: true, height: 36)
                                UIField(title: "目标端口", text: $rule.targetPort, monospaced: true, height: 36).frame(width: 154)
                            }
                            Text("填写从\(rule.kind == .remote ? "本机" : "SSH 服务器")访问的目标 IP 地址或主机名。").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                        }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("打开应用时自动启动").font(.system(size: 13))
                            Text("添加后为已停止状态，可在规则列表中启动。").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                        }
                        Spacer()
                        Toggle("打开应用时自动启动", isOn: $rule.autoStart).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    Hairline()
                    HStack {
                        Text("SSH 连接").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Picker("SSH 连接", selection: $selectedHost) {
                            if configHosts.isEmpty { Text("暂无 config 主机").tag("") }
                            ForEach(configHosts, id: \.self) { alias in Text(alias).tag(alias) }
                        }.labelsHidden().frame(maxWidth: 300).disabled(configHosts.isEmpty)
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        UIField(title: "SSH config 文件", text: $configPath, placeholder: "~/.ssh/config")
                            .onSubmit { reloadConfig() }
                        Button("选择…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true
                            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
                            if panel.runModal() == .OK, let url = panel.url { configPath = url.path; reloadConfig() }
                        }.buttonStyle(FlatButtonStyle())
                        Button { reloadConfig() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(FlatButtonStyle()).help("重新读取 SSH config")
                    }
                    Text("主机列表来自 SSH config；用户名、端口、密钥和跳板机始终使用文件中的配置。")
                        .font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                    if let error { Text(error).font(.system(size: 11)).foregroundStyle(UITheme.danger) }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }.frame(maxHeight: .infinity)
            Hairline()
            HStack(spacing: 10) {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(FlatButtonStyle(height: 34)).keyboardShortcut(.cancelAction)
                Button("添加规则", action: add).buttonStyle(FlatButtonStyle(primary: true, height: 34)).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).frame(height: 69)
        }.frame(width: 560, height: 620).background(UITheme.canvas).foregroundStyle(UITheme.text).tint(UITheme.accent)
            .onAppear { reloadConfig() }
            .onChange(of: configPath) { _, _ in reloadConfig() }
    }
    func reloadConfig() {
        do {
            configHosts = try ConfigHosts.load(configPath)
            if !configHosts.contains(selectedHost) { selectedHost = configHosts.first ?? "" }
            error = configHosts.isEmpty ? "config 中没有可选择的具体 Host 别名。" : nil
        } catch {
            configHosts = []; selectedHost = ""
            self.error = "读取 SSH config 失败：\(error.localizedDescription)"
        }
    }
    func add() {
        guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请填写规则名称。"; return }
        guard !selectedHost.isEmpty else { error = "请先选择 SSH config 中的主机。"; return }
        do {
            try store.addConfigRule(rule, alias: selectedHost, configPath: configPath)
            dismiss()
            let id = rule.id
            Task { @MainActor in
                await Task.yield()
                added(id)
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct SSHConnectionFields: View {
    @EnvironmentObject var store: TunnelStore
    @Binding var profile: Profile
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("连接来源", selection: $profile.useConfig) { Text("手动输入").tag(false); Text("SSH config").tag(true) }.pickerStyle(.segmented)
                .onChange(of: profile.useConfig) { _, enabled in if enabled { store.loadConfig(profile.configPath, showError: false) } }
            if profile.useConfig {
                HStack(alignment: .bottom, spacing: 8) {
                    UIField(title: "SSH config 文件", text: $profile.configPath, placeholder: "~/.ssh/config")
                    Button("选择…") { chooseFile { profile.configPath = $0; store.loadConfig($0) } }.buttonStyle(FlatButtonStyle())
                    Button { store.loadConfig(profile.configPath) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(FlatButtonStyle()).help("重新读取 config")
                }
                HStack(alignment: .bottom, spacing: 8) {
                    UIField(title: "主机别名 / IP", text: $profile.host, placeholder: "选择主机或输入别名")
                    Menu("选择主机") {
                        ForEach(store.aliases, id: \.self) { alias in Button(alias) { profile.host = alias } }
                        if store.aliases.isEmpty { Text("暂无具体主机别名") }
                    }.frame(width: 110, height: 32)
                }
                Text(store.configMessage).font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                Text("沿用 User、Port、IdentityFile、ProxyJump 和 config 已有转发设置。").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
            } else {
                HStack(spacing: 12) {
                    UIField(title: "服务器 IP / 域名", text: $profile.host, placeholder: "192.168.1.10")
                    UIField(title: "SSH 端口", text: $profile.port, placeholder: "22", monospaced: true).frame(width: 100)
                }
            }
            UIField(title: profile.useConfig ? "用户名（可选覆盖）" : "SSH 用户名", text: $profile.user, placeholder: profile.useConfig ? "使用 config 配置" : "留空使用当前系统用户")
            HStack(alignment: .bottom, spacing: 8) {
                UIField(title: "私钥文件（可选）", text: $profile.identity, placeholder: "使用 SSH Agent / 默认密钥")
                Button("选择…") { chooseFile { profile.identity = $0 } }.buttonStyle(FlatButtonStyle())
            }
        }
    }
    func chooseFile(_ picked: (String) -> Void) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        if panel.runModal() == .OK, let url = panel.url { picked(url.path) }
    }
}
struct ConnectionSheet: View {
    @EnvironmentObject var store: TunnelStore
    @Environment(\.dismiss) var dismiss
    let profileID: UUID
    @Binding var password: String
    @ViewState private var draft = Profile()
    @ViewState private var error: String?
    var active: Bool { store.ruleItems.filter { $0.profileID == profileID }.contains { store.state($0.id).active } }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "SSH 连接设置") { dismiss() }
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UIField(title: "连接名称", text: $draft.name)
                    SSHConnectionFields(profile: $draft).environmentObject(store)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("本次连接密码 / 私钥口令（可选）").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                        SecureField("留空使用 SSH Agent，或连接时询问", text: $password).textFieldStyle(.plain).font(.system(size: 12))
                            .padding(.horizontal, 10).frame(height: 32).background(UITheme.canvas, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.inputBorder, lineWidth: 1))
                    }
                    Text("连接设置由同一连接下的规则共享。密码不会保存。首次连接记录主机密钥；已有密钥变化时拒绝连接。").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                    if active { Text("此 SSH 连接下有规则正在运行，请先停止后修改。").font(.system(size: 11)).foregroundStyle(UITheme.secondary) }
                    if let error { Text(error).font(.system(size: 11)).foregroundStyle(UITheme.danger) }
                }.padding(24).disabled(active)
            }.frame(maxHeight: .infinity)
            Hairline()
            HStack(spacing: 10) {
                Spacer()
                Button("取消") { password = ""; dismiss() }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("保存连接", action: save).buttonStyle(FlatButtonStyle(primary: true)).disabled(active).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).frame(height: 69)
        }.frame(width: 560, height: 620).background(UITheme.canvas).foregroundStyle(UITheme.text).tint(UITheme.accent)
            .onAppear { if let profile = store.profiles.first(where: { $0.id == profileID }) { draft = profile; if draft.useConfig { store.loadConfig(draft.configPath, showError: false) } } }
    }
    func save() {
        do {
            _ = try SSHCommand.address(draft.host, label: "SSH 地址")
            if !draft.useConfig { _ = try SSHCommand.port(draft.port, label: "SSH 端口") }
            else if !FileManager.default.fileExists(atPath: SSHCommand.expanded(draft.configPath)) { throw TunnelError.invalid("SSH config 文件不存在。") }
            if let p = store.profiles.firstIndex(where: { $0.id == profileID }), !active {
                draft.rules = store.profiles[p].rules
                store.profiles[p] = draft; store.save(); dismiss()
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct RuleGroupField: View {
    @EnvironmentObject var store: TunnelStore
    @Binding var group: String
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            UIField(title: "分组", text: $group, placeholder: "默认分组；输入名称新建分组")
            Menu {
                Button("默认分组") { group = "" }
                ForEach(store.groups.filter { $0 != "默认分组" }, id: \.self) { name in
                    Button(name) { group = name }
                }
            } label: { Image(systemName: "folder") }
                .menuStyle(.borderlessButton).fixedSize().frame(height: 32).help("选择已有分组")
        }
    }
}
