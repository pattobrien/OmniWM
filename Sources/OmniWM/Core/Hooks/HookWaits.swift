// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct ParkedManagedActivation {
    let appFullscreen: Bool
    let source: ActivationEventSource
    let origin: ActivationCallOrigin
    let activeRequestId: UInt64?
    let bindCurrentPidRequest: Bool
    let callbackGeneration: UInt64?
}

struct ActivationHookWait {
    let id: HookWaitID
    let workspaceId: WorkspaceDescriptor.ID
    var observationGeneration: UInt64
    var focusIntentSeq: UInt64?
    var activation: ParkedManagedActivation
}

struct HookWaits {
    var activation: [WindowToken: ActivationHookWait] = [:]
    var admission: [UInt32: HookWaitID] = [:]
    var admissionReplies: [UInt32: HookDecision<WindowAdmissionModification>] = [:]
}
