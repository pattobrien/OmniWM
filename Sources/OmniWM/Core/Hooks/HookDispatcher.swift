// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

@MainActor
final class HookDispatcher {
    enum GateOutcome: Equatable {
        case unhooked
        case pending(HookWaitID)
    }

    private(set) var registry: HookRegistry = .empty
    private let runner: HookRunner
    private let deliver: @MainActor @Sendable (HookReply) -> Void
    private var nextWaitId: UInt64 = 0

    init(
        runner: HookRunner = HookRunner(),
        deliver: @escaping @MainActor @Sendable (HookReply) -> Void
    ) {
        self.runner = runner
        self.deliver = deliver
    }

    func replace(registry: HookRegistry) {
        self.registry = registry
    }

    func gate<P: BlockingHookPayload>(
        _ payload: P,
        reply: @escaping @Sendable (HookWaitID, HookDecision<P.Modification>) -> HookReply
    ) -> GateOutcome {
        let commands = registry.commands(for: P.event, subject: payload.subject)
        guard !commands.isEmpty, let input = encode(payload) else { return .unhooked }
        nextWaitId &+= 1
        let id = HookWaitID(raw: nextWaitId)
        let runner = runner
        let deliver = deliver
        Task.detached {
            let decision = await runner.decide(commands, input: input, as: P.Modification.self)
            let answer = reply(id, decision)
            if !EventIntake.post(.hookDecided(answer)) {
                await deliver(answer)
            }
        }
        return .pending(id)
    }

    func notify<P: PostHookPayload>(_ payload: P) {
        let commands = registry.commands(for: P.event, subject: payload.subject)
        guard !commands.isEmpty, let input = encode(payload) else { return }
        let runner = runner
        Task.detached {
            await runner.notify(commands, input: input)
        }
    }

    private func encode(_ payload: some HookPayload) -> Data? {
        do {
            return try HookEnvelope.encode(payload)
        } catch {
            Log.hooks.error("hook payload for \(type(of: payload).event.rawValue) could not be encoded: \(error)")
            return nil
        }
    }
}
