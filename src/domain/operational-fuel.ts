import { macPercentForIndex } from "@/domain/aircraft-balance-formula";
import type { AircraftC4Values } from "@/domain/aircraft-c4";
import type { AircraftC5Phase, AircraftC5Values, EnvelopeBoundary } from "@/domain/aircraft-c5";

export type OperationalFuelInput = {
  configurationCode: string | null;
  specificGravity: number;
  blockFuel: number;
  taxiFuel: number;
  tripFuel: number;
  finalise: boolean;
};

export type OperationalFuelPlan = {
  version: number;
  status: "EMPTY" | "PRELIMINARY" | "FINAL";
  configurationCode: string | null;
  specificGravity: number | null;
  blockFuel: number | null;
  taxiFuel: number | null;
  tripFuel: number | null;
  takeOffFuel: number | null;
  landingFuel: number | null;
  updatedAt: string | null;
};

export type FuelCurvePoint = { fuelWeight: number; indexValue: number };
export type FuelledBalancePoint = { weight: number; indexValue: number; macValue: number };
export type OperationalFuelEffect = {
  ramp: FuelledBalancePoint;
  takeOff: FuelledBalancePoint;
  landing: FuelledBalancePoint;
  takeOffFuel: number;
  landingFuel: number;
};
export type FinalPayloadCapability = {
  maximumAllowableTrafficLoad: number;
  allowedTrafficLoad: number;
  acceptedCargoWeight: number;
  actualTrafficLoad: number;
  operationalUnderload: number;
  limitingFactor: string;
};

export class OperationalFuelInvalid extends Error {}

export const envelopeBoundaryConfigured = (boundary: EnvelopeBoundary | null | undefined) =>
  Boolean(boundary && boundary.fwd.length >= 2 && boundary.aft.length >= 2);

export function operationalEnvelopeConfigured(values: AircraftC5Values, phase: AircraftC5Phase) {
  if (values.envelopeModes?.[phase] !== "CONDITIONAL") return envelopeBoundaryConfigured(values.envelopes[phase]);
  return (values.conditionalEnvelopes?.[phase] ?? []).some((item) => envelopeBoundaryConfigured(item.boundary));
}

const whole = (value: unknown, label: string, positive = false) => {
  const result = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(result) || result < (positive ? 1 : 0) || result > 1_000_000) {
    throw new OperationalFuelInvalid(`Enter a valid whole-number ${label}.`);
  }
  return result;
};

export function validateOperationalFuelInput(value: unknown): OperationalFuelInput {
  const row = value as Record<string, unknown>;
  const configurationCode = String(row.configurationCode ?? "").trim().toUpperCase() || null;
  if (configurationCode && !/^[A-Z0-9]{1,12}$/.test(configurationCode)) throw new OperationalFuelInvalid("Select a valid fuel configuration.");
  const specificGravity = Number(row.specificGravity);
  if (!Number.isFinite(specificGravity) || specificGravity <= 0 || specificGravity > 2) throw new OperationalFuelInvalid("Select a valid fuel Specific Gravity.");
  const blockFuel = whole(row.blockFuel, "block fuel");
  const taxiFuel = whole(row.taxiFuel, "taxi fuel");
  const tripFuel = whole(row.tripFuel, "trip fuel");
  if (taxiFuel > blockFuel) throw new OperationalFuelInvalid("Taxi fuel cannot exceed block fuel.");
  const takeOffFuel = blockFuel - taxiFuel;
  if (tripFuel > takeOffFuel) throw new OperationalFuelInvalid("Trip fuel cannot exceed take-off fuel.");
  if (typeof row.finalise !== "boolean") throw new OperationalFuelInvalid("Select whether to save preliminary or final fuel data.");
  return { configurationCode, specificGravity, blockFuel, taxiFuel, tripFuel, finalise: row.finalise };
}

export function fuelIndexAtWeight(points: FuelCurvePoint[], fuelWeight: number) {
  const rows = [...points]
    .filter((point) => Number.isFinite(point.fuelWeight) && Number.isFinite(point.indexValue))
    .sort((left, right) => left.fuelWeight - right.fuelWeight);
  if (rows.length < 2 || fuelWeight < rows[0].fuelWeight || fuelWeight > rows.at(-1)!.fuelWeight) return null;
  const exact = rows.find((point) => point.fuelWeight === fuelWeight);
  if (exact) return exact.indexValue;
  const upperIndex = rows.findIndex((point) => point.fuelWeight > fuelWeight);
  const lower = rows[upperIndex - 1], upper = rows[upperIndex];
  return lower.indexValue + (upper.indexValue - lower.indexValue) * (fuelWeight - lower.fuelWeight) / (upper.fuelWeight - lower.fuelWeight);
}

