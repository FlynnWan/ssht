import Testing
import Foundation
@testable import SSHT

struct CoreTests {
    @Test func testLocalRemoteAndSOCKSArguments() throws {
        var p = Profile(); p.host = "192.0.2.10"; p.user = "deploy"
        p.rules = [ForwardRule(), ForwardRule(kind: .remote, listenPort: "9000", targetPort: "3000"), ForwardRule(kind: .socks, listenPort: "1080")]
        let args = try SSHCommand.arguments(p, socket: "/tmp/test.sock")
        #expect(args.contains("127.0.0.1:8080:127.0.0.1:80"))
        #expect(args.contains("127.0.0.1:9000:127.0.0.1:3000"))
        #expect(args.contains("127.0.0.1:1080"))
        #expect(args.last == "192.0.2.10")
        #expect(args.contains("ExitOnForwardFailure=yes"))
        #expect(args.contains("none"))
    }
    @Test func testIPv6() throws {
        var p = Profile(); p.host = "2001:db8::1"
        p.rules = [ForwardRule(bindAddress: "::1", targetHost: "2001:db8::2")]
        let args = try SSHCommand.arguments(p, socket: "/tmp/test.sock")
        #expect(args.contains("[::1]:8080:[2001:db8::2]:80"))
        #expect(args.last == "2001:db8::1")
    }
    @Test func testInvalidAndConflictingPorts() {
        var p = Profile(); p.host = "server"
        p.rules[0].listenPort = "65536"
        #expect(throws: (any Error).self) { try SSHCommand.arguments(p, socket: "socket") }
        p.rules = [ForwardRule(), ForwardRule(kind: .socks)]
        #expect(throws: (any Error).self) { try SSHCommand.arguments(p, socket: "socket") }
        p.rules = [ForwardRule(enabled: false)]
        #expect(throws: (any Error).self) { try SSHCommand.arguments(p, socket: "socket") }
    }
    @Test func testOptionInjectionAndEmptyHostRejected() {
        var p = Profile(); p.host = "-oProxyCommand=evil"
        #expect(throws: (any Error).self) { try SSHCommand.arguments(p, socket: "socket") }
        p.host = ""
        #expect(throws: (any Error).self) { try SSHCommand.arguments(p, socket: "socket") }
        p.host = "user@host"
        #expect(throws: (any Error).self) { try SSHCommand.arguments(p, socket: "socket") }
    }
    @Test func testConfigIncludesAliasesAndWildcardFiltering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let child = directory.appendingPathComponent("child config")
        let root = directory.appendingPathComponent("config")
        try "Host child second\n HostName 192.0.2.1\nInclude \"\(root.path)\"\n".write(to: child, atomically: true, encoding: .utf8)
        try "Host=prod staging *.example !excluded\n User deploy\nInclude \"\(child.path)\"\nHost prod # comment\n".write(to: root, atomically: true, encoding: .utf8)
        #expect(try ConfigHosts.load(root.path) == ["child", "prod", "second", "staging"])
        var p = Profile(); p.host = "prod"; p.useConfig = true; p.configPath = root.path; p.user = ""; p.port = "n/a"
        let args = try SSHCommand.arguments(p, socket: "socket")
        #expect(args.contains(root.path))
        #expect(!(args.contains("-p")))
        #expect(!(args.contains("-l")))
    }
    @Test func testProfileRoundTrip() throws {
        var p = Profile(); p.host = "dev"; p.rules.append(ForwardRule(kind: .remote))
        #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p)) == p)
    }
}
