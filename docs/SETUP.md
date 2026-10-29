# Set up Cadenza

## First run

Host opens a sequential setup window. Choose **Get started**, then **Detect Apple Music storefront**. The supported MusicKit lookup uses the signed-in music account and can ask for Apple Music access. If authorization, account information or entitlement support is unavailable in the no-fee build, or detection times out, choose your subscription's country/region manually. Cadenza does not treat the Host computer's locale or App Store region as proof of an Apple Music storefront.

Continue to the permission explanation, approve and verify Music Automation and Accessibility, then continue to pairing. Local Network permission can appear as the listener starts. Scan the invitation in Remote and keep it connected; **Finish setup** is enabled only after Host sees an authenticated connection. Setup completion persists and the window closes while Host keeps running.

Reopen **Cadenza Host** from Spotlight or choose **Settings…** from its menu-bar menu to configure it. Closing Settings leaves Host running. **Show menu bar icon** can hide the icon; Spotlight still opens Settings and its **Quit Cadenza Host** action. **Run setup again** provides setup recovery. Permissions revoked later must be reapproved in macOS Settings.

## Prepare Music on the Host

Open Cadenza Host → Settings.

1. Choose **Check Music Automation** and allow Cadenza to control Music when macOS asks.
2. Choose **Allow Accessibility** and enable Cadenza Host under System Settings → Privacy & Security → Accessibility.
3. Allow local-network access if macOS asks.
4. Keep Music's normal window open. The native queue adapter uses Music's accessible interface; a closed, minimized, locked, or changed interface can make queue operations unavailable.

The current native queue adapter uses English Music interface labels. Its exact behavior on macOS 27 must be established during target-device validation. It never substitutes a companion playlist for Music's real queue.

## Configure Host

In Settings → Network:

- **Host name** is shown to Remotes and must fit Bonjour's 63-byte service-name limit.
- **Port** defaults to `43127`.
- **Catalog storefront** is the two-letter Apple Music region, such as `id`, `us`, `gb`, or `jp`. Use your Apple Music account's region.
- **Address shown in pairing** must be reachable from the Remote. Select the correct local interface when Automatic chooses a VPN, disconnected, or otherwise unreachable address.

Choose **Save settings**. Connected Remotes reconnect after a network-setting change.

Wi-Fi client isolation, guest networks, firewalls, separate router subnets, and VPN routing can prevent devices from reaching each other. SSH is a development tool, not a Cadenza runtime requirement; Cadenza uses its own local TLS connection.

## Pair a Remote

1. On Host, open Remotes and choose **Pair a Remote**.
2. On the Remote, enter a name that will appear beside your requests.
3. Scan the QR code. Alternatively, choose **Copy pairing details** on Host, transfer that text privately, and paste it into Remote.
4. Choose **Pair**.

Each invitation expires after five minutes and can pair one Remote. Generate another invitation to pair Remote B; Remote A keeps its connection and identity. Device credentials are distinct and stored in Cadenza Host's Keychain and Android Keystore-backed storage.

Discovery helps locate Host; the QR supplies its public certificate and fingerprint to establish trust. A changed Host identity requires verification and pairing again. No private certificate key is transferred.

The Android 12 / API 31 baseline uses the normal `INTERNET` permission for the LAN connection. This build targets Android 16 / API 36, so it does not request Android 17's `ACCESS_LOCAL_NETWORK` permission. Vendor Android versions may apply their own network restrictions; verify the target device during installation.

## Set request permissions

Host → Remotes → **Allow Remotes to change others' requests** controls cross-Remote edits.

With the switch off:

- A Remote can add requests and edit its own pending requests.
- It cannot jump across someone else's request, remove it, or interrupt their current song.
- Skip, previous, seek-to-end, stop, and Play Now cannot bypass that protection.
- Pause/resume and volume are shared.

The switch defaults off and persists in SQLite. Local Host controls retain authority. Host-originated items are labeled Cadenza Host and are not assigned to a Remote by guessing.

## Prepare lyrics and English translation

Cadenza first reads Music's own locally cached timed lyrics. When Music has no matching document, Host can use the optional LRCLIB fallback over HTTPS. The Host stores successful results and Remotes receive them from Host, so Remote devices do not contact the provider.

The Host can switch Music's lyrics and Playing Next panels while preparing and verifying data. These are Music.app UI operations and depend on the installed Music version.

For machine translation, open Host → Settings → English translation:

1. Enter the source language code, such as `ja`, `ko`, `id`, or `fr`.
2. Choose **Prepare English translation**.
3. Approve the OS language-model download if needed.

Apple-supplied English text is preferred. When a model is installed, fallback translation runs on Cadenza Host and the same result is sent to every Remote. No Android language pack or paid translation service is needed. Missing or unsupported language pairs are shown explicitly.

## Configure update releases

The first release must embed your repository and public signing key in [shared/release-config.json](../shared/release-config.json), or you must enter them in Host → Settings → GitHub Releases and save.

Reconnect Remotes to receive that configuration. A Remote does not silently accept a replacement verification identity.

Automatic checking, staging and installation run only in explicitly selected **Production** builds. Development and CI builds do not start them. Both apps can show bundled offline changes or perform an explicit read-only comparison with signed release notes; an empty configuration or offline failure never means newer releases were successfully checked.

For release packaging and signing, follow the release sections in [BUILDING.md](BUILDING.md). Keep the APK signing identity and update-signing key for all later releases.
