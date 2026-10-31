# Resource measurement

The current source uses no Android audio player, web runtime, persistent foreground service, or translation pack. The visible Now Playing and Lyrics screens request the window keep-awake flag while a song plays; leaving those screens or backgrounding the app releases it, so the display can time out again. Active background playback keeps the authenticated socket and bounded recovery alive for lock-screen metadata and notifications, and no manual pin is required. Session notifications compare title/artist/occurrence/playing/connection/pinned state and ignore progress ticks. Lyric/progress timers stop while paused/disconnected and when their visible screen lifecycle stops.

Host observes Music's distributed player event as an undocumented hint, backed by native readback. While playing it samples at roughly one second to preserve analytics/seek detection; paused with Remotes it checks at two seconds; paused without Remotes at ten seconds. Native commands perform their own readback. A paused unchanged snapshot uses a small authenticated heartbeat for capable Remotes; legacy Remotes still receive full snapshots. Broadcast JSON is encoded once per frame, rather than once per Remote. A notification hint does not prove a Music state change.

These are implementation changes, not measured CPU/battery savings. Windows JVM/render tests are not a substitute for Apple silicon or Huawei measurements. Numeric budgets remain unset until a target baseline exists.

## Target measurement procedure

Use a non-debug, optimized **CI-profile** APK (`:app:assembleRelease -Pcadenza.profile=ci`, with the release signing variables from [BUILDING.md](../BUILDING.md) set) so self-updates cannot affect results. Use an optimized Host development/CI app. Keep screen brightness, Wi-Fi signal, volume, Music content and charger state fixed. Record OS/build ID, installed size and sample duration. Run each state for five minutes after a one-minute warmup:

1. Host idle with Music paused and no Remotes; Remote app backgrounded.
2. Connected Remote foreground, paused, no input.
3. Music playing; perform the same scripted search/enqueue/pause/seek sequence.
4. Sing-along visible with two Remotes, then hidden.
5. Disconnect Wi-Fi for two minutes and restore it; repeat with the Host address changing.

On the Android device collect `adb shell dumpsys meminfo app.cadence.remote.ci`, `adb shell dumpsys batterystats app.cadence.remote.ci`, `adb shell dumpsys cpuinfo` and a Perfetto/system trace where firmware permits. Capture readings before/after without resetting device-wide statistics or changing system power settings unnecessarily. Inspect CPU wakeups, thread activity and socket traffic. Production and CI package suffixes differ; select the installed package explicitly. Do not run device-wide destructive resets as part of profiling.

On macOS use Activity Monitor or Instruments Time Profiler/Energy Log to inspect Cadenza Host and its `osascript` children. Include paused/minimized/locked and user-denied Automation cases. Record CPU median/p95, memory resident/peak, wakeups and bytes transferred. Separate Music.app resource use from Host cost. Confirm that event hints work on the supported macOS version and that fallback observations retain analytics accuracy; do not remove sampling solely to produce a lower idle number.

Report compressed and installed sizes for both final artifacts, CPU/memory per state, queue input-to-confirmation median/p95/p99/max/deadline misses and lyric transition differences. Include sample count, raw measurement method and failures. Set budgets against that measured baseline, then investigate regressions. At present target measurements are **not run**.
