import Testing
import Foundation
@testable import SSHT

struct ConfigSelectionTests {
    @Test @MainActor func addingUsesConfigInsteadOfSavedOverrides() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-config-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "Host test\n HostName 192.0.2.10\n User from-config\n Port 2222\n IdentityFile ~/.ssh/config-key\n ProxyJump bastion\n".write(to: config, atomically: true, encoding: .utf8)
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        var previous = Profile(); previous.useConfig = true; previous.configPath = config.path; previous.host = "test"
        previous.user = "stale-user"; previous.identity = "/missing/old/key"
        store.profiles = [previous]
        let rule = ForwardRule(name: "配置中的主机")
        try store.addConfigRule(rule, alias: "test", configPath: config.path)
        let created = try #require(store.profiles.first { $0.rules.contains { $0.id == rule.id } })
        #expect(created.id != previous.id)
        #expect(created.useConfig)
        #expect(created.host == "test")
        #expect(created.user.isEmpty)
        #expect(created.identity.isEmpty)
        let arguments = try SSHCommand.arguments(created, socket: "/tmp/ssht-test.sock")
        #expect(arguments.contains(config.path))
        #expect(!arguments.contains("-l"))
        #expect(!arguments.contains("-p"))
        #expect(!arguments.contains("-i"))
        let another = ForwardRule(listenPort: "8081", name: "同主机另一条规则")
        try store.addConfigRule(another, alias: "test", configPath: config.path)
        #expect(store.profiles.count == 2)
        #expect(store.profiles.last?.rules.map(\.id) == [rule.id, another.id])
    }
    @Test @MainActor func removedConfigAliasCannotCreateRule() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-config-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "Host previous\n HostName 192.0.2.1\n".write(to: config, atomically: true, encoding: .utf8)
        #expect(try ConfigHosts.load(config.path) == ["previous"])
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        let original = store.profiles
        try "Host current\n HostName 192.0.2.2\n".write(to: config, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try store.addConfigRule(ForwardRule(), alias: "previous", configPath: config.path) }
        #expect(store.profiles == original)
        try store.addConfigRule(ForwardRule(name: "当前主机"), alias: "current", configPath: config.path)
        #expect(store.profiles.last?.host == "current")
    }
}
