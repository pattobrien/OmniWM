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
              let fields = try? JSONDecoder().decode([String: RequestField].self, from: data)
        else { return [:] }
        return fields.reduce(into: [:]) { arguments, field in
            switch (field.key, field.value) {
            case ("name", _):
                return
            case let (key, .scalar(text)):
                arguments[snakeCased(key)] = text
            case let ("arguments", .object(nested)):
                for (key, value) in nested {
                    if let text = value.text { arguments[snakeCased(key)] = text }
                }
            case (_, .object),
                 (_, .other):
                return
            }
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

private enum RequestField: Decodable {
    case scalar(String)
    case object([String: ScalarArgument])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try ScalarArgument(from: decoder).text {
            self = .scalar(text)
        } else if let nested = try? container.decode([String: ScalarArgument].self) {
            self = .object(nested)
        } else {
            self = .other
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
