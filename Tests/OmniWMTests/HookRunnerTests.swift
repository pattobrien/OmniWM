// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

final class HookRunnerTests: XCTestCase {
    func testExitTwoDeniesWithTrimmedStderr() async {
        let decision = await HookRunner().decide(
            [HookCommand(command: "echo '  Terminal is protected  ' >&2; exit 2")],
            input: Data(),
            as: Never.self
        )
        XCTAssertEqual(decision, .deny(HookDenyReason(text: "Terminal is protected")))
    }

    func testExitTwoWithEmptyStderrNamesTheCommand() async {
        let decision = await HookRunner().decide([HookCommand(command: "exit 2")], input: Data(), as: Never.self)
        XCTAssertEqual(decision, .deny(HookDenyReason(text: "denied by exit 2")))
    }

    func testExitZeroWithJSONStdoutModifiesAdmission() async {
        let decision = await HookRunner().decide(
            [HookCommand(command: #"echo '{"float":true,"workspace":"chat"}'"#)],
            input: Data(),
            as: WindowAdmissionModification.self
        )
        XCTAssertEqual(decision, .modify(WindowAdmissionModification(workspace: "chat", float: true)))
    }

    func testExitZeroWithBlankStdoutAllows() async {
        let decision = await HookRunner().decide(
            [HookCommand(command: "echo; echo '   '", onFailure: .deny)],
            input: Data(),
            as: WindowAdmissionModification.self
        )
        XCTAssertEqual(decision, .allow)
    }

    func testStdoutOnANonModifyingEventIsAFailure() async {
        let decision = await HookRunner().decide(
            [HookCommand(command: #"echo '{"float":true}'"#, onFailure: .deny)],
            input: Data(),
            as: Never.self
        )
        XCTAssertEqual(
            decision,
            .deny(HookDenyReason(text: #"hook echo '{"float":true}' printed stdout that is not a valid answer"#))
        )
    }

    func testTimeoutKillsTheHookAndAppliesFailurePolicy() async {
        let start = ContinuousClock.now
        let denied = await HookRunner().decide(
            [HookCommand(command: "sleep 5", timeoutMs: 100, onFailure: .deny)],
            input: Data(),
            as: Never.self
        )
        let allowed = await HookRunner().decide(
            [HookCommand(command: "sleep 5", timeoutMs: 100)],
            input: Data(),
            as: Never.self
        )
        XCTAssertEqual(denied, .deny(HookDenyReason(text: "hook sleep 5 timed out")))
        XCTAssertEqual(allowed, .allow)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
    }

    func testStdinCarriesTheInputBytes() async {
        let input = Data(#"{"hook_event_name":"pre-command"}"#.utf8)
        let outcome = await HookProcess.run(HookCommand(command: "cat"), input: input)
        XCTAssertEqual(outcome, .exited(status: 0, stdout: input, stderr: Data()))
    }

    func testOtherExitStatusFollowsFailurePolicy() async {
        let denied = await HookRunner().decide(
            [HookCommand(command: "exit 1", onFailure: .deny)],
            input: Data(),
            as: Never.self
        )
        let allowed = await HookRunner().decide([HookCommand(command: "exit 1")], input: Data(), as: Never.self)
        XCTAssertEqual(denied, .deny(HookDenyReason(text: "hook exit 1 exited with status 1")))
        XCTAssertEqual(allowed, .allow)
    }

    func testFirstNonAllowAnswerWinsAndLaterCommandsDoNotRun() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("omniwm-hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let decision = await HookRunner().decide(
            [
                HookCommand(command: "exit 0"),
                HookCommand(command: "echo second >&2; exit 2"),
                HookCommand(command: "touch '\(marker.path)'")
            ],
            input: Data(),
            as: Never.self
        )
        XCTAssertEqual(decision, .deny(HookDenyReason(text: "second")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testNotifyRunsEveryCommandWithTheInput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omniwm-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = Data(#"{"to":"web"}"#.utf8)
        await HookRunner().notify(
            [
                HookCommand(command: "exit 2"),
                HookCommand(command: "cat > '\(directory.path)/a'"),
                HookCommand(command: "cat > '\(directory.path)/b'")
            ],
            input: input
        )
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("a")), input)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("b")), input)
    }
}
