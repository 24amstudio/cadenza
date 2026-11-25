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

Catalog search also lists music videos after the songs, labelled "Music video". Play now opens a video in Music's own window, and the video never joins Music's queue. Add to queue and Play next stay disabled for videos.

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

On a supported Apple Silicon Host, open **Sing mode** from Playing to lower the lead vocal while Music continues playing. The Host downloads the pinned MIT Mel-RoFormer vocal-separation model (about 456 MB) into its cache the first time you open Sing mode. Processing stays on Host and the Remote receives only Sing state and controls. Sing supports Music's stereo output sample rate and reports a clear failure when audio capture, model loading, or the output route is unavailable.

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
A paired Remote can start the same check and install from Settings, under Cadenza Host, with Check for Host update and Update Host. The Host does not ask for confirmation for those requests, and any failure is reported on the Remote. Updates do not ask for Keychain access. Ad-hoc builds may still need macOS privacy approvals granted again.

On Remote, Check for updates prepares an APK. Choose Install prepared update and grant install-source authorization if Android asks. Android or Huawei may require a confirmation; unattended installation is conditional on OS policy.

Normal updates preserve pairing, request ownership, SQLite state, and listening history. Re-pairing is different: it creates a new Remote identity, while previous requests keep their original attribution.

Settings shows the version, build profile and immutable Git/source identity. **Changes in this build** reads bundled offline notes. **Compare published changes** explicitly fetches signed metadata, compares release build numbers and lists the relevant signed history. It downloads no APK or app ZIP. A missing source, unavailable history, matching release number with a different identity, or offline failure is reported honestly.

## Recover an unresolved queue

On Host, open Settings → Reconcile native queue.

Match each native row to the saved request it represents. Leave genuine Host-originated items unassigned. A saved request cannot be assigned twice or assigned to a different song.

If a saved request is no longer present, explicitly select the option to cancel missing saved requests. Cadenza does not silently invent ownership after an ambiguous native change or restart.

After the Host applies verified assignments, choose **Check status** on an unconfirmed Remote request. A confirmed queue outcome is returned when available. If Host reviewed an action whose original outcome remains unknowable, Remote releases its pending control and keeps that uncertainty explicit; it does not replay the command.

## Radio, outputs, and library actions

Radio streams show LIVE in place of a time, and seeking is off. The playing screen lists the Mac's audio outputs. Choosing one changes the Mac's default output, which Music plays through. The output menu also lists the Google Cast devices found on your network and the presentation mode set in the Mac's Settings. Sending audio to a Cast device is described under Google Cast below.

**Favorite in Music** sets Music's favorite flag for a library song. **Add to Host playlist** adds it to a Cadenza Host playlist and creates that playlist when it is missing. Both are receipted commands. They have not been run against a live Music session.

Opening an Apple Music song link on Android, or sharing one to Cadenza Remote, offers Play now, Play next, and Add to queue. Album and playlist links are explained but not played.

The web Remote adds OLED ambient mode, a black screen that drifts every 45 seconds, and operating-system media keys for playback.

When the search is empty, the web Remote shows "For You" and "Room Blend" suggestions. The Host ranks them from this Remote's listening history, and Room Blend holds the songs every connected Remote shares. Each song has Play next and Add buttons. The list is read-only until you choose one.

On an artist page, the web and Android Remotes can show a muted, looping motion video when Apple has one for that artist. On the web it sits behind the artist's name. On Android it fills a 16:9 band above the name. The Host fetches the video, so neither Remote contacts Apple's motion service. The Host sends a 256-pixel square rendition that is cropped to fill the space, so it has less detail than a wide header would. Over Bluetooth, under thermal pressure, or with reduced motion, the page shows its artwork instead. On Android, energy saver does the same.

On Android, the volume buttons change Music's volume on Host in 5 percent steps when the Settings switch is on. The session notification clears itself after five minutes of pause or lost connection.

Timed lyrics on the web Remote have a timing nudge. Each press of -0.5 s or +0.5 s moves the lyrics, and Sync First Line sets the timing from the first line you hear. The nudge applies to the current song only and is not saved to Host yet. Tapping a line seeks to that line's time with the nudge applied.

The web and Android output menus list the Google Cast devices on your network. On the web, Send audio here plays Music's stereo output on that device through Google's default media receiver, and Stop sending audio ends it. On Android, choose a device chip to start sending, and choose the same chip again to stop. The status line under the Cast heading shows what is happening, including a failure reason. Neither client has been checked against a real Cast device. Six-channel output is sent as AC-3 through a bundled helper, which is verified to encode but not yet checked against a Cast device. Karaoke on a Cast device needs a registered custom receiver, and Full Cadenza Suite artwork is not built. An Android Remote can share its taste at connect when its Settings switch is on, and the Host uses that history when it ranks suggestions.

## Android widget, lock screen, and screen saver

The home-screen widget shows what the Host is playing. The Host's state is pushed to it, so the widget does not poll on its own.

The motion lock screen shows full-screen motion artwork over the keyguard for a playing track that has motion artwork. It closes on unlock, on pause, or when the Host is lost.

The charging screen saver runs only while the phone is charging and connected to the Host.

None of the three has been checked on a device, including Huawei HarmonyOS 4.3. See [Troubleshooting](TROUBLESHOOTING.md).
