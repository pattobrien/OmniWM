// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension WMController {
    func handleHookReply(_ reply: HookReply) {
        switch reply {
        case let .workspaceActivation(id, token, _):
            Log.hooks.debug("dropped activation hook reply \(id.raw) for \(token)")
        case let .windowAdmission(id, windowId, _):
            Log.hooks.debug("dropped admission hook reply \(id.raw) for \(windowId)")
        case let .command(id, _):
            Log.hooks.debug("dropped command hook reply \(id.raw)")
        }
    }
}
