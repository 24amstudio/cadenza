# Cadenza development

Cadenza is a native monorepo. Host owns Music.app control and the authoritative queue; Remote renders state and stores only its own listening aggregates. Both apps have implementation source, packaging scripts, and user documentation. Remote's native compilation, lint, tests, and debug packaging pass locally. Host compilation and real-device integration remain pending.

## Source responsibilities

| Area                                                    | Location                                                                                                                    |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Host native app and feature components                  | `apps/host/Sources/CadenzaHost/{Host,Lyrics,Artwork,Catalog,Commands,Music,Network,Queue,Database,Security,Updates,Shared}` |
| Shared Host release verification and archive inspection | `apps/host/Sources/CadenzaSecurity`                                                                                         |
| Host update helper and release signer                   | `apps/host/Sources/CadenzaUpdater`, `CadenzaRelease`                                                                        |
| Remote native UI, networking, storage, updater          | `apps/remote/app/src/main`                                                                                                  |
| Native unit tests                                       | `apps/host/Tests`, `apps/remote/app/src/test`                                                                               |
| Wire contracts                                          | `shared/protocol/v1`                                                                                                        |
| Executable cross-platform SQL and JXA checks            | `tests`                                                                                                                     |

Runtime dependencies stay native. Neither app embeds Node, Bun, a browser, or a separate server runtime. SQLiteOpenHelper is used directly on Android; Room and KSP are not dependencies.

Host source is organized by feature and responsibility. Each provider has its own directory under `Sources/CadenzaHost/Lyrics/Providers`, with its adapter, transport, records, and provider-specific helpers kept together. Parsers, transports, cache layers, models, services, and UI surfaces live in separate focused files; a provider change should not require editing an unrelated provider's implementation.

## Local tooling and storage

The Windows root is `D:\Dev`. Use `tools\windows-env.cmd` from Command Prompt, or the equivalent PowerShell script when local policy permits. Caches, temporary files, SDK paths, downloaded distributions, and build output stay under D:/Dev. No execution-policy bypass is needed.

The existing Node 22.23.3 and Bun 1.4.4 installations are development tools. Node's built-in SQLite requires Node 22.13+. Its experimental warning is expected.

With the user's approval, JDK 17, Android command-line tools and SDK packages, Gradle, and native build dependencies were installed under D:/Dev. Android Studio, an emulator, and a Swift toolchain were not installed. The Gradle wrapper and distribution are verified against upstream SHA-256 checksums. Development dependency versions and the patched `fast-uri` override are pinned. Lint-plugin provenance is in [tools/vendor/README.md](../../tools/vendor/README.md).

For an allowed future development-dependency install:

```powershell
$env:SYSTEM_BUN = (Get-Command bun -CommandType Application).Source
& $env:SYSTEM_BUN --version
$env:BUN_INSTALL_CACHE_DIR = 'D:\Dev\.cache\bun'
& $env:SYSTEM_BUN install --frozen-lockfile --ignore-scripts
```

Child scripts must receive and invoke that absolute system Bun path too.

## Validation gates

```powershell
node tools/check.mjs --portable
node tools/check.mjs
```

The portable command runs strict TypeScript analysis of maintained JavaScript/JXA, Oxlint with warnings denied and the generic anti-slop rules, formatting, physical file caps, shell syntax, PowerShell static parsing on Windows, and real SQL/JXA/protocol behavior tests.

The complete command adds the native checks available on the current platform. macOS runs Swift Host checks and Android Remote checks; Windows and Linux run the Remote checks and report Host as deferred. It fails when the native toolchain for the current platform is unavailable. `.githooks/pre-commit` and `pre-push` call this platform-aware gate. CI runs the separate Host and Remote jobs, so a deferred local platform never becomes a reported pass.

Run dependency and scoped secret scans locally. Device, integration, security, accessibility, performance, and update-installation evidence is tracked in [VALIDATION.md](VALIDATION.md). The implementation goalset explicitly authorizes compilation/typechecks, existing tests and build CI in addition to lint/formatting. Checking and Build workflows implement that exception. Local commit/push gates remain mandatory.

## Persistence and failure boundaries

Both native databases apply ordered migrations, enable foreign keys and WAL, and serialize writers. Host stores `database/main.sqlite`, `database/logs.sqlite`, and `database/metadata/`: main schema 1 contains application state and the cache index, logs schema 1 contains separately retained system logs, and artwork, animated artwork, and other binary media remain private files referenced by main SQLite. Logs have seven-day default retention and a thirty-day maximum and never count toward the user media-cache limit. A failed migration preserves existing data; a newer schema is refused. Host uses prepared bindings and SQLite's backup API before an update. Remote also stores settings and Keystore-encrypted credential payloads in its existing SQLite database so failed writes propagate before pairing or installation continues.

Host startup does not delete or recreate an unreadable database. SQLite integrity failures remain visible as a storage error for recovery from the preserved file or backup. If the database file is absent, SQLite creates a new schema and Host tells the user that pairings must be restored. Cache repair removes missing media references and orphaned media files, allowing the next provider lookup to refill the entry. The cache defaults to 256 MB and is user-configurable from 64 MB to 1 GB; eviction removes artwork first, then provider metadata, and retains lyrics longest.

Host journals a unique command and planned queue identity before dispatch. Its session identity supplies the actor. Policy and revision are checked again immediately before a native effect. A receipt is not proof of successful playback: confirmation requires observed Music state. A crash or late native effect can remain unconfirmed, so Remote asks for the original status and never automatically repeats the mutation.

Manual Host reconciliation requires exact song matches and explicit cancellation of missing saved requests. Reviewed but historically uncertain actions retain that distinction. They can be released from pending state without being falsely marked successful.

Host emits contiguous per-pairing credit sequences and retains unacknowledged credits. Remote's insertion, aggregate update, and committed cursor share an atomic transaction. Cleanup preserves the durable cursor and counted occurrence identities, preventing recounts after compaction.

## Platform integration limits

Music's queue and playback badges use bounded Accessibility reads, while transport and library metadata use a fixed JXA script with data-only arguments. Public web catalog tokens and Music's lyric cache are undocumented adapters; LRCLIB and Apple CDN artwork use fixed, bounded HTTPS adapters on Host. Their failure is explicit and must not fabricate queue ownership, lyrics, quality, or AutoMix state.

Translation uses Apple's native Translation framework on Cadenza Host. Remotes receive one lyric document and translation revision. No Android language model or paid developer API is required by this source design.

The Windows tests cannot prove these macOS integrations. macOS access was deferred during implementation; source and documentation now exist, and Host validation needs a reachable supported system. [BUILDING.md](../BUILDING.md) and [VALIDATION.md](VALIDATION.md) record the remaining checks.
