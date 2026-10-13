import Foundation
import Darwin

// Only inspect local listeners; remote (-R) listeners belong to the SSH server.
enum PortInspection {
    struct Occupancy {
        var matchesForward: Bool
        var message: String
    }
    static func inspect(_ profile: Profile) -> Occupancy? {
        let rules = profile.rules.filter { $0.enabled && $0.kind != .remote }
        var messages = [String]()
        var matched = 0
        for rule in rules {
            var seen = Set<Int32>()
            let owners = listeners(port: rule.listenPort).filter { overlaps($0.address, rule.bindAddress) && seen.insert($0.pid).inserted }
            guard !owners.isEmpty else { continue }
            let same = owners.count == 1 && owners.allSatisfy {
                $0.command == "ssh" && matches(arguments: arguments(pid: $0.pid), profile: profile, rule: rule)
            }
            if same { matched += 1 }
            let names = owners.map { "\($0.command)（PID \($0.pid)）" }.joined(separator: "、")
            let owner = names.isEmpty ? "无法读取占用进程" : names
            messages.append("\(rule.bindAddress):\(rule.listenPort) 已被 \(owner) 使用。" + (same ? "已确认 SSH 启动参数及转发目标与本规则一致，跳过重复启动。" : "无法确认与本规则一致，请停止原转发或修改监听端口后重试。"))
        }
        guard !messages.isEmpty else { return nil }
        return Occupancy(matchesForward: matched == rules.count && rules.count == profile.rules.filter(\.enabled).count,
                         message: messages.joined(separator: "\n"))
    }
    private struct Listener { var pid: Int32; var command: String; var address: String }
    private static func listeners(port: String) -> [Listener] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpcn"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        var pid: Int32 = 0, command = "", result = [Listener]()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                if let colon = value.lastIndex(of: ":") {
                    result.append(Listener(pid: pid, command: command, address: String(value[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))))
                }
            default: break
            }
        }
        return result
    }
    private static func overlaps(_ listener: String, _ bind: String) -> Bool {
        listener == "*" || listener == "0.0.0.0" || listener == "::" || bind == "0.0.0.0" || bind == "::" || listener == bind || (bind == "localhost" && ["127.0.0.1", "::1"].contains(listener))
    }
    // KERN_PROCARGS2 preserves argument boundaries, unlike parsing `ps` text.
    private static func arguments(pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var bytes = [UInt8](repeating: 0, count: size)
        let success = bytes.withUnsafeMutableBytes { sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0) }
        guard success == 0 else { return [] }
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size && bytes[index] != 0 { index += 1 } // Executable path.
        while index < size && bytes[index] == 0 { index += 1 }
        var result = [String]()
        for _ in 0..<max(0, count) {
            let start = index
            while index < size && bytes[index] != 0 { index += 1 }
            guard index < size else { return [] }
            result.append(String(decoding: bytes[start..<index], as: UTF8.self)); index += 1
        }
        return result
    }
    static func matches(arguments: [String], profile: Profile, rule: ForwardRule) -> Bool {
        guard let executable = arguments.first, URL(fileURLWithPath: executable).lastPathComponent == "ssh" else { return false }
        var forwards = [String](), host = "", config: String?, user = "", port = "22", identity = ""
        let harmlessOptions: Set<String> = ["exitonforwardfailure", "serveraliveinterval", "serveralivecountmax", "connecttimeout", "controlmaster", "controlpath", "controlpersist", "forkafterauthentication", "stricthostkeychecking", "numberofpasswordprompts", "batchmode", "loglevel"]
        var index = 1
        while index < arguments.count {
            let token = arguments[index]; index += 1
            if !token.hasPrefix("-") {
                guard host.isEmpty, index == arguments.count else { return false }
                host = token; break
            }
            let flags = Array(token.dropFirst())
            var offset = 0
            while offset < flags.count {
                let flag = flags[offset]; offset += 1
                if "fNMTnqv46".contains(flag) { continue }
                guard "LDFilpSoER".contains(flag) else { return false }
                let value: String
                if offset < flags.count { value = String(flags[offset...]); offset = flags.count }
                else { guard index < arguments.count else { return false }; value = arguments[index]; index += 1 }
                switch flag {
                case "L": forwards.append(value)
                case "F": config = value
                case "l": user = value
                case "p": port = value
                case "i": identity = value
                case "o":
                    guard let key = ConfigHosts.tokens(value).first?.lowercased(), harmlessOptions.contains(key) else { return false }
                default: break
                }
            }
        }
        guard host == profile.host, user == profile.user, identity == profile.identity else { return false }
        func path(_ text: String) -> String { URL(fileURLWithPath: SSHCommand.expanded(text)).standardizedFileURL.path }
        if profile.useConfig {
            guard port == "22", path(config ?? "~/.ssh/config") == path(profile.configPath) else { return false }
        } else {
            guard config == "none", port == profile.port else { return false }
        }
        guard rule.kind == .local else { return false } // SOCKS endpoints need separate verification.
        return forwards.contains { spec in
            var parts = [String](), text = "", bracket = false
            for char in spec {
                if char == "[" { bracket = true; continue }
                if char == "]" { bracket = false; continue }
                if char == ":" && !bracket { parts.append(text); text = "" } else { text.append(char) }
            }
            parts.append(text)
            if parts.count == 3 { parts.insert("localhost", at: 0) }
            guard parts.count == 4 else { return false }
            let sameBind = parts[0] == rule.bindAddress || (parts[0] == "localhost" && ["localhost", "127.0.0.1", "::1"].contains(rule.bindAddress))
            return sameBind && parts[1] == rule.listenPort && parts[2] == rule.targetHost && parts[3] == rule.targetPort
        }
    }
}
