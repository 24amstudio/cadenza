# Cadenza Ambient Recognition Service (CARS)

**Status:** Proposed product requirements document
**Scope:** Product and architecture planning only
**Owner:** Cadenza Host
**Last updated:** 2026-10-31

## 1. Summary

Cadenza Ambient Recognition Service (CARS) is a Host-owned, local-first service that continuously recognizes music entering Cadenza Host through a selected audio source. It publishes the recognized recording, confidence, approximate position, and recognition health to authenticated Remotes so they can show the current listening session and its lyrics.

CARS is designed for Music.app observation and external sources such as a turntable, tape deck, radio, line-in interface, or microphone. It analyzes bounded PCM windows locally. It does not become an audio player, cloud relay, general-purpose recorder, or Apple Music replacement.

The first release focuses on a local CARS catalogue. AcoustID/MusicBrainz lookup is an optional metadata fallback for unknown audio. A commercial external recognition provider is explicitly deferred.

## 2. Product decision

CARS is a subsystem of Cadenza Host, not a separate app and not a Remote feature.

The shared Host audio path is:

    Music.app or selected input
        -> one Core Audio capture route
        -> Host audio normalizer and bounded PCM bus
            -> Sing audio processor
            -> CARS recognizer

CARS receives normalized mono PCM from Host. It does not create another process tap, own macOS permissions, access Music.app UI, send raw audio to Remote, or block the real-time audio callback.

CARS is initially a Swift-native implementation. SoundPrint is research input only; CARS does not retain the SoundPrint product name, .NET runtime, PostgreSQL store, or a dependency on the original implementation. Its algorithm may be reimplemented from the published landmark-hashing design after license and attribution review.

## 3. Goals

- Recognize music continuously from a Host audio source with bounded CPU and memory use.
- Work without ShazamKit or a paid external recognition account.
- Keep raw audio local to Host and avoid continuous audio uploads.
- Build a useful catalogue from user-owned reference recordings.
- Reuse the Host PCM path already planned for Sing mode.
- Report approximate track position and recognition confidence.
- Provide useful metadata and lyrics to authenticated Remotes.
- Support long-running monitoring without unbounded buffers, timers, or database writes.
- Make catalogue size, confidence, and retention visible and controllable.
- Leave a provider boundary for a future external recognizer without implementing one now.

## 4. Non-goals

The initial release does not:

- capture or relay raw audio to Remote;
- implement ShazamKit;
- implement a commercial music-recognition API;
- guarantee identification of every commercial recording;
- promise that covers, remixes, live versions, or materially speed-shifted recordings match;
- control a turntable, tape deck, or radio;
- provide seek, skip, or authoritative playback control for external input;
- create a full-world catalogue in the app bundle;
- synchronize multiple Hosts;
- replace Music.app as the playback engine;
- persist Apple Music-derived reference fingerprints before a separate policy and legal review;
- store continuous microphone or system-audio recordings.

## 5. Terminology

- **CARS:** Cadenza Ambient Recognition Service.
- **Source:** A Host audio input selected for recognition.
- **Reference:** User-owned audio that CARS fingerprints to create a local catalogue entry.
- **Fingerprint:** A compact, one-way representation used for matching; it is not playable audio.
- **Catalogue:** The local index mapping fingerprint landmarks to recording identities and positions.
- **Recognition session:** A bounded state machine consuming rolling PCM windows.
- **Stable match:** A candidate supported by the required confidence and repeated agreement policy.
- **Unknown:** Audio for which no stable local or optional AcoustID match exists.
- **Gap:** A period where capture, matching, or source quality is insufficient to claim a current recording.
- **Reference provenance:** The source and permission category for a reference.

## 6. User journeys

### 6.1 Music.app observation

The user plays a song in Music.app. Host observes the process through its Core Audio route. CARS recognizes or confirms the recording, estimates position, and publishes the result to the Remote. Music.app remains the playback authority.

### 6.2 Vinyl or tape

The user selects a line-in or USB interface. CARS recognizes a recording from the local catalogue or optional AcoustID lookup. The Remote shows title, approximate position, confidence, and lyrics when available. It does not show seek or skip controls.

### 6.3 Personal catalogue building

The user imports user-owned local recordings or references. Host fingerprints them once, stores the local index, and associates metadata and provenance. The user can cancel, rebuild, or delete entries.

