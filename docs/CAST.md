# Cast and TV stage

Cadenza sends Music's output to a TV or speaker with no paid account and no hosted server. Nothing needs a Google Cast Developer Console registration, an HTTPS receiver, an Apple Developer membership, or Google Play services.

## The four $0 tiers

| Tier | Target                                                                 | Requires                                                | What plays                                                                                                                            |
| ---- | ---------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | Google Cast default receiver (`CC1AD845`), speakers and Chromecast TVs | Nothing beyond the device on the same network           | Stereo audio with track metadata. A local music video plays with its karaoke as a native WebVTT subtitle track.                       |
| 2    | Browser TV stage at `http://<mac>:<web port>/tv`                       | A TV browser on the same network                        | Artwork, motion loop, synced lyrics with translations, and audio through Media Source or a raw PCM worklet.                           |
| 3    | Android TV receiver in Cadenza Remote                                  | The Remote APK on the TV, and the Host address typed in | The same stage, with an AudioTrack output that passes AC-3 to an AVR over HDMI when the output reports it.                            |
| 4    | AirPlay 2 (Apple TV, HomePod, AirPlay TVs)                             | An AirPlay output on the network                        | Music's audio through the output switcher. A catalog video plays through the FairPlay manifest proxy with a WebVTT karaoke rendition. |

Each Remote and the Host agree on one route per receiver. The Host chooses it from the device's capability record, the presentation mode, and the thermal budget. A Remote never picks its own route.

## Browser stage (`/tv`)

1. Open `http://<mac>:<web port>/tv` on the TV browser. The web port is the Host's control port plus two, and Settings → Cast shows the full address. The address appears only while Cadenza Web is on in Settings → Network. Turning it on takes a Host restart.
2. The TV shows a PIN and a QR code. Approve it in Cadenza Host (Settings → Cast → Approve), or scan the QR code with a Remote that is already paired. The approval link opens the Remote with the PIN, and the Remote approves it.
3. The TV keeps a token for its next visit, so it only asks for approval once. Forget a TV in Settings → Cast to make it pair again.
4. Browsers block audio until someone presses a key or touches the screen. Press OK once after the TV starts.

Keys: OK or Play/Pause toggles playback, the right and left arrows skip and go back, and the up and down arrows move the lip-sync offset by 10 ms, up to 250 ms.

## Android TV receiver

1. Install the Remote APK. On an Android TV, Cadenza Remote starts as the stage. On a tablet, turn on **TV Stage Receiver Mode** in Settings.
2. Type the Host address shown in Settings → Cast, for example `192.168.1.10:8766`. The stage uses plain HTTP on the local network only.
3. Approve the TV as above. The receiver then plays audio for each Remote command that names it.

## Audio formats

- **Transcode (Auto)** is the default. Stereo goes out as AAC-LC in fragmented MP4 for browsers. A 5.1 source goes out as AC-3 only when an AC-3 encoder is available. Without one, 5.1 folds to stereo.
- **Bitstream** sends uncompressed PCM at the receiver's channel count. It uses more network bandwidth, and it does not add a compressed passthrough. Music decodes its own audio, so compressed passthrough is not possible here.
- The AC-3 encoder is not part of the public build. A development build sets `CADENZA_AC3_HELPER` to an FFmpeg helper with only the AC-3 encoder, as described in `docs/credits.md`.

## Lip-sync calibration

Play a track with a visible lyric change, then move the offset until the line changes with the sound. Start at 0 ms. An AVR or soundbar usually needs 80 to 200 ms. The browser stage saves the offset locally, and the Host saves the karaoke nudge per track. The 1,000 ms control budget is a confirmation window, not a promise that Music or a download finishes in that time.

## Limits

- Catalog music videos never reach a Cast device or a stage receiver. Their pictures are FairPlay-protected, and only a local file can be played there.
- Protected audio is not read for alignment, so video alignment uses the local file's audio only.
- The experimental web loader is built but unverified. Settings → Cast → Experimental Web Loader takes a URL-loading Cast app ID that you supply. Cadenza then opens `/tv` through that app on the TV instead of streaming audio to the Default Media Receiver. No app ID is bundled, and no device has run it.
- Nothing in this stage has been run on a real TV, Chromecast, Google TV, Fire TV, or Apple TV in this build. See `docs/agents/VALIDATION.md`.
