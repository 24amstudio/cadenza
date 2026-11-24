const releasePattern = /^(\d+)\.(\d+)\.(\d+)(?:_(\d{8})\.(\d+))?/;

// Version, then the UTC build date and build number when the release carries them.
function releaseFields(value: string): number[] {
  const match = releasePattern.exec(value);

  if (!match) return [0, 0, 0, 0, 0];

  return [match[1], match[2], match[3], match[4] ?? '0', match[5] ?? '0'].map(
    Number,
  );
}

/** True when `current` is an older release than `other`. A value that does not parse counts as the oldest. */
export function isOlderRelease(current: string, other: string): boolean {
  const next = releaseFields(other);

  const fields = releaseFields(current);

  for (const [index, field] of fields.entries()) {
    const target = next[index] ?? 0;

    if (field !== target) return field < target;
  }

  return false;
}
