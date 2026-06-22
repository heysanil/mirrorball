import Foundation
import Testing
@testable import Mirrorball

/// A disabled `Updater` must be a hard no-op: no Sparkle controller, no scheduler,
/// no network, no Keychain. This is what keeps the updater out of every test and
/// out of side-effect-free launches (`MIRRORBALL_DISABLE_UPDATER`).
@Suite("Updater (disabled)")
@MainActor
struct UpdaterTests {
    @Test("Disabled updater reports it cannot check")
    func disabledCannotCheck() {
        let updater = Updater(enabled: false)
        #expect(updater.canCheckForUpdates == false)
    }

    @Test("Disabled updater reports automatic checks off and ignores writes")
    func disabledAutomaticChecksAreInert() {
        let updater = Updater(enabled: false)
        #expect(updater.automaticallyChecksForUpdates == false)
        // With no underlying controller the setter has nowhere to write, so the
        // value stays false rather than flipping.
        updater.automaticallyChecksForUpdates = true
        #expect(updater.automaticallyChecksForUpdates == false)
    }

    @Test("Disabled updater check is a no-op (does not crash)")
    func disabledCheckIsNoop() {
        let updater = Updater(enabled: false)
        updater.checkForUpdates()  // must not touch Sparkle / crash
    }
}
