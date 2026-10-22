// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class HookSettingsApplicationTests: XCTestCase {
    func testAppliedSettingsInstallHooksAndReportBrokenMatchers() {
        let controller = WindowAdmissionTestSupport.controller(prefix: "HookSettingsApplicationTests")
        let settings = controller.settings
        settings.quakeTerminal.enabled = false
        let guardClose = HookCommand(command: "exit 2")
        settings.hooks = [
            HookDefinition(
                event: .preCommand,
                matcher: HookMatcher(commandName: "^window\\.close$"),
                commands: [guardClose]
            ),
            HookDefinition(
                event: .preWindowAdmission,
                matcher: HookMatcher(titleRegex: "(unclosed"),
                commands: [HookCommand(command: "true")]
            )
        ]

        controller.applyPersistedSettings(settings, startServices: false)

        XCTAssertEqual(
            controller.hookDispatcher.registry.commands(
                for: .preCommand,
                subject: HookMatchSubject(commandName: "window.close")
            ),
            [guardClose]
        )
        XCTAssertEqual(
            controller.diagnosticsIssues.filter { $0.id == "hook-configuration" }.map(\.kind),
            [.hookConfiguration(problems: [
                "hooks[1] (pre-window-admission): titleRegex (unclosed is not a valid regular expression"
            ])]
        )

        settings.hooks = []
        controller.applyPersistedSettings(settings, startServices: false)

        XCTAssertTrue(controller.hookDispatcher.registry.isEmpty)
        XCTAssertFalse(controller.diagnosticsIssues.contains { $0.id == "hook-configuration" })
    }
}
