# Cadenza

Control Apple Music from Android devices on the same local network. Music.app on the Cadenza Host remains the audio player.

| Component          | Purpose                                                                                 | Native stack                                                            |
| ------------------ | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| **Cadenza Host**   | macOS companion, pairing, shared queue, Music.app control, and lyric distribution       | Swift, SwiftUI, AppKit where needed, and SQLite                         |
| **Cadenza Remote** | Android interface, attributed requests, synchronized sing along, and personal analytics | Kotlin, Jetpack Compose with Material 3 Expressive, and platform SQLite |

Cadenza supports a macOS Cadenza Host and Android Cadenza Remote without paid Apple Developer membership or a dependency on Google Play services. Music.app remains the audio player; Remote controls playback over the local network.

## Install, set up, and use

- [Installation](docs/INSTALLATION.md) — requirements, Host app, and Huawei APK installation.
- [Setup](docs/SETUP.md) — Music permissions, LAN address, storefront, pairing A/B, lyrics, and English translation.
- [Usage](docs/USAGE.md) — search, queue, protected controls, synchronized lyrics, analytics, and updates.
- [Building](docs/BUILDING.md) — native toolchains, strict checks, D:/Dev storage, and signed artifacts.
- [Troubleshooting](docs/TROUBLESHOOTING.md).

## Monorepo layout

Both native applications and their shared protocol contracts live in one Git repository.

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

After installing the development dependencies, run from the repository root:

```powershell
node tools/check.mjs --portable
```

Portable checks include strict development-script analysis, lint with warnings treated as failures, formatting, line limits, shell syntax, and protocol/SQLite/JXA behavior tests. The complete `node tools/check.mjs` gate adds the native checks available on the current platform. Both local hooks run the fast portable static gate; CI runs both native suites on their supported platforms.

## Required behavior

- Search music and control playback through Host, including catalog songs outside the Host library when the native integration is proven.
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
