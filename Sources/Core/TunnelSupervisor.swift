import Foundation

/// Supervises one forward's `ssh` process: spawn it, watch it, auto-reconnect
/// with backoff while running, and kill it cleanly on stop.
///
/// The actor is the single owner of the `Process`. It publishes `ForwardStatus`
/// changes through an `AsyncStream` — the clean, `Sendable` bridge to the
/// `@MainActor` UI. Callers `start()` once and `stop()` once; a stopped
/// supervisor is finished and should be discarded.
actor TunnelSupervisor {
    private let forward: Forward
    private let sshExecutableURL: URL
    /// Secret (password or key passphrase) handed to `ssh` via `SSH_ASKPASS`,
    /// never via argv. `nil` for agent auth.
    private let secret: String?
    /// Path to the askpass helper script that echoes the secret on demand.
    private let askpassURL: URL?
    /// How long a connection must stay up before a later drop is treated as a
    /// transient reconnect rather than a flap. Injectable so tests don't have to
    /// wait out the full production window.
    private let stableAfter: Duration

    private var process: Process?
    private var supervisionTask: Task<Void, Never>?
    private var lastEmitted: ForwardStatus?

    /// Ordered status updates. Finishes when the supervisor stops for good.
    nonisolated let statusStream: AsyncStream<ForwardStatus>
    private let continuation: AsyncStream<ForwardStatus>.Continuation

    init(
        forward: Forward,
        sshExecutableURL: URL,
        secret: String? = nil,
        askpassURL: URL? = nil,
        stableAfter: Duration = SupervisorConstants.stableAfter
    ) {
        self.forward = forward
        self.sshExecutableURL = sshExecutableURL
        self.secret = secret
        self.askpassURL = askpassURL
        self.stableAfter = stableAfter
        (statusStream, continuation) = AsyncStream<ForwardStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
    }

    /// Begin supervising. Idempotent — a second call is a no-op.
    func start() {
        guard supervisionTask == nil else { return }
        supervisionTask = Task { await superviseLoop() }
    }

    /// Stop for good: cancel the loop, kill the child, finish the stream.
    func stop() {
        supervisionTask?.cancel()
        supervisionTask = nil
        terminateProcess()
        // The loop, on cancellation, unwinds and emits `.off` + finishes. If it is
        // already gone, make sure consumers still see the terminal state.
        emit(.off)
        continuation.finish()
    }

    // MARK: - Supervision loop

    private func superviseLoop() async {
        var backoff = SupervisorConstants.backoffStart

        loop: while !Task.isCancelled {
            emit(.starting)

            // Spawn one attempt.
            let stderr = StderrBuffer()
            let attempt: Process
            do {
                attempt = try spawn(stderr: stderr)
            } catch {
                emit(.error("could not start ssh: \(error.localizedDescription)"))
                if await backoffSleep(backoff) { break }
                backoff = backoff.doubled(upTo: SupervisorConstants.backoffMax)
                continue
            }
            process = attempt

            // Grace window: a near-immediate exit is a failure, not a healthy tunnel.
            let graceDeadline = ContinuousClock.now.advanced(by: SupervisorConstants.grace)
            switch await wait(attempt, until: graceDeadline) {
            case .cancelled:
                terminate(attempt, stderr: stderr)
                break loop
            case .exited:
                let message = exitReason(of: attempt, stderr: stderr) ?? "ssh exited immediately"
                terminate(attempt, stderr: stderr)
                emit(.error(message))
                if await backoffSleep(backoff) { break loop }
                backoff = backoff.doubled(upTo: SupervisorConstants.backoffMax)
                continue
            case .deadlinePassed:
                break // survived — fall through to "up"
            }

            // Healthy.
            emit(.up)
            let upSince = ContinuousClock.now

            let dropReason: String?
            switch await wait(attempt, until: nil) {
            case .cancelled:
                terminate(attempt, stderr: stderr)
                break loop
            case .exited, .deadlinePassed:
                dropReason = exitReason(of: attempt, stderr: stderr)
                terminate(attempt, stderr: stderr)
            }

            // Unexpected drop. Distinguish a transient blip on an established
            // tunnel from a connection that never really settled.
            let wasStable = ContinuousClock.now - upSince >= stableAfter
            // A long-stable connection earns a fresh backoff budget.
            if wasStable {
                backoff = SupervisorConstants.backoffStart
            }
            // Surface the exit reason as an error only for a connection that
            // dropped *before* it stabilized — a flap that only *looked* healthy.
            // A previously-stable tunnel that drops (idle/NAT timeout, server
            // keepalive, a brief network blip) is just reconnecting: if the
            // reconnect can't re-establish, the grace-window path surfaces the real
            // reason on the next attempt. This keeps a tunnel that drops and
            // recovers from spamming "failed" notifications on every cycle.
            if let dropReason, !wasStable {
                emit(.error(dropReason))
            } else {
                emit(.reconnecting)
            }
            if await backoffSleep(backoff) { break }
            backoff = backoff.doubled(upTo: SupervisorConstants.backoffMax)
        }

        terminateProcess()
        emit(.off)
        continuation.finish()
    }

    // MARK: - Process plumbing

    private func spawn(stderr: StderrBuffer) throws -> Process {
        let process = Process()
        process.executableURL = sshExecutableURL
        process.arguments = SSHArguments.build(for: forward)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        // Inject the secret out-of-band: ssh reads it from the SSH_ASKPASS helper
        // rather than argv or stdin, so it never appears on the command line.
        // `SSH_ASKPASS_REQUIRE=force` makes ssh use askpass even without a TTY/DISPLAY.
        if let secret, let askpassURL {
            var environment = ProcessInfo.processInfo.environment
            environment["SSH_ASKPASS"] = askpassURL.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["MIRRORBALL_ASKPASS_SECRET"] = secret
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) {
                stderr.record(String(line))
            }
        }

        try process.run()
        ChildProcessRegistry.shared.register(process)
        return process
    }

    private func terminate(_ process: Process, stderr: StderrBuffer) {
        if let pipe = process.standardError as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        if process.isRunning {
            process.terminate()
        }
        ChildProcessRegistry.shared.unregister(process)
        if self.process === process {
            self.process = nil
        }
    }

    private func terminateProcess() {
        guard let process else { return }
        if let pipe = process.standardError as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        if process.isRunning {
            process.terminate()
        }
        ChildProcessRegistry.shared.unregister(process)
        self.process = nil
    }

    /// Best-effort human reason a process ended: the last stderr line if any,
    /// else a non-zero exit code, else `nil` for a clean exit (exit 0, no stderr).
    private func exitReason(of process: Process, stderr: StderrBuffer) -> String? {
        let line = stderr.last
        if !line.isEmpty { return line }
        guard !process.isRunning else { return nil }
        let code = process.terminationStatus
        return code != 0 ? "ssh exited (code \(code))" : nil
    }

    // MARK: - Waiting

    private enum WaitOutcome { case exited, deadlinePassed, cancelled }

    /// Poll the process until it exits, the optional deadline passes, or we're
    /// cancelled. Polling keeps this fully cancellation-friendly and avoids the
    /// races of attaching a termination handler after `run()`.
    private func wait(_ process: Process, until deadline: ContinuousClock.Instant?) async -> WaitOutcome {
        while true {
            // Cancellation must win over a not-running read: stop() both cancels and
            // kills the child, and we must NOT mistake that for an unexpected drop.
            if Task.isCancelled { return .cancelled }
            if !process.isRunning { return .exited }
            if let deadline, ContinuousClock.now >= deadline { return .deadlinePassed }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return .cancelled
            }
        }
    }

    /// Sleep `duration`, returning true if cancelled (stop requested) mid-wait.
    private func backoffSleep(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return false
        } catch {
            return true
        }
    }

    // MARK: - Emission

    private func emit(_ status: ForwardStatus) {
        guard status != lastEmitted else { return }
        lastEmitted = status
        continuation.yield(status)
    }
}

/// Thread-safe holder for the most recent non-empty stderr line. Shared into the
/// pipe's `@Sendable` readability handler, which runs off the actor.
private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    var last: String { lock.withLock { value } }

    func record(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        lock.withLock { value = trimmed }
    }
}
