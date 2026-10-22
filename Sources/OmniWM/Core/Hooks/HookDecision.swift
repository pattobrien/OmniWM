// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum HookDecision<Modification: Sendable>: Sendable {
    case allow
    case modify(Modification)
    case deny(HookDenyReason)
}

extension HookDecision: Equatable where Modification: Equatable {}

struct HookDenyReason: Sendable, Equatable {
    let text: String
}

extension HookDenyReason {
    init(stderr: Data, fallback: String) {
        let trimmed = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmed.isEmpty ? fallback : trimmed
    }
}

struct WindowAdmissionModification: Decodable, Sendable, Equatable {
    let workspace: String?
    let float: Bool?
}

struct HookWaitID: Hashable, Sendable {
    let raw: UInt64
}

enum HookReply: Sendable {
    case workspaceActivation(HookWaitID, token: WindowToken, HookDecision<Never>)
    case windowAdmission(HookWaitID, windowId: UInt32, HookDecision<WindowAdmissionModification>)
    case command(HookWaitID, HookDecision<Never>)
}
