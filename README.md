# Vaaka (scaffold)

This repository contains an initial Scaffold for Vaaka, a focused macOS browser.

Quick start (development):

- Requires macOS 14.0+ and Swift 5.9+
- Build & run with Swift Package Manager:

  swift run

Notes:

- This is an early scaffold using a Swift package (executable target) to simplify iteration.
- The bundle identifier should be: `com.twistermc.Vaaka` (set in Xcode project or during packaging).
- Git repo is initialized locally and intentionally not pushed to a remote.

Next steps:

- Implement tabs, session persistence and preferences UI
- Add unit tests and CI workflow
