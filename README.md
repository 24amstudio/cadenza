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

Each application retains its native build tooling. The root specification governs both applications and the shared protocol. The TV stage (`/tv` on a browser, and the Android TV receiver) runs from Cadenza Host and needs no Cast developer account. See [docs/CAST.md](docs/CAST.md).

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

## Version 0.4.5 status

Built and checked locally. The stream has not run on a Mac with live Music or on a Remote with real speakers, and [docs/agents/VALIDATION.md](docs/agents/VALIDATION.md) records what each check covers.

- The web Remote streams Music's audio over Wi-Fi in two modes: full-range stereo, with the Mac muted or playing on both, and a subwoofer split. The split sends the Mac's low frequencies and the Remote's high frequencies, joined by a fourth-order Linkwitz-Riley crossover.
- Each stream frame is timed for playout, and the Host drops a frame rather than queue it behind a Wi-Fi stall. The Remote fills the gap with a short fade.
- The Host aligns the two outputs from the devices' reported latency on connect. With microphone access allowed in Settings, it then measures the room for two seconds while music plays, and keeps the result for that output and browser. No test tone plays.
- Streaming works only over Wi-Fi. It stops when the link stalls or falls back to Bluetooth.

## Version 0.4.0 status

Built and checked locally. Device, live Music, and screenshot checks are not yet done, and [docs/agents/VALIDATION.md](docs/agents/VALIDATION.md) records what each check covers.

- Radio streams show LIVE, and their lyric lookup is skipped. The Host records its diagnostics in a rotating log and exports them. A fatal crash leaves a record that the next launch shows. Three launches in thirty seconds enter safe recovery, which pauses automatic Music polling until the user resumes it.
- The Host reports a four-tier thermal budget. The budget pauses new Sing sessions, early cover fetching, and the web Remote's log uploads.
- The Host keeps the Mac awake while Music plays or a Remote is connected. A Remote sends a Wake-on-LAN packet to a sleeping Host after a LAN outage.
- Menu bar only mode hides the Dock icon. Google Cast devices are listed in Settings and in the web and Android output menus, and the presentation choice is saved. Web and Android can send Music's audio to a Cast device, but this has not been checked against a real Cast device.
- Remote and web clients can choose the Mac's audio output, favorite a library song in Music, and add it to a Cadenza Host playlist.
- Android can receive an Apple Music song link from the share sheet. The web Remote has a share target, OLED ambient mode, and media controls for the operating system.
- Recommendations rank with each Remote's taste history. With several Remotes connected, Room Blend drops an artist one of them dislikes and places shared artists first. Results carry reason tags. Taste is recorded for play now, play next, add to queue, promotion, completion, and early skip.
- An Android Remote can share a taste digest at connect when its Settings switch is on.
- Music's storefront and region dialogs are reported as `music_modal_blocked`.
- The web Remote's timed lyrics have a timing setting in Settings → Lyric timing. It applies to the playing song and is saved on Host.
- The web search screen shows "For You" and "Room Blend" suggestions when the search is empty. They are read-only until you queue one. On an artist page, the web and Android Remotes can show a muted motion video, when Apple has one.
- Android can use the volume buttons to change Music's volume on Host when its Settings switch is on, and dismisses the session notification after five minutes of pause or lost connection.
- A Remote can play a music video in Music's window. Its karaoke line appears over Music's window on the Mac, or on a Cast device, and the two never show at once.
- The AVR lip-sync offset, the Cast mode, and each track's karaoke nudge are set on the Host and kept across launches. The Cast 5.1 path uses an AC-3 helper only when one is present at build time or named by `CADENZA_AC3_HELPER`. Without one, 5.1 folds to stereo. The helper encodes in a test, but it has not been checked against a six-channel device.
- Android has a home-screen now-playing widget, a motion lock screen for tracks with motion artwork, and a charging screen saver. None has been checked on a device.

Built but not verified against a live Music session: the MediaRemote and HID media-key fallbacks, which apply only after Music refuses Cadenza's Apple events.

Built, not yet tested against a Cast device or a TV: sending Music's stereo audio to a Cast device through Google's default media receiver, the browser TV stage at `/tv`, the Android TV receiver, the Cadenza TV approval and send controls on the Remotes, and the web taste digest sent at connect when opted in. The TV stage is checked in headless Chromium with a simulated Host, and in JVM and Swift tests.

Not built: compressed Bitstream passthrough, which Music cannot provide because it decodes its audio. Raw PCM is the Bitstream mode that is built. The experimental web loader is built, but it needs a URL-loading Cast app ID that you supply, and no device has run it. Karaoke for a music video uses its studio track's timed lyrics when the two have the same length within 3 seconds. Otherwise the video shows no karaoke, because Music does not expose lyrics for videos. The video segment alignment needs the video's audio, and DRM license forwarding is declined and not implemented.

## License

Cadenza is licensed under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`). Third-party code retains its respective licenses.
