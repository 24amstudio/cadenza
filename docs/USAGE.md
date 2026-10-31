# Use Cadenza

## Home, Favorites and preferences

The Playing destination is the adaptive home. On an expanded window, the queue/Favorites list and selected song details appear together. On a compact window, **Queue and Favorites** opens the list; selecting an item opens its detail pane. Back navigation and switching destinations retain the selection and entered search state.

Choose **Save to Favorites** from Search song details or Now playing. **Favorites** belongs to this Remote's private SQLite library, with no Host synchronization. Select a saved song, prepare it in Music, then choose **Play now**, **Add to queue**, or **Play next**. Playback actions require a connected Host and verified native queue; Play next requires a capable Host. Unavailable tracks show an actionable failure without removing the Favorite. Local save/remove works offline. Current-song protection still applies to Play now.

Settings lets you edit the default Android device name and choose **Follow system**, **Light**, or **Dark**, then **Save preferences**. A name change reconnects to send the new name to a capable Host. The preferences persist after app restarts.

An active control action starts an ongoing session notification if notifications are allowed. While the Host is playing, the song is pinned automatically, and the notification stays connected while Cadenza Remote is backgrounded. Eligible Android versions may promote it to a Live Update or status chip. Devices without promotion use the standard notification. The screen stays on only on Now Playing and Lyrics while a song plays. If playback pauses while the app is in the background, the session ends and the notification is removed. The OS may stop background work if it terminates Cadenza Remote. No notification plays audio on the Remote.

## Search and request a song

On Remote, open Search and choose Apple Music or Host library. Enter a query and choose Search.

Select a result to prepare its exact song in Music on the Host. Once preparation finishes:

- **Add to queue** appends a distinct request.
- **Play now** starts it immediately when request protection and queue order allow.

Two requests for the same song remain separate queue occurrences. Retries use the original command identity; a timed-out request is not automatically sent again as a new enqueue.

Catalog search needs internet access and uses an isolated, undocumented public web-token integration. If Apple changes it, library search and local controls remain independent. Cadenza does not replace failed catalog search with incomplete store results.

Your search text and Apple Music/Host library selection remain when you visit another screen and return.

## Control playback

Playing shows the foreground song, requester, progress, available playback-quality observation, and transport controls.

Pause/resume and volume are shared. Skip, previous, seek, stop, and replacement of a protected request require ownership or Host permission. A lock explains why interruption controls are unavailable.

Audio always comes from Music.app on the Host. Remote includes no Android playback engine.

Buttons show pending state immediately. After one second, a request that lacks confirmation is shown as **unconfirmed**, rather than being called successful or canceled. Choose **Check status** to query its original outcome. This status request cannot replay the mutation.

An action already handed to Music may complete after the deadline. Host reads actual state and keeps uncertain actions available for reconciliation. LAN proximity does not impose a hard execution-time bound on another application or the OS.

## Read the queue

Queue shows song, artist, requesting Remote, duration, estimated wait, and total remaining time. Move-up and move-down buttons provide an alternative to dragging.

Estimates include the current song's remaining duration and every preceding finite request. They exclude unbounded AutoPlay recommendations and unobserved AutoMix overlap. Unknown duration produces an unknown downstream estimate.

When paused, the queue remains visible with paused status. External changes in Music must be reconciled before dependent edits are accepted.

## Sing along together

Open **Playing**, then select **Lyrics** on A and B. Both receive the same lyric document, occurrence, translation revision, and Host timeline. Select **Lyrics** again or use Android Back to return to the player.

On a supported Apple Silicon Host, open **Sing mode** from Playing to lower the lead vocal while Music continues playing. Production Host archives include the MIT Mel-RoFormer vocal-separation model (about 456 MB); development runs without the bundled resource download the pinned model into the Host cache on first use. Processing stays on Host and the Remote receives only Sing state and controls. Sing supports Music's stereo output sample rate and reports a clear failure when audio capture, model loading, or the output route is unavailable.

Each Remote renders highlighting locally. Pause, seek, replay, and song changes use the authoritative occurrence and position. Reconnecting midway requests the current document again. Stale synchronization is marked explicitly.

Scroll lyrics manually to stop automatic following. Select **Follow current line** to resume it. Playback controls remain available in Lyrics mode, subject to the Host's request protections.

Host checks its persistent lyric cache first, then Music's local TTML cache, then the optional LRCLIB provider. A successful provider result is stored on Host and labeled on Remote; both Remotes receive the same document revision. Missing machine translation does not delay the original timeline. After preparing a missing language pair, use **Reload lyrics** to retry it.

Line timing is supported for all parsed documents. When a provider supplies angle-bracket word timing, Remote highlights the active word as well; documents without verified word timing remain line-timed.

Translation is labeled as Apple-provided, machine-translated, or a combination. Missing lyrics or translation does not prevent playback controls.

## Read personal analytics

Your music ranks your requested songs by play count, then observed playing time.

- A play counts once after a distinct playback occurrence starts and progresses.
- A queued or rejected song does not count.
- Paused time and seek jumps are excluded.
- Watching B's lyrics does not add a play to A's history.
- Host holds undelivered credits while a Remote is disconnected. Remote updates aggregates and its acknowledgment cursor transactionally.

Analytics stay in each Remote's private SQLite database. They are not broadcast to other Remotes or uploaded to a cloud analytics service. Time that Host could not observe is excluded and reported as a gap.

## Update

Production builds check configured stable GitHub releases automatically and verify the signed manifest, package hash, identity, and version before installation. Development and CI builds disable checking/download/installation entry points and scheduled jobs.

On Host, Check for updates can stage a release; installation restarts the companion. Music remains the player.
A paired Remote can start the same check and install from Settings, under Cadenza Host, with Check for Host update and Update Host. The Host does not ask for confirmation for those requests, and any failure is reported on the Remote. macOS may still ask for Keychain access after an update if the new build is signed by a different certificate.

On Remote, Check for updates prepares an APK. Choose Install prepared update and grant install-source authorization if Android asks. Android or Huawei may require a confirmation; unattended installation is conditional on OS policy.

Normal updates preserve pairing, request ownership, SQLite state, and listening history. Re-pairing is different: it creates a new Remote identity, while previous requests keep their original attribution.

Settings shows the version, build profile and immutable Git/source identity. **Changes in this build** reads bundled offline notes. **Compare published changes** explicitly fetches signed metadata, compares release build numbers and lists the relevant signed history. It downloads no APK or app ZIP. A missing source, unavailable history, matching release number with a different identity, or offline failure is reported honestly.

## Recover an unresolved queue

On Host, open Settings → Reconcile native queue.

Match each native row to the saved request it represents. Leave genuine Host-originated items unassigned. A saved request cannot be assigned twice or assigned to a different song.

If a saved request is no longer present, explicitly select the option to cancel missing saved requests. Cadenza does not silently invent ownership after an ambiguous native change or restart.

After the Host applies verified assignments, choose **Check status** on an unconfirmed Remote request. A confirmed queue outcome is returned when available. If Host reviewed an action whose original outcome remains unknowable, Remote releases its pending control and keeps that uncertainty explicit; it does not replay the command.
