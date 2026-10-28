# Compatibility and recovery

The source root and application names are now Cadenza. Existing installation identities deliberately retain their Cadence spelling:

| Boundary                           | Preserved value and reason                                                                                                                                                                   |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Android installed ID               | `app.cadence.remote`; `.debug` development and `.ci` CI suffixes keep test packages separate. Keeping the Production ID preserves app-private storage, Keystore alias and permission grants. |
| Kotlin namespace                   | Renamed to `app.cadenza.remote`; manifest component classes use the new namespace. Existing launcher shortcuts may need recreating.                                                          |
| macOS bundle ID / Keychain service | `app.cadence.host`, preserving preferences and saved device/TLS identities. Ad-hoc code-signing changes may still cause macOS privacy prompts.                                               |
| Host storage directory             | `~/Library/Application Support/Cadence Host`, outside the replaceable `.app` bundle.                                                                                                         |
| SQLite files                       | Host uses `database/main.sqlite` and `database/logs.sqlite`, with binary cache files under `database/metadata/`; Remote retains its existing `cadence.sqlite`.                               |
| LAN discovery                      | `_cadence._tcp`, so older installations can still discover the same Host. Certificate pinning remains mandatory.                                                                             |
| Schema identity                    | `urn:cadence:protocol:v1:*`; renaming human-facing names does not create a new wire protocol.                                                                                                |

Do not uninstall or clear app data to upgrade. Reuse the original Android signer; a newly generated key cannot update an existing APK. The old development APK can upgrade only with its original debug keystore. Production and CI installs have separate identities and data.

## Staggered upgrades

The protocol remains major 1, minor 1. A new Remote first sends the legacy hello/pair shape. After receiving capabilities from Host it can opt into `remote.configure` (editable name plus heartbeat support), `state.heartbeat` and `queue.play-next`. An older Host can still accept the initial connection; unsupported Play next stays disabled. A local name change appears on a capable Host after reconnect. Older Remotes continue receiving full snapshots rather than heartbeat-only idle updates.

Every connection path verifies the same paired certificate and authenticated Host ID. DNS-SD names and addresses are hints. Discovery supplies a bounded set of up to eight candidate IPv4 addresses; the saved address remains a fallback. Failed candidates rotate, learned addresses expire after five minutes, and the successful address is persisted. Android API 34+ NSD can report multiple IPv4 addresses; vendor firmware may expose fewer candidates. This is address failover over local TCP/TLS, with no Bluetooth, USB tunnel, public-IP fallback or cloud relay.

Temporary transport failures reconnect with bounded exponential backoff. A handshake times out after six seconds, and missing Host frames trigger recovery. OS network callbacks restart discovery when the default network changes. Backgrounding Cadenza Remote releases an idle or paused unpinned session; active playback and an explicitly pinned song-status session keep their authenticated socket and notification until playback pauses, monitoring is unpinned, or the process is terminated. Reopening resynchronizes state. No persistent service or wake lock keeps a device awake. Host listener recovery retries at 1/2/4/8/16/30 seconds and continues bounded retry cycles after reporting a recovery issue.

The Android 12 / API 31 baseline uses the framework `MediaSession` and a standard ongoing notification for lock-screen metadata and controls. Android 16 / API 36 can request a promoted ongoing notification with a status chip when the permission, user setting, channel and device policy allow it. HarmonyOS 4.3 is treated as the Android 12 baseline: it keeps the standard notification and MediaSession path, while Android 16 promotion is unavailable unless the vendor explicitly exposes a compatible API.

Requests carry durable IDs. Remote never re-enqueues a mutation during reconnect: it asks for the original outcome. An action already sent to Music can remain unconfirmed; native readback/reconciliation is required before retrying it as a new action. A new connection cannot transfer request ownership.

## Damaged or interrupted state

SQLite uses transactional migrations and atomic settings/analytics updates. Schema 3 is additive and does not recreate tables or delete history. A malformed disposable snapshot is ignored and replaced by fresh Host state. An unreadable Favorite is skipped, counted and shown as preserved data needing attention; healthy Favorites remain available. The app does not silently delete the damaged row or claim database corruption was repaired.

Update downloads are staged and hash/signature checked before installation. Android manifest/signature files use atomic writes; a mixed/interrupted metadata pair fails verification and cannot install an unverified package. Host replacement keeps rollback state. Neither updater replaces an installation in development or CI profiles. Ordinary startup failures surface a corrective prompt while keeping existing data; no destructive reset loop is implemented.
