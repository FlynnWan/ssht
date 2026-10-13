import Testing
import Foundation
import AppKit
@testable import SSHT

struct BackgroundLifecycleTests {
    @Test @MainActor func closingWindowKeepsSSHProcessRunning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-background-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config")
        try "Host slow\n HostName 127.0.0.1\n ProxyCommand /bin/sleep 30\n".write(to: config, atomically: true, encoding: .utf8)
        let store = TunnelStore(storageDirectory: directory)
        defer { store.shutdown() }
        var profile = Profile(); profile.host = "slow"; profile.useConfig = true; profile.configPath = config.path
        store.profiles = [profile]
        let item = try #require(store.ruleItems.first)
        store.startRule(item)
        let delegate = AppDelegate(); delegate.store = store
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        #expect(store.state(item.id).status == .connecting)
        store.stopAll()
        for _ in 0..<50 {
            if store.state(item.id).status == .idle { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(store.state(item.id).status == .idle)
    }
    @Test func legacyDisabledBackgroundSettingIsIgnored() throws {
        let data = Data("""
        {"restoreOnLaunch":false,"runInMenuBar":false,"appearance":"dark","recordLogs":true,"retentionDays":7,"previousRules":[]}
        """.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(preferences.appearance == .dark)
        #expect(preferences.retentionDays == 7)
        let saved = String(decoding: try JSONEncoder().encode(preferences), as: UTF8.self)
        #expect(!saved.contains("runInMenuBar"))
    }
    @Test @MainActor func closingBeforeStoreIsAttachedDoesNotQuit() {
        #expect(!AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
