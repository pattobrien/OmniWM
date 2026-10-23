// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

@MainActor
final class CommandHookGate {
    enum PendingCommand {
        case ipc(IPCCommandIntake)
        case hotkey(HotkeyInvocation, seq: UInt64)
    }

    private struct Parked {
        let command: PendingCommand
        let fence: Fence
    }

    private struct Fence: Equatable {
        let focusedToken: WindowToken?
        let activeWorkspaceId: WorkspaceDescriptor.ID?

        @MainActor
        init(_ controller: WMController) {
            focusedToken = controller.workspaceManager.selectedManagedToken
            activeWorkspaceId = controller.hookActiveWorkspace?.id
        }
    }

    private weak var controller: WMController?
    private var pending: [HookWaitID: Parked] = [:]

    init(controller: WMController) {
        self.controller = controller
    }

    func admit(_ command: PendingCommand) {
        guard let controller else { return }
        guard let descriptor = descriptor(for: command) else {
            perform(command, controller: controller)
            return
        }
        let fence = Fence(controller)
        let payload = CommandHookPayload(descriptor, focusedToken: fence.focusedToken, controller: controller)
        switch controller.hookDispatcher.gate(payload, reply: { .command($0, $1) }) {
        case .unhooked:
            perform(command, controller: controller)
        case let .pending(id):
            pending[id] = Parked(command: command, fence: fence)
        }
    }

    func resume(_ id: HookWaitID, decision: HookDecision<Never>) {
        guard let controller, let parked = pending.removeValue(forKey: id) else { return }
        switch decision {
        case .allow:
            guard Fence(controller) == parked.fence else {
                reject(parked.command, result: .workspaceStateConflict, trace: "stale")
                return
            }
            perform(parked.command, controller: controller)
        case let .deny(reason):
            reject(parked.command, result: .hookDenied(reason: reason.text), trace: "denied reason=\(reason.text)")
        }
    }

    func stop() {
        let parked = pending.values
        pending.removeAll()
        for entry in parked {
            if case let .ipc(intake) = entry.command {
                intake.completion(.ignoredDisabled)
            }
        }
    }

    private func descriptor(for command: PendingCommand) -> HookCommandDescriptor? {
        switch command {
        case let .ipc(intake):
            intake.command
        case let .hotkey(invocation, _):
            HookCommandDescriptor(
                name: ActionCatalog.spec(for: invocation.command)?.ipcCommandName?.rawValue
                    ?? invocation.command.displayName,
                source: .hotkey
            )
        }
    }

    private func perform(_ command: PendingCommand, controller: WMController) {
        switch command {
        case let .ipc(intake):
            intake.completion(intake.perform(controller))
        case let .hotkey(invocation, seq):
            InputTrace.record(
                "hotkey.dispatch.begin seq=\(seq)"
                    + " source=\(TraceFormat.token(controller.workspaceManager.selectedManagedToken))"
                    + " repeat=\(invocation.trigger?.isRepeat.description ?? "unknown")"
                    + " cmd=\(invocation.command.displayName)"
            )
            let result = controller.commandHandler.handleHotkeyInvocation(invocation)
            InputTrace.record(
                "hotkey.dispatch.end seq=\(seq)"
                    + " selected=\(TraceFormat.token(controller.workspaceManager.selectedManagedToken))"
                    + " pending=\(TraceFormat.token(controller.workspaceManager.pendingFocusedToken))"
                    + " result=\(result)"
            )
        }
    }

    private func reject(_ command: PendingCommand, result: ExternalCommandResult, trace: String) {
        switch command {
        case let .ipc(intake):
            intake.completion(result)
        case let .hotkey(invocation, seq):
            InputTrace.record("hotkey.dispatch.hook seq=\(seq) cmd=\(invocation.command.displayName) \(trace)")
        }
    }
}
