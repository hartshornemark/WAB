/** Descriptive local-benchmark statistics; failed/unproved samples stay visible. */
export function distribution(values) {
  if (!values.every(v => typeof v === 'number' && Number.isFinite(v) && v >= 0)) throw Error('Invalid timing value.');
  const sorted = [...values].sort((a, b) => a - b), n = sorted.length;
  if (!n) return { samples: 0, minimum: null, median: null, p95: null, maximum: null };
  return { samples: n, minimum: sorted[0], median: n % 2 ? sorted[(n - 1) / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2,
    p95: sorted[Math.ceil(n * 0.95) - 1], maximum: sorted[n - 1] };
}

export function summariseMeasurement(report) {
  const cases = [...new Set(report.rows.map(r => r.caseId))], summary = [];
  for (const caseId of cases) for (const engine of ['database', 'solver']) for (const phase of ['cold', 'warm']) {
    const rows = report.rows.filter(r => r.caseId === caseId && r.engine === engine && r.phase === phase);
    const usable = rows.filter(r => r.outcome === 'VERIFIED' && (phase !== 'warm' || r.sessionReused));
    const metrics = Object.fromEntries(['calculationMilliseconds', 'completeRequestMilliseconds', 'workerStartupMilliseconds', 'workerRoundTripMilliseconds', 'inputMilliseconds', 'backendMilliseconds', 'validationMilliseconds', 'serverHandlerMilliseconds', 'serviceStartupMilliseconds'].map(key => [key, distribution((key === 'serviceStartupMilliseconds' && phase === 'warm' ? [] : usable.map(r => r[key])).filter(v => v !== null && v !== undefined))]));
    summary.push({ caseId, engine, phase, requested: phase === 'warm' ? report.repetitions.warmPerCase : report.repetitions.coldPerCase,
      recorded: rows.length, verified: usable.length, errors: rows.filter(r => r.outcome === 'ERROR').length,
      inconclusive: rows.filter(r => r.outcome === 'INCONCLUSIVE').length, mismatches: rows.filter(r => r.outcome === 'MISMATCH').length,
      warmSessionRestartsExcluded: rows.filter(r => phase === 'warm' && !r.sessionReused && r.outcome === 'VERIFIED').length, metrics });
  }
  return { scope: report.scope, percentileMethod: 'Median averages the two central values for even n; p95 is nearest rank ceil(0.95*n). With 10 warm samples, p95 is the observed maximum; with 3 cold samples, tails are descriptive only.',
    warmupsExcluded: report.rows.filter(r => r.phase === 'warmup').length,
    failures: report.rows.filter(r => r.outcome !== 'VERIFIED').map(r => ({ caseId: r.caseId, engine: r.engine, phase: r.phase, repetition: r.repetition, outcome: r.outcome, error: r.error, status: r.result?.status })),
    summary };
}
