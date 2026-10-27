# Cadenza contributor instructions

Read the global `C:/Users/aftah/.codex/SPEC.md` applicability and relevant sections when that file is available. This repository's [SPEC.md](SPEC.md), [implementation goalset](docs/GOALSET.md), and [validation record](docs/VALIDATION.md) supplement it. Missing native environments remain unverified; never mark them passed.

## Product and architecture

Cadenza Remote is a native Kotlin/Jetpack Compose Material 3 Expressive Android controller. Cadenza Host is a native Swift 6.2+/SwiftUI/AppKit macOS companion. The existing Music.app plays all audio. No Android audio player, cloud relay, Google Play services, paid Apple Developer account, or web runtime is required.

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

Use Cadenza, Cadenza Host and Cadenza Remote in new source, UI and artifacts. Do not globally replace compatibility literals. Android's installed ID remains `app.cadence.remote` (`.debug` for development and `.ci` for CI); Kotlin namespace is `app.cadenza.remote`. Host bundle ID and Keychain service remain `app.cadence.host`; its existing Application Support directory remains `Cadence Host`. Both SQLite filenames remain `cadence.sqlite`. The vault alias derives from the installed package name. Bonjour `_cadence._tcp` and schema URNs `urn:cadence:*` remain stable wire identities. Preserve app signing keys and increasing version codes. Ad-hoc macOS signatures can require privacy approval again.

## Native implementation conventions

- Prefer OS APIs and existing small dependencies. Keep audio, translation models and Apple account access on Cadenza Host. Catalog search currently uses Apple's public web client token and is an undocumented, potentially changeable integration.
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
| `node tools/check.mjs`                                | Platform-aware local gate: Host+Remote on macOS, Remote on Windows/Linux; used by commit/push hooks        |
| `apps\remote\build.cmd Debug`                         | Development APK, with updates disabled                                                                     |
| `bash apps/host/Scripts/build.sh`                     | Ad-hoc native app and ZIP, default development profile                                                     |
| `node tools/build-info.mjs`                           | Immutable commit SHA for a clean Git tree, otherwise a source SHA-256 identity                             |

Run targeted checks for coherent edits and reserve packaging for final validation. The platform-available local gate must pass before commits or pushes; deferred native checks remain explicitly unverified and CI must run both platform suites before merge or release. Do not claim a deferred Host check passed.

## Builds, changelogs and updates

The user has frozen the visible application version at **0.0.1** until they explicitly request a change. Do not infer a version bump from new features or milestones. Keep the internal release build number increasing for upgrade compatibility. Android startup displays `Cadenza VERSION-PROFILE-SOURCE-YYYYMMDD.HHMMSS`; the timestamp is embedded at build time in UTC, and `source-` identifies an uncommitted source digest rather than a Git commit.

Profiles are `development`, `ci`, `production`. Defaults disable automatic update checks/downloads/installation. Android selects a release profile with `-Pcadenza.profile=...`; Host uses `CADENZA_BUILD_PROFILE`. Debug is always development. CI rejects Production profiles. Production Android needs the original private release keystore through environment variables; never commit signing material. Signing identity, manifest verification identity and installed data must survive upgrades.

Apps embed a version and immutable build ID. Packaged users need no Git checkout. Offline bundled changelogs are distinct from an explicit, read-only comparison with signed GitHub release metadata. Compare increasing build numbers and signed history; do not fabricate commit comparisons or newer notes when offline/unconfigured. Automatic update activity is isolated behind the Production gate, including scheduled jobs and installer entry points. See [release instructions](docs/RELEASES.md).

Checking CI runs on pushes across branches and PRs. It intentionally includes compilation/typechecks and existing automated tests per the user's explicit exception to lightweight CI. Build CI accepts only a successful Checking **push on main in the same repository**, checks out its exact SHA and publishes CI APK/native app ZIP artifacts. It signs the CI APK with the release keystore secrets (`CADENZA_ANDROID_KEYSTORE_BASE64`, `CADENZA_ANDROID_KEYSTORE_PASSWORD`, `CADENZA_ANDROID_KEY_ALIAS`, `CADENZA_ANDROID_KEY_PASSWORD`), so CI APKs carry the release signing identity. It does not read the update-key secret. The ZIP already distributes `.app`; a DMG is not required. CI does not replace local validation or target-device/accessibility tests.

## Android and Compose guidance to consult selectively

Before an Android UI, Compose, media-layout, navigation, or performance change, read the relevant current upstream guidance and the exact skill references that govern the proposed edit:

