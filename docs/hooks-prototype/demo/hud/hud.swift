import AppKit
import ApplicationServices

let hudDirectory = URL(filePath: "/Users/runner/demo-v2/hud")
let cardURL = hudDirectory.appending(path: "card.txt")
let narrationURL = hudDirectory.appending(path: "narration.txt")
let dialogURL = hudDirectory.appending(path: "dialog.json")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("hud: \(message)\n".utf8))
    exit(1)
}

func orFail<T>(_ action: String, _ body: () throws -> T) -> T {
    do { return try body() } catch { fail("cannot \(action): \(error.localizedDescription)") }
}

enum Command {
    case serve
    case ask(message: String, first: String, second: String)
    case click(CGPoint)
    case move(CGPoint)
    case type(String)
    case cursor
    case trusted

    init(arguments: [String]) {
        let args = Array(arguments.dropFirst())
        switch (args.first ?? "", args.count) {
        case ("serve", 1): self = .serve
        case ("ask", 4): self = .ask(message: args[1], first: args[2], second: args[3])
        case ("click", 3): self = .click(Self.point(args[1], args[2]))
        case ("move", 3): self = .move(Self.point(args[1], args[2]))
        case ("type", 2): self = .type(args[1])
        case ("cursor", 1): self = .cursor
        case ("trusted", 1): self = .trusted
        default: fail("usage: hud serve | ask <message> <first> <second> | click <x> <y> | move <x> <y> | type <text> | cursor | trusted")
        }
    }

    private static func point(_ x: String, _ y: String) -> CGPoint {
        guard let x = Double(x), let y = Double(y) else { fail("expected numeric <x> <y>, got \(x) \(y)") }
        return CGPoint(x: x, y: y)
    }
}

struct Block {
    let label: String?
    let text: String

    init?(rows: ArraySlice<String>) {
        var rows = rows.trimmingBlankRows
        let label = rows.first.flatMap { $0.hasPrefix("// ") ? String($0.dropFirst(3)) : nil }
        if label != nil { rows = rows.dropFirst().trimmingBlankRows }
        guard label != nil || !rows.isEmpty else { return nil }
        self.label = label
        self.text = rows.joined(separator: "\n")
    }
}

enum Card {
    case result(String)
    case full(headline: String, lines: [String], left: Block?, right: Block?)

    init?(text: String) {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)[...].trimmingBlankRows
        guard let headline = rows.first else { return nil }
        guard rows.count > 1 else {
            self = .result(headline)
            return
        }
        let blank = rows.firstIndex(where: \.isBlank) ?? rows.endIndex
        let body = rows[blank...].dropFirst()
        let divider = body.firstIndex(of: "---") ?? body.endIndex
        self = .full(
            headline: headline,
            lines: Array(rows[..<blank].dropFirst()),
            left: Block(rows: body[..<divider]),
            right: divider == body.endIndex ? nil : Block(rows: body[divider...].dropFirst())
        )
    }
}

struct DialogButtons: Encodable {
    struct Point: Encodable {
        let x, y: Int
    }

    let message: String
    let buttons: [String: Point]

    @MainActor
    init?(message: String, alert: NSAlert) {
        guard alert.window.isVisible, let primary = NSScreen.screens.first else { return nil }
        var buttons: [String: Point] = [:]
        for button in alert.buttons {
            guard let window = button.window else { return nil }
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            buttons[button.title] = Point(x: Int(frame.midX.rounded()), y: Int((primary.frame.maxY - frame.midY).rounded()))
        }
        self.message = message
        self.buttons = buttons
    }
}

extension String {
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

extension ArraySlice<String> {
    var trimmingBlankRows: ArraySlice<String> {
        guard let start = firstIndex(where: { !$0.isBlank }), let end = lastIndex(where: { !$0.isBlank }) else {
            return []
        }
        return self[start...end]
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let channel = { (shift: UInt32) in CGFloat((hex >> shift) & 0xFF) / 255 }
        self.init(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: alpha)
    }
}

final class OverlayPanel: NSPanel {
    init(frame: NSRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ view: NSView?) {
        guard let view else { return orderOut(nil) }
        contentView = view
        orderFrontRegardless()
    }
}

struct WatchedFile {
    enum Stamp: Equatable {
        case missing
        case present(seconds: Int, nanoseconds: Int, size: Int64)
    }

