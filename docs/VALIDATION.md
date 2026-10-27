# Cadenza validation

Cadenza 0.0.1 passes the local Windows Android and portable source gates. The goal is not complete: macOS compilation and target-device behavior remain unverified. No commit, push or published release has been created.

## Current local checks

On 27 October 2026, the Android checks passed after integrating Lyrics into Now Playing: strict compilation, ktlint, debug and release lint, and 46 tests per variant. The Compose checks cover entry and exit, Android Back, simulated keyboard focus restoration, restored mode, manual lyric scrolling, stale lyrics, request protection, compact and large-text layouts, and the accessible reconnecting-status icon. The resulting screenshots use synthetic data in Robolectric; target-device, TalkBack, and live Host behavior remain unverified.

On 26 October 2026, `node tools/check.mjs --portable` passed strict TS/JXA analysis, warnings-as-errors Oxlint, Prettier, 1,000-line limits, shell syntax, PowerShell parsing and all **26 portable behavioral tests**. They execute the real SQL policy/migrations/maintenance and owned Music JXA at its explicit native API boundary. Coverage includes protected current requests, Play next versus protected Play now, expiry/replay boundaries, protocol validation, queue waits and ordered analytics persistence. Both workflow files pass actionlint 1.7.12; root checks now require it.

`apps/remote/check.cmd` is the required native gate: strict Kotlin compilation for both variants, ktlint, Android lint and the full debug/release JVM suites. It passed, with both lint reports stating No issues found and all 38 tests passing in each variant (76 executions, 38 distinct tests). The intentional `OldTargetApi` advisory is disabled because current dependencies require compileSdk 37 while targetSdk remains 36; no other warning suppression is used. Tooling is JDK 17.0.20.1, Android platform 37.0, build-tools 36.0.0, Gradle 9.8.2, Android plugin 9.5.0-rc01, Kotlin 2.4.21 and Robolectric 4.17. See [BUILDING.md](BUILDING.md) for toolchain details.

The native suites include **38 behavioral tests per variant**: clocks, real Android SQLite transactions/upgrades, Favorites reopen/malformed-row recovery, preserved preferences/encrypted payloads, malformed cache recovery, device naming, endpoint rotation/expiry, signing/pin validation, signed changelog filtering, notification fallback/cleanup and non-Production update denial. Sixteen native Compose tests render the actual production UI and exercise pairing/focus, queue attribution/waits, navigation/selection retention, offline Favorites, editable names/themes, changelog/offline feedback, lifecycle/pause timer suspension and startup build-label placement.

The visible app version is fixed at 0.0.1 by user instruction; internal build 3 permits upgrading the earlier local build 2. Startup screenshots cover a light tablet and a 320dp dark phone at 200% text. Tests verify the complete build-label format, horizontal centering and bottom placement. The label uses an embedded UTC build timestamp and a short source digest until a committed Git build is available. Android's earlier system-managed icon splash is separate; Cadenza adds no timed hold to its local-state loading screen. Actual device launch behavior remains unverified.

UI tests register only a test hosting Activity in Robolectric because AGP omits dependency test Activities from its release resource APK. No test Activity is added to the Production manifest. They explicitly control the IO dispatcher for deterministic scheduling while executing real SQLite operations; production's Application-only ViewModel constructor retains Dispatchers.IO. The separate SQLite integration tests execute the same migration and storage code. Test dispatching does not prove real-device timing, thread contention or native networking. The reserved feedback region fixes a reproduced failure where a snackbar covered a scrolled button. The paused-ticker regression checks that no periodic redraw continues after playback pauses. A temporary negative control restored the old unconditional loop and failed (6→8 redraws); the correct conditional loop passed. The temporary defect was restored before final checks.

Captured images under `dist/evidence` are native Compose/Robolectric renders at Android API 31 with **synthetic data**. They include expanded/compact Favorites, dark preferences/changelog, queue/empty states, 320dp forms/queue timing at 200% text, cached quality/AutoMix state and supplied timed English lyrics. They are not target-device screenshots, Host playback proof, Music lyric extraction or Apple Translation execution. Target TalkBack/VoiceOver, complete keyboard journeys and contrast evaluation remain required; no WCAG conformance is claimed.

## Packaging and security

The local packaging outputs are `dist/Cadenza-Remote-0.0.1-dev.apk`, `dist/Cadenza-Remote-0.0.1-ci.apk` and `dist/Cadenza-Source-0.0.1.tar.gz`. Consult generated `dist/artifacts.json` for verified sizes, SHA-256 hashes and the embedded source identity after packaging. Dev and CI updates are disabled; neither is a Production release. The optimized CI APK has a separate `.ci` application ID and a disposable debug signer. Legacy `dist/Cadence-Remote-0.1.0-dev.apk` and `dist/Cadence-Source-0.1.0.tar.gz` remain local historical snapshots. The former is 14,074,987 bytes, package `app.cadence.remote.debug`, SHA-256 `595e8ae58bbf4cd97ace1de8e41852d3a61d4e172ddf461ca76f7f3243829715`. It is not the current Cadenza build or a Production baseline.

