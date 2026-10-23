// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum HookMatcherKey: String, Sendable {
    case bundleId
    case titleRegex
    case commandName
}

extension HookEvent {
    var matcherKeys: Set<HookMatcherKey> {
        switch self {
        case .preWorkspaceActivation,
             .preWindowAdmission:
            [.bundleId, .titleRegex]
        case .preCommand:
            [.commandName]
        case .postWorkspaceChange:
            []
        }
    }
}

struct HookRegistry: Sendable {
    static let empty = HookRegistry(definitions: [])

    let diagnostics: [String]
    private let byEvent: [HookEvent: [CompiledHook]]

    init(definitions: [HookDefinition]) {
        var diagnostics: [String] = []
        var byEvent: [HookEvent: [CompiledHook]] = [:]
        for (index, definition) in definitions.enumerated() {
            let label = "hooks[\(index)] (\(definition.event.rawValue))"
            var matcher: CompiledHookMatcher?
            if let source = definition.matcher {
                var messages: [String] = []
                guard let compiled = CompiledHookMatcher(source, diagnostics: &messages) else {
                    diagnostics += messages.map { "\(label): \($0)" }
                    continue
                }
                if let key = compiled.keys.first(where: { !definition.event.matcherKeys.contains($0) }) {
                    diagnostics.append("\(label): matcher key \(key.rawValue) never matches this event")
                    continue
                }
                matcher = compiled
            }
            byEvent[definition.event, default: []].append(
                CompiledHook(matcher: matcher, commands: definition.commands)
            )
        }
        self.diagnostics = diagnostics
        self.byEvent = byEvent
    }

    var isEmpty: Bool {
        byEvent.isEmpty
    }

    func commands(for event: HookEvent, subject: HookMatchSubject) -> [HookCommand] {
        (byEvent[event] ?? []).filter { $0.matcher?.matches(subject) ?? true }.flatMap(\.commands)
    }

    func requiresTitle(for bundleId: String?) -> Bool {
        (byEvent[.preWindowAdmission] ?? []).contains { hook in
            guard let matcher = hook.matcher, matcher.titleRegex != nil else { return false }
            return matcher.matchesBundle(bundleId)
        }
    }
}

private struct CompiledHook: Sendable {
    let matcher: CompiledHookMatcher?
    let commands: [HookCommand]
}

struct CompiledHookMatcher: Sendable {
    let bundleId: String?
    let titleRegex: NSRegularExpression?
    let commandName: NSRegularExpression?

    init?(_ matcher: HookMatcher, diagnostics: inout [String]) {
        var invalid: [String] = []
        bundleId = matcher.bundleId.flatMap { $0.isEmpty ? nil : $0 }
        titleRegex = Self.compile(matcher.titleRegex, key: .titleRegex, invalid: &invalid)
        commandName = Self.compile(matcher.commandName, key: .commandName, invalid: &invalid)
        guard invalid.isEmpty else {
            diagnostics += invalid
            return nil
        }
    }

    var keys: [HookMatcherKey] {
        [
            bundleId.map { _ in .bundleId },
            titleRegex.map { _ in .titleRegex },
            commandName.map { _ in .commandName }
        ].compactMap(\.self)
    }

    func matches(_ subject: HookMatchSubject) -> Bool {
        matchesBundle(subject.bundleId)
            && Self.matches(titleRegex, subject.title)
            && Self.matches(commandName, subject.commandName)
    }

    func matchesBundle(_ candidate: String?) -> Bool {
        guard let bundleId else { return true }
        return bundleId.caseInsensitiveCompare(candidate ?? "") == .orderedSame
    }

    private static func compile(
        _ pattern: String?,
        key: HookMatcherKey,
        invalid: inout [String]
    ) -> NSRegularExpression? {
        guard let pattern, !pattern.isEmpty else { return nil }
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            invalid.append("\(key.rawValue) \(pattern) is not a valid regular expression")
            return nil
        }
    }

    private static func matches(_ expression: NSRegularExpression?, _ value: String?) -> Bool {
        guard let expression else { return true }
        guard let value else { return false }
        return expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
