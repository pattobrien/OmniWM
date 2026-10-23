// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ActivationHookTests: XCTestCase {
    private let token = WindowToken(pid: 492_301, windowId: 492_302)

    private struct Scene {
        let controller: WMController
        let home: WorkspaceDescriptor.ID
        let away: WorkspaceDescriptor.ID
    }

    private func scene(_ command: String) throws -> Scene {
        let controller = WindowAdmissionTestSupport.controller()
        let manager = controller.workspaceManager
        let home = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let away = try XCTUnwrap(manager.workspaceId(for: "2", createIfMissing: true))
        _ = try XCTUnwrap(manager.focusWorkspace(named: "1"))
        _ = WindowAdmissionTestSupport.track(token, in: away, controller: controller)
        controller.hookDispatcher.replace(registry: HookRegistry(definitions: [
            HookDefinition(event: .preWorkspaceActivation, commands: [HookCommand(command: command)])
        ]))
        controller.eventIntake.open(sink: controller.eventInterpreter)
        controller.hasStartedServices = true
        addTeardownBlock { @MainActor in
            controller.hasStartedServices = false
            controller.eventIntake.close()
        }
        return Scene(controller: controller, home: home, away: away)
    }

    private func gate(_ scene: Scene) throws -> Bool {
        let handler = scene.controller.axEventHandler
        let entry = try XCTUnwrap(scene.controller.workspaceManager.entry(for: token))
        return handler.gateTrackedActivation(
            entry,
            isWorkspaceActive: false,
            requestDisposition: .unrelatedNoRequest,
            facts: ActivationFacts(
                pid: token.pid,
                source: .workspaceDidActivateApplication,
                origin: .external,
                observationGeneration: handler.latestActivationObservationGeneration,
                requestedAtSeq: 0,
                focusedWindow: nil
            ),
            appFullscreen: false
        )
    }

    private func awaitSettled(_ scene: Scene) async throws {
        let deadline = Date().addingTimeInterval(5)
        while scene.controller.hookWaits.activation[token] != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(scene.controller.hookWaits.activation[token])
    }

    private func activeWorkspaceId(_ scene: Scene) -> WorkspaceDescriptor.ID? {
        let manager = scene.controller.workspaceManager
        return manager.monitorId(for: scene.home).flatMap { manager.activeWorkspace(on: $0)?.id }
    }

    func testDenyingHookKeepsTheActiveWorkspace() async throws {
        let scene = try scene("echo 'stay on task' >&2; exit 2")

        XCTAssertTrue(try gate(scene))
        XCTAssertTrue(try gate(scene))
        try await awaitSettled(scene)

        XCTAssertEqual(activeWorkspaceId(scene), scene.home)
        XCTAssertNotEqual(scene.controller.workspaceManager.nativeManagedFocusToken, token)
    }

    func testAllowingHookFollowsTheActivationToItsWorkspace() async throws {
        let scene = try scene("exit 0")

        XCTAssertTrue(try gate(scene))
        try await awaitSettled(scene)

        XCTAssertEqual(activeWorkspaceId(scene), scene.away)
    }

    func testFocusIntentIssuedWhileWaitingDropsTheAllow() async throws {
        let scene = try scene("sleep 0.3")

        XCTAssertTrue(try gate(scene))
        let entry = try XCTUnwrap(scene.controller.workspaceManager.entry(for: token))
        _ = scene.controller.intentLedger.beginManagedRequest(token: token, workspaceId: entry.workspaceId)
        try await awaitSettled(scene)

        XCTAssertEqual(activeWorkspaceId(scene), scene.home)
    }
}
