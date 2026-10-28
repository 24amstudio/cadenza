# Credits and inspiration

Cadenza does not copy source code, assets, or protocols from the projects below. Their public designs and implementation ideas were reviewed while shaping Host-owned lyric caching, cache management, and future media-provider boundaries. All integrations remain Cadenza code and must retain their own license and security review.

- Inspired by [LyricFever](https://github.com/aviwad/LyricFever), [Lyricify-App](https://github.com/WXRIW/Lyricify-App), [LyricsX](https://github.com/ddddxxx/LyricsX), and [BetterLyrics](https://github.com/jayfunc/BetterLyrics) for lyric source handling, fallback providers, word timing, and cache-aware playback experiences. Cadenza's LRCLIB adapter is an independent Swift implementation.
- Inspired by [applemusic-mcp](https://github.com/epheterson/applemusic-mcp), [navidrome/apple-music-plugin](https://github.com/navidrome/apple-music-plugin), and [lyrimuse](https://github.com/Yudaotor/lyrimuse) for provider boundaries and metadata reuse.
- Inspired by [applemusic-like-lyrics](https://github.com/amll-dev/applemusic-like-lyrics), [accompanist-lyrics-ui](https://github.com/6xingyv/accompanist-lyrics-ui), [Minidisc](https://github.com/Loriage/Minidisc), [kawarp-agsl](https://github.com/meowarex/kawarp-agsl), and [NewSync](https://github.com/ban-heesoo/NewSync) for timed lyric presentation, LRC word timestamps, animated artwork direction, and synchronization concepts. Cadenza does not copy their code or add their dependencies.
- Inspired by [sound-processor](https://github.com/woshizja/sound-processor) for keeping media processing at the Host boundary.
- Inspired by [apple-music-animated-artworks](https://github.com/m8tec/apple-music-animated-artworks), [animated-artwork-downloader](https://github.com/m8tec/animated-artwork-downloader), and [Fetcher](https://github.com/bunnykek/Fetcher) for artwork retrieval and local reuse considerations.

Cadenza's LRCLIB and artwork adapters use only fixed HTTPS origins, bounded responses, metadata validation, and Host-side caching. The Remote requests cached artwork through the authenticated Host session and does not contact Apple CDN or lyric providers directly.

Before adopting code or a dependency from any of these repositories, verify its current license, attribution requirements, security posture, and compatibility with Cadenza's AGPL-3.0 license.

The implementation uses no copied source or bundled dependency from these repositories. The reviewed licenses include MIT for LyricFever, MPL-2.0 for LyricsX, AGPL-3.0 for AMLL, and LGPL-3.0 for Kawarp-AGSL; repositories with missing or unclear license metadata remain reference-only until separately reviewed.
