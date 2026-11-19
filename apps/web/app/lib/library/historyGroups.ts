import type { HistoryEntry } from './history';

export interface HistoryGroup {
  key: string;
  label: string;
  entries: HistoryEntry[];
}

const dayFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });

const timeFormat = new Intl.DateTimeFormat(undefined, {
  hour: 'numeric',
  minute: '2-digit',
});

export function formatHistoryTime(at: number): string {
  return timeFormat.format(at);
}

// Entries are newest first, and so are the groups. Each local calendar day is one group, labelled Today, Yesterday, or
// its date.
export function groupHistory(
  entries: HistoryEntry[],
  now: Date,
): HistoryGroup[] {
  const todayStart = dayStart(now);

  const yesterdayStart = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate() - 1,
  ).getTime();

  const days = new Map<number, HistoryEntry[]>();

  for (const entry of entries) {
    const start = dayStart(new Date(entry.at));
    const day = days.get(start);

    if (day === undefined) days.set(start, [entry]);
    else day.push(entry);
  }

  return [...days].map(([start, dayEntries]) => ({
    key: String(start),
    label: dayLabel(start, todayStart, yesterdayStart),
    entries: dayEntries,
  }));
}

function dayStart(date: Date): number {
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
  ).getTime();
}

function dayLabel(start: number, today: number, yesterday: number): string {
  if (start === today) return 'Today';

  if (start === yesterday) return 'Yesterday';

  return dayFormat.format(start);
}
