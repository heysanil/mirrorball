import Foundation
import Observation

/// The single source of truth, shared by the window and the menu bar.
///
/// Owns the list of `ForwardEntry`, wires each enabled forward to a
/// `TunnelSupervisor`, mirrors status changes onto the UI, persists every change,
/// and routes transitions to the `Notifier`. `@MainActor` because every mutation
/// originates from the UI or from a main-isolated status stream.
@MainActor
@Observable
final class AppModel {
    private(set) var entries: [ForwardEntry]
    private(set) var hostAliases: [String] = []

    @ObservationIgnored let configuration: AppConfiguration
    @ObservationIgnored private let persistence: Persistence
    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private let secretStore: SecretStore

    init(
        configuration: AppConfiguration = .fromEnvironment(),
        secretStore: SecretStore = KeychainSecretStore()
    ) {
        self.configuration = configuration
        self.persistence = Persistence(configDirectory: configuration.configDirectory)
        self.notifier = Notifier(enabled: !configuration.disableSideEffects)
        self.secretStore = secretStore

        let initial = AppModel.initialForwards(configuration: configuration, persistence: persistence)
        self.entries = initial.map(ForwardEntry.init)

        // Install the askpass helper so password/passphrase forwards can hand their
        // secret to ssh without it ever touching the command line.
        try? AskpassHelper.install(at: configuration.askpassScriptURL)
    }

    /// Whether a secret is stored for a forward (drives the editor's "stored" UI).
    func hasSecret(for id: UUID) -> Bool {
        secretStore.hasSecret(for: id)
    }

    /// Seed from `MIRRORBALL_SEED` (tests) if present, else load persisted state.
    private static func initialForwards(
        configuration: AppConfiguration,
        persistence: Persistence
    ) -> [Forward] {
        if let seed = configuration.seedJSON,
           let data = seed.data(using: .utf8),
           let seeded = try? JSONDecoder().decode([Forward].self, from: data) {
            try? persistence.save(seeded)
            return seeded
        }
        return persistence.load()
    }

    // MARK: - Launch

    @ObservationIgnored private var didPerformLaunch = false

    /// One-time launch work, safe to call from multiple scene `.task`s. Requests
    /// notification permission, loads SSH host aliases, and brings up everything
    /// marked enabled.
    func performLaunchOnce() {
        guard !didPerformLaunch else { return }
        didPerformLaunch = true
        requestNotificationPermission()
        refreshHostAliases()
        startEnabledForwards()
    }

    /// Bring up everything marked enabled.
    func startEnabledForwards() {
        for entry in entries where entry.forward.enabled {
            startSupervising(entry)
        }
    }

    func refreshHostAliases() {
        hostAliases = SSHConfigParser.aliases()
    }

    func requestNotificationPermission() {
        Task { await notifier.requestAuthorization() }
    }

    // MARK: - Aggregate state (for the menu bar glyph)

    var anyError: Bool { entries.contains { $0.status.errorMessage != nil } }
    var anyUp: Bool { entries.contains { $0.status == .up } }
    var anyActive: Bool { entries.contains { $0.status.isActive } }
    var activeCount: Int { entries.filter { $0.status == .up }.count }

    // MARK: - CRUD

    func toggle(_ entry: ForwardEntry) {
        entry.forward.enabled.toggle()
        if entry.forward.enabled {
            startSupervising(entry)
        } else {
            stopSupervising(entry)
        }
        persist()
    }

    @discardableResult
    func add(_ forward: Forward, secret: SecretUpdate = .unchanged) -> ForwardEntry {
        let entry = ForwardEntry(forward: forward)
        entries.append(entry)
        secretStore.apply(secret, for: forward.id) // before start so the supervisor can read it
        if forward.enabled {
            startSupervising(entry)
        }
        persist()
        return entry
    }

    func update(_ entry: ForwardEntry, with forward: Forward, secret: SecretUpdate = .unchanged) {
        let wasSupervised = entry.isSupervised
        if wasSupervised {
            stopSupervising(entry)
        }
        var updated = forward
        updated.id = entry.id // identity is owned by the entry, never the form
        entry.forward = updated
        secretStore.apply(secret, for: entry.id)
        if updated.enabled {
            startSupervising(entry)
        }
        persist()
    }

    func delete(_ entry: ForwardEntry) {
        stopSupervising(entry)
        secretStore.apply(.clear, for: entry.id)
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            stopSupervising(entry)
            secretStore.apply(.clear, for: entry.id)
        }
        entries.remove(atOffsets: offsets)
        persist()
    }

    // MARK: - Supervision

    private func startSupervising(_ entry: ForwardEntry) {
        stopSupervising(entry)
        entry.status = .starting

        // Fetch the secret only for non-agent auth; pass the askpass script only
        // when there's actually a secret to hand over.
        let secret = entry.forward.authMethod == .agent ? nil : secretStore.secret(for: entry.id)
        let supervisor = TunnelSupervisor(
            forward: entry.forward,
            sshExecutableURL: configuration.sshExecutableURL,
            secret: secret,
            askpassURL: secret == nil ? nil : configuration.askpassScriptURL
        )
        entry.supervisor = supervisor

        let name = entry.forward.name
        let notifier = self.notifier
        entry.statusTask = Task { [weak entry] in
            await supervisor.start()
            for await status in supervisor.statusStream {
                guard let entry else { break }
                let previous = entry.status
                entry.status = status
                await notifier.handleTransition(name: name, from: previous, to: status)
            }
        }
    }

    private func stopSupervising(_ entry: ForwardEntry) {
        entry.statusTask?.cancel()
        entry.statusTask = nil
        if let supervisor = entry.supervisor {
            entry.supervisor = nil
            Task { await supervisor.stop() }
        }
        entry.status = .off
    }

    private func persist() {
        try? persistence.save(entries.map(\.forward))
    }
}
