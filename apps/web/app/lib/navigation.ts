export type AppView = 'now-playing' | 'lyrics' | 'up-next' | 'settings';

export interface NavItem {
  view: AppView;
  label: string;
  icon: 'now' | 'lyrics' | 'queue' | 'settings';
}

const items: NavItem[] = [
  { view: 'now-playing', label: 'Now Playing', icon: 'now' },
  { view: 'lyrics', label: 'Lyrics', icon: 'lyrics' },
  { view: 'up-next', label: 'Up Next', icon: 'queue' },
  { view: 'settings', label: 'Settings', icon: 'settings' },
];

// Lyrics is offered only when the current song has lyrics, so the navigation never points at an empty surface.
export function navigationItems(lyricsAvailable: boolean): NavItem[] {
  return items.filter((item) => item.view !== 'lyrics' || lyricsAvailable);
}
