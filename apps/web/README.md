# Cadenza Remote Web

The browser Remote for Cadenza Host. It is a client-rendered Nuxt 4 single-page app (`ssr: false`). `nuxt generate` emits static files only, with no server bundle. Cadenza Host serves those files and its socket from one origin.

## How it connects

- When Cadenza Web is on (Settings, Network), Cadenza Host serves the app on its control port plus two (43129 by default), over plain HTTP. Browsers therefore show no certificate warning, but this traffic is not encrypted.
- The pairing QR code is `http://<host>:43129/#CDZP:<payload>`. The fragment is the same one-use native invitation that Cadenza Remote reads, so a regular camera opens the web Remote and the native app still pairs from the same code. The page removes the fragment from the address bar as soon as it reads it.
- The browser connects to `wss://<host>:43129/v1/socket` and speaks the `shared/protocol/v1` frames: pairing or hello, state, commands, lyrics, artwork, and clock probes. A command is sent once. If the socket closes before its result, the command is reported as unconfirmed, queried later by its command ID, and never sent again.
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

## Not included yet

- Queue edits and search from the browser. The app only shows the queue and sends playback controls.
- Listening analytics. The browser acknowledges credits so the Host's outbox stays bounded, but it does not store them.
