// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum HookEvent: String, Codable, CaseIterable, Sendable {
    case preWorkspaceActivation = "pre-workspace-activation"
    case preWindowAdmission = "pre-window-admission"
    case preCommand = "pre-command"
    case postWorkspaceChange = "post-workspace-change"

    var isBlocking: Bool {
        self != .postWorkspaceChange
    }
}

struct HookMatchSubject: Sendable {
    var bundleId: String?
    var title: String?
    var commandName: String?

    static let none = HookMatchSubject()
}

protocol HookPayload: Encodable, Sendable {
    static var event: HookEvent { get }
    var subject: HookMatchSubject { get }
}

protocol BlockingHookPayload: HookPayload {
    associatedtype Modification: Decodable & Sendable
}

protocol PostHookPayload: HookPayload {}

struct HookWindowFacts: Encodable, Sendable {
    let id: Int
    let pid: Int32
    let bundleId: String?
    let appName: String?
    let title: String?
    let role: String?
    let subrole: String?

    private enum CodingKeys: String, CodingKey {
        case id, pid, bundleId, appName, title, role, subrole
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pid, forKey: .pid)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(appName, forKey: .appName)
        try container.encode(title, forKey: .title)
        try container.encode(role, forKey: .role)
        try container.encode(subrole, forKey: .subrole)
    }
}

struct HookWorkspaceRef: Encodable, Sendable {
    let id: UUID
    let name: String
}

struct WorkspaceActivationHookPayload: BlockingHookPayload {
    typealias Modification = Never
    static let event = HookEvent.preWorkspaceActivation

    let window: HookWindowFacts
    let workspace: HookWorkspaceRef
    let activeWorkspace: HookWorkspaceRef?
    let monitorId: UInt32
    let source: String

    var subject: HookMatchSubject {
        HookMatchSubject(bundleId: window.bundleId, title: window.title)
    }

    private enum CodingKeys: String, CodingKey {
        case window, workspace, activeWorkspace, monitorId, source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(window, forKey: .window)
        try container.encode(workspace, forKey: .workspace)
        try container.encode(activeWorkspace, forKey: .activeWorkspace)
        try container.encode(monitorId, forKey: .monitorId)
        try container.encode(source, forKey: .source)
    }
}

struct HookProposedAdmission: Encodable, Sendable {
    let workspace: String?
    let float: Bool

    private enum CodingKeys: String, CodingKey {
        case workspace, float
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspace, forKey: .workspace)
        try container.encode(float, forKey: .float)
    }
}

struct WindowAdmissionHookPayload: BlockingHookPayload {
    typealias Modification = WindowAdmissionModification
    static let event = HookEvent.preWindowAdmission

    let window: HookWindowFacts
    let proposed: HookProposedAdmission
    let activeWorkspace: HookWorkspaceRef?

    var subject: HookMatchSubject {
        HookMatchSubject(bundleId: window.bundleId, title: window.title)
    }

    private enum CodingKeys: String, CodingKey {
        case window, proposed, activeWorkspace
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(window, forKey: .window)
        try container.encode(proposed, forKey: .proposed)
        try container.encode(activeWorkspace, forKey: .activeWorkspace)
    }
}

struct CommandHookPayload: BlockingHookPayload {
    typealias Modification = Never
    static let event = HookEvent.preCommand

    struct Command: Encodable, Sendable {
        let name: String
        let source: HookCommandSource
        let arguments: [String: String]
    }

    let command: Command
    let focusedWindow: HookWindowFacts?
    let activeWorkspace: HookWorkspaceRef?

    var subject: HookMatchSubject {
        HookMatchSubject(commandName: command.name)
    }

    private enum CodingKeys: String, CodingKey {
        case command, focusedWindow, activeWorkspace
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(focusedWindow, forKey: .focusedWindow)
        try container.encode(activeWorkspace, forKey: .activeWorkspace)
    }
}

struct WorkspaceChangeHookPayload: PostHookPayload {
    static let event = HookEvent.postWorkspaceChange

    let from: HookWorkspaceRef?
    let to: HookWorkspaceRef?
    let monitorId: UInt32?

    var subject: HookMatchSubject {
        .none
    }

    private enum CodingKeys: String, CodingKey {
        case from, to, monitorId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(monitorId, forKey: .monitorId)
    }
}

struct HookEnvelope<Payload: HookPayload>: Encodable {
    let payload: Payload

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? {
            nil
        }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(Payload.event.rawValue, forKey: Key(stringValue: "hookEventName"))
        try payload.encode(to: encoder)
    }

    static func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(HookEnvelope(payload: payload))
    }
}
