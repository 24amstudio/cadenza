import type { LibrarySongIdentity } from '~/lib/protocol/types';
import type { HostCommandAction } from '~/lib/host/controlQueue';

/** The output and library commands. Each one is handed to `press`, which queues it with the playback controls. */
export function libraryHostCommands(
  press: (action: HostCommandAction) => void,
) {
  return {
    setOutput(uid: string): void {
      press({ kind: 'audio.selectOutput', output: uid });
    },
    setFavorite(song: LibrarySongIdentity, favorite: boolean): void {
      press({ kind: 'library.favorite', song, favorite });
    },
    addToHostPlaylist(name: string, songs: LibrarySongIdentity[]): void {
      press({ kind: 'library.addToPlaylist', name, songs });
    },
  };
}
