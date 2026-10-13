import Foundation
import SwiftUI

struct AppPreferences: Codable, Equatable {
    enum Appearance: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" } }
        var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    }
    var restoreOnLaunch = false
    var appearance: Appearance = .system
    var recordLogs = true
    var retentionDays = 7
    var previousRules = [UUID]()
}

struct RuleItem: Identifiable, Equatable {
    var profileID: UUID
    var profileName: String
    var sshHost: String
    var rule: ForwardRule
    var id: UUID { rule.id }
    var name: String { rule.name.isEmpty ? profileName : rule.name }
    var protocolName: String { rule.kind == .socks ? "SOCKS5" : "TCP" }
    var searchText: String { [name, rule.groupName, profileName, sshHost, rule.bindAddress, rule.listenPort, rule.targetHost, rule.targetPort, rule.kind.title].joined(separator: " ") }
}
