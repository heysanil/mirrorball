import ProjectDescription

// Mirrorball — a Mac-native SSH port-forward manager.
//
// Single non-sandboxed macOS app target (it must spawn /usr/bin/ssh and read
// ~/.ssh/config), plus three test targets: fast unit tests, supervisor
// integration tests driven by a fake-ssh harness, and XCUITest e2e tests.

let deploymentTargets: DeploymentTargets = .macOS("26.0")

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "MARKETING_VERSION": "0.1.2",
    "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Automatic",
]

let project = Project(
    name: "Mirrorball",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: baseSettings,
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "Mirrorball",
            destinations: .macOS,
            product: .app,
            bundleId: "co.sanil.mirrorball",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Mirrorball",
                // Drive the app's version from the build settings so MARKETING_VERSION
                // (and the CI --version override) actually reaches the bundle; Tuist's
                // default Info.plist otherwise hardcodes 1.0 / 1.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSUIElement": false,
                "LSMinimumSystemVersion": "26.0",
                "NSHumanReadableCopyright": "© 2026 Sanil",
                // Sparkle auto-update. The feed is the appcast published to GitHub
                // Pages; enclosures point at the notarized DMG on GitHub Releases.
                // SUPublicEDKey is the *public* half of the EdDSA key pair generated
                // once with Sparkle's `generate_keys` (committing the public key is
                // expected and safe). Sparkle verifies every download against it, so
                // it MUST ship in a release before auto-update can work.
                "SUFeedURL": "https://mirrorball.sanil.co/appcast.xml",
                "SUPublicEDKey": "YnydsvE1uIsebiRrcZnJoGI0NL1rS49Onh/pcOiFiDU=",
                "SUEnableAutomaticChecks": true,
                "SUScheduledCheckInterval": 86400,
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            entitlements: .file(path: "Mirrorball.entitlements"),
            dependencies: [
                .external(name: "Sparkle"),
            ],
            settings: .settings(base: [
                "ENABLE_HARDENED_RUNTIME": "YES",
                "CODE_SIGN_ENTITLEMENTS": "Mirrorball.entitlements",
            ])
        ),
        .target(
            name: "MirrorballUnitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "co.sanil.mirrorball.unit",
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: ["Tests/Unit/**"],
            dependencies: [.target(name: "Mirrorball")]
        ),
        .target(
            name: "MirrorballIntegrationTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "co.sanil.mirrorball.integration",
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: ["Tests/Integration/**"],
            dependencies: [.target(name: "Mirrorball")]
        ),
        .target(
            name: "MirrorballUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "co.sanil.mirrorball.uitests",
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            // Shared identifiers are compiled in directly — XCUITest is
            // out-of-process and can't see the app target's internal symbols.
            sources: ["Tests/UI/**", "Sources/Shared/**"],
            dependencies: [.target(name: "Mirrorball")]
        ),
    ],
    schemes: [
        .scheme(
            name: "Mirrorball",
            shared: true,
            buildAction: .buildAction(targets: ["Mirrorball"]),
            testAction: .targets(
                [
                    .testableTarget(target: "MirrorballUnitTests"),
                    .testableTarget(target: "MirrorballIntegrationTests"),
                    .testableTarget(target: "MirrorballUITests"),
                ]
            ),
            runAction: .runAction(executable: "Mirrorball")
        ),
    ]
)
