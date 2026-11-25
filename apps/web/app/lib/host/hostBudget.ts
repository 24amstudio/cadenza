// Under constrained or survival pressure, the Host asks Remotes to hold back optional work: prefetching and log uploads.
export function hostUnderPressure(budget: string | null | undefined): boolean {
  return budget === 'constrained' || budget === 'survival';
}