### 6.4 Continuous monitoring

The user enables monitoring for a source. CARS runs for hours without retaining raw audio, logs recognition events, detects transitions, and reports gaps after silence, sleep, route changes, or source changes.

## 7. Source requirements

### 7.1 Music.app process tap

Host targets Music.app through the existing Core Audio process-tap route and shared PCM bus.

- CARS must not create a second tap or aggregate device.
- CARS must stop cleanly if the tap, aggregate device, or output route disappears.
- Music.app track changes invalidate the previous recognition session.
- Host Music metadata is preferred when authoritative.
- Results are labelled as observed or acoustically recognized.
- Persistent fingerprints derived from Apple Music content are disabled by default.

### 7.2 Line-in or USB interface

- The input device is explicit and visible.
- Monitoring does not automatically route input back to output.
- Device removal produces a recoverable source error.
- Input level and silence are reported without storing raw audio.

### 7.3 Built-in microphone

Microphone capture is a fallback for music playing through speakers.

- Host explains that room capture is less reliable than line-in.
- Echo, speech, low volume, and room noise reduce confidence.
- The user can pause capture without stopping Host or Music.app.

### 7.4 Future Remote-owned source

Reserved for a future adapter and excluded from the first release.

## 8. Recognition behavior

### 8.1 Rolling analysis

CARS must consume PCM through a bounded queue, convert it to mono and the configured analysis rate, maintain a rolling query window, process outside the audio callback, avoid per-frame database writes, and discard raw audio after the analysis window.

The initial target is a 5â€“10 second window. A longer window may be used when confidence is low or speech/noise masks music.

### 8.2 States

The observable states are:

- disabled
- starting
- listening
- candidate
- recognized
- unknown
- source_unavailable
- permission_required
- failed

A candidate must not replace the current recognized track until it meets the stability policy. A stable match returns recording identity, confidence, matched position, observation timestamp, estimated elapsed position, and optional speed skew.

### 8.3 Position and drift

Host advances elapsed time from a monotonic clock between corrections. CARS periodically rechecks to detect a transition, tape speed drift, or a false match. External-source position is approximate and must not expose Music.app-level seek accuracy.

### 8.4 Boundaries and silence

CARS detects silence, speech-only input, transitions, source changes, confidence drops, and implausible repeated offsets. When no stable match remains, it reports unknown or a gap instead of retaining stale metadata indefinitely.

## 9. Catalogue strategy

### 9.1 Local catalogue first

References may come from user-owned local files, CD or vinyl rips, user-supplied recordings, or another source explicitly approved for fingerprinting. Metadata and provenance are separate from fingerprint postings.

### 9.2 No full-world bundle

The application bundle contains code and schema only. Catalogue data is separate Host application data and may be disabled, compact, balanced, precision, or room-specific. Incomplete catalogue builds must never replace the last valid catalogue.

### 9.3 Density profiles

| Profile   | Intended use             | Trade-off                                    |
| --------- | ------------------------ | -------------------------------------------- |
| Compact   | Large personal catalogue | Lower storage, more retries and lower recall |
| Balanced  | Default monitoring       | General-purpose storage and recall           |
| Precision | Difficult input          | Larger catalogue and higher matching cost    |

Profiles control fingerprint density and storage. Confidence thresholds are separate and do not reduce catalogue size.

Candidate tuning controls include internal sample rate, peaks per band, landmark fan-out, query-window length, offset tolerance, catalogue-window sparsity, and match threshold. Each catalogue records a parameter fingerprint and rejects incompatible queries unless migration exists.

### 9.4 Storage design

CARS should use a packed local representation instead of a general-purpose row per landmark:

- sorted postings by hash;
- compact track and frame identifiers;
- delta encoding where useful;
- memory mapping or bounded hot indexes;
- separate metadata and fingerprint files;
- atomic catalogue generation and swap.

SoundPrint measurements are planning baselines only: approximately 9.4 MB per hour of indexed real music in memory and 55 MB per hour in its PostgreSQL representation. CARS must measure its own profiles before publishing a storage guarantee.

The product must estimate catalogue size before a large import and provide cancellation.

## 10. AcoustID integration

AcoustID is an optional metadata provider, not the CARS catalogue format.

    unknown PCM
        -> compatible fingerprint lookup
        -> AcoustID
        -> MusicBrainz metadata
        -> Host cache

