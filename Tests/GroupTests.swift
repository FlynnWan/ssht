import Testing
import Foundation
@testable import SSHT

struct GroupTests {
    @Test func legacyRulesUseDefaultGroup() throws {
        let rule = ForwardRule()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
        json.removeValue(forKey: "group")
        let decoded = try JSONDecoder().decode(ForwardRule.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.groupName == "默认分组")
        #expect(decoded.id == rule.id)
    }

    @Test @MainActor func groupsPersistAndOperateAcrossConnections() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-groups-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "Host slow\n HostName 127.0.0.1\n ProxyCommand /bin/sleep 30\n".write(to: config, atomically: true, encoding: .utf8)
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        var first = Profile(); first.host = "slow"; first.useConfig = true; first.configPath = config.path
        first.rules = [ForwardRule(group: "开发"), ForwardRule(listenPort: "8081", group: "其他")]
        var second = first; second.id = UUID()
        second.rules = [ForwardRule(listenPort: "8082", group: "开发"), ForwardRule(listenPort: "invalid", name: "无效规则", group: "开发")]
        store.profiles = [first, second]
        let items = store.ruleItems
        store.startRule(items[0])
        let initialLog = store.state(items[0].id).log
        store.startGroup("开发")
        #expect(store.state(items[0].id).log == initialLog)
        #expect(store.state(items[1].id).status == .idle)
        #expect(store.state(items[2].id).status == .connecting)
        #expect(store.state(items[3].id).status == .failed)
        #expect(store.error?.contains("无效规则") == true)
        store.moveRule(items[2], to: "共享")
        #expect(store.state(items[2].id).status == .connecting)
        #expect(store.items(in: "共享").map(\.id) == [items[2].id])
        store.stopGroup("开发")
        #expect(store.state(items[2].id).status == .connecting)
        store.stopGroup("共享")
        for _ in 0..<50 {
            if [items[0], items[2]].allSatisfy({ store.state($0.id).status == .idle }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect([items[0], items[2]].allSatisfy { store.state($0.id).status == .idle })
        let saved = try JSONDecoder().decode([Profile].self, from: Data(contentsOf: directory.appendingPathComponent("profiles.json")))
        #expect(saved[1].rules[0].group == "共享")
        #expect(store.items(in: "不存在").isEmpty)
        #expect(!store.canStartGroup("不存在"))
    }
}
