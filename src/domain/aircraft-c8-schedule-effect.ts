import type { AircraftC4Values } from "@/domain/aircraft-c4";
import type { FuelLoadingSchedule, NonStandardFuelTank } from "@/domain/aircraft-c8";
import {
  indexPerWeightUnitFromBalanceArm,
  validIndexPerWeightUnitFormula,
} from "@/domain/index-per-weight-unit";

export type FuelScheduleEffectPoint = {
  step: number;
  weight: number;
  indexValue: number;
  balanceArm: number;
};

export type FuelScheduleEffect = {
  points: FuelScheduleEffectPoint[];
  error: string | null;
};

function balanceArmAtVolume(tank: NonStandardFuelTank, volume: number) {
  const points = tank.points
    .filter((point) => Number.isFinite(point.volume) && Number.isFinite(point.balanceArm))
    .sort((a, b) => a.volume - b.volume);

  if (points.length < 2 || volume < points[0].volume || volume > points.at(-1)!.volume) {
    return null;
  }

  const exact = points.find((point) => point.volume === volume);
  if (exact) return exact.balanceArm;

  const upperIndex = points.findIndex((point) => point.volume > volume);
  if (upperIndex < 1) return null;
  const lower = points[upperIndex - 1];
  const upper = points[upperIndex];
  const proportion = (volume - lower.volume) / (upper.volume - lower.volume);
  return lower.balanceArm + proportion * (upper.balanceArm - lower.balanceArm);
}

export function calculateFuelScheduleEffect(
  schedule: FuelLoadingSchedule,
  tanks: NonStandardFuelTank[],
  formula: AircraftC4Values | null,
): FuelScheduleEffect {
  if (!validIndexPerWeightUnitFormula(formula)) {
    return { points: [], error: "Complete C4 Formulae to calculate the fuel-loading effect." };
  }
  if (!Number.isFinite(schedule.specificGravity) || schedule.specificGravity <= 0) {
    return { points: [], error: "Enter the schedule Specific Gravity to calculate the fuel-loading effect." };
  }
  if (schedule.steps.length === 0) {
    return { points: [], error: "Add a loading step to calculate the fuel-loading effect." };
  }

  const tankByCode = new Map(tanks.map((tank) => [tank.tankShortCode, tank]));
  const tankVolumes = new Map<string, number>();
  const result: FuelScheduleEffectPoint[] = [];

  for (let stepIndex = 0; stepIndex < schedule.steps.length; stepIndex += 1) {
    const step = schedule.steps[stepIndex];
    if (!Number.isFinite(step.amount) || step.amount <= 0) {
      return { points: [], error: `Complete the amount at Step ${stepIndex + 1}.` };
    }
    if (step.tankCodes.length !== 1) {
      return {
        points: [],
        error: `Select one tank identity at Step ${stepIndex + 1}. A tank identity may represent a paired or grouped tank.`,
      };
    }

    const code = step.tankCodes[0];
    const tank = tankByCode.get(code);
    if (!tank) {
      return { points: [], error: `Tank ${code} at Step ${stepIndex + 1} is not defined.` };
    }

    const stepVolume = schedule.quantityBasis === "VOLUME"
      ? step.amount
      : step.amount / schedule.specificGravity;
    const calculatedVolume = (tankVolumes.get(code) ?? 0) + stepVolume;
    if (tank.maximumVolume !== null && calculatedVolume - tank.maximumVolume > 1 + Number.EPSILON) {
      return { points: [], error: `Step ${stepIndex + 1} exceeds the maximum Volume for tank ${code}.` };
    }
    // Published schedules commonly round each step to a whole volume unit. Allow
    // that accumulated rounding to exceed the tank maximum by one unit, then use
    // the exact tank maximum for the loading-effect calculation.
    const nextVolume = tank.maximumVolume !== null && calculatedVolume > tank.maximumVolume
      ? tank.maximumVolume
      : calculatedVolume;
    tankVolumes.set(code, nextVolume);

    let totalWeight = 0;
    let totalMoment = 0;
    let totalIndex = 0;
    for (const [loadedCode, loadedVolume] of tankVolumes) {
      const loadedTank = tankByCode.get(loadedCode)!;
      const arm = balanceArmAtVolume(loadedTank, loadedVolume);
      if (arm === null) {
        return {
          points: [],
          error: `The ${loadedCode} curve does not cover ${Math.ceil(loadedVolume)} Volume after Step ${stepIndex + 1}.`,
        };
      }
      const weight = loadedVolume * schedule.specificGravity;
      totalWeight += weight;
      totalMoment += weight * arm;
      totalIndex += weight * indexPerWeightUnitFromBalanceArm(arm, formula);
    }

    result.push({
      step: stepIndex + 1,
      weight: totalWeight,
      indexValue: totalIndex,
      balanceArm: totalMoment / totalWeight,
    });
  }

  return { points: result, error: null };
}
