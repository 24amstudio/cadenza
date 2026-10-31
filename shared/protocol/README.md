# Cadenza LAN protocol

Version 1 uses JSON text frames over a persistent local TLS WebSocket. Host advertises `_cadence._tcp` with a public `host_id` TXT record. Discovery identifies a candidate address. New QR invitations carry a Base64URL-wrapped compact binary envelope containing the Host address, one-use secret and SHA-256 fingerprint of the public leaf certificate. Remote uses the one-use secret on the Host's local bootstrap socket to retrieve the public DER certificate, verifies its fingerprint, and then pins the exact TLS leaf. Older invitations may include the public DER certificate directly in the envelope. No private key leaves the Host. The pin binds the Host across LAN address changes; a changed certificate requires pairing again.

The session contract also defines transport policy and status frames. A pairing may bind LAN (Wi-Fi or Ethernet), BLE, or both to one logical Remote session. `transport.configure` selects `lan_only`, `ble_only`, or `hybrid` mode and deterministic or opportunistic path selection. `session.status` carries bounded power, resource, constraints, and per-path health data in both directions; energy estimates use `energy_percent_per_hour`, `energy_confidence`, and `sample_age_ms` and remain estimates rather than exact battery accounting. Either side may reject a path with latency, loss, or reliability limits. Host and Remote preferences are blended only after those hard limits, and the resulting selected path, bulk path, policy mode, confidence, and reason are returned to both sides. Manual Host path selection and minimum dwell are explicit policy fields; they do not override hard limits. Transport hints never replace Host authentication or command receipts.

LAN discovery uses Bonjour/DNS-SD first. Host also joins the local SSDP multicast group and answers a bounded `M-SEARCH` for `urn:cadenza:host:1`; Remote may issue that query as an optional fallback. SSDP responses are untrusted address hints and must include a Host ID and local HTTPS location; the QR certificate fingerprint and authenticated handshake remain authoritative. SSDP is never used for port forwarding, WAN exposure, or trust.

## Contracts

| Schema                | Purpose                                                                        |
| --------------------- | ------------------------------------------------------------------------------ |
| `common.schema.json`  | Identifiers, counters, catalog/library identities                              |
| `command.schema.json` | Strict mutation envelope and allowlisted actions                               |
| `result.schema.json`  | Confirmed, rejected, expired, or unconfirmed results                           |
| `state.schema.json`   | Authoritative playback, queue, quality, and timed lyrics                       |
| `session.schema.json` | Pairing, authentication, clock, search, preparation, state and status requests |
| `credit.schema.json`  | Ordered, per-Remote playback credits                                           |

Messages are bounded to 1 MiB; command messages to 64 KiB. Counters are nonnegative integers no greater than `2^53 - 1`. IDs use their documented string form. A catalog ID, library persistent ID, queue request ID, playback occurrence ID, and command ID are distinct concepts. Duplicate songs retain separate queue occurrences.

Recommendation messages are defined in `v1/recommendation.schema.json`. A Remote sends a bounded, signed `recommendation.passport`; Host verifies the Remote identity, signing key, sequence, expiry, consent, and resource limits before materializing a per-Remote profile. `recommendation.query`, `recommendation.result`, `recommendation.feedback`, and `recommendation.plan` carry the selected occurrence and its durable plan metadata. Plans are idempotent and use the existing native command receipt path; an inconclusive result is queried by its original plan ID and never replayed as a new mutation.

Unknown mutation fields and message types are rejected. Optional defined fields may be omitted. Protocol-major incompatibility requires an upgrade; no deprecated v1 fields or extension namespace currently exists.

## Session and timing

An unpaired Remote can send `pair` with either the one-use QR invitation secret or a four-digit Bluetooth PIN, plus its display name. The Host accepts a PIN for seven seconds and at most three attempts, then returns a distinct credential once. The PIN is only a short provisioning proof; it is not a long-lived credential. Later connections send `hello` with that Remote identity, token, and last committed credit sequence. Tokens are never placed in a URL, Bonjour record, ordinary database row, or log. A Bluetooth pairing can later add a LAN endpoint to the same Host profile; the authenticated Host certificate and identity remain authoritative.

