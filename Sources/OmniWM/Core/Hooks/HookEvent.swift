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
