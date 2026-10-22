// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Darwin
import Foundation

struct HookRunner: Sendable {
    enum Outcome: Sendable, Equatable {
        case exited(status: Int32, stdout: Data, stderr: Data)
        case timedOut
        case launchFailed(String)
    }

    var spawn: @Sendable (HookCommand, Data) async -> Outcome = HookProcess.run

    func decide<M: Decodable & Sendable>(
        _ commands: [HookCommand],
        input: Data,
        as _: M.Type
    ) async -> HookDecision<M> {
        for command in commands {
            let decision: HookDecision<M> = await Self.decision(from: spawn(command, input), command: command)
            if case .allow = decision { continue }
            return decision
        }
        return .allow
    }

    func notify(_ commands: [HookCommand], input: Data) async {
        for command in commands {
            if let failure = await Self.failureDescription(of: spawn(command, input)) {
                Log.hooks.notice("hook \(command.command) \(failure)")
            }
        }
    }

    static func decision<M: Decodable & Sendable>(
        from outcome: Outcome,
        command: HookCommand
    ) -> HookDecision<M> {
        if case let .exited(status, stdout, stderr) = outcome {
            switch status {
            case 0:
                if String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .allow
                }
                if let modification = try? JSONDecoder().decode(M.self, from: stdout) {
                    return .modify(modification)
                }
            case 2:
                return .deny(HookDenyReason(stderr: stderr, fallback: "denied by \(command.command)"))
            default:
                break
            }
        }
        let text = "hook \(command.command) \(failureDescription(of: outcome) ?? "failed")"
        switch command.onFailure {
        case .allow:
            Log.hooks.notice(text)
            return .allow
        case .deny:
            return .deny(HookDenyReason(text: text))
        }
    }

    private static func failureDescription(of outcome: Outcome) -> String? {
        switch outcome {
        case let .exited(0, stdout, _):
            String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : "printed stdout that is not a valid answer"
        case let .exited(status, _, _):
            "exited with status \(status)"
        case .timedOut:
            "timed out"
        case let .launchFailed(message):
            "failed to launch: \(message)"
        }
    }
}

enum HookProcess {
    static func run(_ command: HookCommand, input: Data) async -> HookRunner.Outcome {
        let invocation = HookProcessInvocation()
        return await withTaskCancellationHandler {
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(command.timeoutMs))
                } catch {
                    return
                }
                invocation.finish(.timedOut)
            }
            let outcome = await withCheckedContinuation { continuation in
                invocation.start(command.command, input: input, continuation: continuation)
            }
            timeoutTask.cancel()
            return outcome
        } onCancel: {
            invocation.finish(.timedOut)
        }
    }
}

private final class HookProcessInvocation: @unchecked Sendable {
    private static let outputLimit = 65536

    private let lock = NSLock()
    private var isComplete = false
    private var process: Process?
    private var readers: [FileHandle] = []
    private var continuation: CheckedContinuation<HookRunner.Outcome, Never>?
    private var stdout = Data()
    private var stderr = Data()
    private var openStreams = 2
    private var exitStatus: Int32?

    func start(
        _ commandLine: String,
        input: Data,
        continuation: CheckedContinuation<HookRunner.Outcome, Never>
    ) {
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        guard fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            continuation.resume(returning: .launchFailed("stdin could not refuse SIGPIPE"))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", commandLine]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [self] process in
            exited(process)
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            receive(handle.availableData, isStdout: true, from: handle)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            receive(handle.availableData, isStdout: false, from: handle)
        }

        lock.lock()
        guard !isComplete else {
            lock.unlock()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            continuation.resume(returning: .timedOut)
            return
        }
        self.process = process
        self.continuation = continuation
        readers = [stdoutPipe.fileHandleForReading, stderrPipe.fileHandleForReading]
        do {
            try process.run()
        } catch {
            lock.unlock()
            finish(.launchFailed(error.localizedDescription))
            return
        }
        lock.unlock()

        let writer = stdinPipe.fileHandleForWriting
        try? writer.write(contentsOf: input)
        try? writer.close()
    }

    func finish(_ outcome: HookRunner.Outcome) {
        lock.lock()
        guard !isComplete else {
            lock.unlock()
            return
        }
        isComplete = true
        let process = self.process
        let readers = self.readers
        let continuation = self.continuation
        self.process = nil
        self.readers = []
        self.continuation = nil
        lock.unlock()

        for reader in readers {
            reader.readabilityHandler = nil
        }
        if let process, process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        continuation?.resume(returning: outcome)
    }

    private func receive(_ data: Data, isStdout: Bool, from handle: FileHandle) {
        if data.isEmpty {
            handle.readabilityHandler = nil
        }
        lock.lock()
        if data.isEmpty {
            openStreams -= 1
        } else if isStdout, stdout.count < Self.outputLimit {
            stdout.append(data)
        } else if !isStdout, stderr.count < Self.outputLimit {
            stderr.append(data)
        }
        let outcome = settledOutcome()
        lock.unlock()
        if let outcome {
            finish(outcome)
        }
    }

    private func exited(_ process: Process) {
        let status = process.terminationReason == .uncaughtSignal
            ? 128 + process.terminationStatus
            : process.terminationStatus
        lock.lock()
        exitStatus = status
        let outcome = settledOutcome()
        lock.unlock()
        if let outcome {
            finish(outcome)
        }
    }

    private func settledOutcome() -> HookRunner.Outcome? {
        guard let exitStatus, openStreams == 0 else { return nil }
        return .exited(status: exitStatus, stdout: stdout, stderr: stderr)
    }
}
