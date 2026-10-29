# Troubleshoot Cadenza

## Host cannot be reached

Confirm Host is running and Remote is on a reachable local network. Check the advertised address and port in Host settings.

Guest-network isolation, a second router, VPN routing, or a firewall can block access even when both devices have internet. Use a reachable private address and allow the Host's local connection when macOS asks.

Cadenza does not require SSH. SSH is used only for development access to the Host computer.

## Host identity changed

Do not replace the certificate check with an accept-all handler. Verify the Host in person and generate a new pairing invitation if its Keychain identity was intentionally replaced.

Normal app updates preserve the identity outside the app bundle. Revoking a Remote affects only that pairing.

## Music permission is unavailable

Open Music and check Host → Settings → Music permissions. Allow Automation and Accessibility in macOS privacy settings.

An ad-hoc app update may cause macOS to ask again because macOS authorizes Keychain access by the app's code-signing identity. Production Host archives must use the same stable Developer ID signing identity for every update; changing that identity cannot be fixed by pressing “Always Allow” in the app. A logged-out, sleeping, locked, minimized, or inaccessible Music session may prevent native UI actions.

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
