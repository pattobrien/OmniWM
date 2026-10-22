// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension WMController {
    func handleHookReply(_ reply: HookReply) {
        switch reply {
        case let .workspaceActivation(id, token, decision):
            axEventHandler.handleActivationHookReply(id, token: token, decision: decision)
        case let .windowAdmission(id, windowId, decision):
            axEventHandler.handleAdmissionHookReply(id, windowId: windowId, decision: decision)
        case let .command(id, decision):
            commandHookGate.resume(id, decision: decision)
        }
    }

    var hookActiveWorkspace: HookWorkspaceRef? {
        workspaceManager.interactionMonitorId
            .flatMap { workspaceManager.activeWorkspace(on: $0) }
            .map(HookWorkspaceRef.init)
    }

    func hookWindowFacts(for token: WindowToken) -> HookWindowFacts {
        HookWindowFacts(
            id: token.windowId,
            pid: token.pid,
            bundleId: axEventHandler.resolveBundleId(token.pid),
            appName: appInfoCache.name(for: token.pid),
            title: UInt32(exactly: token.windowId).flatMap { AXWindowService.cachedTitle(windowId: $0) },
            role: nil,
            subrole: nil
        )
    }
}

extension HookWorkspaceRef {
    init(_ descriptor: WorkspaceDescriptor) {
        self.init(id: descriptor.id, name: descriptor.name)
    }
}

extension CommandHookPayload {
    @MainActor
    init(_ descriptor: HookCommandDescriptor, controller: WMController) {
        self.init(
            command: Command(name: descriptor.name, source: descriptor.source, arguments: descriptor.arguments),
            focusedWindow: controller.workspaceManager.nativeManagedFocusToken.map(controller.hookWindowFacts(for:)),
            activeWorkspace: controller.hookActiveWorkspace
        )
    }
}
