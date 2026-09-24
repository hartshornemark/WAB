import type { AircraftC4Values } from "@/domain/aircraft-c4";

/** Convert a Weight and Index pair to % MAC using the configured C4 formula. */
export function macPercentForIndex(weight: number, index: number, formula: AircraftC4Values) {
  const balanceArm = formula.constantC * (index - formula.constantK) / weight + formula.referenceArm;
  return (balanceArm - formula.lemacLerc) / formula.macRcLength * 100;
}

/** Convert a Weight and constant % MAC line to its corresponding Index value. */
export function indexForMacPercent(weight: number, macPercent: number, formula: AircraftC4Values) {
  const balanceArm = formula.lemacLerc + formula.macRcLength * macPercent / 100;
  return weight * (balanceArm - formula.referenceArm) / formula.constantC + formula.constantK;
}
