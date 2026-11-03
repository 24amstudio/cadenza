<script setup lang="ts">
const session = useSessionStore();
const { selected } = useRouteState();
const colorMode = useColorMode();
const closePairingButton = ref<HTMLButtonElement | null>(null);
let previousFocus: HTMLElement | null = null;

watch(
  () => session.pairingVisible,
  async (visible) => {
    if (visible) {
      // SAFETY: the active element is the pairing trigger or another focusable control.
      previousFocus = document.activeElement as HTMLElement | null;
      await nextTick();
      closePairingButton.value?.focus();
    } else {
      previousFocus?.focus();
      previousFocus = null;
    }
  },
);

function useRouteState() {
  const selected = ref<'now-playing' | 'queue' | 'lyrics' | 'settings'>(
    'now-playing',
  );

  return { selected };
}

const navItems = [
  { id: 'now-playing' as const, label: 'Now Playing', icon: '◉' },
  { id: 'queue' as const, label: 'Queue', icon: '≡' },
  { id: 'lyrics' as const, label: 'Lyrics', icon: '♫' },
  { id: 'settings' as const, label: 'Settings', icon: '⌘' },
];

const formattedPosition = computed(() =>
  formatTime(session.snapshot.positionSeconds),
);

const formattedDuration = computed(() =>
  formatTime(session.snapshot.current?.durationSeconds ?? 0),
);

const themeLabel = computed(() =>
  colorMode.preference === 'system'
    ? 'System theme'
    : colorMode.preference === 'light'
      ? 'Switch to dark theme'
      : 'Switch to light theme',
);

function cycleTheme() {
  colorMode.preference =
    colorMode.preference === 'dark'
      ? 'light'
      : colorMode.preference === 'light'
        ? 'system'
        : 'dark';
}

function formatTime(value: number) {
  const minutes = Math.floor(value / 60);

  const seconds = Math.floor(value % 60)
    .toString()
    .padStart(2, '0');

  return `${minutes}:${seconds}`;
}
</script>

