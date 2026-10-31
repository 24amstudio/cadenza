# Build Cadenza from source

This guide covers the toolchains, checks, and packaging steps for building Cadenza from source.

## Toolchain requirements

Host needs a supported Apple silicon Mac, macOS 26+, Swift 6.2+, and the macOS SDK supplied by compatible Apple command-line tools or Xcode. No paid Apple Developer membership is required.

Remote needs JDK 17, Android SDK platform `android-37.0`, build-tools 36.0.0, and Gradle 9.8.2 with Android Gradle Plugin 9.5.0-rc01. The checked-in wrapper pins and verifies Gradle's distribution. `compileSdk` is 37, `targetSdk` is 36, and the installation floor is Android 12 / API 31. Android Studio and an emulator are not required.

The Android plugin is a release candidate. Plugin 9.4.1 calls a deprecated Gradle API that fails the strict build on Gradle 9.8.2; older Gradle versions fail the current Android lint update check. The release candidate removes those deprecated calls. Warnings remain errors. The only disabled lint advisory is `OldTargetApi`, because current dependencies require compileSdk 37 while the requested runtime target remains 36; no lint baseline or other warning suppression is used.

Temurin JDK 17, Android command-line tools, SDK components, Gradle, and build dependencies can be installed under D:/Dev. Verify downloaded archives against the checksums published by their upstream projects. Android Studio and an emulator are optional; release users install the app packages without these build tools.

## Windows storage on D:/Dev

Open Command Prompt in `D:\Dev`:

```bat
call tools\windows-env.cmd
```

This keeps temporary files, Bun's package cache, Gradle distributions, Android user state, and the SDK under the repository on D:/Dev. Existing executables may remain on C:.

PowerShell users whose script policy permits local scripts can use:

```powershell
. .\tools\windows-env.ps1
```

If PowerShell blocks it, use the Command Prompt version. Changing execution policy is unnecessary.

Place a chosen JDK in `D:\Dev\.tools\jdk-17` and configure the current shell:

```bat
set "JAVA_HOME=D:\Dev\.tools\jdk-17"
set "PATH=%JAVA_HOME%\bin;%PATH%"
javac -version
```

On another Windows checkout, install the current Android command-line tools under `.tools\android-sdk\cmdline-tools\latest` and keep the SDK root on D:/Dev. Then, from Command Prompt:

```bat
call tools\windows-env.cmd
"%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="%ANDROID_HOME%" "platforms;android-37.0" "build-tools;36.0.0" "platform-tools"
```

That command downloads the selected SDK components and asks you to accept their licenses. Older command-line tools may not recognize the `android-37.0` package; use command-line tools 22.0 or later. SDK Manager 22.0 still supports this command and recommends the newer Android CLI for future installations.

## Build and check Host

If you build from a source archive, extract it into a new, empty macOS directory. The archive should include both apps, shared SQL/version/changelog files and the Gradle wrapper, and exclude toolchains, caches, build output, Git metadata and signing material. Without Git history the build tool uses a source SHA-256 identity. Node 22+ is needed for build identification and development checks; it is not shipped with the app.

On macOS, from the monorepo root:

```bash
bash apps/host/Scripts/check.sh
bash apps/host/Scripts/build.sh
```

The default build creates an optimized `Cadenza Host.app` signed with `Cadenza Host Local Signing` when that identity is in your Keychain, and ad-hoc otherwise under the Host staging directory and `dist/Cadenza-Host-VERSION-development-arm64.zip`. Set `CADENZA_MACOS_SIGNING_IDENTITY` to a stable installed macOS signing identity for production updates; otherwise each ad-hoc replacement can trigger a new Keychain authorization prompt. Build CI restores the same identity from `CADENZA_MACOS_SIGNING_CERTIFICATE_BASE64` and `CADENZA_MACOS_SIGNING_CERTIFICATE_PASSWORD` before the production Host build. The updater helper is bundled separately. OS frameworks provide UI, networking, security, translation, XML, and SQLite. Development updates are disabled.

To apply native formatting before checks:

```bash
cd apps/host
swift format format --in-place --recursive Package.swift Sources Tests
```

Build and packaging must pass before a release is described as installable.

## Build and check Remote

On Windows:

```bat
apps\remote\check.cmd
apps\remote\build.cmd Debug
```

On macOS/Linux with an existing JDK and Android SDK:

```bash
bash apps/remote/build.sh Debug
```

The first wrapper invocation downloads the pinned Gradle distribution if absent. All Gradle caches remain inside the repository. The scripts stop if the required SDK platform is missing; Gradle may download missing licensed build components inside the configured SDK root.

The Windows environment scripts prefer the repository's JDK when present. Kotlin compilation runs in the Gradle process. JVM tests, Robolectric's downloaded Android runtime, and the debug signing key also use directories under `.cache` on D:/Dev.

Debug output is `apps/remote/app/build/outputs/apk/debug/app-debug.apk`. It preserves the separate `app.cadence.remote.debug` installation ID and is for testing. The Kotlin namespace is `app.cadenza.remote`; this is deliberately different from the installed ID.

