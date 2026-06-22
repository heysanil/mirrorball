// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

// Force Sparkle to integrate as a framework so Tuist embeds *and code-signs* it
// (and its nested Autoupdate / Updater.app / XPC-service helpers) into the app
// bundle. A static product would not be embedded/signed correctly.
let packageSettings = PackageSettings(
    productTypes: ["Sparkle": .framework]
)
#endif

// The only third-party dependency: Sparkle, the auto-update framework for apps
// distributed outside the Mac App Store. Keep this version pinned in lockstep
// with the Sparkle CLI tools (sign_update) downloaded in scripts/package-dmg.sh.
let package = Package(
    name: "MirrorballDeps",
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    ]
)
