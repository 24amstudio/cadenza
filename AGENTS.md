# Cadenza contributor instructions

Read the global `C:/Users/aftah/.codex/SPEC.md` applicability and relevant sections when that file is available. This repository's [SPEC.md](SPEC.md), [implementation goalset](docs/GOALSET.md), and [validation record](docs/VALIDATION.md) supplement it. Missing native environments remain unverified; never mark them passed.

## Product and architecture

Cadenza Remote is a native Kotlin/Jetpack Compose Material 3 Expressive Android controller. Cadenza Host is a native Swift 6.2+/SwiftUI/AppKit Mac companion. The existing Music.app plays all audio. No Android audio player, cloud relay, Google Play services, paid Apple Developer account, or web runtime is required.

One Host accepts multiple paired Remotes over certificate-pinned local TLS WebSockets. Bonjour/Android NSD discovers IPv4 addresses. A one-use, five-minute pairing invitation carries a public certificate and random pairing secret. It never carries a private key. Each Remote authenticates independently. Host owns queue revisions, native row bindings, authorization and command receipts. Remotes interpolate progress from a sampled monotonic timeline and share the Host's timed lyric document and English translation revision.

Host protects other Remotes' pending and current requests when cross-Remote editing is off. Pause/resume and volume are shared. Play next inserts a new request without replacing the current song. Never replay a mutation after reconnect: query its original command ID and durable receipt. The 1,000 ms contract is confirmed/rejected/expired/unconfirmed feedback, not a universal promise that Music or an internet download completes in that time.

## Structure

| Location                                           | Responsibility                                                                               |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `apps/host/Sources/CadenzaHost`                    | Native Host UI, onboarding, Music adapters, local service, SQLite and updates                |
| `apps/host/Sources/CadenzaSecurity`                | Signed release/asset/archive validation shared with the updater and release tool             |
| `apps/host/Sources/CadenzaUpdater`                 | Verified, rollback-capable app replacement helper                                            |
| `apps/host/Sources/CadenzaRelease`                 | Local P-256 key generation and release manifest signing                                      |
| `apps/host/Resources/music.js`                     | Fixed, strictly checked JXA Music boundary; no arbitrary script endpoint                     |
| `apps/remote/app/src/main/java/app/cadenza/remote` | ViewModel, native UI, discovery/network, SQLite and updates                                  |
| `apps/*/storage`                                   | Ordered, transactional, versioned SQL migrations and authorization/maintenance SQL           |
| `shared/protocol`                                  | JSON schemas, examples and compatibility contract                                            |
| `shared/version.properties`                        | Human version and strictly increasing release build number                                   |
| `shared/changelog.json`                            | Maintained release history, bundled offline and included in signed release metadata          |
| `shared/release-config.json`                       | Explicit public repository and public verification key; intentionally empty until configured |
| `tests`, `tools`                                   | Portable behavioral checks, strict JS tooling and native build/CI scripts                    |

## Compatibility and naming

Use Cadenza, Cadenza Host and Cadenza Remote in new source, UI and artifacts. Do not globally replace compatibility literals. Android's installed ID remains `app.cadence.remote` (`.debug` for development and `.ci` for CI); Kotlin namespace is `app.cadenza.remote`. Host bundle ID and Keychain service remain `app.cadence.host`; its existing Application Support directory remains `Cadence Host`. Both SQLite filenames remain `cadence.sqlite`. The vault alias derives from the installed package name. Bonjour `_cadence._tcp` and schema URNs `urn:cadence:*` remain stable wire identities. Preserve app signing keys and increasing version codes. Ad-hoc Mac signatures can require privacy approval again.

## Native implementation conventions

- Prefer OS APIs and existing small dependencies. Keep audio, translation models and Apple account access on the Mac. Catalog search currently uses Apple's public web client token and is an undocumented, potentially changeable integration.
- Host UI/state is `@MainActor`; use actors/async boundaries for network and other independent work. Do not block the main actor with a long subprocess. Keep native readback and authorization immediately before external effects.
- Remote uses `StateFlow`, lifecycle-aware UI collection and ViewModel coroutines. Move blocking SQLite, file and network operations to IO. Persist preferences/favorites before publishing success. Use saveable navigation, input, selection and scroll state; never suppress Activity recreation to hide state loss.
- Keep migrations additive when practical. Never fall back to deleting/recreating a damaged database. A disposable malformed snapshot may be ignored; a damaged Favorite is skipped and reported while its original row is preserved. Credentials/analytics/Favorites must survive maintenance and updates.
- Preserve strict warnings-as-errors, formatting and lint rules. Maintained files must remain at most 1,000 physical lines. JS complexity is at most 20, with the vendored generic anti-slop rules enforced. Do not add suppressions, test skips, baselines or weaker checks to pass.
- Use native semantics, labelled controls, accessible modal blockers and viewport-anchored routine feedback. Show pending state immediately and prevent duplicate submissions. No eyebrow labels or filler copy. Capture and inspect real implementation renders at tablet/phone widths and large text. Robolectric evidence uses synthetic data and does not prove target-device behavior.

## Permissions, recovery and resources

Onboarding tries MusicKit's supported `MusicDataRequest.currentCountryCode`; unavailable authorization/entitlements/account information leads to a manual storefront choice. Do not infer the Apple Music account country from an App Store region or locale. Explain Automation, Accessibility and Local Network access before their respective actions. Never claim to grant macOS privacy approval programmatically. Setup completes only after an authenticated Remote is connected. Reopening Host returns to Settings; closing it leaves the service running; hiding its menu-bar icon must leave a Spotlight/Settings recovery and Quit action.

