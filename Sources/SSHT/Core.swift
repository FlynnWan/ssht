import Foundation

enum ForwardKind: String, Codable, CaseIterable, Identifiable {
    case local, remote, socks
    var id: String { rawValue }
    var title: String { switch self { case .local: "本地转发"; case .remote: "远程转发"; case .socks: "SOCKS 代理" } }
    var flag: String { switch self { case .local: "-L"; case .remote: "-R"; case .socks: "-D" } }
}
struct ForwardRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var kind: ForwardKind = .local
    var bindAddress = "127.0.0.1"
    var listenPort = "8080"
    var targetHost = "127.0.0.1"
    var targetPort = "80"
    var name = ""
    var autoStart = false
    var group = ""
    var groupName: String {
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "默认分组" : name
    }
    enum CodingKeys: String, CodingKey { case id, enabled, kind, bindAddress, listenPort, targetHost, targetPort, name, autoStart, group }
    init(id: UUID = UUID(), enabled: Bool = true, kind: ForwardKind = .local, bindAddress: String = "127.0.0.1", listenPort: String = "8080", targetHost: String = "127.0.0.1", targetPort: String = "80", name: String = "", autoStart: Bool = false, group: String = "") {
        self.id = id; self.enabled = enabled; self.kind = kind; self.bindAddress = bindAddress; self.listenPort = listenPort; self.targetHost = targetHost; self.targetPort = targetPort; self.name = name; self.autoStart = autoStart; self.group = group
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        kind = try values.decodeIfPresent(ForwardKind.self, forKey: .kind) ?? .local
        bindAddress = try values.decode(String.self, forKey: .bindAddress)
        listenPort = try values.decode(String.self, forKey: .listenPort)
        targetHost = try values.decode(String.self, forKey: .targetHost)
        targetPort = try values.decode(String.self, forKey: .targetPort)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        autoStart = try values.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        group = try values.decodeIfPresent(String.self, forKey: .group) ?? ""
    }
}
struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新建连接"
    var useConfig = false
    var configPath = "~/.ssh/config"
    var host = ""
    var user = ""
    var port = "22"
    var identity = ""
    var rules = [ForwardRule()]
}
enum TunnelError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
enum SSHCommand {
    static func expanded(_ path: String) -> String { (path as NSString).expandingTildeInPath }
    static func address(_ value: String, label: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("-"), !text.contains(where: { $0.isWhitespace }), !text.contains("/"), !text.contains("@"), !text.contains("["), !text.contains("]") else { throw TunnelError.invalid("\(label)不是有效的主机名或 IP 地址。IPv6 请直接填写，不加方括号。") }
        return text.contains(":") ? "[\(text)]" : text
    }
    static func port(_ value: String, label: String) throws -> String {
        guard let number = Int(value), (1...65535).contains(number) else { throw TunnelError.invalid("\(label)必须是 1–65535 的整数。") }
        return String(number)
    }
    static func arguments(_ profile: Profile, socket: String) throws -> [String] {
        let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try address(host, label: "SSH 地址")
        var args = ["-N", "-T", "-M", "-S", socket, "-o", "ControlPersist=no", "-o", "ForkAfterAuthentication=no", "-o", "ExitOnForwardFailure=yes", "-o", "ClearAllForwardings=no", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-o", "StrictHostKeyChecking=accept-new", "-o", "NumberOfPasswordPrompts=1"]
        if profile.useConfig {
            guard FileManager.default.fileExists(atPath: expanded(profile.configPath)) else { throw TunnelError.invalid("SSH config 文件不存在。") }
            args += ["-F", expanded(profile.configPath)]
        } else {
            args += ["-F", "none", "-p", try port(profile.port, label: "SSH 端口")]
        }
        if !profile.user.isEmpty {
            guard !profile.user.contains(where: { $0.isWhitespace }), !profile.user.hasPrefix("-") else { throw TunnelError.invalid("SSH 用户名格式不正确。") }
            args += ["-l", profile.user]
        }
        if !profile.identity.isEmpty {
            let path = expanded(profile.identity)
            guard FileManager.default.fileExists(atPath: path) else { throw TunnelError.invalid("私钥文件不存在。") }
            args += ["-i", path]
        }
        let active = profile.rules.filter(\.enabled)
        guard !active.isEmpty else { throw TunnelError.invalid("请至少启用一条转发规则。") }
        var listeners = Set<String>()
        for rule in active {
            let bind = try address(rule.bindAddress, label: "监听地址")
            let listen = try port(rule.listenPort, label: "监听端口")
            let key = "\(rule.kind == .remote ? "remote" : "local"):\(bind):\(listen)"
            guard listeners.insert(key).inserted else { throw TunnelError.invalid("存在重复的监听地址和端口：\(bind):\(listen)") }
            var spec = "\(bind):\(listen)"
            if rule.kind != .socks { spec += ":\(try address(rule.targetHost, label: "目标地址")):\(try port(rule.targetPort, label: "目标端口"))" }
            args += [rule.kind.flag, spec]
        }
        args += [host]
        return args
    }
    static func display(_ args: [String]) -> String {
        (["ssh"] + args).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }
}

// Lists concrete aliases only. OpenSSH itself handles Host/Match, defaults and jumps.
enum ConfigHosts {
    static func tokens(_ line: String) -> [String] {
        var result = [String](), token = "", quote: Character?, escaped = false
        for char in line {
            if escaped { token.append(char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if let q = quote { if char == q { quote = nil } else { token.append(char) }; continue }
            if char == "\"" || char == "'" { quote = char; continue }
            if char == "#" { break }
            if char.isWhitespace || char == "=" { if !token.isEmpty { result.append(token); token = "" } } else { token.append(char) }
        }
        if !token.isEmpty { result.append(token) }
        return result
    }
    static func load(_ path: String) throws -> [String] {
        var visited = Set<String>(), hosts = Set<String>()
        func read(_ path: String, depth: Int) throws {
            let expanded = SSHCommand.expanded(path)
            guard depth < 16, visited.insert(expanded).inserted else { return }
            let content = try String(contentsOfFile: expanded, encoding: .utf8)
            for line in content.components(separatedBy: .newlines) {
                let parts = tokens(line)
                guard let directive = parts.first?.lowercased() else { continue }
                if directive == "host" {
                    for alias in parts.dropFirst() where !alias.contains("*") && !alias.contains("?") && !alias.hasPrefix("!") { hosts.insert(alias) }
                }
                if directive == "include" {
                    for include in parts.dropFirst() {
                        let pattern = include.hasPrefix("/") || include.hasPrefix("~") ? SSHCommand.expanded(include) : NSHomeDirectory() + "/.ssh/" + include
                        var matches = glob_t()
                        if glob(pattern, 0, nil, &matches) == 0, let paths = matches.gl_pathv {
                            for index in 0..<Int(matches.gl_pathc) { if let file = paths[index] { try? read(String(cString: file), depth: depth + 1) } }
                        }
                        globfree(&matches)
                    }
                }
            }
        }
        try read(path, depth: 0)
        return hosts.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
