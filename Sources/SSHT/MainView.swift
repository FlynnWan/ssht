import SwiftUI
import AppKit

enum RuleFilter: String, CaseIterable { case all, running, stopped }
enum RuleSort: String, CaseIterable { case custom = "自定义排序", name = "按名称排序", port = "按端口排序" }
enum Modal: String, Identifiable { case add, connection, settings, logs; var id: String { rawValue } }

@MainActor final class InterfaceState: ObservableObject {
    @Published var selectedRule: UUID?
    @Published var query = ""
    @Published var filter: RuleFilter = .all
    @Published var sort: RuleSort = .custom
    @Published var expandedGroups = Set<String>()
    @Published var modal: Modal?
    @Published var password = ""
    @Published var deleteItem: RuleItem?
}

struct MainView: View {
    @EnvironmentObject var store: TunnelStore
    @ObservedObject var interface: InterfaceState
    var selected: RuleItem? { store.ruleItems.first { $0.id == interface.selectedRule } }
    var runningCount: Int { store.ruleItems.filter { [.connected, .external].contains(store.state($0.id).status) }.count }
    var activeCount: Int { store.ruleItems.filter { store.state($0.id).running }.count }
    var managedCount: Int { store.ruleItems.filter { store.state($0.id).active }.count }
    var stoppedCount: Int { store.ruleItems.count - activeCount }
    var visibleItems: [RuleItem] {
        var items = store.ruleItems.filter { item in
            (interface.query.isEmpty || item.searchText.localizedCaseInsensitiveContains(interface.query)) &&
            (interface.filter == .all || (interface.filter == .running ? store.state(item.id).running : !store.state(item.id).running))
        }
        switch interface.sort {
        case .custom: break
        case .name: items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .port: items.sort { (Int($0.rule.listenPort) ?? 0) < (Int($1.rule.listenPort) ?? 0) }
        }
        return items
    }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Hairline()
            HStack(spacing: 0) {
                ruleList.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(UITheme.border).frame(width: 1)
                details.frame(width: 371).frame(maxHeight: .infinity).background(UITheme.sidebar)
            }
            Hairline()
            statusBar
        }.background(UITheme.canvas).foregroundStyle(UITheme.text).tint(UITheme.accent)
            .frame(minWidth: 1050, minHeight: 720).ignoresSafeArea()
            .onAppear { if interface.selectedRule == nil { interface.selectedRule = store.ruleItems.first?.id } }
            .onChange(of: store.ruleItems.map(\.id)) { _, ids in if !ids.contains(interface.selectedRule ?? UUID()) { interface.selectedRule = ids.first } }
            .onChange(of: interface.selectedRule) { _, _ in interface.password = "" }
            .onChange(of: store.preferences) { _, _ in store.savePreferences() }
            .onChange(of: store.preferences.appearance) { _, appearance in applyAppearance(appearance) }
            .onReceive(NotificationCenter.default.publisher(for: .sshtAddRule)) { _ in interface.modal = .add }
            .onReceive(NotificationCenter.default.publisher(for: .sshtSettings)) { _ in interface.modal = .settings }
            .onReceive(NotificationCenter.default.publisher(for: .sshtLogs)) { _ in interface.modal = .logs }
            .sheet(item: $interface.modal) { destination in
                switch destination {
                case .add: AddRuleSheet { id in interface.selectedRule = id }.environmentObject(store)
                case .connection:
                    if let item = selected { ConnectionSheet(profileID: item.profileID, password: $interface.password).environmentObject(store) }
                case .settings: PreferencesSheet().environmentObject(store)
                case .logs: LogsSheet(selectedRule: interface.selectedRule).environmentObject(store)
                }
            }
            .alert("无法完成操作", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
            .alert("删除这条规则？", isPresented: Binding(get: { interface.deleteItem != nil }, set: { if !$0 { interface.deleteItem = nil } })) {
                Button("取消", role: .cancel) { interface.deleteItem = nil }
                Button("删除", role: .destructive) { if let item = interface.deleteItem { store.removeRule(item) }; interface.deleteItem = nil }
            } message: { Text("删除“\(interface.deleteItem?.name ?? "")”的端口转发规则，SSH 连接配置会保留。") }
    }
    var toolbar: some View {
        HStack(spacing: 12) {
            WindowControls().frame(width: 52, height: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("端口转发").font(.system(size: 16, weight: .semibold))
                Text("本地与远程，轻松连接").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
            }
            Spacer()
            Button { store.startAll() } label: {
                HStack(spacing: 6) { Image(systemName: "play.fill").font(.system(size: 11)); Text("全部开启") }
            }.buttonStyle(FlatButtonStyle()).disabled(!store.canStartAll)
            Button { store.stopAll() } label: { HStack(spacing: 6) { FigmaIcon(name: "square"); Text("全部停止") } }.buttonStyle(FlatButtonStyle()).disabled(managedCount == 0).help("仅停止由本软件启动的转发")
            Button { interface.modal = .add } label: { HStack(spacing: 6) { FigmaIcon(name: "plus"); Text("添加规则") } }.buttonStyle(FlatButtonStyle(primary: true))
            Button { interface.modal = .settings } label: { FigmaIcon(name: "settings").frame(width: 28, height: 32) }.buttonStyle(.plain).help("设置（⌘,）").accessibilityLabel("设置")
        }.padding(.horizontal, 24).frame(height: 77).background(UITheme.toolbar)
    }
    var ruleList: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 8) { Text("转发规则").font(.system(size: 19, weight: .semibold)); Text("\(store.ruleItems.count)").font(.system(size: 12)).foregroundStyle(UITheme.secondary) }
                Spacer()
                HStack(spacing: 7) {
                    FigmaIcon(name: "search")
                    TextField("搜索名称、端口或地址", text: $interface.query).textFieldStyle(.plain).font(.system(size: 11)).accessibilityLabel("搜索规则")
                }.padding(.horizontal, 9).frame(width: 204, height: 30).background(UITheme.toolbar, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.inputBorder, lineWidth: 1))
            }
            HStack {
                HStack(spacing: 3) {
                    filterButton(.all, text: "全部  \(store.ruleItems.count)")
                    filterButton(.running, text: "运行中  \(activeCount)")
                    filterButton(.stopped, text: "已停止  \(stoppedCount)")
                }.padding(3).background(UITheme.canvas, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.inputBorder, lineWidth: 1))
                Spacer()
                Menu { Picker("排序", selection: $interface.sort) { ForEach(RuleSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { Text(interface.sort.rawValue).font(.system(size: 11)).foregroundStyle(UITheme.secondary) }.menuStyle(.borderlessButton).fixedSize()
            }.frame(height: 29)
            VStack(spacing: 4) {
                tableHeader
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.groups, id: \.self) { group in
                            let items = visibleItems.filter { $0.rule.groupName == group }
                            if !items.isEmpty {
                                groupHeader(group)
                                if interface.expandedGroups.contains(group) {
                                    ForEach(items) { item in ruleRow(item) }
                                }
                            }
                        }
                        if visibleItems.isEmpty {
                            VStack(spacing: 10) {
                                Text(store.ruleItems.isEmpty ? "还没有转发规则" : "没有匹配的规则").font(.system(size: 14, weight: .medium))
                                Text(store.ruleItems.isEmpty ? "点击上方「添加规则」，配置 SSH 连接和端口。" : "尝试其他搜索词或状态筛选。").font(.system(size: 12)).foregroundStyle(UITheme.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 65)
                        }
                    }
                }
            }.frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 6) { FigmaIcon(name: "info"); Text("选择规则查看详情；停止后可修改转发配置。").font(.system(size: 11)).foregroundStyle(UITheme.secondary) }
        }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
    }
    private func groupHeader(_ group: String) -> some View {
        let items = store.items(in: group)
        let active = items.filter { store.state($0.id).running }.count
        let managed = items.contains { store.state($0.id).active }
        return HStack(spacing: 8) {
            Button {
                if interface.expandedGroups.contains(group) { interface.expandedGroups.remove(group) }
                else { interface.expandedGroups.insert(group) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: interface.expandedGroups.contains(group) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).frame(width: 10).foregroundStyle(UITheme.secondary)
                    Image(systemName: "folder").foregroundStyle(UITheme.secondary)
                    Text(group).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(items.count) 条 · \(active) 条运行中").font(.system(size: 10)).foregroundStyle(UITheme.secondary)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 26).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(interface.expandedGroups.contains(group) ? "折叠" : "展开")分组：\(group)")
                .accessibilityValue(interface.expandedGroups.contains(group) ? "已展开" : "已折叠")
            Button("开启分组") { store.startGroup(group) }
                .buttonStyle(FlatButtonStyle(height: 26)).disabled(!store.canStartGroup(group))
            Button("停止分组") { store.stopGroup(group) }
                .buttonStyle(FlatButtonStyle(height: 26)).disabled(!managed).help("仅停止此分组内由本软件启动的转发")
        }.padding(.horizontal, 12).padding(.vertical, 7)
            .background(UITheme.sidebar, in: RoundedRectangle(cornerRadius: 6)).padding(.top, 6)
    }
    private func filterButton(_ value: RuleFilter, text: String) -> some View {
        Button { interface.filter = value } label: {
            Text(text).font(.system(size: 11, weight: interface.filter == value ? .medium : .regular))
                .foregroundStyle(interface.filter == value ? UITheme.text : UITheme.secondary).padding(.horizontal, 11).frame(height: 23)
                .background(interface.filter == value ? UITheme.toolbar : .clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(interface.filter == value ? UITheme.border : .clear, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(interface.filter == value ? .isSelected : [])
    }
    var tableHeader: some View {
        HStack(spacing: 10) {
            Text("名称 / 协议").frame(width: 124, alignment: .leading)
            Text("监听端口").frame(width: 128, alignment: .leading)
            Color.clear.frame(width: 16, height: 1)
            Text("目标地址").frame(maxWidth: .infinity, alignment: .leading)
            Text("状态").frame(width: 70, alignment: .leading)
            Text("操作").frame(width: 46, alignment: .leading)
        }.font(.system(size: 11)).foregroundStyle(UITheme.secondary).padding(.horizontal, 12).frame(height: 28)
    }
    func ruleRow(_ item: RuleItem) -> some View {
        let state = store.state(item.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(item.name).font(.system(size: 13, weight: item.id == interface.selectedRule ? .semibold : .medium)).lineLimit(1)
                Text(item.protocolName).font(.system(size: 10, weight: .medium)).foregroundStyle(UITheme.secondary)
            }.frame(width: 124, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.rule.listenPort).font(.system(size: 13, weight: .medium, design: .monospaced))
                Text(item.rule.bindAddress).font(.system(size: 10, design: .monospaced)).foregroundStyle(UITheme.secondary).lineLimit(1)
            }.frame(width: 128, alignment: .leading)
            FigmaIcon(name: item.id == interface.selectedRule ? "arrow-active" : "arrow")
            VStack(alignment: .leading, spacing: 7) {
                Text(item.rule.kind == .socks ? item.sshHost : item.rule.targetHost).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                Text(item.rule.kind == .socks ? "SOCKS 代理" : "端口 \(item.rule.targetPort)").font(.system(size: 10, design: .monospaced)).foregroundStyle(UITheme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            RuleStatus(state: state).frame(width: 70, alignment: .leading)
            Button(state.status == .external ? "检查" : state.active ? "停止" : "启动") { interface.selectedRule = item.id; toggle(item) }.buttonStyle(FlatButtonStyle(height: 28, horizontalPadding: 10)).frame(width: 46).disabled(state.status == .stopping)
        }.padding(.horizontal, 12).frame(height: 78)
            .background(item.id == interface.selectedRule ? UITheme.selection : UITheme.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.border, lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture { interface.selectedRule = item.id }
            .accessibilityElement(children: .contain).accessibilityLabel("\(item.name) 规则")
            .contextMenu {
                Button("SSH 连接设置…") { interface.selectedRule = item.id; interface.modal = .connection }
                Button("复制 SSH 命令") {
                    if let profile = store.sessionProfile(for: item), let args = try? SSHCommand.arguments(profile, socket: "/tmp/ssht-preview.sock") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(SSHCommand.display(args), forType: .string)
                    }
                }
                Menu("移动到分组") {
                    ForEach(store.groups, id: \.self) { group in
                        Button(group) { store.moveRule(item, to: group) }
                    }
                    if !store.groups.contains("默认分组") {
                        Button("默认分组") { store.moveRule(item, to: "") }
                    }
                }
                Divider()
                Button("删除规则…", role: .destructive) { interface.deleteItem = item }.disabled(state.active)
            }
    }
    @ViewBuilder var details: some View {
        if let item = selected,
           store.profiles.contains(where: { $0.id == item.profileID }) {
            RuleDetail(rule: Binding(get: { store.profiles.first(where: { $0.id == item.profileID })?.rules.first(where: { $0.id == item.id }) ?? item.rule }, set: { store.updateRule($0, profileID: item.profileID) }), item: item, password: $interface.password, connect: { toggle(item) }, editConnection: { interface.modal = .connection }, delete: { interface.deleteItem = item })
                .id(item.id).environmentObject(store)
        } else {
            VStack(spacing: 10) {
                Text("规则详情").font(.system(size: 14, weight: .semibold))
                Text("选择左侧规则，查看并修改配置。").font(.system(size: 12)).foregroundStyle(UITheme.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    func toggle(_ item: RuleItem) {
        if store.state(item.id).active { store.stop(item.id) }
        else if item.sshHost.isEmpty { interface.selectedRule = item.id; interface.modal = .connection }
        else { store.startRule(item, password: interface.selectedRule == item.id ? interface.password : ""); interface.password = "" }
    }
    var statusBar: some View {
        HStack(spacing: 7) {
            FigmaIcon(name: runningCount > 0 ? "status-active" : "status-idle")
            Text("\(runningCount) 条规则运行中 · \(stoppedCount) 条已停止").font(.system(size: 11)).foregroundStyle(UITheme.secondary)
            Spacer()
            Button { interface.modal = .logs } label: {
                HStack(spacing: 6) { FigmaIcon(name: "terminal"); Text("查看日志").font(.system(size: 11)); Text("⌘ L").font(.system(size: 10)).foregroundStyle(UITheme.muted) }
            }.buttonStyle(.plain).foregroundStyle(UITheme.secondary)
        }.padding(.horizontal, 24).frame(height: 35).background(UITheme.toolbar)
    }
}

struct RuleDetail: View {
    @EnvironmentObject var store: TunnelStore
    @Binding var rule: ForwardRule
    let item: RuleItem
    @Binding var password: String
    let connect: () -> Void
    let editConnection: () -> Void
    let delete: () -> Void
    var state: TunnelState { store.state(item.id) }
    var displayName: Binding<String> { Binding(get: { rule.name.isEmpty ? item.profileName : rule.name }, set: { rule.name = $0 }) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("规则详情").font(.system(size: 14, weight: .semibold)); Spacer(); RuleStatus(state: state) }.padding(.horizontal, 24).frame(height: 66)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    UIField(title: "规则名称", text: displayName).disabled(state.active)
                    RuleGroupField(group: Binding(get: { rule.group }, set: { store.moveRule(item, to: $0) })).environmentObject(store)
                    ProtocolControl()
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            SectionLabel(title: rule.kind == .remote ? "远端监听" : "本地监听", icon: "laptop")
                            Spacer()
                            Menu(rule.kind.title) { ForEach(ForwardKind.allCases) { kind in Button(kind.title) { rule.kind = kind } } }.font(.system(size: 10)).menuStyle(.borderlessButton).fixedSize().disabled(state.active)
                        }
                        HStack(spacing: 12) {
                            UIField(title: "监听地址", text: $rule.bindAddress, monospaced: true)
                            UIField(title: rule.kind == .remote ? "远端端口" : "本地端口", text: $rule.listenPort, monospaced: true).frame(width: 94)
                        }.disabled(state.active)
                        Text(rule.bindAddress == "127.0.0.1" || rule.bindAddress == "::1" ? "仅允许本机访问" : "监听范围由地址及 SSH 服务器配置决定").font(.system(size: 10)).foregroundStyle(UITheme.secondary)
                    }
                    Hairline()
                    VStack(alignment: .leading, spacing: 11) {
                        SectionLabel(title: "转发目标", icon: "server")
                        if rule.kind == .socks {
                            Text("SOCKS4 / SOCKS5\n目标地址由使用代理的应用决定。").font(.system(size: 12)).foregroundStyle(UITheme.secondary)
                        } else {
                            HStack(spacing: 12) {
                                UIField(title: "目标主机", text: $rule.targetHost, monospaced: true)
                                UIField(title: "目标端口", text: $rule.targetPort, monospaced: true).frame(width: 94)
                            }.disabled(state.active)
                        }
                    }
                    HStack {
                        Text("打开应用时自动启动").font(.system(size: 12))
                        Spacer()
                        Toggle("打开应用时自动启动", isOn: $rule.autoStart).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }.disabled(state.active)
                    if [.external, .occupied].contains(state.status) {
                        Text(state.status == .external ? "已确认其他 SSH 进程提供相同转发，跳过重复启动。停止操作仅作用于软件创建的连接。" : "监听端口已被其他进程占用，无法确认转发配置一致。请修改监听端口，或通过原启动方式停止占用进程。")
                            .font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                        Button("查看占用详情") { NotificationCenter.default.post(name: .sshtLogs, object: nil) }
                            .buttonStyle(FlatButtonStyle())
                    }
                    HStack(alignment: .top, spacing: 7) {
                        FigmaIcon(name: "lock")
                        Text(state.active ? "规则正在运行，配置已锁定。\n停止转发后即可编辑。" : "配置更改后自动保存。\nOpenSSH 支持 TCP，UDP 暂不可用。")
                            .font(.system(size: 11)).foregroundStyle(UITheme.secondary).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(10).background(UITheme.canvas, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(UITheme.inputBorder, lineWidth: 1))
                    Button(action: editConnection) {
                        HStack { Text("SSH 连接"); Spacer(); Text(item.sshHost.isEmpty ? "尚未配置" : item.sshHost).lineLimit(1); Image(systemName: "chevron.right").font(.system(size: 9)) }
                            .font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                    }.buttonStyle(.plain).help("编辑 SSH 主机、用户名、密钥或本次连接密码")
                }.padding(.horizontal, 24).padding(.bottom, 18)
            }.frame(maxHeight: .infinity)
            Hairline()
            HStack {
                Button(action: delete) { FigmaIcon(name: "trash").frame(width: 30, height: 32) }.buttonStyle(.plain).disabled(state.active).accessibilityLabel("删除规则")
                Spacer()
                Button(state.status == .external ? "重新检查" : state.active ? "停止并编辑" : "启动转发", action: connect).buttonStyle(FlatButtonStyle(primary: true)).disabled(state.status == .stopping)
            }.padding(.horizontal, 24).frame(height: 69)
        }
    }
}
