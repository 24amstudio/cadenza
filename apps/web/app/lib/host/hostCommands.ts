import type {
  CastPresentation,
  LibrarySongIdentity,
  SongIdentity,
  VideoOutputTarget,
} from '~/lib/protocol/types';
import type { HostCommandAction } from '~/lib/host/controlQueue';

/** The output, Cast, and library commands. Each one is handed to `press`, which queues it with the playback controls. */
export function libraryHostCommands(
  press: (action: HostCommandAction) => void,
) {
  return {
    setOutput(uid: string): void {
      press({ kind: 'audio.selectOutput', output: uid });
    },
    setCastTransmit(device: string, start: boolean): void {
      press({ kind: 'cast.transmit', device, start });
    },
    setVideoOutput(target: VideoOutputTarget): void {
      press({ kind: 'video.output', target });
    },
    setCastPresentation(presentation: CastPresentation): void {
      press({ kind: 'cast.presentation', presentation });
    },
    setLipSyncOffset(offsetMs: number): void {
      press({ kind: 'lip_sync.offset', offsetMs });
    },
    setLyricOffset(song: SongIdentity, offsetMs: number): void {
      press({ kind: 'lyrics.offset', song, offsetMs });
    },
    setFavorite(song: LibrarySongIdentity, favorite: boolean): void {
      press({ kind: 'library.favorite', song, favorite });
    },
    addToHostPlaylist(name: string, songs: LibrarySongIdentity[]): void {
      press({ kind: 'library.addToPlaylist', name, songs });
    },
  };
}