    let url: URL
    var last: Stamp?

    mutating func changedText() -> String? {
        var info = stat()
        let stamp: Stamp = stat(url.path, &info) == 0
            ? .present(seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec, size: info.st_size)
            : .missing
        guard stamp != last, let data = stamp == .missing ? Data() : try? Data(contentsOf: url) else { return nil }
        last = stamp
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, wrapWidth: CGFloat? = nil) -> NSTextField {
    let field = wrapWidth == nil ? NSTextField(labelWithString: string) : NSTextField(wrappingLabelWithString: string)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    if let wrapWidth {
        field.preferredMaxLayoutWidth = wrapWidth
        field.alignment = .center
    }
    return field
}

@MainActor
func surface(_ color: NSColor, radius: CGFloat = 0, size: NSSize = .zero) -> NSView {
    let view = NSView(frame: NSRect(origin: .zero, size: size))
    view.wantsLayer = true
    view.layer?.backgroundColor = color.cgColor
    view.layer?.cornerRadius = radius
    return view
}

@MainActor
func stack(_ views: [NSView], _ orientation: NSUserInterfaceLayoutOrientation, _ alignment: NSLayoutConstraint.Attribute, spacing: CGFloat) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = orientation
    stack.alignment = alignment
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

@MainActor
func blockView(_ block: Block, unit: CGFloat) -> NSView {
    let code = NSTextField(labelWithString: block.text)
    code.font = .monospacedSystemFont(ofSize: 30 * unit, weight: .regular)
    code.textColor = NSColor(hex: 0xE6EDF3)
    code.translatesAutoresizingMaskIntoConstraints = false
    code.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let box = surface(NSColor(hex: 0x1B232C), radius: 20 * unit)
    box.layer?.borderColor = NSColor(hex: 0x2E3A46).cgColor
    box.layer?.borderWidth = 2 * unit
    box.addSubview(code)
    NSLayoutConstraint.activate([
        code.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 32 * unit),
        code.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -32 * unit),
        code.topAnchor.constraint(equalTo: box.topAnchor, constant: 28 * unit),
        code.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -28 * unit),
    ])
    let caption = block.label.map { label($0, size: 28 * unit, weight: .medium, color: NSColor(hex: 0x7D8A97)) }
    return stack([caption, box].compactMap { $0 }, .vertical, .leading, spacing: 12 * unit)
}

@MainActor
func cardView(_ card: Card, size: NSSize, unit: CGFloat) -> NSView {
    let root = surface(NSColor(hex: 0x101418), size: size)
    let wrap = size.width - 320 * unit
    let text: [NSView]
    let blocks: [NSView]
    switch card {
    case .result(let line):
        text = [label(line, size: 56 * unit, weight: .semibold, color: .white, wrapWidth: wrap)]
        blocks = []
    case .full(let headline, let lines, let left, let right):
        text = [label(headline, size: 72 * unit, weight: .bold, color: .white, wrapWidth: wrap)]
            + lines.map { label($0, size: 44 * unit, color: NSColor(hex: 0xB4BEC8), wrapWidth: wrap) }
        blocks = [left, right].compactMap { $0.map { blockView($0, unit: unit) } }
    }
    let row = stack(blocks, .horizontal, .top, spacing: 48 * unit)
    let column = stack(text + (blocks.isEmpty ? [] : [row]), .vertical, .centerX, spacing: 20 * unit)
    if let lastLine = text.last {
        column.setCustomSpacing(64 * unit, after: lastLine)
    }
    root.addSubview(column)
    NSLayoutConstraint.activate([
        column.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        column.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        column.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -160 * unit),
    ])
    return root
}

@MainActor
func narrationView(_ lines: [String], size: NSSize, unit: CGFloat) -> NSView {
    let root = surface(NSColor(hex: 0x101418, alpha: 0.92), radius: 18 * unit, size: size)
    let fields = lines.map { line in
        let field = label(line, size: 30 * unit, color: .white)
        field.lineBreakMode = .byTruncatingTail
        field.alignment = .left
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    let column = stack(fields, .vertical, .leading, spacing: 8 * unit)
    root.addSubview(column)
    NSLayoutConstraint.activate(fields.map { $0.widthAnchor.constraint(equalTo: column.widthAnchor) } + [
        column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28 * unit),
        column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28 * unit),
        column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22 * unit),
    ])
    return root
}

