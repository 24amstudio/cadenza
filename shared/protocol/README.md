# Cadenza LAN protocol

Version 1 uses JSON text frames over a persistent local WebSocket. The protocol uses no TLS and no certificate pinning: authentication comes from the one-use pairing secret and per-device tokens. Host advertises `_cadence._tcp` with a public `host_id` TXT record. Discovery identifies a candidate address. QR invitations carry a Base64URL-wrapped compact binary envelope, version 3, containing the Host address, control port, and one-use secret. Invitations carry no key or certificate material, and no private key leaves the Host.

The session contract also defines transport policy and status frames. A pairing may bind LAN (Wi-Fi or Ethernet), BLE, or both to one logical Remote session. `transport.configure` selects `lan_only`, `ble_only`, or `hybrid` mode and deterministic or opportunistic path selection. `session.status` carries bounded power, resource, constraints, and per-path health data in both directions; energy estimates use `energy_percent_per_hour`, `energy_confidence`, and `sample_age_ms` and remain estimates rather than exact battery accounting. Either side may reject a path with latency, loss, or reliability limits. Host and Remote preferences are blended only after those hard limits, and the resulting selected path, bulk path, policy mode, confidence, and reason are returned to both sides. Manual Host path selection and minimum dwell are explicit policy fields; they do not override hard limits. Transport hints never replace Host authentication or command receipts.

LAN discovery uses Bonjour/DNS-SD first. Host also joins the local SSDP multicast group and answers a bounded `M-SEARCH` for `urn:cadenza:host:1`; Remote may issue that query as an optional fallback. SSDP responses are untrusted address hints and must include a Host ID and local HTTP location; the pairing token and authenticated handshake remain authoritative. SSDP is never used for port forwarding, WAN exposure, or trust.

Cadenza Web is a browser Remote that uses the same v1 frames. When it is on, the Host serves a WebSocket on a second plain-HTTP listener at the control port plus two, and serves its static web bundle when the build includes one. This listener has no TLS, so browsers show no certificate warning, and nothing on it is encrypted. The WebSocket upgrades only at `/v1/socket`, only for an `Origin` exactly equal to `http://` plus this request's `Host` header or to the hosted Cadenza Web origin `https://24amstudio.github.io`, and only when that `Host` is one of this Host's local addresses or loopback. The hosted origin is accepted on that socket path only, never on the stage socket. The Host answers any other request with a refusal. While the listener runs, the Host's welcome carries `web_port` and `web_host`, the Host's Bonjour name, so a browser that paired over Bluetooth can try `ws://<web_host>:<web_port>/v1/socket`, which follows a network address change, then `ws://<host_address>:<web_port>/v1/socket`, before Bluetooth. The QR code carries `http://<host>:<web port>/#CDZP:<payload>` only when the build includes the web bundle. The fragment is the native invitation and is never sent to the server. Native Remotes read the same invitation from the fragment. When Cadenza Web is off or the build has no web page, the QR code is the native `CDZP:` payload alone, which a regular camera does not open as a link. Traffic on this listener, including the pairing secret during pairing and the token on reconnect, is readable and replayable by anyone on the same network. Native Remotes use the same plain WebSocket on the control port. The `Origin` and `Host` checks stop other websites and DNS names from opening the socket, but not a network attacker.

## Contracts

| Schema                | Purpose                                                                                             |
| --------------------- | --------------------------------------------------------------------------------------------------- |
| `common.schema.json`  | Identifiers, counters, catalog/library identities                                                   |
| `command.schema.json` | Strict mutation envelope and allowlisted actions                                                    |
| `result.schema.json`  | Confirmed, rejected, expired, or unconfirmed results                                                |
| `state.schema.json`   | Authoritative playback, queue, quality, and timed lyrics                                            |
| `session.schema.json` | Pairing, authentication, clock, search, preparation, state and status requests                      |
| `media.schema.json`   | Artwork and animated album art requests, responses, and chunks                                      |
| `browse.schema.json`  | Album, artist, and playlist browse requests and results                                             |
| `cast.schema.json`    | Zero-account Cast stage messages: receiver profile, track suite, prefetch, clock, and karaoke video |
| `credit.schema.json`  | Ordered, per-Remote playback credits                                                                |

