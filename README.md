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
- [Building](docs/BUILDING.md) — native toolchains, strict checks, H:/Dev storage, and signed artifacts.
- [Troubleshooting](docs/TROUBLESHOOTING.md).

## Monorepo layout

Both native applications and their shared protocol contracts live in one Git repository.

```text
cadenza/
  apps/
    host/          Cadenza Host for macOS
    remote/        Cadenza Remote for Android
    web/           Browser Cadenza Remote, served by Cadenza Host
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

## Version 0.3.4 status

Built and checked locally. Device, live Music, and screenshot checks are not yet done, and [docs/agents/VALIDATION.md](docs/agents/VALIDATION.md) records what each check covers.

- Radio streams show LIVE, and their lyric lookup is skipped. The Host records its diagnostics in a rotating log and exports them. A fatal crash leaves a record that the next launch shows. Three launches in thirty seconds enter safe recovery, which pauses automatic Music polling until the user resumes it.
- The Host reports a four-tier thermal budget. The budget pauses new Sing sessions and early cover fetching in the web Remote.
- The Host keeps the Mac awake while Music plays or a Remote is connected. A Remote sends a Wake-on-LAN packet to a sleeping Host after a LAN outage.
- Menu bar only mode hides the Dock icon. Google Cast devices are listed in Settings and in the web output menu, and the presentation choice is saved. Cast audio is not transmitted yet.
- Remote and web clients can choose the Mac's audio output, favorite a library song in Music, and add it to a Cadenza Host playlist.
- Android can receive an Apple Music song link from the share sheet. The web Remote has a share target, OLED ambient mode, and media controls for the operating system.
- Recommendations rank with each Remote's taste history. With several Remotes connected, Room Blend drops an artist one of them dislikes and places shared artists first. Results carry reason tags. Taste is recorded for play now, play next, add to queue, promotion, completion, and early skip.
- An Android Remote can share a taste digest at connect when its Settings switch is on.
- Music's storefront and region dialogs are reported as `music_modal_blocked`.
- The web Remote's timed lyrics have a timing nudge for the current song. It is not saved to Host yet.
- The web search screen shows "For You" and "Room Blend" suggestions when the search is empty. They are read-only until you queue one.
- Android can use the volume buttons to change Music's volume on Host when its Settings switch is on, and dismisses the session notification after five minutes of pause or lost connection.

Built but not verified against a live Music session: the MediaRemote and HID media-key fallbacks, which apply only after Music refuses Cadenza's Apple events.

Not built yet: the Cast transmit pipeline and receiver app, the karaoke overlay and video discovery, the web taste digest, and Cast transmit controls. DRM license forwarding is declined and not implemented.

## License

Cadenza is licensed under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`). Third-party code retains its respective licenses.
