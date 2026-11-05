export type AppView = 'now-playing' | 'up-next' | 'settings';

export interface NavItem {
  view: AppView;
  label: string;
  icon: 'now' | 'queue' | 'settings';
}

// Lyrics are part of the Now Playing page, so they have no entry of their own.
export const navigationItems: NavItem[] = [
  { view: 'now-playing', label: 'Now Playing', icon: 'now' },
  { view: 'up-next', label: 'Up Next', icon: 'queue' },
  { view: 'settings', label: 'Settings', icon: 'settings' },
];