Messages are bounded to 1 MiB; command messages to 64 KiB. Counters are nonnegative integers no greater than `2^53 - 1`. IDs use their documented string form. A catalog ID, library persistent ID, queue request ID, playback occurrence ID, and command ID are distinct concepts. Duplicate songs retain separate queue occurrences.

Recommendation messages are defined in `v1/recommendation.schema.json`. A Remote sends a bounded, signed `recommendation.passport`; Host verifies the Remote identity, signing key, sequence, expiry, consent, and resource limits before materializing a per-Remote profile. `recommendation.query`, `recommendation.result`, `recommendation.feedback`, and `recommendation.plan` carry the selected occurrence and its durable plan metadata. Plans are idempotent and use the existing native command receipt path; an inconclusive result is queried by its original plan ID and never replayed as a new mutation.

Unknown mutation fields and message types are rejected. Optional defined fields may be omitted. Protocol-major incompatibility requires an upgrade; no deprecated v1 fields or extension namespace currently exists.

## Playback modes, browsing, and lyric placement

A Host that advertises `playback.modes` reports `shuffle` (boolean) and `repeat` (`off`, `one`, or `all`) in every state snapshot, and accepts the shared `playback.shuffle` (`enabled`) and `playback.repeat` (`mode`) commands. Like `playback.volume`, they name no occurrence, are authorized for any paired Remote, and use the ordinary command receipt. The Host confirms them by reading Music's mode back.

A Host that advertises `library.browse` answers `browse.get` with `browse.result` under the same `request_id`, or with an `error` frame (`catalog_unavailable`, `not_found`, or `invalid_command`). `browse.kind` is `album`, `artist`, `playlists`, or `playlist`. `playlists` takes neither `id` nor `song`. `playlist` requires `id`, a library persistent ID. `album` and `artist` require exactly one of `id`, a catalog numeric ID, or `song`, a catalog or library song whose album or artist the Host resolves itself. An `artist` may instead carry `artist_name`, the artist's text, which the Host finds in Apple's catalog. It is how a Remote browses an artist of a song the Host cannot identify, and it is never combined with `id` or `song`. A result holds at most 8 sections: songs at most 100 per section, albums at most 60, playlists at most 200, and the whole frame at most 256 KiB. Over Bluetooth the Host returns a smaller result of at most 32 KiB, without `detail` and with whole items dropped, in the same shape. Its songs are the same objects search returns and play through `song.prepare` plus the `queue.*` commands. Item artwork is fetched through `artwork.get`, so a Remote never contacts Apple. The request is asynchronous like `search` and is stopped by `operation.cancel`. The Host keeps results only in memory, up to 64 for six hours (60 seconds for playlists), and runs at most two provider fetches at a time.

A lyric line may carry `align: "end"` or `align: "center"`. The Host takes the first person `ttm:agent` in a TTML document as the start side. A group agent (`type="group"`) gets `align: "center"`, and every other person agent gets `align: "end"`. A line without `align`, including every LRC line, starts at the start.

## Session and timing

An unpaired Remote can send `pair` with either the one-use QR invitation secret or a four-digit Bluetooth PIN, plus its display name. The Host accepts each PIN for fifteen seconds and at most three attempts, and it issues a new PIN every fifteen seconds while the pairing window is open, then returns a distinct credential once. The PIN is only a short provisioning proof; it is not a long-lived credential. Later connections send `hello` with that Remote identity, token, and last committed credit sequence. Tokens are never placed in a URL, Bonjour record, ordinary database row, or log. A Bluetooth pairing can later add a LAN endpoint to the same Host profile; the authenticated Host identity and token remain authoritative.

Host creates a fresh epoch for every service start. Clock exchanges include the original Remote monotonic timestamp and Host receive/send times. Remote uses repeated samples and measured uncertainty before issuing an absolute Host deadline. Native animation uses that mapped timeline.

`search` and `song.prepare` are asynchronous preparation operations with identified results or errors. A control mutation has a separate deadline and visible Remote feedback by 1,000 ms. Preparation is not mislabeled as completed playback.

