import Foundation
import Observation
import Sparkle

/// Thin wrapper over Sparkle's `SPUStandardUpdaterController` — the auto-update
/// engine for apps shipped outside the Mac App Store. Sparkle owns the whole
/// update flow (scheduled background checks, the appcast download, the
/// signature-verified install, relaunch) and shows its own native UI; this type
/// only exposes the few hooks SwiftUI needs and keeps everything off when the
/// updater is disabled.
///
/// Disabled (`enabled == false`, i.e. tests or `MIRRORBALL_DISABLE_UPDATER`) is a
/// hard no-op: no `SPUStandardUpdaterController` is ever created, so there is no
/// scheduler, no network traffic, and no Keychain access. Every member returns a
/// benign default.
///
/// Owned by `AppDelegate` (it must be created once and outlive every scene) and
/// injected into the SwiftUI environment so the menu bar, the app menu, and
/// Settings can drive it.
@MainActor
@Observable
final class Updater {
    /// Mirrors Sparkle's `canCheckForUpdates` so SwiftUI can disable the
    /// "Check for Updates…" controls until the updater is ready (and while a
    /// check is already running). Bridged from KVO into the Observation idiom.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(enabled: Bool) {
        guard enabled else {
            controller = nil
            return
        }

        // `startingUpdater: true` begins Sparkle's scheduled background checks
        // immediately. No delegates: the standard user driver handles all UI.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates

        // Sparkle mutates `canCheckForUpdates` on the main thread, so the KVO
        // callback is already main-isolated — `assumeIsolated` lets us write the
        // observable property without an async hop (and without the @Sendable
        // capture dance a `Task { @MainActor }` would require).
        observation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// Whether scheduled background checks are on. Persisted by Sparkle in the
    /// host bundle's user defaults; the Settings toggle is bound to this.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Begin a user-initiated check. Sparkle shows its own progress/results UI.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
