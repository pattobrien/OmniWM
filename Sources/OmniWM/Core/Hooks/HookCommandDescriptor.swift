// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC

enum HookCommandSource: String, Encodable, Sendable {
    case ipc
    case hotkey
    case shell
}

struct HookCommandDescriptor: Sendable, Equatable {
    let name: String
    let source: HookCommandSource
    var arguments: [String: String] = [:]
}

extension HookCommandDescriptor {
    init(_ command: IPCCommandRequest, source: HookCommandSource) {
        self.init(name: command.name.rawValue, source: source, arguments: Self.scalarArguments(of: command))
    }

    init(_ workspace: IPCWorkspaceRequest, source: HookCommandSource) {
        self.init(
            name: "workspace.\(workspace.name.rawValue)",
            source: source,
            arguments: Self.scalarArguments(of: workspace)
        )
    }

    init(_ window: IPCWindowRequest, source: HookCommandSource) {
        self.init(name: "window.\(window.name.rawValue)", source: source, arguments: Self.scalarArguments(of: window))
    }

    private static func scalarArguments(of request: some Encodable) -> [String: String] {
        guard let data = try? JSONEncoder().encode(request),
              let fields = try? JSONDecoder().decode([String: ScalarArgument].self, from: data)
        else { return [:] }
        return fields.reduce(into: [:]) { arguments, field in
            guard field.key != "name", let text = field.value.text else { return }
            arguments[snakeCased(field.key)] = text
        }
    }

    private static func snakeCased(_ key: String) -> String {
        key.reduce(into: "") { result, character in
            if character.isUppercase {
                result += "_" + character.lowercased()
            } else {
                result.append(character)
            }
        }
    }
}

private struct ScalarArgument: Decodable {
    let text: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            text = String(value)
        } else if let value = try? container.decode(Int.self) {
            text = String(value)
        } else if let value = try? container.decode(Double.self) {
            text = String(value)
        } else {
            text = try? container.decode(String.self)
        }
    }
}
