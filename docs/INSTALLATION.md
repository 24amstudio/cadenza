# Install Cadenza

The repository contains source and a locally built Android development APK. No stable Host/Remote release has been published. The development APK passes build, signature, and alignment checks; installation on the MatePad and real Music control remain unverified. To build a stable release, follow [BUILDING.md](BUILDING.md) and [RELEASES.md](RELEASES.md), including the remaining [validation gates](VALIDATION.md).

## Requirements

- MacBook Air M4 with macOS 27 is the initial target. The Host build targets Apple silicon and macOS 26 or newer.
- Huawei MatePad Mini with HarmonyOS 4.3 is the initial Remote target. The APK requires Android API 26 or newer; actual Huawei compatibility remains a device check.
- Both devices must be able to reach each other on the local network. Merely sharing an internet connection does not establish LAN connectivity.
- Music.app must be installed and signed in for Apple Music streaming. Your existing Apple Music subscription is used. Cadenza does not require paid Apple Developer membership.

Cadenza Remote does not play audio. Music continues to play on the Mac and through the Mac's selected output or AirPlay device.

## Install Host

1. Open your configured GitHub repository's Releases page.
2. Download `Cadenza-Host-VERSION-arm64.zip` from the chosen stable release.
3. Expand it and move `Cadenza Host.app` to `/Applications` or your user's `~/Applications` folder.
4. Open the app. For a personally signed, unnotarized build, macOS may require you to use Finder's Open action or approve it under System Settings → Privacy & Security. No paid signing certificate is required.
5. Open Music and make sure it can play a song.

Cadenza Host opens setup on first run. After setup it stays in the menu bar. Choose **Settings…** or reopen the app from Spotlight. Hiding the icon and closing Settings keep the service running; the Settings window includes a complete Quit action.

The Host must be running for Remote control. Music.app itself can continue playing if Host quits, but requests and observation gaps must be reconciled when Host returns.

## Install Remote

1. On the tablet, download `Cadenza-Remote-VERSION.apk` from the same GitHub release.
2. Open the APK in Files or your browser.
3. Approve installation from that source if HarmonyOS asks.
4. Open **Cadenza Remote**.

The app uses native Android APIs, Compose, Camera2, and Android Keystore. Core operation has no Google Play services dependency. Camera permission is optional: pairing details can be pasted instead.

Initial installation permission for your browser or Files app is separate from allowing future app updates from Cadenza Remote.

## Install the current development APK

When listed as built in [VALIDATION.md](VALIDATION.md), the local file is `F:\Development\cadenza\dist\Cadenza-Remote-0.0.1-dev.apk`, with a companion `.sha256` file. Copy it to the MatePad and open it in Files. Its preserved application ID is `app.cadence.remote.debug`, separately from stable and CI installs. Its updater is disabled. Updating a previously installed Cadence debug APK requires the same original debug keystore; do not uninstall or clear data if you want to retain it.

If the tablet is connected by USB with USB debugging enabled and its authorization prompt accepted, the already installed command-line tools can install it:

```bat
call tools\windows-env.cmd
"%ANDROID_HOME%\platform-tools\adb.exe" devices -l
"%ANDROID_HOME%\platform-tools\adb.exe" install -r "F:\Development\cadenza\dist\Cadenza-Remote-0.0.1-dev.apk"
```

Run these commands from the monorepo root. No tablet was attached during this build session; the install command has not been executed. Host must be built and running on the Mac before pairing can succeed.

## Continue setup

Follow [SETUP.md](SETUP.md) to grant Music permissions, choose the correct network address and storefront, and pair the tablet. Then use [USAGE.md](USAGE.md).