Host creates a fresh epoch for every service start. Clock exchanges include the original Remote monotonic timestamp and Host receive/send times. Remote uses repeated samples and measured uncertainty before issuing an absolute Host deadline. Native animation uses that mapped timeline.

`search` and `song.prepare` are asynchronous preparation operations with identified results or errors. A control mutation has a separate deadline and visible Remote feedback by 1,000 ms. Preparation is not mislabeled as completed playback.

## Commands and ownership

Commands contain a unique command ID, Host epoch, expiry, expected revision, and action. They contain no actor, owner, or trusted song metadata. Host derives the actor from the authenticated connection and resolves song metadata itself.

Enqueue appends a distinct request. Play Now also requires an explicit current-occurrence guard, including `null` when nothing plays, and cannot jump protected requests. Remove and move identify queue entries; `before_entry_id: null` means the pending queue's end. Transport and seek identify the current occurrence.

The native coordinator serializes mutations, reads current Music state, evaluates [authorization SQL](../../apps/host/storage/authorize-command.sql), journals the intent, and rechecks authorization before dispatch. Cadenza Host-originated queue rows remain Host-controlled. The cross-Remote policy defaults off and protects the currently playing request too.

A repeated command ID is matched to its validated payload fingerprint. A changed payload produces `command_conflict`. Remote reconnects use the read-only `command.status` request; they never resend a mutation automatically.

## Results and reconciliation

`applied` requires confirmed native state. `rejected` and `expired` explain why an effect was refused or expired before dispatch. `unconfirmed` means the original outcome is unknown; it is not a cancellation guarantee.

An already-dispatched native action may finish after the deadline. Host keeps its intent and receipt for readback or manual reconciliation. A manually reviewed uncertain receipt may carry `resolved: true` with `unconfirmed`. This releases Remote's pending trigger while preserving the unknown historical outcome. It never permits automatic replay.

## State, lyrics, and credits

Minor 1 adds optional capabilities `remote.configure`, `state.heartbeat`, `queue.play-next`, `lyrics.lrclib`, `artwork.host-cache`, and `host.update`. An authenticated Remote sends `host.update` with `update_action` set to `check` or `install`. Host answers `host.update.status` with `update_state` and an optional `update_version` or `message`, and it shows no Host alert for these requests. Artwork requests are sent only when `artwork.host-cache` is advertised. New Remotes keep the initial hello/pair shape compatible with older Hosts and negotiate extensions from the welcome capabilities. An authenticated `remote.configure` names only its own identity and opts into idle heartbeats. Its name is bounded to 1-80 characters and control characters are rejected. A heartbeat carries the current Host epoch; an unknown epoch requires a full state refresh. Legacy Remotes continue receiving snapshots. New song insertion via `queue.play_next` preserves the current song and existing request order; it is distinct from protected `queue.play_now`.

Host pushes ordered snapshots containing one epoch, revision, sequence, current occurrence, finite requested queue, immutable requester attribution, waits, total remaining time, and optional observations. Unknown duration or unavailable quality remains unknown. An incoming AutoMix song is reported only when observed native text identifies it; it is not inferred from the queue head alone.

Host distributes one timed lyric document and English translation revision for the current occurrence. Remotes discard previous-occurrence documents, interpolate locally, and mark stale synchronization. The document source identifies Apple Music or the Host's LRCLIB fallback; translation sources distinguish original, Apple-supplied, and machine-translated text. Artwork requests are authenticated Host requests and return bounded cached bytes, keeping provider access on Host.

Credits have positive contiguous sequences per pairing. The first credit increments one occurrence's count only with positive observed time; later credits add playing time. Host excludes pauses and seek jumps. Remote commits aggregate and cursor changes before acknowledging. Duplicate or older credits remain ignored after raw cleanup, while a sequence gap requires replay.

These contracts define the wire format; each native application must also pass its platform-specific build and integration checks.
