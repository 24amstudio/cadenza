# Cadenza contributor instructions

Read the global `C:/Users/aftah/.codex/SPEC.md` applicability and relevant sections when that file is available. This repository's [SPEC.md](SPEC.md), [implementation goalset](docs/agents/GOALSET.md), and [validation record](docs/agents/VALIDATION.md) supplement it. Missing native environments remain unverified; never mark them passed. Read the relevant agent-only references in [docs/agents/README.md](docs/agents/README.md) before implementation, review, or validation.

## Product and architecture

Cadenza Remote is a native Kotlin/Jetpack Compose Material 3 Expressive Android controller. Cadenza Host is a native Swift 6.2+/SwiftUI/AppKit macOS companion. The existing Music.app plays all audio. No Android audio player, cloud relay, Google Play services, paid Apple Developer account, or web runtime is required.

One Host accepts multiple paired Remotes over certificate-pinned local TLS WebSockets. Bonjour/Android NSD discovers IPv4 addresses. A one-use, five-minute pairing invitation carries a public certificate and random pairing secret. It never carries a private key. Each Remote authenticates independently. Host owns queue revisions, native row bindings, authorization and command receipts. Remotes interpolate progress from a sampled monotonic timeline and share the Host's timed lyric document and English translation revision.

Host protects other Remotes' pending and current requests when cross-Remote editing is off. Pause/resume and volume are shared. Play next inserts a new request without replacing the current song. Never replay a mutation after reconnect: query its original command ID and durable receipt. The 1,000 ms contract is confirmed/rejected/expired/unconfirmed feedback, not a universal promise that Music or an internet download completes in that time.

## Product and UI preferences

These are explicit product preferences and acceptance criteria for Cadenza UI work:

