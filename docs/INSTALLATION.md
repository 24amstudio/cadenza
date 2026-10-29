# Install Cadenza

This repository contains source, not packaged application installers. Download a release from the configured GitHub Releases page, or follow [BUILDING.md](BUILDING.md) to build one locally.

## Requirements

- A supported Apple silicon Mac running macOS 26 or newer is required for Cadenza Host.
- A supported Android device running Android 12 / API 31 or newer is required for Cadenza Remote. Vendor compatibility remains a device check.
- Both devices must be able to reach each other on the local network. Merely sharing an internet connection does not establish LAN connectivity.
- Music.app must be installed and signed in for Apple Music streaming. Your existing Apple Music subscription is used. Cadenza does not require paid Apple Developer membership.

Cadenza Remote does not play audio. Music continues to play on the Cadenza Host and through its selected output or AirPlay device.

## Install Host

1. Open your configured GitHub repository's Releases page.
2. Download `Cadenza-Host-VERSION-arm64.zip` from the chosen stable release.
3. Expand it and move `Cadenza Host.app` to `/Applications` or your user's `~/Applications` folder.
4. Open the app. For a personally signed, unnotarized build, macOS may require you to use Finder's Open action or approve it under System Settings → Privacy & Security. No paid signing certificate is required.
5. Open Music and make sure it can play a song.

Cadenza Host opens setup on first run. After setup it stays in the menu bar. Choose **Settings…** or reopen the app from Spotlight. Hiding the icon and closing Settings keep the service running; the Settings window includes a complete Quit action.

The Host must be running for Remote control. Music.app itself can continue playing if Host quits, but requests and observation gaps must be reconciled when Host returns.

## Install Remote

1. On the Android device, download `Cadenza-Remote-VERSION.apk` from the same GitHub release.
2. Open the APK in Files or your browser.
3. Approve installation from that source if Android asks.
4. Open **Cadenza Remote**.

The app uses native Android APIs, Compose, Camera2, and Android Keystore. Core operation has no Google Play services dependency. Camera permission is optional: pairing details can be pasted instead.

Initial installation permission for your browser or Files app is separate from allowing future app updates from Cadenza Remote.

## Install the current development APK

After a development APK is built, copy it to the Android device and open it in Files. Its preserved application ID is `app.cadence.remote.debug`, separately from stable and CI installs. Its updater is disabled. Updating a previously installed debug APK requires the same original debug keystore; do not uninstall or clear data if you want to retain it.

If the Android device is connected by USB with USB debugging enabled and its authorization prompt accepted, Android command-line tools can install it:

```bat
call tools\windows-env.cmd
"%ANDROID_HOME%\platform-tools\adb.exe" devices -l
"%ANDROID_HOME%\platform-tools\adb.exe" install -r "<path-to-built-development-apk>"
```

Run these commands from the monorepo root. The current workspace has no ADB session, so the install command has not been independently executed here. Host must be built and running before pairing can succeed.

## Continue setup

Follow [SETUP.md](SETUP.md) to grant Music permissions, choose the correct network address and storefront, and pair a Remote. Then use [USAGE.md](USAGE.md).