For the final dependency state, system Bun 1.4.4 audit reported no vulnerabilities in 30 development packages, and an OSV batch query returned no findings for 71 resolved native Maven coordinates. Ten XML/plist source files parsed; a scoped private-key/GitHub/AWS credential-pattern scan returned no matches. Query/results are under `.cache/security`. These narrow scans do not prove absence of all vulnerabilities or credentials. Browser CSP/cookie-CSRF checks are inapplicable to these native apps: Host serves no HTML and uses no browser cookies. Native/transport/storage security tests remain applicable. Pattern/database/unit checks do not establish a complete security audit.

An earlier Windows external-boundary probe mirrored Catalog.swift's discovery/token-selection URLs and successfully searched Apple's public catalog without Apple account credentials or paid developer keys. Its sanitized metadata is under `.cache/catalog-probe-result.json`. This does not execute the Swift actor or prove catalog playback/native queue control. The web-token adapter remains undocumented and changeable.

## External validation still needed

The development Host endpoint still is not reachable from this Windows workspace. Swift compilation, strict Swift formatting, native database/protocol/TTML/release/archive tests, MusicKit storefront detection, onboarding/background/menu behavior, Automation/Accessibility/Local Network grants, actual Music queue/cache/translation, AutoMix/quality and the ad-hoc updater have not run. The source and packaging scripts are prepared; a reachable macOS system remains necessary. The platform-aware root gate can validate Windows portable and Remote checks while reporting Host as deferred; CI still requires the separate Host job.

No target Android device is attached to ADB. APK installation, vendor notification behavior, actual IPv4 discovery/failover, camera scanning, independent multi-Remote latency/lyrics timing and OS package-install confirmation remain unverified. No Android Studio or emulator was installed. Hardware idle/connected/control/disconnected CPU, memory, wakeup, network and battery measurements remain pending; [RESOURCES.md](RESOURCES.md) defines the procedure, with no invented budgets or savings.

Checking and Build CI are configured and locally linted, but have not run on GitHub. There is no configured repository URL, public verification key, stable signing identity or published baseline. Build checks exact successful Checking/main/push/same-repository SHA and produces CI profiles with updates disabled. No source publication or Production secrets are used by these workflows.

## Required gates

| Area                           | Required evidence                                                                                                                                                | Environment                                              |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Portable contracts and storage | Strict script typecheck, lint with warnings denied, formatting, file caps, real SQL/JXA behavior tests, dependency and scoped secret scans                       | Existing Windows tools; caches and temporary files on F: |
| Host source                    | Swift 6.2 strict compilation, native format/lint, unit tests, signed bundle build                                                                                | macOS with existing or explicitly installed toolchain    |
| Remote source                  | Kotlin warnings as errors, ktlint, Android lint, unit tests, signed APK build                                                                                    | JDK 17 and Android SDK platform android-37.0             |
| Pairing                        | A and B paired concurrently, wrong invitation/pin/token rejected, expiry/revocation, reconnect without replay                                                    | Host system and two Remotes                              |
| Queue                          | Exact selected versions, duplicate occurrences, FIFO concurrency, off/on ownership, seek/Play Now bypass negatives, actual native readback, direct Music changes | Target Music.app                                         |
| Lyrics                         | Same revision and line on both Remotes; pause/seek/replay/rejoin; source labels; missing cache/model behavior                                                    | Host system and target Android devices                   |
| Analytics                      | Correct requester, measured playing time, no seek/pause inflation, ordered exactly-once delivery after crash/reconnect/update                                    | Native apps and real SQLite                              |
| Updates                        | First signed baseline, authentic upgrade, invalid signature/hash/identity/downgrade rejection, interruption recovery, OS confirmation                            | Installed previous Host/APK release                      |
| Accessibility                  | VoiceOver/TalkBack, keyboard, focus entry/restoration, contrast, large text, orientation, reduced motion, visible action feedback                                | Actual native interfaces                                 |
| Performance                    | Input-to-confirmation sample count, median/p95/p99/max/misses; inter-Remote lyric timing; idle/active CPU, memory, traffic, release and installed size           | Declared healthy LAN and targets                         |

## Platform tests after source completion

Start with the read-only Music probe, permission checks, and an accessibility-tree inspection. Then verify exact native queue selection and readback before enabling normal queue controls.

Use synthetic data for storage/security tests. Do not destructively test a user's library or existing queue. Any real playback-control test must preserve and restore the inspected native state.

Capture actual running Host and Remote screenshots in relevant themes and sizes. A proposed HTML layout is not evidence of working native software.

## Release status

Complete Host/Remote integration, stable signing identities, GitHub release configuration, actual update installation, target accessibility and measured performance remain outstanding. No commit, push, merge or stable release may bypass the final local gates.
