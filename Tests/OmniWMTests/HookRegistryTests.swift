// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

final class HookRegistryTests: XCTestCase {
    private func hook(
        _ event: HookEvent,
        _ command: String,
        bundleId: String? = nil,
        titleRegex: String? = nil,
        commandName: String? = nil
    ) -> HookDefinition {
        let matcher = bundleId == nil && titleRegex == nil && commandName == nil
            ? nil
            : HookMatcher(bundleId: bundleId, titleRegex: titleRegex, commandName: commandName)
        return HookDefinition(event: event, matcher: matcher, commands: [HookCommand(command: command)])
    }

    private func commandLines(
        _ registry: HookRegistry,
        _ event: HookEvent,
        _ subject: HookMatchSubject
    ) -> [String] {
        registry.commands(for: event, subject: subject).map(\.command)
    }

    func testWindowMatcherComparesBundleCaseInsensitivelyAndTitleUnanchored() {
        let registry = HookRegistry(definitions: [
            hook(.preWorkspaceActivation, "any"),
            hook(.preWorkspaceActivation, "terminal", bundleId: "com.apple.Terminal"),
            hook(.preWorkspaceActivation, "zoom", bundleId: "us.zoom.xos", titleRegex: "Meeting"),
            hook(.preWindowAdmission, "admission")
        ])

        XCTAssertEqual(registry.diagnostics, [])
        XCTAssertEqual(
            commandLines(
                registry,
                .preWorkspaceActivation,
                HookMatchSubject(bundleId: "COM.APPLE.terminal", title: "zsh")
            ),
            ["any", "terminal"]
        )
        XCTAssertEqual(
            commandLines(
                registry,
                .preWorkspaceActivation,
                HookMatchSubject(bundleId: "us.zoom.xos", title: "Zoom Meeting 3")
            ),
            ["any", "zoom"]
        )
        XCTAssertEqual(
            commandLines(registry, .preWorkspaceActivation, HookMatchSubject(bundleId: "us.zoom.xos", title: nil)),
            ["any"]
        )
        XCTAssertEqual(commandLines(registry, .postWorkspaceChange, .none), [])
    }

    func testCommandNameMatcherIsAnUnanchoredRegex() {
        let registry = HookRegistry(definitions: [
            hook(.preCommand, "workspace", commandName: "^workspace\\."),
            hook(.preCommand, "close", commandName: "close")
        ])

        XCTAssertEqual(
            commandLines(registry, .preCommand, HookMatchSubject(commandName: "workspace.focus-name")),
            ["workspace"]
        )
        XCTAssertEqual(commandLines(registry, .preCommand, HookMatchSubject(commandName: "window.close")), ["close"])
        XCTAssertEqual(commandLines(registry, .preCommand, HookMatchSubject(commandName: "focus")), [])
    }

    func testEmptyMatcherStringsMatchEverything() {
        let registry = HookRegistry(definitions: [
            hook(.preWindowAdmission, "blank", bundleId: "", titleRegex: "")
        ])

        XCTAssertEqual(registry.diagnostics, [])
        XCTAssertEqual(
            commandLines(registry, .preWindowAdmission, HookMatchSubject(bundleId: "com.example", title: nil)),
            ["blank"]
        )
        XCTAssertFalse(registry.requiresTitle(for: "com.example"))
    }

    func testInvalidRegexAndUnreachableKeysAreDroppedWithDiagnostics() {
        let registry = HookRegistry(definitions: [
            hook(.preWindowAdmission, "bad", titleRegex: "(unclosed"),
            hook(.preCommand, "bundle", bundleId: "com.apple.Terminal"),
            hook(.postWorkspaceChange, "post", commandName: "focus"),
            hook(.preWindowAdmission, "command", commandName: "focus"),
            hook(.postWorkspaceChange, "kept")
        ])

        XCTAssertEqual(registry.diagnostics, [
            "hooks[0] (pre-window-admission): titleRegex (unclosed is not a valid regular expression",
            "hooks[1] (pre-command): matcher key bundleId never matches this event",
            "hooks[2] (post-workspace-change): matcher key commandName never matches this event",
            "hooks[3] (pre-window-admission): matcher key commandName never matches this event"
        ])
        XCTAssertEqual(
            commandLines(registry, .preWindowAdmission, HookMatchSubject(bundleId: "a", title: "(unclosed")),
            []
        )
        XCTAssertEqual(commandLines(registry, .preCommand, HookMatchSubject(commandName: "focus")), [])
        XCTAssertEqual(commandLines(registry, .postWorkspaceChange, .none), ["kept"])
    }

