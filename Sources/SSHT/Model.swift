import Foundation
import AppKit

struct TunnelState {
    enum Status: String { case idle = "未连接", connecting = "连接中", connected = "转发中", stopping = "正在停止", failed = "连接失败", external = "外部转发", occupied = "端口占用" }
    var status: Status = .idle
    var log = ""
    var started: Date?
    var active: Bool { [.connecting, .connected, .stopping].contains(status) }
    var running: Bool { active || status == .external }
}
@MainActor final class TunnelStore: ObservableObject {
    @Published var profiles = [Profile()]
    @Published var selection: UUID?
    @Published var states: [UUID: TunnelState] = [:]
    @Published var aliases = [String]()
    @Published var configMessage = ""
    @Published var error: String?
    @Published var preferences = AppPreferences()
    @Published var logsRevision = 0
    private var didRestore = false
    private var processes: [UUID: Process] = [:]
    private var pipes: [UUID: Pipe] = [:]
    private var sockets: [UUID: String] = [:]
    private var monitors: [UUID: Task<Void, Never>] = [:]
    private let inspectPorts: (Profile) -> PortInspection.Occupancy?
    private let dataURL: URL
    private let runtimeURL: URL
    init(storageDirectory: URL? = nil, inspectPorts: @escaping (Profile) -> PortInspection.Occupancy? = PortInspection.inspect) {
        self.inspectPorts = inspectPorts
        let directory = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SSHT")
        dataURL = directory.appendingPathComponent("profiles.json")
        runtimeURL = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? Data(contentsOf: dataURL), let saved = try? JSONDecoder().decode([Profile].self, from: data), !saved.isEmpty { profiles = saved }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("preferences.json")), let saved = try? JSONDecoder().decode(AppPreferences.self, from: data) { preferences = saved }
        selection = profiles.first?.id
        loadConfig("~/.ssh/config", showError: false)
        pruneLogs()
    }
    func state(_ id: UUID) -> TunnelState { states[id] ?? TunnelState() }
    func save() {
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: dataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
        } catch { self.error = "保存配置失败：\(error.localizedDescription)" }
    }
    func add() { let profile = Profile(); profiles.append(profile); selection = profile.id; save() }
    func delete(_ id: UUID) {
        if let profile = profiles.first(where: { $0.id == id }) { for rule in profile.rules { stop(rule.id) } }
        stop(id)
        profiles.removeAll { $0.id == id }
        if profiles.isEmpty { profiles = [Profile()] }
        selection = profiles.first?.id
        save()
    }
    func loadConfig(_ path: String, showError: Bool = true) {
        do { aliases = try ConfigHosts.load(path); configMessage = "已读取 \(aliases.count) 个主机；通配符配置由 OpenSSH 自动应用。" }
        catch { aliases = []; configMessage = "未读取 SSH config"; if showError { self.error = error.localizedDescription } }
    }
    func append(_ id: UUID, _ message: String) {
        let clean = message.replacingOccurrences(of: "\r", with: "")
        var state = state(id)
        state.log += clean
        if state.log.count > 60_000 { state.log = String(state.log.suffix(50_000)) }
        states[id] = state
        persistLog(id, clean)
    }
    func start(_ profile: Profile, password: String) {
        guard !state(profile.id).active else { return }
        let id = profile.id
        let socket = runtimeURL.appendingPathComponent(String(id.uuidString.prefix(8))).path
        do {
            let args = try SSHCommand.arguments(profile, socket: socket)
            monitors.removeValue(forKey: id)?.cancel()
            if let occupancy = inspectPorts(profile) {
                observeOccupancy(occupancy, profile: profile)
                if !occupancy.matchesForward { self.error = occupancy.message }
                return
            }
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = args
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = pipe
            var env = ProcessInfo.processInfo.environment
            env["SSH_ASKPASS"] = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = "ssht:0"
            if !password.isEmpty { env["SSHT_SECRET"] = password }
            process.environment = env
            states[id] = TunnelState(status: .connecting, log: "正在连接 \(profile.host)…\n", started: nil)
            pipes[id] = pipe
            sockets[id] = socket
            processes[id] = process
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                let message = String(decoding: data, as: UTF8.self)
                Task { @MainActor in self?.append(id, message) }
            }
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    guard let self else { return }
                    let stopped = self.state(id).status == .stopping
                    self.monitors.removeValue(forKey: id)?.cancel()
                    self.processes.removeValue(forKey: id)
                    self.pipes.removeValue(forKey: id)?.fileHandleForReading.readabilityHandler = nil
                    self.sockets.removeValue(forKey: id)
                    try? FileManager.default.removeItem(atPath: socket)
                    var state = self.state(id)
                    state.status = stopped || process.terminationStatus == 0 ? .idle : .failed
                    self.states[id] = state
                    self.append(id, stopped ? "\n转发已停止。\n" : "\nSSH 进程退出，退出码 \(process.terminationStatus)。\n")
                    if !stopped && process.terminationStatus != 0, let occupancy = self.inspectPorts(profile) {
                        self.observeOccupancy(occupancy, profile: profile)
                    }
                }
            }
            try process.run()
            monitors[id] = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled, let self, self.state(id).status == .connecting else { return }
                    if FileManager.default.fileExists(atPath: socket) {
                        self.states[id]?.status = .connected
                        self.states[id]?.started = Date()
                        self.append(id, "连接已建立，\(profile.rules.filter(\.enabled).count) 条转发规则运行中。\n")
                        return
                    }
                }
            }
            save()
        } catch {
            processes.removeValue(forKey: id)
            pipes.removeValue(forKey: id)?.fileHandleForReading.readabilityHandler = nil
            sockets.removeValue(forKey: id)
            states[id] = TunnelState(status: .failed, log: error.localizedDescription + "\n")
            self.error = error.localizedDescription
        }
    }
    private func observeOccupancy(_ occupancy: PortInspection.Occupancy, profile: Profile) {
        let id = profile.id
        states[id] = TunnelState(status: occupancy.matchesForward ? .external : .occupied, log: "")
        append(id, occupancy.message + "\n外部进程由原启动方式管理，软件不会停止它。\n")
        monitors.removeValue(forKey: id)?.cancel()
        monitors[id] = Task { [weak self] in
            var previousMessage = occupancy.message
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let currentProfile = self.ruleItems.first(where: { $0.id == id }).flatMap { self.sessionProfile(for: $0) } ?? profile
                let inspection = self.inspectPorts(currentProfile)
                guard !Task.isCancelled else { return }
                let status: TunnelState.Status = inspection.map { $0.matchesForward ? .external : .occupied } ?? .idle
                if self.state(id).status != status || inspection?.message != previousMessage {
                    self.states[id]?.status = status
                    self.append(id, inspection.map { $0.message + "\n" } ?? "监听端口已释放，可以启动本规则。\n")
                    previousMessage = inspection?.message ?? ""
                }
                if inspection == nil { self.monitors.removeValue(forKey: id); return }
            }
        }
    }
    func stop(_ id: UUID) {
        guard let process = processes[id], process.isRunning else { return }
        states[id]?.status = .stopping
        monitors.removeValue(forKey: id)?.cancel()
        process.terminate()
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    var ruleItems: [RuleItem] {
        profiles.flatMap { profile in profile.rules.map { RuleItem(profileID: profile.id, profileName: profile.name, sshHost: profile.host, rule: $0) } }
    }
    func sessionProfile(for item: RuleItem) -> Profile? {
        guard var profile = profiles.first(where: { $0.id == item.profileID }) else { return nil }
        profile.id = item.id
        profile.name = item.name
        var rule = item.rule; rule.enabled = true
        profile.rules = [rule]
        return profile
    }
    func startRule(_ item: RuleItem, password: String = "") {
        guard let profile = sessionProfile(for: item) else { return }
        start(profile, password: password)
    }
    var canStartAll: Bool { ruleItems.contains { !state($0.id).running } }
    var groups: [String] {
        Set(ruleItems.map { $0.rule.groupName }).sorted {
            if $0 == "默认分组" { return $1 != "默认分组" }
            if $1 == "默认分组" { return false }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
    func items(in group: String) -> [RuleItem] { ruleItems.filter { $0.rule.groupName == group } }
    func canStartGroup(_ group: String) -> Bool { items(in: group).contains { !state($0.id).running } }
    func startGroup(_ group: String) { startRules(items(in: group)) }
    func stopGroup(_ group: String) { for item in items(in: group) { stop(item.id) } }
    func moveRule(_ item: RuleItem, to group: String) {
        guard let p = profiles.firstIndex(where: { $0.id == item.profileID }),
              let r = profiles[p].rules.firstIndex(where: { $0.id == item.id }) else { return }
        profiles[p].rules[r].group = group == "默认分组" ? "" : group
        save()
    }
    func startAll() { startRules(ruleItems) }
    private func startRules(_ items: [RuleItem]) {
        let pending = items.filter { !state($0.id).running }
        guard !pending.isEmpty else { return }
        var failures = [String]()
        for item in pending {
            startRule(item)
            if [.failed, .occupied].contains(state(item.id).status), let error { failures.append("\(item.name)：\(error)") }
        }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
    func stopAll() { for id in Array(processes.keys) { stop(id) } }
    func updateRule(_ rule: ForwardRule, profileID: UUID) {
        guard !state(rule.id).active,
              let p = profiles.firstIndex(where: { $0.id == profileID }),
              let r = profiles[p].rules.firstIndex(where: { $0.id == rule.id }) else { return }
        guard profiles[p].rules[r] != rule else { return }
        monitors.removeValue(forKey: rule.id)?.cancel()
        if [.external, .occupied].contains(state(rule.id).status) { states[rule.id]?.status = .idle }
        profiles[p].rules[r] = rule
        save()
    }
    func removeRule(_ item: RuleItem) {
        guard !state(item.id).active, let p = profiles.firstIndex(where: { $0.id == item.profileID }) else { return }
        monitors.removeValue(forKey: item.id)?.cancel()
        profiles[p].rules.removeAll { $0.id == item.id }
        states.removeValue(forKey: item.id)
        save()
    }
    func addRule(_ rule: ForwardRule, to profileID: UUID) {
        guard let p = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[p].rules.append(rule)
        save()
    }
    func addConfigRule(_ rule: ForwardRule, alias: String, configPath: String) throws {
        let path = URL(fileURLWithPath: SSHCommand.expanded(configPath)).standardizedFileURL.path
        // Re-read on submission so removed aliases cannot create stale connections.
        guard try ConfigHosts.load(path).contains(alias) else {
            throw TunnelError.invalid("所选主机已不在 SSH config 中，请重新读取并选择主机。")
        }
        var profile = Profile()
        profile.name = alias
        profile.host = alias
        profile.useConfig = true
        profile.configPath = path
        profile.rules = [rule]
        _ = try SSHCommand.arguments(profile, socket: "/tmp/ssht-validation.sock")
        if let index = profiles.firstIndex(where: {
            $0.useConfig && $0.host == alias && $0.user.isEmpty && $0.identity.isEmpty &&
            URL(fileURLWithPath: SSHCommand.expanded($0.configPath)).standardizedFileURL.path == path
        }) {
            profiles[index].rules.append(rule)
        } else {
            profiles.append(profile)
        }
        save()
    }
    func restoreRules() {
        guard !didRestore else { return }; didRestore = true
        let previous = Set(preferences.restoreOnLaunch ? preferences.previousRules : [])
        for item in ruleItems where item.rule.autoStart || previous.contains(item.id) {
            if !item.sshHost.isEmpty { startRule(item) }
        }
    }
    func savePreferences() {
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let url = dataURL.deletingLastPathComponent().appendingPathComponent("preferences.json")
            try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            pruneLogs()
        } catch { self.error = "保存设置失败：\(error.localizedDescription)" }
    }
    var logsDirectory: URL { dataURL.deletingLastPathComponent().appendingPathComponent("Logs") }
    private func persistLog(_ id: UUID, _ message: String) {
        guard preferences.recordLogs, !message.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            let url = logsDirectory.appendingPathComponent(formatter.string(from: Date()) + ".log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
            try file.seekToEnd()
            let entry = "[\(Date().formatted(date: .omitted, time: .standard))] [\(id.uuidString.prefix(8))] \(message)"
            try file.write(contentsOf: Data(entry.utf8))
            logsRevision += 1
        } catch { self.error = "写入日志失败：\(error.localizedDescription)" }
    }
    func pruneLogs() {
        let cutoff = Date().addingTimeInterval(-Double(preferences.retentionDays) * 86400)
        let files = (try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "log" {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
    func clearLogs() {
        for id in Array(states.keys) { states[id]?.log = "" }
        let files = (try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "log" { try? FileManager.default.removeItem(at: file) }
        logsRevision += 1
    }
    func savedLog() -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(7).compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
    func shutdown() {
        preferences.previousRules = processes.keys.filter { state($0).status == .connected }
        savePreferences()
        save()
        for process in processes.values where process.isRunning { process.terminate() }
        for monitor in monitors.values { monitor.cancel() }
        try? FileManager.default.removeItem(at: runtimeURL)
    }
}
