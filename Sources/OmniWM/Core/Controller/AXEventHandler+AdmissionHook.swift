// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension AXEventHandler {
    enum AdmissionHookOutcome {
        case pending
        case denied
        case decided(WindowDecision)
    }

    func admissionHookDecision(
        for evaluation: WMController.WindowDecisionEvaluation,
        windowId: UInt32,
        controller: WMController
    ) -> AdmissionHookOutcome {
        if let reply = controller.hookWaits.admissionReplies.removeValue(forKey: windowId) {
            return admissionOutcome(reply, decision: evaluation.decision, windowId: windowId, controller: controller)
        }
        if controller.hookWaits.admission[windowId] != nil { return .pending }
        guard evaluation.decision.tracksWindow else { return .decided(evaluation.decision) }
        let payload = WindowAdmissionHookPayload(
            window: HookWindowFacts(
                id: Int(windowId),
                pid: evaluation.token.pid,
                bundleId: evaluation.facts.ax.bundleId,
                appName: evaluation.facts.appName,
                title: evaluation.facts.ax.title,
                role: evaluation.facts.ax.role,
                subrole: evaluation.facts.ax.subrole
            ),
            proposed: .init(
                workspace: evaluation.decision.workspaceName,
                float: evaluation.decision.disposition == .floating
            ),
            activeWorkspace: controller.hookActiveWorkspace
        )
        switch controller.hookDispatcher.gate(payload, reply: { .windowAdmission($0, windowId: windowId, $1) }) {
        case .unhooked:
            return .decided(evaluation.decision)
        case let .pending(id):
            controller.hookWaits.admission[windowId] = id
            return .pending
        }
    }

    func handleAdmissionHookReply(
        _ id: HookWaitID,
        windowId: UInt32,
        decision: HookDecision<WindowAdmissionModification>
    ) {
        guard let controller, controller.hookWaits.admission[windowId] == id else {
            Log.hooks.debug("dropped stale admission hook reply \(id.raw) for \(windowId)")
            return
        }
        controller.hookWaits.admission[windowId] = nil
        controller.hookWaits.admissionReplies[windowId] = decision
        if !dispatchAdmissionRetry(windowId: windowId) {
            forgetAdmissionHook(windowId: windowId)
        }
    }

    func forgetAdmissionHook(windowId: UInt32) {
        guard let controller else { return }
        controller.hookWaits.admission[windowId] = nil
        controller.hookWaits.admissionReplies[windowId] = nil
    }

    private func admissionOutcome(
        _ reply: HookDecision<WindowAdmissionModification>,
        decision: WindowDecision,
        windowId: UInt32,
        controller: WMController
    ) -> AdmissionHookOutcome {
        switch reply {
        case .allow:
            return .decided(decision)
        case let .modify(modification):
            guard let name = modification.workspace,
                  controller.workspaceManager.workspaceId(named: name) == nil
            else { return .decided(decision.applying(modification)) }
            Log.hooks.notice("pre-window-admission named unknown workspace \(name) for window \(windowId)")
            return .decided(decision.applying(WindowAdmissionModification(workspace: nil, float: modification.float)))
        case let .deny(reason):
            Log.hooks.notice("pre-window-admission denied window \(windowId): \(reason.text)")
            return .denied
        }
    }
}