`search.suggest` asks for Apple Music completions for text being typed, and `search.suggestions` answers with `terms` and the top `songs`; an empty query is answered with empty suggestions. A `song.prepare` may carry `song_metadata` (the song's title, artist, album, and optional duration and artwork). The Host uses it only to find a library song whose persistent ID no longer resolves, and only when its identity matches `song`. When the Host cannot decode a frame, it answers with `error` carrying the request's `request_id`, or the command's `command_id` for a `command`, when that ID is a valid identifier. The Remote settles that request or command at once.

## Commands and ownership

Commands contain a unique command ID, Host epoch, expiry, expected revision, and action. They contain no actor, owner, or trusted song metadata. Host derives the actor from the authenticated connection and resolves song metadata itself.

Enqueue appends a distinct request. Play Now also requires an explicit current-occurrence guard, including `null` when nothing plays, and cannot jump protected requests. Remove and move identify queue entries; `before_entry_id: null` means the pending queue's end. Transport and seek identify the current occurrence.

The native coordinator serializes mutations, reads current Music state, evaluates [authorization SQL](../../apps/host/storage/authorize-command.sql), journals the intent, and rechecks authorization before dispatch. Cadenza Host-originated queue rows remain Host-controlled. The cross-Remote policy defaults off and protects the currently playing request too.

A repeated command ID is matched to its validated payload fingerprint. A changed payload produces `command_conflict`. Remote reconnects use the read-only `command.status` request; they never resend a mutation automatically.

## Results and reconciliation

`applied` requires confirmed native state. `rejected` and `expired` explain why an effect was refused or expired before dispatch. `unconfirmed` means the original outcome is unknown; it is not a cancellation guarantee.

An already-dispatched native action may finish after the deadline. Host keeps its intent and receipt for readback or manual reconciliation. A manually reviewed uncertain receipt may carry `resolved: true` with `unconfirmed`. This releases Remote's pending trigger while preserving the unknown historical outcome. It never permits automatic replay.

## State, lyrics, and credits

A Remote that sends `heartbeat: true` in `pair`, `hello`, or `remote.configure` receives a `heartbeat` while the state it already has still holds. Bluetooth Remotes also receive one while playback continues, when only the sample time, the position, and queue wait estimates changed and the position is where the last full state predicts. The Host still sends a full `state` at least every fifteen seconds to those Remotes, and immediately for a seek, a track change, or an edit. A heartbeat-capable Remote hears from the Host at least every 5 seconds over Bluetooth while playing and every 15 seconds while paused (about every 2 seconds over the LAN), by a small `heartbeat` frame that carries no snapshot, so a Remote may treat 35 seconds of Bluetooth silence as a missing Host. Minor 1 adds optional capabilities `remote.configure`, `state.heartbeat`, `queue.play-next`, `lyrics.lrclib`, `artwork.host-cache`, `motion.host-cache`, `artwork.progressive`, and `host.update`. An authenticated Remote sends `host.update` with `update_action` set to `check` or `install`. Host answers `host.update.status` with `update_state` and an optional `update_version` or `message`, and it shows no Host alert for these requests. Artwork requests are sent only when `artwork.host-cache` is advertised. A Remote that also advertises `artwork.progressive` may send `progressive: true` with `artwork.get`. The Host then answers with a small preview `artwork` frame (`variant` set to `preview`) before the full image, which travels as ordered `artwork.chunk` messages of 1 KiB each. The full image is at most 256 by 256 pixels, and so is the motion video. The preview is at most 32 by 32 pixels. The current song's state carries its preview as `artwork_preview`, so the title and the cover arrive together. A song change waits up to 1.5 seconds for that cover before the state goes out without it, and the Remote then asks for the preview itself. Each chunk carries its index, the chunk count, the total byte length, and the SHA-256 of the whole file. The Remote replaces the preview only after that digest verifies, and keeps the preview if verification fails. Without `progressive`, the full image is one `artwork` frame. Chunked artwork and motion travel after state frames, so they never hold a state update back. A Remote that advertises `motion.host-cache` may send `motion: true` with `occurrence_id` on `artwork.get`. The Host then sends the preview, followed by the song's motion video as `motion.chunk` messages under that request's ID when Apple has one, and the full image otherwise. Remotes that do not ask this way use `motion.get` for animated album art, which is only sent when `motion.host-cache` is advertised. A Remote whose song has changed sends `artwork.cancel` with the request's `request_id`. The Host stops that transfer and drops the frames of it that have not started going out, and sends nothing more for it. Host answers with ordered `motion.chunk` messages of at most 480 KiB of raw MP4 each over the LAN and 2 KiB each over Bluetooth, carrying the chunk count, total byte length, and a SHA-256 digest of the whole file; Remote assembles and verifies the file before playing it, and any refusal is `motion.unavailable`. The video is at most 1 MiB, and the Host stops a transfer that is not complete 30 seconds after its request, leaving the Remote with its still artwork. New Remotes keep the initial hello/pair shape compatible with older Hosts and negotiate extensions from the welcome capabilities. An authenticated `remote.configure` names only its own identity and opts into idle heartbeats. Its name is bounded to 1-80 characters and control characters are rejected. A heartbeat carries the current Host epoch; an unknown epoch requires a full state refresh. Legacy Remotes continue receiving snapshots. New song insertion via `queue.play_next` preserves the current song and existing request order; it is distinct from protected `queue.play_now`.

Sing is an optional Host-owned audio route. The `sing` snapshot field and `sing.enable`, `sing.disable`, and `sing.mix` command shapes are reserved for a negotiated `sing.mode` capability. They carry only state and bounded controls; PCM audio and model data never cross the authenticated Remote session. The production implementation advertises the capability for the MLX backend; release acceptance still requires a native capture and benchmark on supported Apple Silicon. Tests may inject the deterministic fallback for route and control validation.

Host pushes ordered snapshots containing one epoch, revision, sequence, current occurrence, finite requested queue, immutable requester attribution, waits, total remaining time, and optional observations. Unknown duration or unavailable quality remains unknown. An incoming AutoMix song is reported only when observed native text identifies it; it is not inferred from the queue head alone.

Host distributes one timed lyric document and English translation revision for the current occurrence. Remotes discard previous-occurrence documents, interpolate locally, and mark stale synchronization. The document source identifies Apple Music or the Host's LRCLIB fallback; translation sources distinguish original, Apple-supplied, and machine-translated text. Artwork requests are authenticated Host requests and return bounded cached bytes, keeping provider access on Host.

Credits have positive contiguous sequences per pairing. The first credit increments one occurrence's count only with positive observed time; later credits add playing time. Host excludes pauses and seek jumps. Remote commits aggregate and cursor changes before acknowledging. Duplicate or older credits remain ignored after raw cleanup, while a sequence gap requires replay.

Sing reports `model_ready` in its state object. It is `true` only when the verified Sing model is installed on the Host. A `sing.enable` command that needs an uninstalled model is rejected with `sing_model_not_installed`. The model-free stereo fallback in production needs no model, so it is not affected.

Remote updates are served by the Host's HTTP listener, not by the command socket. `GET /api/v1/updates/manifest` returns `version`, `buildNumber`, `sha256`, `sizeBytes`, and `lanDownloadPath`. `GET /api/v1/updates/remote/android.apk` returns the cached APK with `Accept-Ranges: bytes`, `X-Cadenza-SHA256`, and `206 Partial Content` for at most 8 MiB per range. Both requests must carry the paired Remote's `X-Cadenza-Remote-Id` and `X-Cadenza-Remote-Token` headers. Otherwise the Host answers `401`.

## Zero-account Cast stage contracts

`v1/cast.schema.json` defines the messages for receivers that need no registered Cast app: a Tier-2 `/tv` browser stage and a Tier-3 Android TV receiver. They travel on the Host's stage channel, `ws://<host>:<port>/cast/live?role=tv_stage` or `?role=android_tv_receiver`. JSON messages are text frames. Binary audio frames are binary frames. Remote command sockets never carry stage traffic, and the stage channel is refused on the Remote socket path.

### Pairing and receiver identity

A receiver sends `RECEIVER_PROFILE` on connect. Its `transportType` is `cadenza_web_tv_stage` or `cadenza_android_tv_receiver`. A standard Google Cast device (`CC1AD845`) never sends a profile. The Host reads its display capability from the `ca` bitmask of its `_googlecast._tcp` record, where bit `0x0001` means video output.

A profile without an approved `receiverToken` gets `STAGE_PAIRING` with a four-digit `pin` and `expiresInMs`. The Host shows the PIN and a `/tv` QR code, and a listener approves it on the Host or on a paired Remote. Approval returns `STAGE_ACCEPTED` with a `receiverToken` that the receiver stores and sends in its next profile. The Host stores only a hash of that token, so a receiver never reconnects without it. Until approval, the Host sends no audio, no lyrics, and no track data.

After approval, a receiver may send two advisory messages. `STAGE_PLAYBACK` (`codec`, `channels`, `path`, `active`) says what its audio output is playing. `channels` is 0 when the receiver cannot tell its output layout: a browser's MediaSource path, an AC-3 passthrough that the receiver decodes itself, or an output that reports no layouts. An Android TV reports 5.1 as 0 when its routed output accepts 5.1, because the TV may still downmix after HDMI. When the output is narrower, Android mixes the stereo itself, and the report says 2. It is sent when playback starts, changes path, or stops, and the Host shows it beside the route it sends. `STAGE_LOG` (`level`, `message`) records one line on the Host, and the Host limits each receiver to 30 lines in 10 seconds. A report that arrives before approval is ignored, and the socket stays open. The Host's status line names what was sent and what was reported, and it flags a mismatch. Google Cast devices send no reports, so their line ends with "(Unknown)" in place of a receiver format. Unknown means the Host cannot tell whether the receiver plays the sent layout or downmixes it.

An approved receiver sends `STAGE_COMMAND` with `action` set to `playback.pause`, `playback.resume`, `playback.skip`, or `playback.previous`, for example from a TV remote key. The Host runs it as an ordinary playback command, with the receiver as the actor, and a receiver that is not approved cannot send one.

### Track, clock, and video messages

- `TRACK_SUITE_PAYLOAD` carries track metadata, an optional quality badge that is omitted while the tier is unknown, the artwork and motion URLs, and timed lines with translations. `lines` use the same `line` shape as the state snapshot.
- `PREFETCH_NEXT_SUITE` tells the receiver to warm the next track's suite. The Host sends it 10 seconds before the track ends or when the queue is reordered.
- `OPTIMISTIC_STATE` follows a transport command at about +2 ms. `CLOCK_CALIBRATE` follows the Music command with the measured position, so the receiver corrects its drift.
- `VIDEO_KARAOKE_PAYLOAD` plays a DRM-free local music video (`source: lan_mp4`). Its `subtitleUrl` is a WebVTT track on the same LAN, and `userOffsetMs` is the saved nudge. Catalog video is never sent to a stage receiver.

### Binary stage frames

Integers are big-endian. Audio payloads are at most 65,536 bytes.

| Frame               | Layout                                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------- |
| `0x01` AUDIO_FRAME  | `[1B 0x01][1B codec][1B channels][1B sampleRateCode][8B presentationTimeUs][4B payloadLength][payload]` |
| `0x02` FLUSH_STREAM | `[1B 0x02][4B generationSeq]`                                                                           |
| `0x03` INIT_SEGMENT | `[1B 0x03][1B codec][1B channels][1B sampleRateCode][4B payloadLength][payload]`                        |

`INIT_SEGMENT` carries the fragmented MP4 `ftyp` and `moov` boxes that a Media Source buffer needs before any fragment. It is sent once per codec and layout, and again after a flush that changes it. A receiver appends each `AUDIO_FRAME` payload that carries a fragment (`moof` + `mdat`) for codecs 1 and 4.

| Codec | Name      | Payload                                                 | Produced by the Host                                  |
| ----- | --------- | ------------------------------------------------------- | ----------------------------------------------------- |
| `1`   | AC3_FMP4  | AC-3 fragments in fragmented MP4                        | 5.1 when the AC-3 helper is configured                |
| `2`   | FLAC_FMP4 | Reserved. Not produced: browser support is inconsistent | never                                                 |
| `3`   | LPCM_RAW  | Interleaved little-endian float32 PCM, no container     | Bitstream mode and receivers without fragment support |
| `4`   | AAC_FMP4  | AAC-LC fragments in fragmented MP4                      | stereo, and 5.1 folded down when AC-3 is unavailable  |

`sampleRateCode` is `1` for 48 kHz and `2` for 44.1 kHz. Channels range from 1 to 8. `FLUSH_STREAM` resets the receiver's buffers within 2 ms. It increases `generationSeq`, and the receiver drops any frame whose generation is older.

A receiver rejects any frame whose length or payload length does not match its header. It rejects an unknown type, codec, channel count, or sample-rate code. The contract has no Widevine, FairPlay, or license fields, and every stage URL is a plain HTTP LAN address.

Presentation mode keeps the `full_suite` wire value that shipped Remotes already send. The `full_cadenza_suite` name is a label only.

These contracts define the wire format. Each native application must also pass its platform-specific build and integration checks.
