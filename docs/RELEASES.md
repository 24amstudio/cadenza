# Create a GitHub release

No repository, release, production signing identity, or first installable baseline has been published by this task. A public GitHub Releases repository is the current updater source; private-repository authentication is not implemented.

## Establish the signing identities

Keep the Android APK signing identity stable. A new unrelated key cannot update an existing installation.

Cadenza also signs release metadata with a P-256 key. This authenticates both the Host archive and APK independently of GitHub checksums. It does not require paid Apple Developer membership.

On macOS, build the release utility:

```bash
cd apps/host
swift build -c release --arch arm64 -Xswiftc -warnings-as-errors
binary_root="$(swift build -c release --arch arm64 --show-bin-path)"
"$binary_root/CadenzaRelease" keygen ../../secrets/update-private.pem
```

The utility creates a new private key with mode 600 and prints only the public SPKI key as base64. It refuses to overwrite an existing key.

Back up the private update key and APK keystore securely before publishing a baseline. Keep them out of commits, app bundles, logs, and release assets.

## Configure the apps

Edit `shared/release-config.json`:

```json
{
  "repository": "OWNER/REPOSITORY",
  "public_key_spki_base64": "PUBLIC_KEY_PRINTED_BY_THE_RELEASE_TOOL"
}
```

This file contains public configuration. Both native builds include it. Host settings can configure an initial source, and paired Remotes receive it through their trusted local connection.

## Build the release

1. Keep `VERSION_NAME=0.0.1` until the user explicitly authorizes another version. Set a strictly increasing `VERSION_CODE` in `shared/version.properties` for a new release build.
2. Run all required local portable and native checks.
3. Build both apps with the explicit `production` profile, from identical source, using the preserved signing identities. Development and CI profiles cannot self-update.
4. Put both versioned artifacts in `dist`.
5. Sign the exact bytes:

```bash
bash tools/sign-release.sh OWNER/REPOSITORY /private/path/update-private.pem
```

This creates:

- `Cadenza-Host-VERSION-arm64.zip`
- `Cadenza-Remote-VERSION.apk`
- `cadenza-release.json`
- `cadenza-release.sig`

The manifest binds repository, tag, app build, immutable source ID, maintained changelog history, protocol major, platform, minimum OS, filename, size, and SHA-256. Keep `shared/changelog.json` current for every release, retaining earlier entries needed for comparisons. The signing script checks the Host's embedded Production profile and the APK's manifest profile/package, plus both embedded source identities. Set `ANDROID_HOME` to the checked SDK so its `apkanalyzer` is available. It refuses mismatched or non-Production inputs. The detached signature covers the exact manifest bytes. Do not edit it after signing.

## Publish after validation

Use a GitHub stable release tagged `vVERSION` and upload all four files. The tag must match the signed manifest. Draft and prerelease builds are excluded from automatic installation.

Creating a draft for review can be done with GitHub CLI after the final checks and the repository choice are complete:

```bash
gh release create vVERSION --repo OWNER/REPOSITORY --draft --title "Cadenza VERSION" --notes-file release-notes.md dist/Cadenza-Host-VERSION-arm64.zip dist/Cadenza-Remote-VERSION.apk dist/cadenza-release.json dist/cadenza-release.sig
```

Publishing is a separate action. The implementation scripts do not upload anything automatically.

## Verify updates

Test a real upgrade from the previous signed installation on both targets. Exercise invalid signatures, hash mismatch, wrong application identity, older build numbers, interrupted download/install, required OS confirmation, retained pairing and analytics, and a Host restart while Music plays.

Ad-hoc macOS updates may require privacy-permission reauthorization. Huawei may require an install confirmation. Neither platform is promised permanently silent installation.

Run the complete local gates before publishing. The implementation goalset explicitly authorizes compilation/typechecks and build CI: Checking runs on branches/PRs, and Build follows only successful same-repository `main` push checks for the exact SHA. Its artifacts are CI profiles with automatic updates disabled and no Production signing secrets. Real device, accessibility, security and resource verification remain local acceptance requirements. No DMG is required because the updater distributes a verified ZIP containing the native `.app`.
