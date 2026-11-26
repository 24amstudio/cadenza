# Troubleshoot Cadenza

If Sing causes Host to exit before it can return a command result, the bundled CadenzaWatchdog records `host.crash.detected` in `logs.sqlite` and relaunches Host. Recovery is bounded to three restarts in one minute; the marker is marked clean on a normal quit. Sing startup also records preparation and route-failure events so the watchdog row can be correlated with the last safe phase.

## Host cannot be reached

Confirm Host is running and Remote is on a reachable local network. Check the advertised address and port in Host settings.

Guest-network isolation, a second router, VPN routing, or a firewall can block access even when both devices have internet. Use a reachable private address and allow the Host's local connection when macOS asks.

Cadenza does not require SSH. SSH is used only for development access to the Host computer.

## Host identity changed

Cadenza uses no TLS and no certificate pinning. Remote and Host authenticate with the pairing secret and per-device tokens. If the Host's credential file was removed or the Host was reinstalled with a new identity, pair the Remote again from Host's Remotes page.

Normal app updates preserve the identity outside the app bundle. Revoking a Remote affects only that pairing.

## Music permission is unavailable

Open Music and check Host → Settings → Music permissions. Allow Automation and Accessibility in macOS privacy settings.

Host credentials are kept in an owner-only file, not the Keychain, so app updates do not trigger Keychain prompts. Builds before this change kept them in the Keychain. This build reads only its owner-only credential file, so updates do not prompt. A logged-out, sleeping, locked, minimized, or inaccessible Music session may prevent native UI actions.

## Catalog search fails

Verify internet access and the two-letter storefront. The public web-token catalog integration is undocumented and can change independently of Cadenza.

Use Host library search for local/library items. Catalog failure must not block pause/resume, volume, or other already available local controls.

## Queue action is blocked or unconfirmed

An ownership rejection leaves the queue unchanged. Check Host's cross-Remote setting and the requester shown beside the song.

An unconfirmed action may already have reached Music. Use Check status rather than submitting a fresh enqueue. Host retains the original command identity.

If actual native state cannot be matched safely, use Host's reconciliation UI. Keep Music's window and Playing Next panel available. Never treat a changed internal list as confirmation that Music accepted it.

## Lyrics are unavailable

Play the song and open Music's lyrics pane. Its cache may not contain a timed document yet, may omit a song, or may change format after an OS update.

Cadenza reads bounded local cache data first. If the LRCLIB fallback is enabled in Host settings, Host performs a bounded HTTPS lookup and labels the resulting source in Remote. If the provider is disabled or unavailable, the miss remains explicit.

For missing English text, prepare the source-to-English language pair in Host settings. Unsupported or undownloaded pairs are shown explicitly. Word timing is not promised by the current line-timed renderer.

## Analytics look lower than a track's full duration

Cadenza counts observed playing time. It excludes pauses, seeks, rejected requests, and intervals it could not observe.

Only the requesting Remote receives that song's credits. Reopen a disconnected Remote to apply its queued credits. Watching another person's lyrics does not count a personal play.

Do not reset or recreate SQLite to fix an event gap. The persisted acknowledgment cursor and occurrence records prevent duplicate counting.

## Update cannot install

Check the repository, release tag, public verification key, compatible build, package identity, and signature. Keep the existing installation when verification fails.

On Android, allow app installs from Cadenza Remote when requested, and complete any OS confirmation. A debug APK has a different identity from a signed release.

On macOS, run the installed Cadenza Host bundle from a writable Applications location. Resolve unconfirmed actions before restarting Host for an update.

## Developer scripts cannot run

If PowerShell blocks local scripts, use `tools\windows-env.cmd` and `apps\remote\build.cmd` from Command Prompt. Do not change system execution policy for Cadenza.

Missing SDKs and compilers are reported explicitly. Native verification cannot be replaced by the portable Node suite.

## Sing mode is unavailable

The vocal-separation model is not in the app bundle. Sing mode downloads it the first time you open it, so check the Host's network connection and free disk space, then open Sing mode again. Sing needs an Apple silicon Host and stereo output at Music's sample rate. Other routes show a failure.

## Music shows a dialog

When Music shows a sheet or dialog, such as a storefront or region prompt, Cadenza reports `music_modal_blocked` instead of a generic song-not-ready error. Dismiss the dialog in Music, then send the request again.

## Radio shows LIVE

Apple Music radio streams have no reliable length. Cadenza shows LIVE in place of times, turns seeking off, and skips lyric lookups for them. Radio does not count toward taste.

## Export diagnostic logs

Open Logs on Host and choose Export Diagnostic Logs. The mirrored log rotates through three generations of 2 MB each. A fatal crash leaves a record with the signal, time, and active track, and the next launch shows a crash banner. Three launches within thirty seconds enter safe recovery, which pauses automatic Music polling until you resume it from Logs. Crash backtraces are addresses in the stripped executable. Resolve them with `atos` and the dSYM that the build writes to `dist/`, matched by UUID.

## Cast devices are listed but play nothing

The output menu lists the Google Cast devices on your network. If Send audio here fails, the reason appears under the Cast heading. Check that the device is on the same network and awake, and that Music is playing on the Mac. Transmission has not yet been checked against a real Cast device in this build.

## A TV shows a PIN but never connects

Approve the PIN in Settings → Cadenza TV on the Mac, or on a paired Remote's output menu, before it expires. The code expires after five minutes, and the TV then asks for a new one. If the TV shows "Reconnecting to Cadenza", check that the TV can reach the Mac's address and web port, and that both are on the same network. The web port is the control port plus two.

## A TV is connected but has no sound

Browsers and TV apps block audio until someone presses a key or touches the screen. Press OK once. Then check that Settings → Cadenza TV lists the TV as playing, and that Music is playing on the Mac. A 5.1 track sends stereo when no AC-3 encoder is available, which is expected.

## Lyrics are early or late on a TV

Adjust the lip-sync offset on the TV with the up and down arrows, in 10 ms steps. Then compare the lyric change with the sound. See the lip-sync section in [docs/CAST.md](CAST.md).

## Lock screen and screen saver on Android

The lock-screen motion artwork and the charging screen saver have not been checked on a device, including Huawei HarmonyOS 4.3. Confirm both on your device before you rely on them.
