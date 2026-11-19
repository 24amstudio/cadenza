export type AppView =
  'now-playing' | 'up-next' | 'search' | 'library' | 'settings';

export interface NavItem {
  view: AppView;
  label: string;
  // The phone tab bar has five slots, so its label is kept short enough to fit a 360 px screen.
  shortLabel: string;
  icon: 'now' | 'queue' | 'search' | 'library' | 'settings';
}

// Lyrics are part of the Now Playing page, so they have no entry of their own.
export const navigationItems: NavItem[] = [
  {
    view: 'now-playing',
    label: 'Now Playing',
    shortLabel: 'Playing',
    icon: 'now',
  },
  { view: 'up-next', label: 'Up Next', shortLabel: 'Up Next', icon: 'queue' },
  { view: 'search', label: 'Search', shortLabel: 'Search', icon: 'search' },
  { view: 'library', label: 'Library', shortLabel: 'Library', icon: 'library' },
  {
    view: 'settings',
    label: 'Settings',
    shortLabel: 'Settings',
    icon: 'settings',
  },
];