An AcoustID result may enrich metadata or propose a candidate. It does not become a CARS posting unless CARS also receives permitted reference audio and fingerprints it using the active CARS profile.

The adapter must be optional, rate-limited, cached, labelled, bounded, and unable to block local recognition. It must use a meaningful User-Agent and back off after provider failures. Public AcoustID data has separate licensing and attribution requirements.

## 11. Apple Music policy boundary

CARS may technically receive Music.app PCM through Hostâ€™s process tap. Persistent catalogue learning from Apple Music content is disabled pending explicit policy and legal review.

- Music.app observation may support current-session recognition and synchronization experiments.
- CARS must not retain raw Music.app PCM.
- Host may retain Music metadata and recognition events under existing policy.
- The UI must not describe the feature as training CARS on Apple Music.

This policy is independent of the Core Audio implementation.

## 12. Host architecture

Host owns source selection, Core Audio permissions, normalization, PCM fan-out, CARS lifecycle, catalogue files, provider requests, recognition state, lyric/artwork enrichment, and Remote publication.

CARS owns DSP, fingerprint extraction, catalogue matching, confidence, offsets, boundaries, and profile compatibility.

CARS does not own WebSockets, pairing, command receipts, Music.app automation, Remote identity, UI, or raw-audio export.

The real-time path is:

    Core Audio callback
        -> preallocated bounded ring buffer
        -> CARS worker or actor
        -> catalogue store
        -> Host session coordinator
        -> Remote state

Catalogue lookups and provider requests run away from the main actor. A blocked provider cannot block local matching or playback.

### 12.1 Sing integration

Sing and CARS consume the same normalized PCM bus. If Sing falls behind, its bypass and recovery remain independent. If CARS falls behind, Host may drop analysis windows and report a gap; it must not affect Music playback or Sing output.

## 13. Remote behavior

Remote receives an optional CARS state extension containing source, state, identity, confidence, approximate elapsed, freshness, provenance, lyrics revision, and error status.

Remote may show current source, artwork, title, artist, approximate position, confidence, provider label, lyric availability, recognition gaps, and an identify-again action.

Remote must not show raw PCM, false seek controls for external sources, guaranteed exact position for vinyl or tape, or a stale title without freshness.

## 14. UX requirements

Setup lets the user select a source, grant permission, choose an input device, select a catalogue profile, view estimated storage, choose optional AcoustID lookup, and start or stop monitoring.

The explanation must state that continuous monitoring is not continuous recording and identify what is retained and discarded.

Active monitoring shows source, state, last match, approximate position, confidence, catalogue profile, storage use, last recognition time, and a clear stop control.

Routine recognition uses a toast. Permission failures, unavailable devices, catalogue corruption, and decisions requiring user action use an accessible modal.

Catalogue management supports import, progress, cancellation, size inspection, removal, rebuild, profile selection for future imports, deletion, and provenance labels. Long actions show pending state and prevent duplicate submission.

All controls require semantic labels, keyboard access, visible focus, large-text support, non-color confidence indicators, localized durations and timestamps, and accessible announcements for recognition changes.

## 15. Privacy and security

- Raw audio remains in bounded Host buffers unless a future recording feature receives separate consent.
- Fingerprints are derived Host data and receive Host storage protection.
- Provider requests contain only the minimum required fingerprint and metadata.
- Provider origins and responses are bounded and validated.
- Diagnostics redact fingerprints, raw audio, provider tokens, and local paths.
- Remote authorization controls access to CARS state and catalogue mutations.
- CARS cannot silently enable a source or import references after reconnect.

## 16. Resource requirements

Optimized Apple Silicon builds must measure idle Host, silence, Music.app, line-in, indexing, matching, catalogue size, lookup latency, wakeups, sleep/wake, and source changes.

Measurements must cover 500, 1,000, 5,000, and 10,000 reference tracks where practical. CARS must not claim a universal CPU, battery, or catalogue-size budget before these measurements exist.

## 17. Failure and recovery

CARS handles denied permissions, missing Music.app, removed devices, aggregate-device failure, sample-rate changes, buffer overrun, catalogue mismatch or corruption, provider timeouts, no match, low confidence, transitions, sleep/wake, and Host restart during indexing.

