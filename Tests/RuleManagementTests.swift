import Testing
import Foundation
@testable import SSHT

struct RuleManagementTests {
    @Test func legacyProfilesKeepConnectionAndRules() throws {
        var p = Profile(); p.host = "legacy-host"; p.useConfig = true
        p.rules = [ForwardRule(listenPort: "11002", targetPort: "11002"), ForwardRule(listenPort: "10009", targetPort: "10009")]
        let encoded = try JSONEncoder().encode(p)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["rules"] = (json["rules"] as! [[String: Any]]).map { value in
            var old = value; old.removeValue(forKey: "name"); old.removeValue(forKey: "autoStart"); return old
        }
        let migrated = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(migrated.host == "legacy-host")
        #expect(migrated.useConfig)
        #expect(migrated.rules.map(\.id) == p.rules.map(\.id))
        #expect(migrated.rules.map(\.listenPort) == ["11002", "10009"])
        #expect(migrated.rules.allSatisfy { $0.name.isEmpty && !$0.autoStart })
    }
    @Test @MainActor func rulesHaveIndependentSSHProcessesAndLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        var p = Profile(); p.host = "127.0.0.1"; p.port = "1"
        p.rules = [ForwardRule(name: "Web"), ForwardRule(listenPort: "13306", targetPort: "3306", name: "Database")]
        store.profiles = [p]
        let items = store.ruleItems
        let session = try #require(store.sessionProfile(for: items[0]))
        #expect(session.id == items[0].id)
        #expect(session.rules == [p.rules[0]])
        #expect(session.host == p.host)
        store.startRule(items[0])
        #expect(store.state(items[1].id).status == .idle)
        for _ in 0..<100 {
            if store.state(items[0].id).status == .failed { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(store.state(items[0].id).status == .failed)
        #expect(store.state(p.id).status == .idle)
        store.removeRule(items[0])
        #expect(store.ruleItems.map(\.id) == [items[1].id])
        #expect(store.profiles.first?.host == p.host)
    }
    @Test @MainActor func stopAllCancelsConnectingSSH() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "Host slow\n HostName 127.0.0.1\n ProxyCommand /bin/sleep 30\n".write(to: config, atomically: true, encoding: .utf8)
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        var p = Profile(); p.host = "slow"; p.useConfig = true; p.configPath = config.path
        store.profiles = [p]
        let item = try #require(store.ruleItems.first)
        store.startRule(item)
        #expect(store.state(item.id).status == .connecting)
        store.stopAll()
        for _ in 0..<50 {
            if store.state(item.id).status == .idle { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(store.state(item.id).status == .idle)
        #expect(store.state(item.id).log.contains("转发已停止"))
    }
    @Test @MainActor func preferencesAndLogRetention() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        store.preferences.appearance = .dark
        store.preferences.retentionDays = 1
        store.savePreferences()
        store.append(UUID(), "连接失败测试\n")
        #expect(store.savedLog().contains("连接失败测试"))
        let old = store.logsDirectory.appendingPathComponent("2000-01-01.log")
        try Data("old".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)
        store.pruneLogs()
        #expect(!FileManager.default.fileExists(atPath: old.path))
        store.preferences.recordLogs = false
        store.append(UUID(), "should-not-persist\n")
        #expect(!store.savedLog().contains("should-not-persist"))
        store.savePreferences()
        let restored = TunnelStore(storageDirectory: directory)
        defer { restored.shutdown() }
        #expect(restored.preferences.appearance == .dark)
        #expect(restored.preferences.retentionDays == 1)
        #expect(!restored.preferences.recordLogs)
        store.clearLogs()
        #expect(store.savedLog().isEmpty)
    }
}
