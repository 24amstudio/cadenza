import type { CastDisplay, CastPresentation } from '~/lib/protocol/types';

/** What a Remote says about a Cast device's screen. */
export function castDisplayLabel(display: CastDisplay): string {
  switch (display) {
    case 'none':
      return 'audio only';
    case 'display':
      return 'screen';
    case 'unknown':
      return 'capability unknown';
  }
}

/** The presentation mode the Mac's Settings chose. */
export function castPresentationLabel(presentation: CastPresentation): string {
  switch (presentation) {
    case 'auto':
      return 'Auto';
    case 'audio_only':
      return 'Audio Only';
    case 'full_suite':
      return 'Full Cadenza Suite';
  }
}
