# Cadenza Remote Web

The browser Remote for Cadenza Host. It is a client-rendered Nuxt 4 single-page app (`ssr: false`). `nuxt generate` emits static files only, with no server bundle. Cadenza Host serves those files and its socket from one origin.

## How it connects

- When Cadenza Web is on (Settings, Network), Cadenza Host serves the app on its control port plus two (43129 by default), over plain HTTP. Browsers therefore show no certificate warning, but this traffic is not encrypted.
- The pairing QR code is `http://<host>:43129/#CDZP:<payload>`. The fragment is the same one-use native invitation that Cadenza Remote reads, so a regular camera opens the web Remote and the native app still pairs from the same code. The page removes the fragment from the address bar as soon as it reads it.
- Web Bluetooth exists only in a secure context (HTTPS or localhost) and only in Chromium-based browsers. The LAN page at `http://<host>` therefore offers the QR code, not Bluetooth.
- Pairing over Bluetooth works from a secure origin: the GitHub Pages site below. Open it, choose Pair a Remote on Cadenza Host, then enter the four-digit PIN that Cadenza Host shows. Like Cadenza Remote, the browser pairs over the Host's BLE service with the name and PIN, not the QR code. The Pages site cannot reach the Host's plain `ws://` socket, so this browser stays on Bluetooth for control after pairing. Reconnecting needs a click, because the browser's device chooser requires one.
- The browser connects to `ws://<host>:43129/v1/socket` and speaks the `shared/protocol/v1` frames: pairing or hello, state, commands, lyrics, artwork, and clock probes. A command is sent once. If the socket closes before its result, the command is reported as unconfirmed, queried later by its command ID, and never sent again.
- Lyrics and artwork come from Cadenza Host. The browser never contacts lyric or artwork providers.
- Anyone on the same network can read what the browser receives, including the session token it sends on reconnect. Turn Cadenza Web off when you leave the network, and remove a browser's pairing in Cadenza Host if it is lost.
- `crypto.randomUUID` needs a secure context, so the app builds its identifiers with `getRandomValues` instead.

## Layout

- `app/components/` holds the shell, pairing, player, lyrics, queue, and views.
- `app/lib/` holds the protocol encoders and decoders, the Host client, clock estimation, invitation parsing, and playback math. These modules have no Nuxt dependency, so the tests import them directly.
- `app/stores/` holds the Pinia stores for the host connection, notices, preferences, and the active view.
- `tests/` holds the `bun test` suites for protocol framing, the host client against a fake socket, and the pure helpers.

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

## Not included yet

- Queue edits and search from the browser. The app only shows the queue and sends playback controls.
- Listening analytics. The browser acknowledges credits so the Host's outbox stays bounded, but it does not store them.
