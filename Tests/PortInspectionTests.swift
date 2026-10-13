import Testing
import Foundation
@testable import SSHT

struct PortInspectionTests {
    @Test func verifiesSSHForwardAndConnectionOptions() {
        var profile = Profile(); profile.host = "dell"; profile.useConfig = true
        let rule = ForwardRule(listenPort: "6379", targetPort: "9736")
        let args = ["ssh", "-fN", "-M", "-S", "/tmp/test-control", "-o", "ExitOnForwardFailure=yes", "-L", "6379:127.0.0.1:9736", "dell"]
        #expect(PortInspection.matches(arguments: args, profile: profile, rule: rule))
        #expect(PortInspection.matches(arguments: ["/usr/bin/ssh", "-L127.0.0.1:6379:127.0.0.1:9736", "dell"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: ["ssh", "-L6379:127.0.0.1:6379", "dell"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: Array(args.dropLast()) + ["other"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: ["ssh", "-F", "/tmp/different-config", "-L6379:127.0.0.1:9736", "dell"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: ["ssh", "-l", "other", "-L6379:127.0.0.1:9736", "dell"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: ["ssh", "-oHostName=other", "-L6379:127.0.0.1:9736", "dell"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: ["ssh", "-J", "other", "-L6379:127.0.0.1:9736", "dell"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: args + ["remote-command"], profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: ["other", "-L6379:127.0.0.1:9736", "dell"], profile: profile, rule: rule))
    }

    @Test func verifiesIPv6AndManualConfiguration() {
        var profile = Profile(); profile.host = "server"; profile.port = "2222"; profile.user = "deploy"
        let rule = ForwardRule(bindAddress: "::1", listenPort: "9090", targetHost: "2001:db8::1", targetPort: "90")
        let args = ["ssh", "-Fnone", "-p2222", "-ldeploy", "-L[::1]:9090:[2001:db8::1]:90", "server"]
        #expect(PortInspection.matches(arguments: args, profile: profile, rule: rule))
        #expect(!PortInspection.matches(arguments: ["ssh", "-p2222", "-ldeploy", "-L[::1]:9090:[2001:db8::1]:90", "server"], profile: profile, rule: rule))
    }

    @Test @MainActor func occupiedPortDoesNotLaunchSSHOrStopExternalListener() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-occupied-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let port = "45001"
        var profile = Profile(); profile.host = "127.0.0.1"; profile.rules = [ForwardRule(listenPort: port)]
        var occupied = true
        let store = TunnelStore(storageDirectory: directory, inspectPorts: { _ in
            occupied ? PortInspection.Occupancy(matchesForward: false, message: "127.0.0.1:\(port) 已被其他程序（PID 123）使用。") : nil
        })
        defer { store.shutdown() }
        store.start(profile, password: "")
        #expect(store.state(profile.id).status == .occupied)
        #expect(store.error?.contains(port) == true)
        #expect(store.state(profile.id).log.contains("PID"))
        #expect(!store.state(profile.id).log.contains("正在连接"))
        store.stopAll()
        #expect(occupied)
        occupied = false
        for _ in 0..<45 {
            if store.state(profile.id).status == .idle { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(store.state(profile.id).status == .idle)
        #expect(store.state(profile.id).log.contains("已释放"))
    }
    @Test @MainActor func matchingExternalForwardIsSkippedAndNeverStopped() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ssht-external-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var available = true
        var inspections = 0
        let store = TunnelStore(storageDirectory: directory, inspectPorts: { _ in
            inspections += 1
            return available ? PortInspection.Occupancy(matchesForward: true, message: "相同 SSH 转发已存在（PID 123）") : nil
        })
        defer { store.shutdown() }
        var profile = Profile(); profile.host = "127.0.0.1"
        store.profiles = [profile]
        let item = try #require(store.ruleItems.first)
        store.startRule(item)
        #expect(store.state(item.id).status == .external)
        #expect(store.state(item.id).running)
        #expect(!store.state(item.id).active)
        #expect(store.error == nil)
        #expect(!store.canStartAll)
        #expect(!store.canStartGroup("默认分组"))
        let log = store.state(item.id).log
        store.startAll(); store.startGroup("默认分组")
        #expect(inspections == 1)
        #expect(store.state(item.id).log == log)
        store.stopAll(); store.stopGroup("默认分组")
        #expect(store.state(item.id).status == .external)
        #expect(available)
        available = false
        for _ in 0..<45 {
            if store.state(item.id).status == .idle { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(store.state(item.id).status == .idle)
        #expect(store.canStartAll)
    }

}
