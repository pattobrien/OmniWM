// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class CommandHookGateTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func openController(hooks: [HookDefinition]) -> WMController {
        let controller = InputControllerTestSupport.controller(for: self)
        controller.hookDispatcher.replace(registry: HookRegistry(definitions: hooks))
        controller.eventIntake.open(sink: controller.eventInterpreter)
        addTeardownBlock { @MainActor in controller.eventIntake.close() }
        return controller
    }

    private func closeHook(_ command: String, timeoutMs: Int = HookCommand.defaultTimeoutMs) -> HookDefinition {
        HookDefinition(
            event: .preCommand,
            matcher: HookMatcher(commandName: "^window\\.close$"),
            commands: [HookCommand(command: command, timeoutMs: timeoutMs)]
        )
    }

    private func postClose(
        _ recorder: CommandRecorder,
        completed: XCTestExpectation,
        marker: URL? = nil
    ) {
        let request = IPCWindowRequest(name: .close, windowId: "opaque-1")
        let intake = IPCCommandIntake(
            perform: { _ in
                recorder.performed += 1
                recorder.markerExistedAtPerform = marker.map { FileManager.default.fileExists(atPath: $0.path) }
                return .executed
            },
            completion: { result in
                recorder.results.append(result)
                completed.fulfill()
            },
            command: HookCommandDescriptor(request, source: .ipc)
        )
        XCTAssertTrue(EventIntake.post(.ipcCommand(intake)))
    }

    func testUnhookedCommandRunsInline() async {
        _ = openController(hooks: [
            HookDefinition(
                event: .preCommand,
                matcher: HookMatcher(commandName: "^focus$"),
                commands: [HookCommand(command: "exit 2")]
            )
        ])
        let recorder = CommandRecorder()
        let completed = expectation(description: "completed")

        postClose(recorder, completed: completed)
        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(recorder.performed, 1)
        XCTAssertEqual(recorder.results, [.executed])
    }

    func testHookedCommandRunsAfterTheHookAllows() async {
        let marker = directory.appendingPathComponent("hook-ran")
        let stdinCopy = directory.appendingPathComponent("stdin.json")
        _ = openController(hooks: [closeHook("cat > '\(stdinCopy.path)'; touch '\(marker.path)'")])
        let recorder = CommandRecorder()
        let completed = expectation(description: "completed")

        postClose(recorder, completed: completed, marker: marker)
        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(recorder.performed, 1)
        XCTAssertEqual(recorder.markerExistedAtPerform, true)
        XCTAssertEqual(recorder.results, [.executed])
        let stdin = try? JSONSerialization.jsonObject(with: Data(contentsOf: stdinCopy)) as? [String: Any]
        XCTAssertEqual(stdin?["hook_event_name"] as? String, "pre-command")
        let command = stdin?["command"] as? [String: Any]
        XCTAssertEqual(command?["name"] as? String, "window.close")
        XCTAssertEqual(command?["source"] as? String, "ipc")
        XCTAssertEqual(command?["arguments"] as? [String: String], ["window_id": "opaque-1"])
    }

    func testDeniedCommandCompletesWithTheHookReasonAndNeverRuns() async {
        _ = openController(hooks: [closeHook("echo 'window is protected' >&2; exit 2")])
        let recorder = CommandRecorder()
        let completed = expectation(description: "completed")

        postClose(recorder, completed: completed)
        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(recorder.performed, 0)
        XCTAssertEqual(recorder.results, [.hookDenied(reason: "window is protected")])
        XCTAssertEqual(
            IPCApplicationBridge.response(for: recorder.results[0], id: "r1", kind: .window),
            .failure(id: "r1", kind: .window, code: .hookDenied, reason: "window is protected")
        )
    }

    func testStopCompletesParkedCommandsAsDisabled() async throws {
        let started = directory.appendingPathComponent("started")
        let controller = openController(hooks: [closeHook("touch '\(started.path)'; sleep 5", timeoutMs: 1_000)])
        let recorder = CommandRecorder()
        let completed = expectation(description: "completed")

        postClose(recorder, completed: completed)
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: started.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(recorder.results, [])
        controller.commandHookGate.stop()
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(recorder.performed, 0)
        XCTAssertEqual(recorder.results, [.ignoredDisabled])
    }
}

@MainActor
private final class CommandRecorder {
    var performed = 0
    var markerExistedAtPerform: Bool?
    var results: [ExternalCommandResult] = []
}
