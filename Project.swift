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
    "MARKETING_VERSION": "0.1.0",
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
                "LSUIElement": false,
                "LSMinimumSystemVersion": "26.0",
                "NSHumanReadableCopyright": "© 2026 Sanil",
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            entitlements: .file(path: "Mirrorball.entitlements"),
            dependencies: [],
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
