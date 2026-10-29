# Create a GitHub release

No repository, release, production signing identity, or first installable baseline has been published by this task. The updater requires an explicitly configured public GitHub repository; `shared/release-config.json` is intentionally unconfigured and private-repository authentication is not implemented.

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

## Configure automatic Build CI publishing

The `Build` workflow runs after a successful static `Checking` push to `main`. It repeats those checks, builds both apps with the `production` profile, signs the release metadata, and creates a unique stable release for every checked revision. Each CI job has a six-minute limit. CI derives a release version such as `0.0.3_20261029.1001-eb751fa0730d` from the checked-in semantic version, the Checking run number, the UTC commit date, and the commit hash. The GitHub title is shown as `Cadenza 0.0.3_20261029.1001 (eb751fa0730d)`. No manual version bump or tag is required for ordinary builds.

Generate the Android release keystore on a trusted machine with JDK `keytool`; never use the disposable debug keystore:

```bash
mkdir -p secrets
keytool -genkeypair -v -keystore secrets/cadenza-release.jks -storetype JKS \
  -alias cadenza-release -keyalg RSA -keysize 4096 -validity 10000
base64 -i secrets/cadenza-release.jks | tr -d '\n' > secrets/cadenza-release.jks.base64
```

On PowerShell, encode it with:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('secrets/cadenza-release.jks')) |
  Set-Content -NoNewline secrets/cadenza-release.jks.base64
```

Generate the P-256 update key with the native release utility on macOS:

```bash
cd apps/host
swift build -c release --arch arm64 -Xswiftc -warnings-as-errors
binary_root="$(swift build -c release --arch arm64 --show-bin-path)"
"$binary_root/CadenzaRelease" keygen ../../secrets/update-private.pem
```

The command prints the public SPKI key as base64. Put that public value in `shared/release-config.json` together with `OWNER/REPOSITORY`, then add these repository Actions secrets under **Settings → Secrets and variables → Actions**:

| Secret                              | Value                                                              |
| ----------------------------------- | ------------------------------------------------------------------ |
| `CADENZA_ANDROID_KEYSTORE_BASE64`   | Contents of `cadenza-release.jks.base64`                           |
| `CADENZA_ANDROID_KEYSTORE_PASSWORD` | Keystore password entered for `keytool`                            |
| `CADENZA_ANDROID_KEY_ALIAS`         | `cadenza-release` (or the alias you chose)                         |
| `CADENZA_ANDROID_KEY_PASSWORD`      | Private-key password entered for `keytool`                         |
| `CADENZA_UPDATE_PRIVATE_PEM`        | Complete `update-private.pem`, including its PEM header and footer |

Do not upload a `.env`, keystore, private PEM, or base64 export to the repository. The workflow writes the secrets only to temporary runner files and removes them with the runner. `GITHUB_TOKEN` is provided by Actions; no separate token secret is needed.

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

1. Change `VERSION_NAME` only when the user explicitly authorizes another product version. Ordinary CI builds leave `shared/version.properties` unchanged; CI supplies a strictly increasing Checking run number as the build code and derives the unique release version automatically.
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

After the repository configuration and Actions secrets are present, the `Build` workflow publishes the four signed files to a unique stable `vVERSION_DATE.RUN-SHA` release automatically. Draft and prerelease builds are excluded from automatic installation.

## Verify updates

Test a real upgrade from the previous signed installation on both targets. Exercise invalid signatures, hash mismatch, wrong application identity, older build numbers, interrupted download/install, required OS confirmation, retained pairing and analytics, and a Host restart while Music plays.

Ad-hoc macOS updates may require privacy-permission reauthorization. Huawei may require an install confirmation. Neither platform is promised permanently silent installation.

Run the complete local gates before publishing. Checking runs on branches/PRs, and Build follows only successful same-repository `main` push checks for the exact SHA. Build uses Production signing secrets and publishes the signed APK, Host ZIP, release manifest, and detached signature. Real device, accessibility, security and resource verification remain local acceptance requirements. No DMG is required because the updater distributes a verified ZIP containing the native `.app`.
