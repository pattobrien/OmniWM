// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class PostWorkspaceChangeHookTests: XCTestCase {
    func testWorkspaceSwitchRunsThePostHookWithBothWorkspaces() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdinCopy = directory.appendingPathComponent("stdin.json")
        let controller = WindowAdmissionTestSupport.controller(prefix: "PostWorkspaceChangeHookTests")
        let frame = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let monitor = Monitor(
            id: .init(displayId: 3),
            displayId: 3,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Hooks"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        let ws1 = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let ws2 = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "2", createIfMissing: true))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws1, on: monitor.id))
        controller.handleSessionStateChanged(surfaceScope: .border)
        controller.hookDispatcher.replace(registry: HookRegistry(definitions: [
            HookDefinition(
                event: .postWorkspaceChange,
                matcher: nil,
                commands: [
                    HookCommand(
                        command: "cat > '\(stdinCopy.path).tmp'; mv '\(stdinCopy.path).tmp' '\(stdinCopy.path)'"
                    )
                ]
            )
        ]))

        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws2, on: monitor.id))
        controller.handleSessionStateChanged(surfaceScope: .border)
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: stdinCopy.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let stdin = try JSONSerialization.jsonObject(with: Data(contentsOf: stdinCopy)) as? [String: Any]
        XCTAssertEqual(stdin?["hook_event_name"] as? String, "post-workspace-change")
        XCTAssertEqual((stdin?["from"] as? [String: Any])?["name"] as? String, "1")
        XCTAssertEqual((stdin?["from"] as? [String: Any])?["id"] as? String, ws1.uuidString)
        XCTAssertEqual((stdin?["to"] as? [String: Any])?["name"] as? String, "2")
        XCTAssertEqual(stdin?["monitor_id"] as? Int, 3)
    }
}