Use bounded candidate sets, transport/handshake deadlines, adaptive reconnect backoff and cleanup on lifecycle exit. Discovery does not confer trust; verify the paired public certificate on every address. Do not scan unrelated machines or fall back to internet relays. Host listening retries are bounded; revoked credentials require pairing. Recover quietly during routine interruptions, with actionable prompts for blocked permissions, invalid credentials or storage failures.

Android control sockets, discovery, status notifications and animation stop when the foreground control session ends. A standard ongoing notification follows meaningful session changes. Only explicit current-song monitoring may request a Live Update on an eligible OS, with an Unpin action. Huawei/Android may decline promotion; respect notification permissions and channel preferences. Never add a timer that redraws or writes SQLite for every progress frame. Host uses event hints plus bounded fallback observation; active requester analytics still require native time samples. Measure optimized, non-debug builds on the actual devices before claiming battery/CPU improvements. See [resource validation](docs/RESOURCES.md).

## Local setup and checks

Windows work, toolchains, caches, temporary files and outputs belong under `F:/Development/cadenza`. Do not install Android Studio, an emulator, or large tools without the user's authorization. Android command-line tools and their build dependencies on F: are authorized. In Command Prompt, `call tools\windows-env.cmd` configures F: paths; PowerShell execution policy need not be changed. Always invoke the Gradle wrapper by its explicit path.

Use the existing system Bun by absolute path. Resolve it from the original shell PATH before a Bun-launched script: PowerShell `$env:SYSTEM_BUN=(Get-Command bun -CommandType Application).Source`, or POSIX `export SYSTEM_BUN="$(command -v bun)"`. Never use a temporary `bun-node-*` shim. Native app packages contain neither Bun nor Node.

| Command                                               | Checks/output                                                                                              |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `node tools/check.mjs --portable`                     | Strict TS/JXA analysis, strict Oxlint, Prettier, source limits, shell syntax and portable behavioral tests |
| `apps\remote\check.cmd` / `bash apps/remote/check.sh` | Kotlin compilation (both variants), ktlint, unit/render tests, Android lint                                |
| `bash apps/host/Scripts/check.sh`                     | Strict Swift format lint and Swift compilation/tests on macOS                                              |
| `node tools/check.mjs`                                | Complete local gate, requiring Mac plus Android tools; used by commit/push hooks                           |
| `apps\remote\build.cmd Debug`                         | Development APK, with updates disabled                                                                     |
| `bash apps/host/Scripts/build.sh`                     | Ad-hoc native app and ZIP, default development profile                                                     |
| `node tools/build-info.mjs`                           | Immutable commit SHA for a clean Git tree, otherwise a source SHA-256 identity                             |

Run targeted checks for coherent edits and reserve packaging for final validation. Full local gates must pass for final code before commits, pushes, merges or releases. A missing Mac does not waive Swift compilation/format checks. Do not commit or publish partial verification.

## Builds, changelogs and updates

The user has frozen the visible application version at **0.0.1** until they explicitly request a change. Do not infer a version bump from new features or milestones. Keep the internal release build number increasing for upgrade compatibility. Android startup displays `Cadenza VERSION-PROFILE-SOURCE-YYYYMMDD.HHMMSS`; the timestamp is embedded at build time in UTC, and `source-` identifies an uncommitted source digest rather than a Git commit.

Profiles are `development`, `ci`, `production`. Defaults disable automatic update checks/downloads/installation. Android selects a release profile with `-Pcadenza.profile=...`; Host uses `CADENZA_BUILD_PROFILE`. Debug is always development. CI rejects Production profiles. Production Android needs the original private release keystore through environment variables; never commit signing material. Signing identity, manifest verification identity and installed data must survive upgrades.

Apps embed a version and immutable build ID. Packaged users need no Git checkout. Offline bundled changelogs are distinct from an explicit, read-only comparison with signed GitHub release metadata. Compare increasing build numbers and signed history; do not fabricate commit comparisons or newer notes when offline/unconfigured. Automatic update activity is isolated behind the Production gate, including scheduled jobs and installer entry points. See [release instructions](docs/RELEASES.md).

Checking CI runs on pushes across branches and PRs. It intentionally includes compilation/typechecks and existing automated tests per the user's explicit exception to lightweight CI. Build CI accepts only a successful Checking **push on main in the same repository**, checks out its exact SHA and publishes CI APK/native app ZIP artifacts. It uses no Production signing secrets. The ZIP already distributes `.app`; a DMG is not required. CI does not replace local validation or target-device/accessibility tests.

## Guidance to consult selectively

Before relevant platform changes consult [Android agent skills](https://developer.android.com/tools/agents/android-skills), especially adaptive state preservation, lifecycle/performance and permission guidance, and the [Swift agent skills directory](https://github.com/twostraws/swift-agent-skills). Read the exact skill and relevant reference files before adopting guidance. Verify authors, current APIs, licenses, deployment targets and scope. Do not blindly install skills or migrate architecture merely because a skill recommends a framework. The current home uses the documented Material adaptive navigable list-detail scaffold without a wholesale Navigation 3 migration; it remains a native official adaptive component. SwiftUI Pro's applicable data-flow, lifecycle and performance guidance supplements project conventions without raising the existing deployment target.

## Known validation boundaries

Read the current validation record before reporting completion. Mac compilation, real Music queue/cache/translation adapters, ad-hoc update installation, actual MatePad notification behavior, independent multi-Remote latency/lyric sync, VoiceOver/TalkBack and hardware resource measurements need target evidence. Catalog/AX/cache adapters are conditional integrations, not documented Apple session-control APIs. No repository URL, release key, signing identity or published baseline may be invented. No subagents are requested for this implementation: continue solo unless the user changes that instruction.
