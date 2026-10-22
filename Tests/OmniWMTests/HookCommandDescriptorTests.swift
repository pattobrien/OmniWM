// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import OmniWMIPC
import XCTest

final class HookCommandDescriptorTests: XCTestCase {
    func testCommandArgumentsComeFromTheNestedArgumentsObject() {
        let descriptor = HookCommandDescriptor(.focus(.spatial(direction: .left)), source: .ipc)

        XCTAssertEqual(descriptor.name, "focus")
        XCTAssertEqual(descriptor.arguments, ["direction": "left"])
    }

    func testWindowRequestArgumentsStayFlatAndSnakeCased() {
        let descriptor = HookCommandDescriptor(IPCWindowRequest(name: .close, windowId: "opaque-1"), source: .ipc)

        XCTAssertEqual(descriptor.name, "window.close")
        XCTAssertEqual(descriptor.arguments, ["window_id": "opaque-1"])
    }
}