To format Kotlin using the existing toolchain:

```bash
cd apps/remote
bash gradlew :app:ktlintFormat
```

Then rerun strict compilation, lint, formatting checks, and tests.

## Sign a release APK

Create and back up one release keystore. Keep it under the ignored `secrets` directory or another protected location. JDK's `keytool` prompts for passwords; do not put private keys or actual passwords in source files.

Set these environment variables for the build process:

| Variable                    | Value                                 |
| --------------------------- | ------------------------------------- |
| `CADENZA_KEYSTORE_PATH`     | Absolute path to the release keystore |
| `CADENZA_KEYSTORE_PASSWORD` | Keystore password                     |
| `CADENZA_KEY_ALIAS`         | Signing alias                         |
| `CADENZA_KEY_PASSWORD`      | Key password                          |

Run:

```bat
apps\remote\build.cmd Release production
```

The signed APK is `apps/remote/app/build/outputs/apk/release/app-release.apk`. Copy it to `dist/Cadenza-Remote-VERSION.apk` before signing release metadata.

For Host Production packaging use `CADENZA_BUILD_PROFILE=production bash apps/host/Scripts/build.sh`; its canonical release ZIP has no profile suffix. The build fetches and SHA-256-verifies the pinned 456 MB Sing model, then embeds the model and its license in the Host resource bundle. `ci` and `development` archives include the profile in their filename and have updates disabled. The `Build` workflow uses Production signing and publishes the canonical APK/Host ZIP to GitHub Releases after successful `main` checks. Plain `Release` defaults to development and does not enable updates merely because it is optimized.

The apps embed version, profile and immutable source identity. A clean Git checkout embeds its commit SHA; an uncommitted tree or source archive embeds a SHA-256 over maintained source files. The APK also includes `assets/build-identity.txt`. Release signing checks both artifacts' embedded identities against the current source and requires a Production Host profile. Do not edit source between building the two artifacts and signing their release metadata.

The checked-in product version is **0.1.1** in `shared/version.properties`. Change it only when the user authorizes a new product version. CI does not edit this file: it uses the Checking run number as the strictly increasing build code and derives a release version such as `0.1.1_20261029.1001-eb751fa0730d`; the GitHub title is `Cadenza 0.1.1_20261029.1001 (eb751fa0730d)`. Android's native startup screen centers the build label at the bottom: `Cadenza VERSION-PROFILE-SOURCE-20261026.223300`. The profile is `dev`, `ci` or `prod`; dirty/uncommitted trees use `source-` followed by a short digest. The final timestamp is build time in UTC, not launch time. Set `SOURCE_DATE_EPOCH` to epoch seconds when a reproducible timestamp is required. Android's earlier system-managed splash remains an OS-provided icon screen; the text appears while Cadenza loads local state, without a forced delay.

## GitHub CI

Checking runs on pushes across branches and pull requests. Remote checks have a six-minute limit; Host checks have a fifteen-minute limit for the MLX dependency and Swift build. It performs static portable type/lint/format checks, Android ktlint/lint/Kotlin compilation, and Host Swift format, warnings-as-errors compilation, and XCTest checks. Build runs only after a successful Checking push for `main` in the same repository, checks out that exact SHA, repeats those checks, builds Production artifacts with repository Actions secrets, benchmarks the bundled Sing backend on arm64, signs the release metadata, and creates or updates the stable GitHub Release. Remote Build jobs have a six-minute limit; Host Build jobs have a fifteen-minute limit. The ZIP contains the `.app`; no DMG is needed for this distribution approach.

Configure and push the repository before relying on the CI workflows. CI runners must provide the platform SDKs and toolchains described above.

## Shared checks

Workflow validation uses `actionlint` 1.7.12. Install the official platform binary into `.tools/actionlint-1.7.12` or set `CADENZA_ACTIONLINT` to its absolute executable path. The Windows amd64 ZIP SHA-256 is `6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9`; the Apple silicon macOS tarball SHA-256 is `aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f`. Both come from the official `rhysd/actionlint` v1.7.12 release. Keep local tooling under D:/Dev; root checks never download tools themselves. CI bootstraps the pinned Linux binary with its SHA-256 check.

Node is development tooling only. After installing the development dependencies, run the portable checks from the repository root:

```powershell
node tools/check.mjs --portable
```

Native strict compilation, platform lint/formatting, real-device networking, accessibility, and Music integration remain separate mandatory gates. A green portable suite does not establish that either native app builds.

The pre-commit hook runs `node tools/check.mjs --portable --static`, which covers strict type analysis, lint, formatting, source limits, shell syntax, and workflow validation without requiring a native toolchain. The pre-push hook runs the complete `node tools/check.mjs` gate from the monorepo root. It adds the native checks available on the current platform: macOS runs `apps/host/Scripts/check.sh` and `apps/remote/check.sh`, while Windows runs `apps\remote\check.cmd` and reports Host as deferred. The Remote check compiles both Kotlin variants and runs unit tests, ktlint, and Android lint without producing an installable release. CI runs both native suites on their supported runners.
