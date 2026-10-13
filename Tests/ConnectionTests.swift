import Testing
import Foundation
@testable import SSHT

struct ConnectionTests {
    @Test @MainActor func testRealSSHFailureAndPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        var p = Profile(); p.host = "127.0.0.1"; p.port = "1"; p.name = "测试连接"
        store.profiles = [p]
        store.start(p, password: "test-secret-do-not-persist")
        for _ in 0..<100 {
            if store.state(p.id).status == .failed { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(store.state(p.id).status == .failed)
        #expect(store.state(p.id).log.contains("退出码"))
        let saved = try String(contentsOf: directory.appendingPathComponent("profiles.json"), encoding: .utf8)
        #expect(!(saved.contains("test-secret")))
        let restored = TunnelStore(storageDirectory: directory)
        defer { restored.shutdown() }
        #expect(restored.profiles == [p])
    }
    @Test @MainActor func testValidationDoesNotLaunchProcess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        let p = Profile()
        store.start(p, password: "")
        #expect(store.state(p.id).status == .failed)
        #expect(store.error != nil)
    }
}