- [Jetpack Compose performance](https://developer.android.com/develop/ui/compose/performance)
- [Compose API guidelines](https://android.googlesource.com/platform/frameworks/support/+/androidx-main/compose/docs/compose-api-guidelines.md)
- [Media discovery and exploration](https://developer.android.com/design/ui/gallery/media/discovery)
- [Media detail and playback](https://developer.android.com/design/ui/gallery/media/detail)
- [Android skills repository](https://github.com/android/skills)
- [Jetpack Compose performance skill](https://github.com/android/skills/tree/main/jetpack-compose/jetpack-compose-performance)
- [Edge-to-edge skill](https://github.com/android/skills/tree/main/system/edge-to-edge)
- [Navigation 3 skill](https://github.com/android/skills/tree/main/navigation/navigation-3)

Use only the skill that owns the problem. Read a performance skill's matching `references/*.md` file before reporting or fixing a finding, and follow its scope guards. Verify the upstream author, current API/version, license, deployment target and applicability before adopting a recommendation. Do not install every skill, add a dependency, or migrate architecture solely because a skill exists. The current Remote uses the official Material adaptive navigable list-detail scaffold; keep it unless a requested change explicitly selects Navigation 3. The [Swift agent skills directory](https://github.com/twostraws/swift-agent-skills) remains the reference for Host-specific Swift work.

### Compose API and state rules

- Follow Kotlin conventions and the Compose API guidelines for app code. Unit-returning `@Composable` elements use PascalCase nouns; value-returning composables use normal Kotlin function naming; remembered mutable factories use a `remember` prefix.
- Element composables accept one `modifier: Modifier = Modifier` as the first optional parameter and pass it to the emitted root node, appending internal modifiers after the caller's chain. Layout APIs use `content` for their primary slot.
- A composable emits content or returns a value, rather than doing both. Hoist state and events to the caller; use explicit state objects when related policy must stay consistent. Do not use `null` as a sentinel for internally remembered state. Name `CompositionLocal` values descriptively and use a `Local` prefix only when it is useful.

### Compose performance rules

- Profile and benchmark optimized release builds with R8; use app-specific Baseline Profiles for critical journeys such as cold start and scrolling. Debug or Robolectric results do not establish target-device performance.
- Reason about composition, layout and draw phases. Defer rapidly changing reads with lambda modifiers, avoid backwards writes, use `remember` only for expensive work or required identity with complete keys, and use `computedStateOf` for simple derived checks on Compose 1.13+ (or `derivedStateOf` where its heavier caching is justified).
- Lazy layouts provide primitive stable `key` and `contentType` values. Do not add `@Stable`, `@Immutable`, or `ImmutableList` to collection-bearing models as a blanket optimization; leave existing annotations alone unless the skill's large lazy-dataset scope applies.
- Keep side effects out of composable bodies, use lifecycle-aware collection for active Android flows, move blocking I/O and database work to `Dispatchers.IO`, and avoid impression effects inside lazy items. Preserve the project rule that progress animation does not create a timer, SQLite write, or network message for every frame.

### Edge-to-edge and IME rules

- Every Android `Activity` must call `enableEdgeToEdge()` before `setContent`. Activities with text input must declare `android:windowSoftInputMode="adjustResize"` and keep focused fields visible.
- Choose one inset strategy per hierarchy. Prefer `Scaffold` `PaddingValues` passed to the scrollable content's `contentPadding` and consumed there; otherwise use `safeDrawingPadding`, `windowInsetsPadding`, or `fitInside` at the appropriate child. Never double-apply `imePadding`, and do not put `safeDrawingPadding` on an adaptive scaffold parent when its inner screens need to draw edge-to-edge.
- Check light/dark system-bar icon legibility, navigation-bar contrast when a bottom bar is present, list first/last item reachability, FAB placement, full-screen dialogs, and keyboard behavior at narrow widths and large text sizes.

### Adaptive media and navigation rules

- Use the media discovery guidance to make meaningful use of expanded windows: richer feeds, supporting content, and related titles may share the space while the primary task remains clear. Use the media detail guidance for contextual detail, browse-while-listening layouts, supporting panes, and list-detail relationships; preserve Cadenza's queue, now-playing and lyric priorities.
- If a future change explicitly adopts Navigation 3, use type-safe destination keys, a controlled back stack, `NavDisplay`, saveable navigation state, and scene strategies for dialogs, bottom sheets, list-detail, two-pane, supporting-pane, multiple-backstack, deep-link, and conditional flows as applicable. Preserve selection, input, scroll and media state through configuration changes and process recreation. Do not perform a wholesale Navigation 2-to-3 migration as incidental cleanup.

## Known validation boundaries

Read the current validation record before reporting completion. macOS compilation, real Music queue/cache/translation adapters, ad-hoc update installation, target-device notification behavior, independent multi-Remote latency/lyric sync, VoiceOver/TalkBack and hardware resource measurements need target evidence. Catalog/AX/cache adapters are conditional integrations, not documented Apple session-control APIs. No repository URL, release key, signing identity or published baseline may be invented. No subagents are requested for this implementation: continue solo unless the user changes that instruction.