export function calculateOperationalFuelEffect(input: {
  zfw: FuelledBalancePoint;
  blockFuel: number;
  taxiFuel: number;
  tripFuel: number;
  curve: FuelCurvePoint[];
  formula: AircraftC4Values;
}): OperationalFuelEffect {
  const clean = validateOperationalFuelInput({ ...input, specificGravity: 0.8, configurationCode: null, finalise: false });
  const takeOffFuel = clean.blockFuel - clean.taxiFuel, landingFuel = takeOffFuel - clean.tripFuel;
  const point = (fuelWeight: number): FuelledBalancePoint => {
    const fuelIndex = fuelIndexAtWeight(input.curve, fuelWeight);
    if (fuelIndex === null) throw new OperationalFuelInvalid(`The selected fuel curve does not cover ${fuelWeight.toLocaleString()} KG.`);
    const weight = input.zfw.weight + fuelWeight, indexValue = input.zfw.indexValue + fuelIndex;
    return { weight, indexValue, macValue: macPercentForIndex(weight, indexValue, input.formula) };
  };
  return { ramp: point(clean.blockFuel), takeOff: point(takeOffFuel), landing: point(landingFuel), takeOffFuel, landingFuel };
}

const boundaryIndex = (points: EnvelopeBoundary["fwd"], weight: number) => {
  const rows = [...points].sort((left, right) => left.weight - right.weight);
  if (rows.length < 2 || weight < rows[0].weight || weight > rows.at(-1)!.weight) return null;
  const exact = rows.find((point) => point.weight === weight);
  if (exact) return exact.indexValue;
  const upperIndex = rows.findIndex((point) => point.weight > weight), lower = rows[upperIndex - 1], upper = rows[upperIndex];
  return lower.indexValue + (upper.indexValue - lower.indexValue) * (weight - lower.weight) / (upper.weight - lower.weight);
};

export function operationalEnvelopeBoundary(values: AircraftC5Values, phase: AircraftC5Phase, fuelWeight: number, configurationCode: string | null) {
  if (values.envelopeModes?.[phase] !== "CONDITIONAL") return envelopeBoundaryConfigured(values.envelopes[phase]) ? values.envelopes[phase] : null;
  const candidates = (values.conditionalEnvelopes?.[phase] ?? []).filter((item) => !item.configurationCode || item.configurationCode === configurationCode);
  const boundary = candidates.find((item) => {
    const conditionFuel = item.conditionBasis === "TAKE_OFF_FUEL" || item.conditionBasis === "LANDING_FUEL" ? fuelWeight : null;
    if (conditionFuel === null) return false;
    const lower = item.lowerBound === null || (item.lowerInclusive ? conditionFuel >= item.lowerBound : conditionFuel > item.lowerBound);
    const upper = item.upperBound === null || (item.upperInclusive ? conditionFuel <= item.upperBound : conditionFuel < item.upperBound);
    return lower && upper;
  })?.boundary ?? null;
  return envelopeBoundaryConfigured(boundary) ? boundary : null;
}

export function balancePointWithinEnvelope(point: FuelledBalancePoint, boundary: EnvelopeBoundary | null) {
  if (!boundary) return null;
  const fwd = boundaryIndex(boundary.fwd, point.weight), aft = boundaryIndex(boundary.aft, point.weight);
  if (fwd === null || aft === null) return false;
  return point.indexValue >= Math.min(fwd, aft) && point.indexValue <= Math.max(fwd, aft);
}

export function calculateFinalPayloadCapability(input: {
  dryOperatingWeight: number;
  acceptedCargoWeight: number;
  nonCargoTrafficWeight: number;
  takeOffFuel: number;
  landingFuel: number;
  maximumWeights: AircraftC5Values["maximumWeights"];
}): FinalPayloadCapability {
  const structuralLimits = [
    { label: "MTOW", value: input.maximumWeights.tow - input.dryOperatingWeight - input.takeOffFuel },
    { label: "MLAW", value: input.maximumWeights.law - input.dryOperatingWeight - input.landingFuel },
    { label: "MZFW", value: input.maximumWeights.zfw - input.dryOperatingWeight },
  ];
  const limiting = structuralLimits.reduce((lowest, item) => item.value < lowest.value ? item : lowest);
  const maximumAllowableTrafficLoad = Math.max(0, Math.floor(limiting.value));
  const allowedTrafficLoad = maximumAllowableTrafficLoad;
  const actualTrafficLoad = input.nonCargoTrafficWeight + input.acceptedCargoWeight;
  return {
    maximumAllowableTrafficLoad,
    allowedTrafficLoad,
    acceptedCargoWeight: input.acceptedCargoWeight,
    actualTrafficLoad,
    operationalUnderload: allowedTrafficLoad - actualTrafficLoad,
    limitingFactor: limiting.label,
  };
}
