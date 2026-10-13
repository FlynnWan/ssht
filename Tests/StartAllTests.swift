import Testing
import Foundation
@testable import SSHT

struct StartAllTests {
    @Test @MainActor func startsPendingRulesAndPreservesExistingConnection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-start-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "Host slow\n HostName 127.0.0.1\n ProxyCommand /bin/sleep 30\n".write(to: config, atomically: true, encoding: .utf8)
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        var profile = Profile(); profile.host = "slow"; profile.useConfig = true; profile.configPath = config.path
        profile.rules = [ForwardRule(name: "已连接中的规则"), ForwardRule(listenPort: "8081", name: "待启动规则"), ForwardRule(listenPort: "invalid", name: "无效规则"), ForwardRule(listenPort: "8082", name: "后续有效规则")]
        store.profiles = [profile]
        let items = store.ruleItems
        store.startRule(items[0])
        let initialLog = store.state(items[0].id).log
        #expect(store.canStartAll)
        store.startAll()
        #expect(store.state(items[0].id).status == .connecting)
        #expect(store.state(items[0].id).log == initialLog)
        #expect(store.state(items[1].id).status == .connecting)
        #expect(store.state(items[2].id).status == .failed)
        #expect(store.state(items[3].id).status == .connecting)
        #expect(store.error?.contains("无效规则") == true)
        store.startAll()
        #expect(store.state(items[0].id).log == initialLog)
        #expect(store.state(items[1].id).log.components(separatedBy: "正在连接").count == 2)
        store.stopAll()
        for _ in 0..<50 {
            if [items[0], items[1], items[3]].allSatisfy({ store.state($0.id).status == .idle }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect([items[0], items[1], items[3]].allSatisfy { store.state($0.id).status == .idle })
    }
}