    func testRequiresTitleOnlyForAdmissionHooksWithTitleRegexOnMatchingBundle() {
        let registry = HookRegistry(definitions: [
            hook(.preWindowAdmission, "zoom", bundleId: "us.zoom.xos", titleRegex: "Meeting"),
            hook(.preWorkspaceActivation, "any-title", titleRegex: "Secret")
        ])

        XCTAssertTrue(registry.requiresTitle(for: "US.ZOOM.XOS"))
        XCTAssertFalse(registry.requiresTitle(for: "com.apple.Terminal"))
        XCTAssertFalse(registry.requiresTitle(for: nil))
        XCTAssertTrue(HookRegistry(definitions: [hook(.preWindowAdmission, "t", titleRegex: "x")])
            .requiresTitle(for: nil))
    }

    func testEnvelopeEncodesSnakeCaseWithEventNameAndNullTitle() throws {
        let payload = try WorkspaceActivationHookPayload(
            window: HookWindowFacts(
                id: 42,
                pid: 7,
                bundleId: "com.apple.Terminal",
                appName: "Terminal",
                title: nil,
                role: "AXWindow",
                subrole: nil
            ),
            workspace: HookWorkspaceRef(
                id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                name: "2"
            ),
            activeWorkspace: nil,
            monitorId: 1,
            source: "app-activation"
        )

        let json = try String(decoding: HookEnvelope.encode(payload), as: UTF8.self)

        XCTAssertEqual(
            json,
            #"{"hook_event_name":"pre-workspace-activation","monitor_id":1,"source":"app-activation","#
                + #""window":{"app_name":"Terminal","bundle_id":"com.apple.Terminal","id":42,"pid":7,"#
                + #""role":"AXWindow","subrole":null,"title":null},"#
                + #""workspace":{"id":"00000000-0000-0000-0000-000000000001","name":"2"}}"#
        )
    }

    @MainActor
    func testDispatcherRunsMatchingCommandsAndDeliversTheDecision() async {
        let delivered = expectation(description: "reply delivered")
        let replies = ReplyBox()
        let dispatcher = HookDispatcher { reply in
            replies.value = reply
            delivered.fulfill()
        }
        dispatcher.replace(registry: HookRegistry(definitions: [
            hook(
                .preCommand,
                "read input; case \"$input\" in *window.close*) echo \"close blocked\" >&2; exit 2;; esac"
            )
        ]))
        let payload = CommandHookPayload(
            command: .init(name: "window.close", source: .ipc, arguments: [:]),
            focusedWindow: nil,
            activeWorkspace: nil
        )

        let outcome = dispatcher.gate(payload) { id, decision in .command(id, decision) }

        XCTAssertEqual(outcome, .pending(HookWaitID(raw: 1)))
        await fulfillment(of: [delivered], timeout: 5)
        guard case let .command(id, decision) = replies.value else {
            return XCTFail("expected a command reply, got \(String(describing: replies.value))")
        }
        XCTAssertEqual(id, HookWaitID(raw: 1))
        XCTAssertEqual(decision, .deny(HookDenyReason(text: "close blocked")))
    }

    @MainActor
    func testDispatcherReportsUnhookedWhenNothingMatches() {
        let dispatcher = HookDispatcher { _ in XCTFail("no reply expected") }
        dispatcher.replace(registry: HookRegistry(definitions: [
            hook(.preCommand, "exit 2", commandName: "^focus$")
        ]))
        let payload = CommandHookPayload(
            command: .init(name: "window.close", source: .hotkey, arguments: [:]),
            focusedWindow: nil,
            activeWorkspace: nil
        )

        XCTAssertEqual(dispatcher.gate(payload) { id, decision in .command(id, decision) }, .unhooked)
    }
}

@MainActor
private final class ReplyBox {
    var value: HookReply?
}
