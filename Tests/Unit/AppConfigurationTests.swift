import Foundation
import Testing
@testable import Mirrorball

/// `AppConfiguration.fromEnvironment` is the single place launch overrides are
/// read; it's a pure function over an injected env dict, so its seams are tested
/// directly without touching the real environment.
@Suite("App configuration")
struct AppConfigurationTests {
    @Test("Empty environment uses defaults and enables side effects + updater")
    func defaults() {
        let config = AppConfiguration.fromEnvironment([:])
        #expect(config.sshExecutableURL.path == AppConfiguration.defaultSSHPath)
        #expect(config.disableSideEffects == false)
        #expect(config.disableUpdater == false)
        #expect(config.seedJSON == nil)
    }

    @Test("MIRRORBALL_SSH_PATH overrides the ssh executable")
    func sshPathOverride() {
        let config = AppConfiguration.fromEnvironment(["MIRRORBALL_SSH_PATH": "/tmp/fake-ssh"])
        #expect(config.sshExecutableURL.path == "/tmp/fake-ssh")
    }

    @Test("Disabling side effects also disables the updater")
    func sideEffectsImplyUpdaterOff() {
        let config = AppConfiguration.fromEnvironment(["MIRRORBALL_DISABLE_SIDE_EFFECTS": "1"])
        #expect(config.disableSideEffects == true)
        #expect(config.disableUpdater == true)
    }

    @Test("The updater can be disabled independently of other side effects")
    func updaterDisabledIndependently() {
        let config = AppConfiguration.fromEnvironment(["MIRRORBALL_DISABLE_UPDATER": "1"])
        #expect(config.disableSideEffects == false)  // notifications/login item still on
        #expect(config.disableUpdater == true)
    }

    @Test("A value other than \"1\" does not disable anything")
    func onlyExactlyOneDisables() {
        let config = AppConfiguration.fromEnvironment([
            "MIRRORBALL_DISABLE_SIDE_EFFECTS": "0",
            "MIRRORBALL_DISABLE_UPDATER": "true",
        ])
        #expect(config.disableSideEffects == false)
        #expect(config.disableUpdater == false)
    }
}
