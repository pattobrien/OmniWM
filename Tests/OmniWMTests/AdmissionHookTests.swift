// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class AdmissionHookTests: XCTestCase {
    private let token = WindowToken(pid: 491_301, windowId: 491_302)
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var windowId: UInt32 {
        UInt32(token.windowId)
    }

    private func openController(_ command: String, bundleId: String = "com.example.tileable") -> WMController {
        let controller = WindowAdmissionTestSupport.controller()
        controller.hookDispatcher.replace(registry: HookRegistry(definitions: [
            HookDefinition(
                event: .preWindowAdmission,
                matcher: HookMatcher(bundleId: bundleId),
                commands: [HookCommand(command: command)]
            )
        ]))
        controller.eventIntake.open(sink: controller.eventInterpreter)
        let axRef = WindowAdmissionTestSupport.axRef(for: token)
        controller.axEventHandler.admissionRetryStateByWindowId[windowId] = AdmissionRetryState(
            expectedToken: token,
            axRef: axRef,
            reason: .hookPending,
            attempt: 0,
            generation: 1,
            trigger: .candidate(token: token, axRef: axRef),
            exhausted: false,
            executionPhase: .running(1),
            task: Task {}
        )
        addTeardownBlock { @MainActor [windowId] in
            controller.axEventHandler.cancelCreatedWindowRetry(windowId: windowId)
            controller.eventIntake.close()
        }
        return controller
    }

    private func evaluation(_ controller: WMController) -> WMController.WindowDecisionEvaluation {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        return controller.evaluateWindowDisposition(
            token: token,
            evidence: AXWindowDecisionEvidence(
                facts: AXWindowFacts(
                    role: kAXWindowRole as String,
                    subrole: kAXStandardWindowSubrole as String,
                    title: "Inbox",
                    hasCloseButton: true,
                    hasFullscreenButton: true,
                    fullscreenButtonEnabled: true,
                    hasZoomButton: true,
                    hasMinimizeButton: true,
                    appPolicy: .regular,
                    bundleId: "com.example.tileable",
                    attributeFetchSucceeded: true
                ),
                sizeConstraints: .unconstrained
            ),
            appFullscreen: false,
            windowInfo: WindowServerInfo(id: windowId, pid: token.pid, level: 0, frame: frame),
            admissionGeometry: WindowAdmissionGeometryEvidence(isSizeSettable: true, frame: frame)
        )
    }

    private func awaitReply(_ controller: WMController) async throws {
        let deadline = Date().addingTimeInterval(5)
        while controller.hookWaits.admissionReplies[windowId] == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testModifyingHookAppliesItsWorkspaceAndFloatOnTheRetryVisit() async throws {
        let stdinCopy = directory.appendingPathComponent("stdin.json")
        let runs = directory.appendingPathComponent("runs")
        let controller = openController(
            "cat > '\(stdinCopy.path)'; echo run >> '\(runs.path)'; echo '{\"workspace\":\"2\",\"float\":true}'"
        )
        let target = WindowAdmissionTestSupport.workspace(
            named: "2",
            layoutType: .defaultLayout,
            controller: controller
        )
        XCTAssertNotNil(target)
        let handler = controller.axEventHandler
        let proposed = evaluation(controller)
        XCTAssertEqual(proposed.decision.disposition, .managed)

        guard case .pending = handler.admissionHookDecision(for: proposed, windowId: windowId, controller: controller)
        else { return XCTFail("first visit should wait for the hook") }
        guard case .pending = handler.admissionHookDecision(for: proposed, windowId: windowId, controller: controller)
        else { return XCTFail("second visit should keep waiting") }
        try await awaitReply(controller)
        guard case let .decided(decision) = handler.admissionHookDecision(
            for: proposed,
            windowId: windowId,
            controller: controller
        ) else { return XCTFail("retry visit should apply the hook answer") }

        XCTAssertEqual(decision.disposition, .floating)
        XCTAssertEqual(decision.workspaceName, "2")
        XCTAssertEqual(decision.source, .hook)
        XCTAssertEqual(try String(contentsOf: runs, encoding: .utf8), "run\n")
        let stdin = try JSONSerialization.jsonObject(with: Data(contentsOf: stdinCopy)) as? [String: Any]
        XCTAssertEqual(stdin?["hook_event_name"] as? String, "pre-window-admission")
        let window = stdin?["window"] as? [String: Any]
        XCTAssertEqual(window?["bundle_id"] as? String, "com.example.tileable")
        XCTAssertEqual(window?["title"] as? String, "Inbox")
        XCTAssertEqual(window?["id"] as? Int, token.windowId)
        let proposedJSON = stdin?["proposed"] as? [String: Any]
        XCTAssertEqual(proposedJSON?["float"] as? Bool, false)
        XCTAssertTrue(proposedJSON?["workspace"] is NSNull)
    }

    func testUnknownWorkspaceKeepsTheRulePlacementAndAppliesFloat() async throws {
        let controller = openController("echo '{\"workspace\":\"nowhere\",\"float\":true}'")
        let handler = controller.axEventHandler
        let proposed = evaluation(controller)

        guard case .pending = handler.admissionHookDecision(for: proposed, windowId: windowId, controller: controller)
        else { return XCTFail("first visit should wait for the hook") }
        try await awaitReply(controller)
        guard case let .decided(decision) = handler.admissionHookDecision(
            for: proposed,
            windowId: windowId,
            controller: controller
        ) else { return XCTFail("retry visit should apply the hook answer") }

        XCTAssertEqual(decision.workspaceName, proposed.decision.workspaceName)
        XCTAssertEqual(decision.disposition, .floating)
        XCTAssertEqual(decision.source, .hook)
    }

    func testDenyingHookRejectsTheWindow() async throws {
        let controller = openController("echo 'not on my watch' >&2; exit 2")
        let handler = controller.axEventHandler
        let proposed = evaluation(controller)

        guard case .pending = handler.admissionHookDecision(for: proposed, windowId: windowId, controller: controller)
        else { return XCTFail("first visit should wait for the hook") }
        try await awaitReply(controller)
        guard case .denied = handler.admissionHookDecision(for: proposed, windowId: windowId, controller: controller)
        else { return XCTFail("retry visit should deny") }
        XCTAssertNil(controller.hookWaits.admissionReplies[windowId])
    }

    func testUnmatchedBundleDecidesInlineWithoutWaiting() {
        let controller = openController("exit 2", bundleId: "com.example.other")
        let proposed = evaluation(controller)

        guard case let .decided(decision) = controller.axEventHandler.admissionHookDecision(
            for: proposed,
            windowId: windowId,
            controller: controller
        ) else { return XCTFail("unhooked admission should decide inline") }

        XCTAssertEqual(decision, proposed.decision)
        XCTAssertNil(controller.hookWaits.admission[windowId])
    }

    func testHookPendingRetriesDoNotSpendTheCreatedWindowBudget() throws {
        let controller = WindowAdmissionTestSupport.controller()
        let handler = controller.axEventHandler
        let axRef = WindowAdmissionTestSupport.axRef(for: token)
        defer { handler.cancelCreatedWindowRetry(windowId: windowId) }
        for (reason, expectedScheduled) in [(WindowAdmissionPendingReason.hookPending, true), (.factsDeferred, false)] {
            handler.admissionRetryStateByWindowId[windowId] = AdmissionRetryState(
                expectedToken: token,
                axRef: axRef,
                reason: reason,
                attempt: AXEventHandler.createdWindowRetryLimit,
                generation: 1,
                trigger: .candidate(token: token, axRef: axRef),
                exhausted: false,
                executionPhase: .running(1),
                task: Task {}
            )

            XCTAssertEqual(
                handler.scheduleCandidateAdmissionRetry(
                    windowId: windowId,
                    pid: token.pid,
                    axRef: axRef,
                    reason: reason
                ),
                expectedScheduled,
                reason.rawValue
            )
            let state = try XCTUnwrap(handler.admissionRetryStateByWindowId[windowId])
            XCTAssertEqual(state.attempt, AXEventHandler.createdWindowRetryLimit, reason.rawValue)
            XCTAssertEqual(state.exhausted, !expectedScheduled, reason.rawValue)
            handler.cancelCreatedWindowRetry(windowId: windowId)
        }
    }
}