- Cadenza should feel polished, expressive and intentional from the first onboarding screen onward. Do not ship raw form layouts, generic default-looking cards, unexplained dead space, arbitrary control placement or a phone layout stretched across a tablet. A small color change around an unchanged composition is not a sufficient polish pass.
- Use Material 3 Expressive as a design system, not just as a dependency. Make color, typography, shape, elevation, motion and spacing work together to establish hierarchy. Prefer a small number of strong surfaces with a clear primary action over a stack of equal-weight cards. Avoid eyebrow labels, all-caps kickers, filler subtitles, vague slogans and implementation copy that narrates obvious controls.
- Treat [BunPod](https://github.com/kamranbekirovyz/bunpod), [Rhythm's tablet references](https://github.com/cromaguy/Rhythm/tree/main/assets/ScreenShots/Tablet) and [Navic](https://github.com/ssalggnikool/Navic) as the visual quality bar for Remote. Use them as references for expressive media hierarchy, artwork-led playback, adaptive tablet composition and refined empty states. Do not copy their assets or branding; reproduce the underlying clarity and care in Cadenza's own visual language.
- For Android UI decisions, consult [Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3), [Material 3 foundations](https://m3.material.io/foundations), [media detail and playback](https://developer.android.com/design/ui/gallery/media/detail), [media discovery](https://developer.android.com/design/ui/gallery/media/discovery), and the [adaptive list-detail canonical layout](https://developer.android.com/develop/ui/compose/layouts/adaptive/canonical-layouts#list-detail). These references are design constraints for Remote, not optional inspiration after implementation.
- On large screens, use the canonical adaptive list-detail pattern deliberately. The queue or library is a supporting browsing pane and the Now Playing pane is an immersive media-detail surface. Give artwork, title, artist, playback progress and transport controls a clear reading order. Do not merely place the same phone column beside a list and call it tablet support.
- The tablet Now Playing transport is one balanced action group, ordered left to right as Lyrics, Previous, Play/Pause, Next and Favorite when lyrics are available. If lyrics are unavailable, omit Lyrics and keep the remaining controls centered. On compact screens, move Lyrics to the header when the five-control group cannot fit without crowding.
- Now Playing content is conditional: do not show the Now Playing surface when there is no current media. Do not show a Lyrics action when the current song has no lyrics. Lyrics use four levels: 0 no lyrics, 1 untimed lines, 2 timed lines, and 3 timed lines with per-word timing. In timed lyrics, inactive lines and words should recede visually through restrained blur/opacity while the active line remains legible; following the current line must work immediately without requiring a manual scroll first.
- Pairing and onboarding must make the next action obvious. Pairing is QR-only: do not expose a manual invitation-details field, paste flow or separate Pair button because the invitation is machine-readable and too long for humans to enter. Make the Host QR code prominent at tablet size, use a centered adaptive composition with a strong visual anchor, explain the local-network step in plain language, preserve the Remote name after errors, start pairing immediately when a valid QR code is recognized, and give scanning, pending and failure states clear feedback.
- Use clean, natural product copy and valid UTF-8. Never ship mojibake such as `Â·`, `â†’` or broken apostrophes in UI text, tests, screenshots or release notes.
- Debug and support UI should be useful to a real user: expose current-session CPU, memory, storage and recent errors, keep routine results in toasts, use accessible modal blockers for failures requiring a decision, and make diagnostic errors easy to copy without exposing secrets.
- UI work is incomplete without visual evidence. Capture fresh screenshots from the implementation after the final code change, use distinct evidence filenames when a prior screenshot could be confused with the new one, inspect the screenshots at tablet, phone, dark/light and large-text sizes as applicable, and compare the result against the stated visual references. Do not claim a UI is polished based only on compilation or a passing semantics test.

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

The newest released build and the current source are authoritative. Do not prioritize compatibility with obsolete builds, preserve dangling protocol branches, or keep legacy adapters and shims solely so an older build can connect. When an older build conflicts with the current protocol, state, security model, or product behavior, reject or break the older build and remove its obsolete path. Add backward compatibility only when the current release explicitly requires it and document the supported version boundary; never let legacy support constrain current design or implementation.

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

Android control sockets, discovery, status notifications and animation stop when the foreground control session ends. A standard ongoing notification follows meaningful session changes. Only explicit current-song monitoring may request a Live Update on an eligible OS, with an Unpin action. Huawei/Android may decline promotion; respect notification permissions and channel preferences. Never add a timer that redraws or writes SQLite for every progress frame. Host uses event hints plus bounded fallback observation; active requester analytics still require native time samples. Measure optimized, non-debug builds on the actual devices before claiming battery/CPU improvements. See [resource validation](docs/agents/RESOURCES.md).

## Local setup and checks

Windows work, toolchains, caches, temporary files and outputs belong under `D:/Dev`. Do not install Android Studio, an emulator, or large tools without the user's authorization. Android command-line tools and their build dependencies on D:/Dev are authorized. In Command Prompt, `call tools\windows-env.cmd` configures D:/Dev paths; PowerShell execution policy need not be changed. Always invoke the Gradle wrapper by its explicit path.

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

The visible application version is currently **0.0.2**. Do not bump it again unless the user explicitly requests a version change; do not infer a version bump from ordinary features or milestones. Keep the internal release build number increasing so the newest build is identifiable and preferred; do not use it as a reason to preserve obsolete build behavior. Android startup displays `Cadenza VERSION-PROFILE-SOURCE-YYYYMMDD.HHMMSS`; the timestamp is embedded at build time in UTC, and `source-` identifies an uncommitted source digest rather than a Git commit.

Profiles are `development`, `ci`, `production`. Defaults disable automatic update checks/downloads/installation. Android selects a release profile with `-Pcadenza.profile=...`; Host uses `CADENZA_BUILD_PROFILE`. Debug is always development. CI rejects Production profiles. Production Android needs the original private release keystore through environment variables; never commit signing material. Signing identity, manifest verification identity and installed data must survive upgrades.

Apps embed a version and immutable build ID. Packaged users need no Git checkout. Offline bundled changelogs are distinct from an explicit, read-only comparison with signed GitHub release metadata. Compare increasing build numbers and signed history; do not fabricate commit comparisons or newer notes when offline/unconfigured. Automatic update activity is isolated behind the Production gate, including scheduled jobs and installer entry points. See [release instructions](docs/agents/RELEASES.md).

Checking CI runs on pushes across branches and PRs. It intentionally includes compilation/typechecks and existing automated tests per the user's explicit exception to lightweight CI. Build CI accepts only a successful Checking **push on main in the same repository**, checks out its exact SHA and publishes CI APK/native app ZIP artifacts. It signs the CI APK with the release keystore secrets (`CADENZA_ANDROID_KEYSTORE_BASE64`, `CADENZA_ANDROID_KEYSTORE_PASSWORD`, `CADENZA_ANDROID_KEY_ALIAS`, `CADENZA_ANDROID_KEY_PASSWORD`), so CI APKs carry the release signing identity. It does not read the update-key secret. The ZIP already distributes `.app`; a DMG is not required. CI does not replace local validation or target-device/accessibility tests.

## Android and Compose guidance to consult selectively

Before an Android UI, Compose, media-layout, navigation, or performance change, INSTALL (the relevant skills) and read the relevant current upstream guidance and the exact skill references that govern the proposed edit:

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
