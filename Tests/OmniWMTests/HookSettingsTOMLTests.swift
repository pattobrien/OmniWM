// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

final class HookSettingsTOMLTests: XCTestCase {
    private func defaultTOML(appending text: String) throws -> Data {
        let base = try String(decoding: SettingsTOMLCodec.encode(SettingsExport.defaults()), as: UTF8.self)
        return Data((base + "\n" + text).utf8)
    }

    func testDecodesHooksWithDefaultTimeoutAndFailurePolicy() throws {
        let data = try defaultTOML(appending: """
        [[hooks]]
        event = "pre-command"
        matcher = { commandName = "close-focused-window" }

        [[hooks.commands]]
        command = "~/.config/omniwm/hooks/protect.sh"

        [[hooks.commands]]
        command = "logger denied"
        timeoutMs = 150
        onFailure = "deny"
        """)

        let export = try SettingsTOMLCodec.decode(data)

        XCTAssertEqual(export.hooks, [
            HookDefinition(
                event: .preCommand,
                matcher: HookMatcher(commandName: "close-focused-window"),
                commands: [
                    HookCommand(command: "~/.config/omniwm/hooks/protect.sh", timeoutMs: 500, onFailure: .allow),
                    HookCommand(command: "logger denied", timeoutMs: 150, onFailure: .deny)
                ]
            )
        ])
    }

    func testHooksRoundTripThroughTheSettingsFile() throws {
        var export = SettingsExport.defaults()
        export.hooks = [
            HookDefinition(
                event: .preWindowAdmission,
                matcher: HookMatcher(bundleId: "com.tinyspeck.slackmacgap", titleRegex: "^Huddle"),
                commands: [HookCommand(command: "route.sh", timeoutMs: 300, onFailure: .deny)]
            ),
            HookDefinition(event: .postWorkspaceChange, commands: [HookCommand(command: "log.sh")])
        ]

        let encoded = try SettingsTOMLCodec.encode(export)

        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("[[hooks.commands]]"))
        XCTAssertEqual(try SettingsTOMLCodec.decode(encoded).hooks, export.hooks)
        XCTAssertFalse(SettingsTOMLCodec.unknownKeyPaths(in: encoded).contains { $0.hasPrefix("hooks") })
    }

    func testMissingHooksKeyDecodesToNoHooksAndDefaultFileOmitsIt() throws {
        let encoded = try SettingsTOMLCodec.encode(SettingsExport.defaults())

        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("hooks"))
        XCTAssertEqual(try SettingsTOMLCodec.decode(encoded).hooks, [])
    }

    func testUnknownHookEventRejectsTheFile() throws {
        let data = try defaultTOML(appending: """
        [[hooks]]
        event = "pre-everything"

        [[hooks.commands]]
        command = "true"
        """)

        XCTAssertThrowsError(try SettingsTOMLCodec.decode(data))
    }

    @MainActor
    func testApplyExportStoresHooksAndExportsThemBack() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMHookSettingsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        var export = SettingsExport.defaults()
        export.hooks = [HookDefinition(event: .preWorkspaceActivation, commands: [HookCommand(command: "stay.sh")])]

        settings.applyExport(export)

        XCTAssertEqual(settings.toExport().hooks, export.hooks)
    }
}
