# Cadenza Remote

The native Android app uses Kotlin, Jetpack Compose Material 3 Expressive, Android NSD, Camera2, Keystore, SQLiteOpenHelper, PackageInstaller, and the framework MediaSession API. It targets Android 12 / API 31 and newer devices and does not require an Android audio engine or Google Play services.

The Cadenza evolution adds editable device identity, local Favorites, theme preferences, an official adaptive list-detail home, ongoing session notifications and bounded address failover. Current strict compile/lint/test and packaging evidence is recorded in [validation](../../docs/agents/VALIDATION.md); the user reports a device installation, but this workspace has no ADB evidence and Host integration remains unverified. See [building](../../docs/BUILDING.md) and [setup](../../docs/SETUP.md).

## Source map

- `RemoteModel.kt` manages connection generations, commands, the one-second feedback timer, clock samples, replicated state, and personal credits.
- `network` implements pinned local TLS/WebSocket connections, NSD discovery, bounded endpoint selection and OS network callbacks.
- `data` contains strict message parsing, SQLite migrations, observed-time synchronization, and encrypted credential storage.
- `ui` contains native pairing, adaptive home/Favorites, playback with integrated Lyrics mode, search, shared queue, analytics and settings screens.
- `updates` verifies P-256 release metadata and APK identity, stages updates, and handles OS installation confirmation.

Android Keystore protects the key used to encrypt Host credentials. SQLite schema 3 stores encrypted payloads, settings, Favorites, profile references, state cache, unresolved command identities and local analytics. Settings use checked SQLite transactions. A credit insertion atomically updates its aggregate and sequence cursor; acknowledgment follows the commit. Daily maintenance preserves Favorites, aggregates, counted occurrences, cursors and unresolved commands. The installed application ID remains `app.cadence.remote` for data/signing compatibility. Development and CI builds disable updater scheduling, download and installation.

## Build

Use `build.cmd Debug` on Windows or `bash build.sh Debug` with JDK 17 and SDK platform `android-37.0`. Caches remain under the monorepo. The scripts stop if the platform is missing. Gradle resolves dependencies and may fetch missing licensed build components inside the configured SDK root; its first invocation can also download the pinned distribution.

`check.cmd` on Windows and `check.sh` on macOS/Linux run native source gates without packaging a release. Tests cover clocks, input validation, lyric identity, certificate pinning, signed release metadata, SQLite migration/replay/recovery, and representative production Compose screens. Robolectric renders Android API 31 under JDK 17; screenshots use synthetic data and do not establish device or Music integration. Release APK builds require the stable signing identity described in [BUILDING.md](../../docs/BUILDING.md).