@MainActor
final class Server {
    let unit: CGFloat
    let cardPanel: OverlayPanel
    let narrationPanel: OverlayPanel
    var cardFile = WatchedFile(url: cardURL)
    var narrationFile = WatchedFile(url: narrationURL)

    init() {
        guard let screen = NSScreen.screens.first?.frame else { fail("no screen attached") }
        unit = screen.width / 2560
        let narration = NSRect(x: screen.maxX - 1016 * unit, y: screen.minY + 16 * unit, width: 1000 * unit, height: 300 * unit)
        cardPanel = OverlayPanel(frame: screen, level: .screenSaver)
        narrationPanel = OverlayPanel(frame: narration, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
    }

    func tick() {
        if let text = cardFile.changedText() {
            cardPanel.show(Card(text: text).map { cardView($0, size: cardPanel.frame.size, unit: unit) })
        }
        if let text = narrationFile.changedText() {
            let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isBlank }.suffix(6)
            narrationPanel.show(lines.isEmpty ? nil : narrationView(Array(lines), size: narrationPanel.frame.size, unit: unit))
        }
    }
}

@MainActor
func serve() -> Never {
    NSApplication.shared.setActivationPolicy(.accessory)
    let server = Server()
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in MainActor.assumeIsolated { server.tick() } }
    NSApplication.shared.run()
    exit(0)
}

@MainActor
func ask(message: String, first: String, second: String) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = message
    alert.addButton(withTitle: first)
    alert.addButton(withTitle: second)
    let poll = Timer(timeInterval: 0.05, repeats: true) { timer in
        MainActor.assumeIsolated {
            guard let buttons = DialogButtons(message: message, alert: alert) else { return }
            orFail("write \(dialogURL.path)") { try JSONEncoder().encode(buttons).write(to: dialogURL, options: .atomic) }
            timer.invalidate()
        }
    }
    RunLoop.main.add(poll, forMode: .common)
    app.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    poll.invalidate()
    if FileManager.default.fileExists(atPath: dialogURL.path) {
        orFail("remove \(dialogURL.path)") { try FileManager.default.removeItem(at: dialogURL) }
    }
    let choseFirst = response == .alertFirstButtonReturn
    print(choseFirst ? first : second)
    exit(choseFirst ? 0 : 1)
}

func cursorLocation() -> CGPoint {
    guard let location = CGEvent(source: nil)?.location else { fail("cannot read the cursor position") }
    return location
}

struct Input {
    let source: CGEventSource

    init() {
        guard AXIsProcessTrusted() else { fail("\(CommandLine.arguments[0]) is not trusted for Accessibility") }
        guard CGPreflightPostEventAccess() else { fail("\(CommandLine.arguments[0]) has no PostEvent access") }
        guard let source = CGEventSource(stateID: .hidSystemState) else { fail("cannot create a HID event source") }
        self.source = source
    }

    func post(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            fail("cannot create a mouse event")
        }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }

    func glide(to target: CGPoint) {
        let start = cursorLocation()
        for step in 1...38 {
            let t = Double(step) / 38
            let eased = t * t * (3 - 2 * t)
            post(.mouseMoved, at: CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased))
            usleep(16_000)
        }
    }

    func click(at target: CGPoint) {
        glide(to: target)
        usleep(250_000)
        post(.leftMouseDown, at: target)
        usleep(40_000)
        post(.leftMouseUp, at: target)
    }

    func type(_ text: String) {
        for (index, character) in text.replacingOccurrences(of: "\\n", with: "\n").enumerated() {
            if index > 0 { usleep(70_000) }
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: character == "\n" ? 36 : 0, keyDown: keyDown) else {
                    fail("cannot create a key event")
                }
                event.flags = []
                if character != "\n" { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

switch Command(arguments: CommandLine.arguments) {
case .serve: MainActor.assumeIsolated { serve() }
case .ask(let message, let first, let second): MainActor.assumeIsolated { ask(message: message, first: first, second: second) }
case .click(let point): Input().click(at: point)
case .move(let point): Input().glide(to: point)
case .type(let text): Input().type(text)
case .trusted: _ = Input()
case .cursor:
    let location = cursorLocation()
    print("\(Int(location.x.rounded())) \(Int(location.y.rounded()))")
}
