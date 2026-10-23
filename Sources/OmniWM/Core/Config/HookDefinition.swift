// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct HookDefinition: Codable, Equatable, Sendable {
    var event: HookEvent
    var matcher: HookMatcher?
    var commands: [HookCommand]
}

struct HookMatcher: Codable, Equatable, Sendable {
    var bundleId: String?
    var titleRegex: String?
    var commandName: String?
}

struct HookCommand: Codable, Equatable, Sendable {
    static let defaultTimeoutMs = 500

    var command: String
    var timeoutMs = HookCommand.defaultTimeoutMs
    var onFailure = HookFailurePolicy.allow
}

enum HookFailurePolicy: String, Codable, Sendable {
    case allow
    case deny
}

extension HookCommand {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? Self.defaultTimeoutMs
        onFailure = try container.decodeIfPresent(HookFailurePolicy.self, forKey: .onFailure) ?? .allow
    }
}