Recovery stops CARS without interrupting Music playback, discards incomplete builds, retains the previous valid catalogue, marks elapsed position stale after a gap, and never silently guesses or replays a catalogue mutation.

## 18. Protocol implications

CARS may remain Host-local while the recognition contract is validated. When Remote publication is enabled, advertise an optional capability such as ambient.recognition.

Future state includes session identifier, source, state, identity, title, artist, confidence, matched offset, estimated elapsed, observed-at time, freshness, provenance, lyric revision, and bounded error information.

Future commands may include ambient.start, ambient.stop, ambient.identify_again, ambient.catalogue.import, ambient.catalogue.cancel, and ambient.catalogue.delete. All mutations use the existing Host journal and replay-safe receipt rules.

## 19. Acceptance criteria

### Core

- A local reference can be indexed and matched from a clean PCM clip.
- A 5â€“10 second rolling window can produce identity, confidence, and offset.
- Unknown audio remains unknown.
- Track transitions do not leave the previous title indefinitely visible.
- Multi-hour monitoring does not grow memory without bound.

### Host

- CARS consumes the existing PCM path and creates no duplicate tap.
- CARS cannot block the audio callback, Music playback, or Sing.
- Permission, device removal, sleep, and wake are recoverable.
- Stopping CARS releases buffers and catalogue handles.

### Catalogue

- Builds are cancellable and atomic.
- Incomplete builds never replace the last valid catalogue.
- Profile incompatibility is detected.
- Size is estimated before large imports.
- Provenance is stored and deletion removes postings.

### AcoustID

- It is optional and cannot block local recognition.
- Rate limits and failures produce backoff and a visible state.
- Metadata is cached with source labels.
- Results are not silently converted into CARS references.

### Remote

- Only authorized, bounded CARS state is published.
- Freshness and uncertainty are visible.
- External sources do not expose seek or skip.
- Lyrics use the existing Host document and revision model.
- Reconnect refreshes state without replaying commands.

### Validation

- Swift strict compilation and formatting pass on macOS.
- Tests cover deterministic fingerprints, profile compatibility, offset voting, thresholds, boundaries, and catalogue recovery.
- Integration tests cover the real PCM bus, bounded queues, source changes, and lifecycle.
- Optimized performance tests cover representative Macs and catalogue sizes.
- Accessibility checks cover keyboard, VoiceOver, large text, contrast, modal focus, and status announcements.

## 20. Rollout

### Phase 0: design and measurement

Finalize the PCM bus, catalogue format, benchmark corpus, density profiles, and licensing decisions.

### Phase 1: local CARS core

Implement Swift-native DSP, matching, packed storage, and Host-local recognition. Do not publish Remote state or persist Apple Music-derived references.

### Phase 2: Host sources

Add Music.app process-tap input, line-in, microphone, source selection, permission handling, and Sing sharing.

### Phase 3: catalogue management

Add reference import, profile selection, size estimates, cancellation, deletion, rebuild, and provenance.

### Phase 4: Remote session

Add optional capability negotiation, recognition state, lyrics, source-aware UI, uncertainty, and reconnect behavior.

### Phase 5: AcoustID enrichment

Add optional lookup, Host cache, rate limiting, and provider labels.

### Deferred

Persistent Apple Music-derived reference learning, commercial recognition providers, synchronized multi-Host recognition, a bundled world catalogue, and cloud audio processing.

## 21. Open decisions

1. Should references be imported from folders, individual files, or both?
2. Should a saved source and catalogue be associated with each Host room?
3. What compact-profile recall is acceptable for vinyl and tape?
4. Should the store be packed binary, SQLite-backed, or both?
5. Which metadata fields are retained from AcoustID?
6. What minimum macOS version is required for the process-tap source?
7. Is persistent Music.app-derived learning permanently disabled or reviewable later?
8. Should low-confidence candidates be visible or hidden until stable?
9. Should users export local CARS catalogues?
10. What size triggers a recommendation to use Compact?

## 22. Decision record

The current recommendation is to build CARS as a Swift-native Host subsystem, reuse the Sing-mode Core Audio and PCM architecture, use a local catalogue as the primary recognizer, keep density and confidence separate, use packed profile-aware storage, make AcoustID an optional metadata fallback, defer commercial providers, and keep persistent Apple Music-derived catalogue learning disabled pending explicit review.
