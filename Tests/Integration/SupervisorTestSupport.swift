import Foundation
@testable import Mirrorball

/// Writes an executable fake-`ssh` script whose body you control, returning its
/// URL. Lets integration tests drive the supervisor through up / drop / fail /
/// reconnect scenarios deterministically, with no real network or SSH.
@discardableResult
func makeFakeSSH(body: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mb-fakessh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("ssh", isDirectory: false)
    let script = "#!/bin/bash\n\(body)\n"
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

/// Common fake-ssh behaviors.
enum FakeSSH {
    /// Connects and stays up until killed.
    static let staysUp = "exec sleep 100"
    /// Fails immediately with a recognizable stderr line (e.g. port in use).
    static let failsImmediately = #"echo "bind: Address already in use" >&2; exit 1"#
    /// Comes up, then drops after ~2s (long enough to pass the 1.5s grace window).
    static let dropsAfterComingUp = "sleep 2; exit 0"
}

/// A fake `ssh` that records the argv of every invocation, then stays up like
/// `FakeSSH.staysUp`. Each spawned process writes its full argument vector (one
/// element per line) to a uniquely-named file in `recordDirectory`, so a test can
/// assert on exactly the arguments the supervisor passed to `ssh` — the real
/// binary never runs. This is how the multi-mapping argv is proven end-to-end:
/// the pure builder is unit-tested, and this confirms the supervisor actually
/// spawns one ssh carrying every spec.
struct RecordingFakeSSH: Sendable {
    /// Path to the executable fake-ssh script (hand to a supervisor/config).
    let url: URL
    /// Directory the script writes one argv-record file into per invocation.
    let recordDirectory: URL

    /// Every recorded invocation's argv, in filesystem order (one entry per
    /// spawned ssh process). Empty until the supervisor has spawned the fake.
    var invocations: [[String]] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: recordDirectory.path) else { return [] }
        return names.sorted().compactMap { name in
            let file = recordDirectory.appendingPathComponent(name, isDirectory: false)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
    }
}

/// Build a fake `ssh` that records each invocation's argv and then stays up past
/// the 1.5s grace window, so the connection counts as healthy (`.up`).
func makeRecordingFakeSSH() throws -> RecordingFakeSSH {
    let recordDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mb-fakessh-argv-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: recordDir, withIntermediateDirectories: true)
    // Write this invocation's argv (one per line, PID-unique filename) before
    // `exec sleep`, so it lands well before the grace window — once the forward is
    // `.up`, the record is guaranteed present.
    let body = """
    printf '%s\\n' "$@" > "\(recordDir.path)/$$"
    exec sleep 100000
    """
    let url = try makeFakeSSH(body: body)
    return RecordingFakeSSH(url: url, recordDirectory: recordDir)
}

/// The values that follow each `-L` flag in an argv, in order — i.e. the local
/// forwarding specs the supervisor emitted (`"3000:localhost:3000"`, …).
func localForwardSpecs(in argv: [String]) -> [String] {
    var specs: [String] = []
    var iterator = argv.makeIterator()
    while let arg = iterator.next() {
        if arg == "-L", let value = iterator.next() {
            specs.append(value)
        }
    }
    return specs
}

/// Thread-safe sink for status updates streamed off the supervisor actor.
final class StatusCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ForwardStatus] = []

    var snapshot: [ForwardStatus] { lock.withLock { items } }

    func append(_ status: ForwardStatus) { lock.withLock { items.append(status) } }

    var sawUp: Bool { snapshot.contains(.up) }
    var sawReconnecting: Bool { snapshot.contains(.reconnecting) }
    var startingCount: Int { snapshot.filter { $0 == .starting }.count }
    var lastError: String? { snapshot.compactMap(\.errorMessage).last }
    var isOff: Bool { snapshot.last == .off }
}

/// Begin draining a status stream into a collector on a detached task.
func collectStatuses(from stream: AsyncStream<ForwardStatus>) -> StatusCollector {
    let collector = StatusCollector()
    Task.detached {
        for await status in stream {
            collector.append(status)
        }
    }
    return collector
}

/// Poll `predicate` until true or `timeout` elapses. Returns the final value.
@discardableResult
func poll(timeout: Duration, _ predicate: @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return predicate()
}

/// A minimal forward whose ssh args are irrelevant (the fake ignores them).
func sampleForward() -> Forward {
    Forward(name: "test", kind: .local, target: "host", listenPort: 5555, remoteHost: "localhost", remotePort: 5555)
}

/// A forward carrying an explicit list of port mappings — used when the ssh args
/// *do* matter (e.g. proving one ssh process multiplexes every mapping).
func sampleForward(
    kind: ForwardKind = .local,
    target: String = "host",
    mappings: [PortMapping]
) -> Forward {
    Forward(name: "test", kind: kind, target: target, mappings: mappings)
}
