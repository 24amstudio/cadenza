# Cadenza UI revision addendum

This document records the UI revision supplied on 26 October 2026. The base product requirements and definition of done are in [GOALSET.md](GOALSET.md). This addendum is agent-facing acceptance guidance; it does not duplicate the base goalset.

## Artwork and visual hierarchy

- Now Playing shows the exact current song's cover artwork whenever the Host supplies it. Search, Favorites, Queue, and Lyrics use the same song artwork metadata.
- Artwork loading validates the HTTPS Apple Music image origin, bounds response size and decoded dimensions, reserves layout space, rejects stale responses after a song change, retries through an explicit bounded policy, and uses a bounded cache.
- The principal cover keeps its aspect ratio. Missing or failed artwork gets a deliberate themed fallback and never changes playback state.
- Now Playing and Lyrics derive a restrained backdrop accent from the current artwork. The palette must retain readable text and controls in light and dark themes; fallback palettes remain theme-consistent.
- Surrounding navigation and utility screens follow the persisted system, light, or dark preference. Do not add decorative labels, fabricated quality states, or invented playback capabilities.

## One player with Lyrics mode

- Lyrics is a visible, accessible mode of Now Playing. It is not a separate primary navigation destination.
- Entering Lyrics transforms the player presentation, keeps essential progress and transport controls reachable, and provides a clear exit. Android Back returns to the normal player before navigating away.
- Compact windows use a compact track identity area and give the lyric reader the main space. Expanded windows place artwork and playback controls beside the lyric reader.
- Resizing, rotation, and ordinary state restoration preserve the selected mode and surrounding navigation state. A track change updates the identity and drops lyrics for the previous occurrence without restarting playback.
- Existing Host protections, requester attribution, translations, timing levels, and queue state remain authoritative.

## Honest lyric states and feedback

- Show loading, timed, untimed, unavailable, failed, stale, and disconnected states explicitly. Untimed lyrics do not receive fabricated active-line timing.
- Manual scrolling pauses follow mode and exposes a visible “Follow current line” action. Reconnection reconciles the current playback occurrence before live highlighting resumes.
- Lyrics actions acknowledge immediately, prevent duplicate requests, and keep routine outcomes in stable accessible feedback. Blocking errors use the existing accessible prompt path.
- Missing lyrics never disable the normal player or trap the user in Lyrics mode.

## Browsing and adaptive behavior

- Queue, Favorites, and Search rows keep compact artwork thumbnails, title, artist, duration, requester attribution, wait estimates, and permission-aware actions.
- The official Material adaptive list-detail scaffold remains the home layout. Expanded windows show list and detail together; compact windows preserve selection, input, and navigation state.
- Long, multilingual, and right-to-left content must wrap or truncate without hiding controls. Alternatives to dragging remain available.

## Required evidence

The revision is complete only when the working native Remote has evidence for artwork loading and failure, palette readability, Lyrics entry and exit, track changes, manual scroll/follow, stale synchronization, adaptive widths, large text, keyboard/focus, TalkBack, reduced motion, feedback surfaces, and actual phone/tablet screenshots. Robolectric renders and synthetic data document source behavior but do not establish target-device or Host integration conformance.

Android Live Updates remain conditional on OS, permission, channel, and manufacturer eligibility. Cadenza must keep the standard ongoing notification fallback, pin automatically while the Host plays, and never promise promotion on unsupported devices.
