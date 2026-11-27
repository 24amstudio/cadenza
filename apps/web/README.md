# Cadenza Remote Web

The browser Remote for Cadenza Host. It is a client-rendered Nuxt 4 single-page app (`ssr: false`). `nuxt generate` emits static files only, with no server bundle. Cadenza Host serves those files and its socket from one origin.

## How it connects

- When Cadenza Web is on (Settings, Network), Cadenza Host serves the app on its control port plus two (43129 by default), over plain HTTP. Browsers therefore show no certificate warning, but this traffic is not encrypted.
- The pairing QR code is `http://<host>:43129/#CDZP:<payload>`. The fragment is the same one-use native invitation that Cadenza Remote reads, so a regular camera opens the web Remote and the native app still pairs from the same code. The page removes the fragment from the address bar as soon as it reads it.
- Web Bluetooth exists only in a secure context (HTTPS or localhost) and only in Chromium-based browsers. The LAN page at `http://<host>` therefore offers the QR code, not Bluetooth.
- Pairing over Bluetooth works from a secure origin: the GitHub Pages site below. Open it, choose Pair a Remote on Cadenza Host, then enter the four-digit PIN that Cadenza Host shows. Like Cadenza Remote, the browser pairs over the Host's BLE service with the name and PIN, not the QR code. The welcome records the Host's LAN address and Cadenza Web port. After a reload, a paired page first tries `ws://<host address>:<web port>/v1/socket` on the LAN, which Chrome gates behind its Local Network Access prompt. A socket that does not welcome within three seconds, or is refused, falls back to Bluetooth: the page reconnects silently when the browser still permits the paired device, and otherwise the connect button opens the device chooser. A Host that offers no LAN socket is reached over Bluetooth only. Once the LAN socket has welcomed, a dropped link reconnects over the LAN.
- The browser connects to `ws://<host>:43129/v1/socket` and speaks the `shared/protocol/v1` frames: pairing or hello, state, commands, lyrics, artwork, and clock probes. A command is sent once. If the socket closes before its result, the command is reported as unconfirmed, queried later by its command ID, and never sent again. Presses are queued so one command is in flight at a time, each built from the newest state with a deadline of the Host's one-second window less the measured clock uncertainty. When the Host refuses a command before dispatching it (stale revision, busy, or expired), the page sends that same press once more with a new command ID, at most twice. An unconfirmed result is never retried. A result that is late is not called unknown at once: after four seconds the browser asks the Host for its receipt with `command.status`, and only a Host that answers `unconfirmed`, or does not answer at all, leaves the command unconfirmed. That message, "Music may still apply this request. Cadenza is checking.", is the only one shown for it, and the browser keeps checking a few more times while the link is up.
- Lyrics and artwork come from Cadenza Host. The browser never contacts lyric or artwork providers. The playing song's full image and its motion video are requested apart, so a refused or corrupt video never leaves the cover at preview size. A failed or silent artwork request is retried with backoff and asked for again after a reconnect.
- Anyone on the same network can read what the browser receives, including the session token it sends on reconnect. Turn Cadenza Web off when you leave the network, and remove a browser's pairing in Cadenza Host if it is lost.
- `crypto.randomUUID` needs a secure context, so the app builds its identifiers with `getRandomValues` instead.

## Layout

- `app/components/` holds the shell, pairing, player, lyrics, queue, library, and views.
- `app/lib/` holds the protocol encoders and decoders, the Host client, clock estimation, invitation parsing, playback math, the search session, and the local favorites and history. These modules have no Nuxt dependency, so the tests import them directly.
- `app/stores/` holds the Pinia stores for the host connection, notices, preferences, search, library, song requests, and the active view.
- `tests/` holds the `bun test` suites for protocol framing, the host client against a fake socket, command and request delivery, search, and the library storage.

## Commands

```sh
bun install --frozen-lockfile
bun run dev            # local development
bun run typecheck      # nuxt prepare, then strict vue-tsc
bun run lint           # Oxlint with the root configuration and anti-slop rules
bun run format:check   # Prettier
bun run test           # bun test
bun run generate       # static bundle in .output/public
```

`apps/host/Scripts/build.sh` copies `.output/public` into the Host resources when it exists, so run `bun run generate` before building Cadenza Host with the browser Remote.

## Publishing the Bluetooth build

`.github/workflows/pages.yml` publishes this app to GitHub Pages on each push to `main` that changes `apps/web`. The site is `https://24amstudio.github.io/cadenza/`, served over HTTPS, so Web Bluetooth works there.

- One-time setup: in the repository's Settings, Pages, set Source to GitHub Actions. The `configure-pages` step fails until this is set.
- The workflow reads the base path from Pages and passes it to the build as `CADENZA_WEB_BASE_URL`. Cadenza Host's build leaves that variable unset, so the Host bundle keeps serving from the root.
- Only `main` deploys. The `github-pages` environment and `main` should both be protected, because anyone who can push to `main` controls the page that holds a paired browser's token.

## Browse and playback modes

- The Library page has a Playlists tab, and an artist or album name on Now Playing or on any song row opens that artist's or album's page. Both need the Host to advertise `library.browse`. A page is requested once from the Host with `browse.get`, kept in memory for a minute (playlists) or five minutes (albums and artists), and cancelled with `operation.cancel` when it is left before it loads.
- Shuffle and Repeat sit beside the volume on Now Playing and in the player bar when the Host advertises `playback.modes`. Repeat steps through off, all, and one. A press shows its new state at once and is sent through the same one-at-a-time queue as the other controls.
- Lyric lines the Host places at the end are right-aligned. Every word that is sounding sweeps, so overlapping lines such as a second voice animate together.

## Search, Library, and local data

- Search has two sources: Apple Music, which the Host searches through its catalog, and Library, which searches the Host's Music library. Results can be played next or added to the queue. The Host needs a song prepared before it can queue it, so the browser prepares a song the first time this Host process hears about it and shows Preparing… on that row.
- Suggestions appear while typing, after a 250 ms pause, when the Host advertises `search.suggest`. Older answers are dropped when newer text has been typed.
- Favorites and History are kept in this browser's local storage under `cadenza.web.favorites.v1` and `cadenza.web.history.v1`. Nothing is sent to Cadenza Host, so they do not follow you to another browser or device.
- History keeps the newest 200 entries. It records a request when this browser sends it, and a play once per occurrence while this browser is connected. Clear history asks first and keeps Favorites.
- When storage is blocked or full, Favorites and History still work until the page is closed.

## Not included yet

- Listening analytics. The browser acknowledges credits so the Host's outbox stays bounded, but it does not store them.
