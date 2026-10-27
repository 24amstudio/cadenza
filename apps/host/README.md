# Cadenza Host

The native macOS companion uses Swift 6, SwiftUI, AppKit, Network.framework, Accessibility, Translation, Keychain, and the system SQLite library. It controls the existing Music.app and serves multiple independently paired Cadenza Remotes. Audio remains on the Host computer.

Application, local TLS/WebSocket service, command journal, native queue adapter, lyric distribution, signed updater, packaging, and unit-test source is implemented. Native compilation and device validation remain pending. No installable release has been verified or published.

## Build and use

See [building](../../docs/BUILDING.md), [setup](../../docs/SETUP.md), [usage](../../docs/USAGE.md), and [validation](../../docs/VALIDATION.md). From the monorepo root on a supported Apple silicon macOS system with a compatible existing toolchain, use the check and build scripts under Scripts.

The package has no external Swift dependency. CadenzaSecurity provides release verification and safe archive inspection; CadenzaUpdater installs a staged update; CadenzaRelease creates signing identities and signed metadata. Paid Apple Developer membership is not required by this design. Its ad-hoc update and privacy-permission behavior needs an actual target-system test.

Transport and library metadata use the fixed owned JXA resource. Native queue effects use Accessibility with bounded reads, exact selected-song matching, durable intents, and native readback. Catalog search and lyric-cache integration are isolated undocumented adapters. Their exact macOS 27 behavior must be tested before support is claimed.

Host stores pairing references, policy, attributed requests, receipts, playback sessions, and credit delivery in SQLite outside the app bundle. Credentials and TLS identity material stay in Keychain. Database maintenance preserves unacknowledged credits and live requests.

## Read-only Music probe

On macOS, from this repository's root:

```bash
bash apps/host/tools/music-probe.sh status
bash apps/host/tools/music-probe.sh dictionary > /tmp/cadenza-music-dictionary.xml
bash apps/host/tools/music-probe.sh cache
bash apps/host/tools/music-probe.sh lyrics 123456789 > /tmp/cadenza-lyrics.ttml
```

Replace the example song ID with one printed by `cache`. Open Music's lyrics pane and play that song before scanning. This diagnostic uses built-in Bash, AppleScript, `sdef`, `plutil`, and filesystem tools. It does not install software, change playback, access the network, or start Music when Music is closed. macOS may ask for Automation access for the status read.

- `status` reads playback state, position, and basic track metadata. Its output is a human diagnostic, not a protocol snapshot or proof of catalog identity.
- `dictionary` prints the installed Music.app scripting dictionary for inspection. It does not prove every declared operation works on streaming tracks.
- `cache` lists song IDs and titles whose first cached record mentions lyric data. It does not print lyric text.
- `lyrics` attempts to print the matching first-record TTML, preferring syllable lyrics over line lyrics. The diagnostic does not parse timings or translations yet.

The cache path follows this [existing cache-reader investigation](https://github.com/Yudaotor/lyrimuse/blob/35792d674f3dce7f55e5a00baba4fca6bf8a6715/lyrimuse-engine/applemusiclocal.go). It is undocumented Music.app storage. Cadenza's probe examines at most 512 regular files, 4 MiB per file, and 32 MiB per scan, skips symbolic links, and only examines the first song/relationship record. Files must be JSON readable by `plutil`; trailing padding or another cache format may be missed. It does not order candidates by freshness or reconcile multiple versions. A miss is inconclusive, and an extracted file still needs song identity and safe TTML validation before use.

Exit codes are `0` for a completed status/dictionary/cache operation or found lyrics, `2` for invalid usage or a non-macOS host, and `3` for missing/unreadable cache or no match. System tool failures can return their own nonzero status. Diagnostic outputs may include your music choices or lyrics; keep them local.

Only Bash syntax and the non-Mac refusal have been checked on the Windows development machine. AppleScript compilation, macOS 27 permissions, and actual cache extraction remain unverified. Native queue mutation, AutoMix observations, live quality badges, and no-fee app updates require separate target-device checks.
