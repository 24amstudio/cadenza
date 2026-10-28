# Cadenza — Implementation Goalset

## 1. Objective

Refactor and improve the existing application into **Cadenza**, a reliable, lightweight, native cross-device application for controlling Apple Music from Android.

The two applications are:

- **Cadenza Host:** Native macOS application, implemented using Swift and appropriate native Apple frameworks.
- **Cadenza Remote:** Native Android application, implemented using Kotlin and Jetpack Compose.

This is an evolution of the existing project, not a greenfield rewrite. Preserve existing working functionality unless a change is necessary and justified. Follow native platform conventions and best practices.

## 2. Working Rules and Initial Audit

- All local project work, source changes, temporary files, and generated artifacts must reside on the `D:/Dev\` drive. Verify the working directory before making changes. Do not create the project or working copies on `C:\`.
- First inspect the existing Git repository, working-tree status, architecture, project structure, build systems, dependencies, connection protocols, permissions, tests, and release/update mechanisms.
- Identify existing user changes and preserve them. Never discard work, perform destructive Git operations, or rewrite Git history.
- Create or update an implementation plan after the initial audit, then execute the work. Do not stop after producing a plan.
- Prefer the smallest reliable solution. Avoid unnecessary dependencies, duplicated logic, excessive abstractions, background polling, and speculative rewrites.
- If a requirement conflicts with platform limitations or the current architecture, investigate alternatives, implement the best viable solution, and document the trade-off rather than silently ignoring the requirement.

## 3. Project Rename

Rename the project consistently to **Cadenza**, with application names **Cadenza Host** and **Cadenza Remote**.

Update all relevant project files, folder/module names, source references, application display names, code identifiers, configuration, build scripts, documentation, and CI workflows.

Audit bundle identifiers, Android application IDs, signing configuration, persisted data locations, permission grants, deep links, and update mechanisms before changing identifiers that could break existing installations. Preserve compatibility or provide an appropriate migration where necessary.

Verify that both applications still build and their existing functionality remains intact after renaming.

## 4. Cadenza Host — macOS

### First-run onboarding

Implement a clean, minimal, sequential onboarding flow:

1. Welcome the user to Cadenza Host.
2. Detect the user's Apple Music catalog storefront automatically using supported APIs and available account information.
3. Ask the user to select a storefront only when automatic detection fails or produces an ambiguous result.
4. Explain and request each necessary macOS permission, including appropriate Apple Music access. Handle denied, restricted, or revoked permissions gracefully.
5. Complete the existing Host–Remote pairing process and verify that the connection works.

Persist onboarding completion so returning users do not repeat the flow unnecessarily. Make setup and recovery accessible from Settings.

Never assume permissions can be granted programmatically when macOS requires user approval.

### Background operation and settings

After successful onboarding, close the onboarding window and keep Cadenza Host running in the background.

- Expose a lightweight menu-bar interface appropriate for macOS.
- Provide a Settings option to **Show in Tray** or **Hide Tray Icon**, using the appropriate native macOS terminology and behavior.
- When the user opens Cadenza Host again through Spotlight or another application-launch mechanism while it is already running, bring its Settings window to the foreground rather than launching a duplicate instance.
- Closing the Settings window must not terminate the background service.
- Provide a clear, discoverable way to quit the application completely.

### Resource efficiency

Minimize memory consumption and CPU usage, especially while idle. Profile the existing implementation, remove unnecessary work, and use efficient native APIs and event-driven updates wherever practical. Report measured resource behavior rather than making unsupported optimization claims.

## 5. Cadenza Remote — Android

### Client identity

During onboarding, automatically obtain the Android device's name and use it as the default client name.

Allow users to change their client name in Settings. Persist the custom name across application restarts.

### Favorites

Implement locally stored favorites on Cadenza Remote.

Users must be able to favorite a song easily and perform these actions from the Favorites interface:

- Play immediately.
- Add to queue.
- Play next.

Favorites must persist across application restarts and remain client-side data. Do not require favorites to be stored or synchronized by Cadenza Host. Handle unavailable tracks and corrupted local data gracefully.

### Theming and adaptive UI

Support three theme preferences:

- Follow system theme.
- Light mode.
- Dark mode.

Respect Android's system theming and native UI conventions.

Use the official Android adaptive list-detail pattern for the Remote home screen, with Jetpack Compose and the appropriate Material 3 adaptive components. On expanded windows, display list and detail panes together; on compact windows, adapt navigation to the available space while preserving selection and navigation state.

Use the following references:

- Android adaptive list-detail layouts: https://developer.android.com/develop/ui/compose/layouts/adaptive/canonical-layouts?authuser=445#list-detail
- Media detail and playback design: https://developer.android.com/design/ui/gallery/media/detail?hl=en&authuser=445
- Material Design foundations: https://m3.material.io/foundations

Follow the current official guidance, adapt it to Cadenza's actual user flows, and retain accessibility, responsive layouts, and clear interaction states.

### Android Live Updates

When a user actively begins controlling a media device, provide an appropriate ongoing Android notification and implement the current Live Updates APIs where the use case, Android version, and system eligibility requirements permit.

The notification should communicate the current control-session state and update only when meaningful state changes occur. Stop or appropriately transition the notification when the session ends.

Respect notification permissions, user preferences, and platform restrictions. Fall back gracefully to a standard ongoing notification when Live Update promotion is unavailable or unsupported. Never promise promotion that Android or the device manufacturer does not guarantee.

I prefer if you can have "Status chips" working here "https://developer.android.com/develop/ui/compose/notifications/live-update#status-chips".

Reference: https://developer.android.com/develop/ui/compose/notifications/live-update

## 6. Connection, State, and Crash Resilience

Reliability is a core requirement for both applications.

Inspect the existing communication architecture and implement appropriate connection discovery, recovery, and failover mechanisms. Support multiple viable connection paths between Host and Remote where the existing architecture and platform capabilities permit.

Requirements:

- Automatically reconnect after temporary network interruptions, process restarts, or recoverable system termination.
- Detect broken or stale connections and recover without requiring unnecessary user intervention.
- Fail over to another viable connection path when the active path becomes unavailable.
- Preserve important application state and user settings across crashes and restarts.
- Handle malformed messages, interrupted writes, stale state, duplicate events, missing data, and partially completed operations safely.
- Prevent reconnection from causing duplicated playback commands or inconsistent queue state.
- Use bounded retries, appropriate backoff, timeouts, and sensible resource cleanup.
- Keep error handling quiet and unobtrusive during normal recovery, but provide actionable feedback when user intervention is necessary.

Do not assume that either application can prevent the operating system from terminating it. Design for safe recovery instead.

Test the failure and recovery paths. Document any transport limitations and the fallback behavior implemented.

## 7. Battery and Resource Efficiency

**Android battery efficiency is mandatory.** Host efficiency remains a high priority.

- Prefer event-driven updates over continuous polling.
- Avoid unnecessary network requests, CPU wakeups, timers, and repeated state serialization.
- Suspend or reduce nonessential work when disconnected or when application lifecycle constraints permit.
- Use adaptive retry intervals and efficient state synchronization.
- Stop background work when it is no longer required.
- Avoid UI redraws and network synchronization when the underlying state has not changed.

Profile representative idle, connected, active-control, and disconnected states. Correct inefficient behavior rather than optimizing solely for theoretical benchmarks.

## 8. Version Awareness and Changelog

Each build must embed its application version and Git commit SHA, or equivalent immutable build identifier.

Implement a changelog mechanism that compares the installed build against a defined newer release or commit and presents the relevant changes to the user.

First inspect the existing repository remote, release workflow, and update infrastructure to determine the appropriate source of newer release metadata. Do not invent repository URLs or assume that production users have access to the local Git repository.

If no suitable release metadata source exists, implement a documented, maintainable mechanism appropriate to the project's existing infrastructure.

Handle offline access, missing release metadata, and unavailable Git history gracefully. Never display fabricated changes or claim that newer commits were checked when no reliable comparison was possible.

## 9. Automatic Updates and Build Configurations

Any automatic update checking, downloading, or installation functionality must be enabled **only for Production builds**.

Development, test, and CI builds must not unexpectedly download or install updates. Use explicit build-configuration or feature-flag controls, with sensible defaults and tests to prevent accidental activation.

Keep update-related behavior isolated enough that it can be tested without installing a real update.

## 10. Crash Handling and Data Integrity

Implement robust error handling across both applications.

- Validate persisted data and incoming messages before using them.
- Use safe persistence strategies that prevent partially written data from destroying valid existing state.
- Recover from malformed or missing local state where possible.
- Preserve user settings and Android favorites during ordinary crashes and upgrades.
- Avoid infinite recovery loops and repeated crash cycles.
- Log enough information for debugging without exposing credentials, sensitive user data, or unnecessary personal information.

Add or update tests for significant recovery paths.

## 11. CI/CD

Implement two clearly separated CI pipelines.

### Checking CI

Runs on every relevant commit/push and pull request, across branches.

It must run the checks applicable to each project:

- Unit and other existing automated tests.
- Compilation and type checking.
- Linting and static analysis.
- Code formatting checks.
- Any additional repository-specific quality gates identified during the audit.

Use the project's supported tools and add missing configuration where necessary. Document the commands so developers can run the same checks locally.

### Build CI

Build CI may execute only on the `main` branch, and only after Checking CI has completed successfully for the relevant revision.

It must:

- Build the Android APK.
- Build the native macOS `.app` bundle.
- Produce a `.dmg` installer artifact when required by the project's distribution approach.
- Publish the resulting artifacts as CI workflow artifacts.
- Use appropriate platform runners, including a macOS runner for native macOS builds.
- Keep signing credentials and secrets outside the source repository.

Failed checks must block the build pipeline. Clearly distinguish test artifacts from production release artifacts, and do not expose signing credentials in logs or build outputs.

## 12. AGENTS.md and Documentation

Create or update the root `AGENTS.md` so future coding agents understand and consistently follow the project's architecture and conventions.

Include:

- Product overview and Host/Remote responsibilities.
- Repository structure and important files.
- Language, framework, and implementation conventions.
- Architecture, communication protocol, state management, and persistence.
- Setup, build, run, test, lint, formatting, and CI commands.
- Naming conventions and platform-specific constraints.
- Permission handling, crash recovery, battery, and resource-efficiency principles.
- Release, build-version, changelog, and automatic-update behavior.
- A concise list of known limitations and architectural decisions.

Include these references and instruct future agents to consult the relevant guidance before making changes:

- Android development agent skills: https://developer.android.com/tools/agents/android-skills
- Swift agent skills directory: https://github.com/twostraws/swift-agent-skills

Review and use relevant guidance selectively. Do not blindly install or trust arbitrary third-party skills.

Update the README and all affected documentation so the Cadenza names, architecture, onboarding, permissions, pairing, builds, and release processes are consistent with the implementation.

## 13. Definition of Done

The work is complete when:

1. Both applications and the project structure consistently use the Cadenza naming.
2. Existing working functionality remains intact, and both applications build successfully in their supported environments.
3. Host onboarding, storefront detection, permissions, pairing, background operation, and Settings behavior work as specified.
4. Remote client naming, local favorites, theme preferences, adaptive layouts, and ongoing control notifications work as specified, subject to documented platform limitations.
5. Connection interruptions and recoverable crashes do not permanently corrupt application state; viable reconnection and failover paths are tested.
6. Idle and active resource usage has been reviewed, with avoidable polling and unnecessary background work eliminated.
7. Version identification and changelog comparison use a reliable source and fail gracefully when that source is unavailable.
8. Automatic-update behavior is disabled in non-production builds.
9. Checking CI and Build CI enforce their required triggers, dependencies, and platform-specific build outputs.
10. `AGENTS.md` and all affected documentation accurately describe the finished implementation.

At completion, provide a concise report covering the changes made, architectural decisions, tests and builds executed, artifact locations, and any remaining limitations. Clearly distinguish verified results from functionality that could not be tested in the available environment.
