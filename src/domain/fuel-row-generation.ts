export type FuelRange = {start: string; last: string; increment: string; includeLast: boolean};
export function fuelRowGeneration(range: FuelRange, existingWeights: number[]) {
  const read = (value: string, label: string) => {
    const n = Number(value);
    if (!value.trim() || !Number.isSafeInteger(n) || n < 0 || n > 1_000_000_000)
      throw new Error(`${label} must be a whole number between 0 and 1,000,000,000.`);
    return n;
  };
  const start = read(range.start, "Start Weight"), last = read(range.last, "Last Generated Weight"), increment = read(range.increment, "Increment");
  if (!increment) throw new Error("Increment must be greater than zero.");
  if (last < start) throw new Error("Last Generated Weight must be at least Start Weight.");
  const offStep = (last - start) % increment !== 0;
  const count = Math.floor((last - start) / increment) + 1;
  if (count + (offStep && range.includeLast ? 1 : 0) > 1000)
    throw new Error("Generate up to 1,000 rows at a time. Increase the increment or reduce the range.");
  const weights = Array.from({length: count}, (_, i) => start + i * increment);
  if (offStep && range.includeLast) weights.push(last);
  const existing = new Set(existingWeights);
  const added = weights.filter(weight => !existing.has(weight));
  return {weights: added, skipped: weights.length - added.length, offStep, first: weights[0], last: weights[weights.length - 1]};
}
export function mergeFuelRows<T extends {fuelWeight: number}>(rows: T[], weights: number[], create: (weight: number) => T): T[] {
  const existing = new Set(rows.map(row => row.fuelWeight));
  const added: T[] = [];
  for (const weight of weights) if (!existing.has(weight)) { existing.add(weight); added.push(create(weight)); }
  return [...rows, ...added].sort((a,b) => (Number.isFinite(a.fuelWeight) ? a.fuelWeight : Infinity) - (Number.isFinite(b.fuelWeight) ? b.fuelWeight : Infinity));
}