<template>
  <div class="app-shell">
    <aside class="sidebar" aria-label="Primary navigation">
      <div class="brand">
        <span class="brand-mark">C</span><span>Cadenza</span>
      </div>
      <div class="sidebar-section">
        <nav class="nav-list">
          <button
            v-for="item in navItems"
            :key="item.id"
            class="nav-item"
            :class="{ active: selected === item.id }"
            type="button"
            @click="selected = item.id"
          >
            <span class="nav-icon" aria-hidden="true">{{ item.icon }}</span
            ><span>{{ item.label }}</span>
            <span v-if="item.id === 'queue'" class="nav-count">2</span>
          </button>
        </nav>
      </div>
      <div class="sidebar-footer">
        <div class="host-card">
          <span
            class="status-dot"
            :class="session.state"
            aria-hidden="true"
          ></span>
          <div>
            <strong>Cadenza Host</strong
            ><small>{{ session.status.detail }}</small>
          </div>
          <button class="more-button" aria-label="Host options" type="button">
            •••
          </button>
        </div>
        <button class="profile-button" type="button">
          <span class="avatar">M</span
          ><span><strong>Mia</strong><small>Web remote</small></span
          ><span class="chevron">⌄</span>
        </button>
      </div>
    </aside>

    <main class="main-content">
      <header class="topbar">
        <div class="mobile-brand"><span class="brand-mark">C</span>Cadenza</div>
        <div class="connection-pill" :class="session.state">
          <span class="status-dot" aria-hidden="true"></span
          >{{
            session.state === 'connected'
              ? session.status.label
              : session.state === 'unreachable'
                ? 'Host unreachable'
                : 'Connecting'
          }}
        </div>
        <button
          class="icon-button"
          type="button"
          aria-label="Pair this browser"
          @click="session.openPairing"
        >
          <span aria-hidden="true">⌁</span>
        </button>
        <button
          class="icon-button"
          type="button"
          :aria-label="themeLabel"
          @click="cycleTheme"
        >
          <span aria-hidden="true">◐</span>
        </button>
        <button
          class="icon-button"
          type="button"
          aria-label="Open settings"
          @click="selected = 'settings'"
        >
          <span aria-hidden="true">⚙</span>
        </button>
      </header>

      <section
        v-if="session.state === 'unreachable'"
        class="unreachable-state"
        aria-labelledby="unreachable-title"
      >
        <div class="state-icon">⌁</div>
        <h1 id="unreachable-title">Cadenza Host is unreachable</h1>
        <p>
          Make sure Cadenza is open and your device is on the same local
          network. The remote will reconnect when the Host is available.
        </p>
        <button
          class="primary-button"
          type="button"
          @click="session.state = 'connected'"
        >
          Try again
        </button>
      </section>

      <template v-else>
        <section class="hero-grid" aria-labelledby="now-playing-title">
          <div class="artwork-wrap">
            <img
              class="hero-artwork"
              :src="session.snapshot.current?.artwork"
              alt="Colorful concert lights for the current song"
            /><span class="artwork-shine" aria-hidden="true"></span>
          </div>
          <div class="now-playing-copy">
            <h1 id="now-playing-title">
              {{ session.snapshot.current?.title }}
            </h1>
            <p class="artist">
              {{ session.snapshot.current?.artist }} <span>·</span>
              {{ session.snapshot.current?.album }}
            </p>
            <div class="progress-block">
              <div
                class="progress-track"
                role="progressbar"
                :aria-valuenow="Math.round(session.progress)"
                aria-valuemin="0"
                aria-valuemax="100"
              >
                <span :style="{ width: `${session.progress}%` }"></span>
              </div>
              <div class="time-row">
                <span>{{ formattedPosition }}</span
                ><span>{{ formattedDuration }}</span>
              </div>
            </div>
            <div class="controls">
              <button
                class="control-button"
                type="button"
                aria-label="Previous track"
              >
                |◀</button
              ><button
                class="play-button"
                type="button"
                :aria-label="session.snapshot.isPlaying ? 'Pause' : 'Play'"
                @click="session.togglePlayback"
              >
                <span v-if="session.isBusy" class="spinner"></span
                ><span v-else>{{
                  session.snapshot.isPlaying ? 'Ⅱ' : '▶'
                }}</span></button
              ><button
                class="control-button"
                type="button"
                aria-label="Next track"
              >
                ▶|</button
              ><button
                class="favorite-button"
                type="button"
                aria-label="Add to favorites"
              >
                ♡
              </button>
            </div>
          </div>
        </section>

        <section class="lower-grid">
          <div class="panel queue-panel">
            <div class="panel-heading">
              <div>
                <h2>
                  Queue <span>· {{ session.snapshot.queue.length }}</span>
                </h2>
              </div>
              <button
                class="text-button"
                type="button"
                @click="selected = 'queue'"
              >
                View all <span>→</span>
              </button>
            </div>
            <div class="queue-list">
              <article
                v-for="item in session.snapshot.queue"
                :key="item.requestId"
                class="queue-row"
              >
                <img :src="item.artwork" :alt="`${item.title} artwork`" />
                <div class="queue-meta">
                  <strong>{{ item.title }}</strong
                  ><span>{{ item.artist }}</span>
                </div>
                <div class="queue-wait">
                  <span>{{ item.waitLabel }}</span
                  ><small>{{ item.requester }}</small>
                </div>
                <button
                  class="more-button"
                  :aria-label="`More options for ${item.title}`"
                  type="button"
                >
                  •••
                </button>
              </article>
            </div>
          </div>
          <div class="panel lyrics-panel">
            <div class="panel-heading">
              <div>
                <h2>Lyrics</h2>
              </div>
              <button
                class="text-button"
                type="button"
                @click="selected = 'lyrics'"
              >
                Open <span>↗</span>
              </button>
            </div>
            <div class="lyrics-preview">
              <p class="faded-line">I was doing fine without you</p>
              <p class="active-line">Till I saw your face, now I can't erase</p>
              <p class="faded-line">Giving in to all your games</p>
              <span class="lyrics-rule"></span
              ><span class="timed-badge">Timed lyrics</span>
            </div>
          </div>
        </section>
      </template>
      <footer class="transport-footer">
        <span
          ><span class="status-dot" aria-hidden="true"></span
          >{{ session.status.label }} <small>· Direct connection</small></span
        ><button
          type="button"
          class="transport-link"
          @click="session.setUnreachable"
        >
          Connection details
        </button>
      </footer>
    </main>
    <div
      v-if="session.pairingVisible"
      class="modal-backdrop"
      role="presentation"
      @click.self="session.pairingVisible = false"
    >
      <section
        class="pairing-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="pairing-title"
      >
        <button
          ref="closePairingButton"
          class="modal-close"
          type="button"
          aria-label="Close pairing dialog"
          @click="session.pairingVisible = false"
        >
          ×
        </button>
        <div class="pairing-code" aria-hidden="true">
          <span
            v-for="cell in 49"
            :key="cell"
            :class="{ filled: (cell * 17) % 7 < 3 }"
          ></span>
        </div>
        <h2 id="pairing-title">Pair this browser</h2>
        <p>
          Open Web remote on your Cadenza Host and scan this one-use invitation.
          The invitation expires after five minutes and never contains a private
          key.
        </p>
        <div
          v-if="session.pairingState === 'scanning'"
          class="pairing-pending"
          role="status"
        >
          <span class="spinner"></span> Waiting for the Host…
        </div>
        <div
          v-else-if="session.pairingState === 'paired'"
          class="pairing-success"
          role="status"
        >
          Browser paired successfully
        </div>
        <button
          v-else
          class="primary-button pairing-action"
          type="button"
          @click="session.pairBrowser"
        >
          Start pairing
        </button>
      </section>
    </div>
    <div v-if="session.toast" class="toast" role="status">
      {{ session.toast }}
    </div>
  </div>
</template>
