// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension AXEventHandler {
    func gateTrackedActivation(
        _ entry: WindowState,
        isWorkspaceActive: Bool,
        requestDisposition: ActivationRequestDisposition,
        facts: ActivationFacts,
        appFullscreen: Bool
    ) -> Bool {
        guard !isWorkspaceActive, case .unrelatedNoRequest = requestDisposition else { return false }
        return gateWorkspaceActivation(
            entry,
            observationGeneration: facts.observationGeneration,
            activation: ParkedManagedActivation(
                appFullscreen: appFullscreen,
                source: facts.source,
                origin: facts.origin,
                activeRequestId: nil,
                bindCurrentPidRequest: true,
                callbackGeneration: facts.callbackGeneration
            )
        )
    }

    func gateFocusedAdmissionActivation(
        _ entry: WindowState,
        isWorkspaceActive: Bool,
        activation: PendingFocusedManagedActivation,
        bindCurrentPidRequest: Bool
    ) -> Bool {
        guard !isWorkspaceActive else { return false }
        return gateWorkspaceActivation(
            entry,
            observationGeneration: activation.observationGeneration,
            activation: ParkedManagedActivation(
                appFullscreen: activation.appFullscreen,
                source: activation.source,
                origin: activation.origin,
                activeRequestId: activation.request.requestId,
                bindCurrentPidRequest: bindCurrentPidRequest,
                callbackGeneration: activation.callbackGeneration
            )
        )
    }

    func handleActivationHookReply(_ id: HookWaitID, token: WindowToken, decision: HookDecision<Never>) {
        guard let controller, let wait = controller.hookWaits.activation[token], wait.id == id else { return }
        controller.hookWaits.activation[token] = nil
        guard wait.observationGeneration == latestActivationObservationGeneration,
              controller.intentLedger.newestFocusIntentIssuedAtSeq() == wait.focusIntentSeq,
              let entry = controller.workspaceManager.entry(for: token),
              entry.workspaceId == wait.workspaceId,
              !isActiveWorkspace(entry.workspaceId, controller: controller)
        else {
            Log.hooks.debug("dropped stale activation hook reply \(id.raw) for \(token)")
            return
        }
        switch decision {
        case .allow:
            handleManagedAppActivation(
                entry: entry,
                isWorkspaceActive: false,
                appFullscreen: wait.activation.appFullscreen,
                source: wait.activation.source,
                confirmRequest: true,
                origin: wait.activation.origin,
                activeRequestId: wait.activation.activeRequestId,
                bindCurrentPidRequest: wait.activation.bindCurrentPidRequest,
                callbackGeneration: wait.activation.callbackGeneration
            )
        case let .deny(reason):
            denyWorkspaceActivation(entry, reason: reason, controller: controller)
        }
    }

    private func gateWorkspaceActivation(
        _ entry: WindowState,
        observationGeneration: UInt64,
        activation: ParkedManagedActivation
    ) -> Bool {
        guard let controller,
              controller.intentLedger.classifyFocusObservation(token: entry.token) == .external
        else { return false }
        let token = entry.token
        let focusIntentSeq = controller.intentLedger.newestFocusIntentIssuedAtSeq()
        if var wait = controller.hookWaits.activation[token], wait.workspaceId == entry.workspaceId {
            wait.observationGeneration = observationGeneration
            wait.focusIntentSeq = focusIntentSeq
            wait.activation = activation
            controller.hookWaits.activation[token] = wait
            return true
        }
        guard let payload = activationPayload(entry, source: activation.source, controller: controller),
              case let .pending(id) = controller.hookDispatcher.gate(
                  payload,
                  reply: { .workspaceActivation($0, token: token, $1) }
              )
        else { return false }
        controller.hookWaits.activation[token] = ActivationHookWait(
            id: id,
            workspaceId: entry.workspaceId,
            observationGeneration: observationGeneration,
            focusIntentSeq: focusIntentSeq,
            activation: activation
        )
        return true
    }

    private func activationPayload(
        _ entry: WindowState,
        source: ActivationEventSource,
        controller: WMController
    ) -> WorkspaceActivationHookPayload? {
        guard let workspace = controller.workspaceManager.descriptor(for: entry.workspaceId),
              let monitor = controller.workspaceManager.monitor(for: entry.workspaceId)
        else { return nil }
        let facts = controller.hookWindowFacts(for: entry.token)
        return WorkspaceActivationHookPayload(
            window: HookWindowFacts(
                id: facts.id,
                pid: facts.pid,
                bundleId: entry.managedReplacementMetadata?.bundleId ?? facts.bundleId,
                appName: facts.appName,
                title: facts.title,
                role: facts.role,
                subrole: facts.subrole
            ),
            workspace: HookWorkspaceRef(workspace),
            activeWorkspace: controller.workspaceManager.activeWorkspace(on: monitor.id).map(HookWorkspaceRef.init),
            monitorId: monitor.displayId,
            source: source.rawValue
        )
    }

    private func isActiveWorkspace(_ workspaceId: WorkspaceDescriptor.ID, controller: WMController) -> Bool {
        guard let monitorId = controller.workspaceManager.monitorId(for: workspaceId) else { return false }
        return controller.workspaceManager.activeWorkspace(on: monitorId)?.id == workspaceId
    }

    private func denyWorkspaceActivation(_ entry: WindowState, reason: HookDenyReason, controller: WMController) {
        WindowAdmissionTrace.record(
            .init(
                action: .managedFocusObserved,
                pid: entry.pid,
                windowId: entry.windowId,
                bundleId: entry.managedReplacementMetadata?.bundleId,
                reason: "hook_denied: \(reason.text)",
                axRef: entry.axRef
            )
        )
        Log.hooks.notice("pre-workspace-activation denied for \(entry.token): \(reason.text)")
        guard !controller.shouldSuppressManagedFocusRecovery,
              !controller.isLockScreenActive,
              let monitorId = controller.workspaceManager.monitorId(for: entry.workspaceId),
              let activeWorkspaceId = controller.workspaceManager.activeWorkspace(on: monitorId)?.id
        else { return }
        if let token = controller.resolveAndSetWorkspaceFocusToken(for: activeWorkspaceId),
           controller.focusWindow(token) != nil
        {
            return
        }
        controller.workspaceNavigationHandler.clearManagedFocusAfterEmptyWorkspaceSwitch()
    }
}
