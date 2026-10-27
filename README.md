# Cadenza

Control Apple Music on a Mac from Android devices on the same local network. Music.app on the Mac remains the audio player.

| Component          | Purpose                                                                                 | Native stack                                                            |
| ------------------ | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| **Cadenza Host**   | Mac companion, pairing, shared queue, Music.app control, and lyric distribution         | Swift, SwiftUI, AppKit where needed, and SQLite                         |
| **Cadenza Remote** | Android interface, attributed requests, synchronized sing along, and personal analytics | Kotlin, Jetpack Compose with Material 3 Expressive, and platform SQLite |

The initial targets are a MacBook Air M4 running macOS 27 Golden Gate and a Huawei MatePad Mini running HarmonyOS 4.3. Cadenza must work without paid Apple Developer membership or a dependency on Google Play services.

The [implementation goalset](docs/GOALSET.md) evolves the existing Cadence source into Cadenza. It adds sequential Host setup, local Favorites, editable device names, theme preferences, adaptive home panes, session notifications, address failover, build identification, signed changelogs and separate Checking/Build CI. See the [current verification record](docs/VALIDATION.md) for exact checks and artifact availability. Mac compilation, real Music.app integration, MatePad testing, hardware resource measurements and release installation remain unverified; no stable release has been published.

The approved Android command-line toolchain is installed under `.tools` on F:, with Gradle distributions and dependencies under `.cache`. Android Studio and an emulator are not installed. Node.js is used only for development checks and will not be bundled in either app. On Windows, caches, downloads, temporary files, and build output belong on F:.

## Install, set up, and use

- [Installation](docs/INSTALLATION.md) — requirements, Host app, and Huawei APK installation.
- [Setup](docs/SETUP.md) — Music permissions, LAN address, storefront, pairing A/B, lyrics, and English translation.
- [Usage](docs/USAGE.md) — search, queue, protected controls, synchronized lyrics, analytics, and updates.
- [Building](docs/BUILDING.md) — native toolchains, strict checks, F: storage, and signed artifacts.
- [Releases](docs/RELEASES.md) — stable GitHub baseline and signed update metadata.
- [Troubleshooting](docs/TROUBLESHOOTING.md) and [validation status](docs/VALIDATION.md).
- [Resource measurement](docs/RESOURCES.md), [compatibility](docs/COMPATIBILITY.md), and [contributor instructions](AGENTS.md).

## Monorepo layout

The Windows project root is `F:\Development\cadenza`. Both native applications and their shared protocol contracts live in one Git repository.

```text
cadenza/
  apps/
    host/          Cadenza Host for macOS
    remote/        Cadenza Remote for Android
  shared/
    protocol/      Shared LAN protocol contracts and fixtures
  tests/           Protocol and SQLite behavior checks
  tools/           Local development checks and vendored lint plugin
  README.md
  SPEC.md
```

Each application retains its native build tooling. The root specification governs both applications and the shared protocol.

## Development checks

With the already available development dependencies, run from the repository root:

```powershell
node tools/check.mjs --portable
```

Portable checks include strict development-script analysis, lint with warnings treated as failures, formatting, line limits, shell syntax, and protocol/SQLite/JXA behavior tests. The complete `node tools/check.mjs` gate additionally requires native compilation, lint, formatting, and tests on a Mac with the Android command-line toolchain. Commit and push hooks use the complete gate. Missing native tools do not count as a pass.

The next platform check, after source review, is the [Mac Music probe](apps/host/README.md#read-only-mac-probe). It uses built-in macOS tools and installs nothing. Native queue control, catalog playback, cache access, update installation, and actual UI screenshots still require target-device evidence.

## Required behavior

- Search music and control playback through Host, including catalog songs outside the Mac's library when the native integration is proven.
- Pair one Host with multiple Remotes and show everyone the same queue, request ownership, estimated waits, and total remaining queue time.
- Let the Host decide whether a Remote can change another Remote's requests. With that setting off, protect the other Remote's currently playing request too.
- Store each Remote's play counts and playback duration locally on that Remote.
- Keep Favorites on each Remote, with Play now, Add to queue and Play next actions; retain names and system/light/dark preferences across restarts.
- Share one timed lyric document and English translation across Remotes, starting with Music.app's own cached lyrics.
- Keep controls responsive with a 1,000 ms response deadline and explicit failure or unconfirmed outcomes when an operation cannot finish.
- Use native interfaces, a small dependency set, automatically maintained SQLite databases, and updates sourced from GitHub Releases.

The strict interpretation that every operation must successfully finish within one second remains a platform feasibility limit. Native queue control, lyric cache access, AutoMix state, live quality indicators, and updates all need proof on the target devices before their support can be claimed.

## License

Cadenza is licensed under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`). Third-party code retains its respective licenses.
