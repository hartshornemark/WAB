import type { AircraftD2Snapshot, AircraftD2HoldRow } from "./aircraft-d2";
import type { AircraftD4Snapshot } from "./aircraft-d4";
import type { AircraftD3Snapshot } from "./aircraft-d3";
import { aircraftD2Status } from "./aircraft-d2-status";
import { aircraftD4Status } from "./aircraft-d4-status";
import { aircraftD3ConfigurationStatus } from "./aircraft-d3-status";
import { balanceArmFromIndexPerWeightUnit, validIndexPerWeightUnitFormula } from "./index-per-weight-unit";

export type AircraftLayoutCalibration = {
  typeCode: string; subtype: string; length: number; noseArm: number;
  tailX: number; span: number; centreY: number; asset: string;
  cropLeft: number; cropRight: number; holdY: number; holdHeight: number;
  leftDoorY: number; rightDoorY: number; labelCharWidth: number;
  holdArmOffsets?: Readonly<Record<string, number>>;
  holdArmDefaults?: Readonly<Record<string, Readonly<{ from: number; to: number }>>>;
};

// Each outline has its own longitudinal and vertical calibration. Both vectors
// are plan views isolated from their Airbus general-arrangement DWGs; neither
// aircraft is produced by stretching the other outline.
export const A319_LAYOUT = {
  typeCode: "319", subtype: "100", length: 33.84, noseArm: 2.540,
  // The Airbus plan occupies x=137.4..330.3 after the engine-bounded crop.
  tailX: 330.3, span: 192.9, centreY: 375,
  asset: "/aircraft-layouts/a319-100-fuselage.svg?v=airbus-20260923",
  cropLeft: 102, cropRight: 338,
  holdY: 364, holdHeight: 22, leftDoorY: 359, rightDoorY: 389,
  labelCharWidth: 0.58,
} satisfies AircraftLayoutCalibration;
export const A320_LAYOUT = {
  typeCode: "320", subtype: "200", length: 37.57, noseArm: 0,
  // The Airbus plan occupies x=123.5..337.8 after the engine-bounded crop.
  tailX: 337.8, span: 214.3, centreY: 359.5,
  asset: "/aircraft-layouts/a320-200-fuselage.svg",
  cropLeft: 102, cropRight: 338,
  holdY: 348.5, holdHeight: 22, leftDoorY: 344, rightDoorY: 374,
  labelCharWidth: 0.58,
  // The isolated Airbus plan places the aft cargo bay group two AKH widths
  // farther aft than the longitudinal station overlay. Correct the drawing
  // only; the carrier's saved D2 balance-arm values remain authoritative.
  holdArmOffsets: { "3": -3.068, "4": -3.068, "5": -3.068 },
  // Physical hold boundaries established from the Airbus A320-200 general
  // arrangement drawing. They let every carrier use the global aircraft-type
  // layout when optional D2 From/To values have not been supplied.
  holdArmDefaults: {
    "1": { from: 7.255, to: 12.205 },
    "3": { from: 21.412, to: 24.480 },
    "4": { from: 24.480, to: 27.548 },
    "5": { from: 27.548, to: 31.212 },
  },
} satisfies AircraftLayoutCalibration;
export const AIRCRAFT_LAYOUTS = [A319_LAYOUT, A320_LAYOUT] as const;
export function aircraftLayoutFor(typeCode: string, subtype: string): AircraftLayoutCalibration | undefined {
  return AIRCRAFT_LAYOUTS.find(layout => layout.typeCode === typeCode && layout.subtype === subtype);
}
export function holdLayoutX(arm: number, aircraft: AircraftLayoutCalibration = A319_LAYOUT) {
  return aircraft.tailX - (arm - aircraft.noseArm) * aircraft.span / aircraft.length;
}
export function applicableHolds(d2: AircraftD2Snapshot) {
  return d2.rows.filter(r => r.holdType === "BLK" ? d2.bulkApplicable === true : d2.uldApplicable === true);
}
function effectiveHoldArms(row: AircraftD2HoldRow, aircraft: AircraftLayoutCalibration) {
  const from = row.balanceFrom, to = row.balanceTo;
  if (from !== null || to !== null) {
    return typeof from === "number" && Number.isFinite(from) && typeof to === "number" && Number.isFinite(to) && from < to
      ? { from, to } : null;
  }
  return aircraft.holdArmDefaults?.[row.name] ?? null;
}
export function holdLayoutUnavailable(d2: AircraftD2Snapshot): string | null {
  if (!d2.canView) return "You do not have permission to view the hold layout.";
  const aircraft = aircraftLayoutFor(d2.typeCode, d2.subtype);
  if (!aircraft)
    return "A calibrated aircraft outline is not yet available for this aircraft.";
  if (aircraftD2Status(d2) !== "configured") return "Complete all applicable D2 sections first.";
  const rows = applicableHolds(d2);
  if (!rows.length) return "No applicable holds are available.";
  for (const row of rows) {
    const arms = effectiveHoldArms(row, aircraft);
    if (!arms)
      return `Hold ${row.name}: no global aircraft-type boundary is available. Supply valid Balance Arm From and To values in D2 to draw its length.`;
    if (holdLayoutX(arms.to, aircraft) < aircraft.cropLeft || holdLayoutX(arms.from, aircraft) > aircraft.cropRight)
      return `Hold ${row.name} falls outside the calibrated hold view. Check its D2 limits.`;
  }
  return null;
}
export type LayoutSubdivision = {
  kind: "HOLD" | "COMPARTMENT" | "AREA" | "BAY"; id: string; compartmentId: string;
  uldType: string | null; maxWeight: number | null; maxVolume: number | null;
  x: number; width: number;
};
export type LayoutHold = AircraftD2HoldRow & { x: number; width: number; subdivisions: LayoutSubdivision[] };
export type LayoutDoor = { holdId: string; deckCode: string; x: number; width: number; orientation: "L" | "R" | "C" };
export type HoldLayout = {
  typeCode: string; subtype: string; doorsIncluded: boolean; usesGlobalHoldBoundaries: boolean;
  holds: LayoutHold[]; doors: LayoutDoor[]; decks: { code: string; name: string }[];
};
function fallbackSubdivisions(row: AircraftD2HoldRow, x: number, width: number): LayoutSubdivision[] {
  if (!row.compartments.length) return [{ kind: "HOLD", id: row.name, compartmentId: "", uldType: null,
    maxWeight: row.maxWeight, maxVolume: row.maxVolume, x, width }];
  return row.compartments.map((compartment, index) => ({ kind: "COMPARTMENT", id: compartment.id, compartmentId: compartment.id,
    uldType: null, maxWeight: null, maxVolume: null, x: x + width * index / row.compartments.length, width: width / row.compartments.length }));
}
export function buildHoldLayout(d2: AircraftD2Snapshot, d4: AircraftD4Snapshot, d3?: AircraftD3Snapshot): HoldLayout {
  const reason = holdLayoutUnavailable(d2);
  if (reason) throw new Error(reason);
  const aircraft = aircraftLayoutFor(d2.typeCode, d2.subtype)!;
  const applicable = applicableHolds(d2);
  const usesGlobalHoldBoundaries = applicable.some(row => row.balanceFrom === null && row.balanceTo === null && !!aircraft.holdArmDefaults?.[row.name]);
  const holds = applicable.map(row => {
    const arms = effectiveHoldArms(row, aircraft)!;
    const armOffset = aircraft.holdArmOffsets?.[row.name] ?? 0;
    const x = holdLayoutX(arms.to + armOffset, aircraft);
    const width = holdLayoutX(arms.from + armOffset, aircraft) - x;
    let subdivisions: LayoutSubdivision[] = [];
    if (row.holdType === "BLK") {
      const areas = row.compartments.flatMap(compartment => compartment.areas.map(area => {
        const centroid = validIndexPerWeightUnitFormula(d2.balanceFormula) && area.indexPerWeightUnit !== null
          ? balanceArmFromIndexPerWeightUnit(area.indexPerWeightUnit, d2.balanceFormula) : null;
        return { compartmentId: compartment.id, area, centroid };
      })).sort((a, b) => (b.centroid ?? 0) - (a.centroid ?? 0));
      const totalWeight = areas.reduce((sum, item) => sum + (item.area.maxWeight ?? 0), 0);
      let cursor = x;
      subdivisions = areas.map((item, index) => {
        const segmentWidth = index === areas.length - 1 ? x + width - cursor : totalWeight > 0 ? width * (item.area.maxWeight ?? 0) / totalWeight : width / areas.length;
        const result: LayoutSubdivision = { kind: "AREA", id: item.area.id, compartmentId: item.compartmentId, uldType: null,
          maxWeight: item.area.maxWeight, maxVolume: item.area.maxVolume, x: cursor, width: segmentWidth };
        cursor += segmentWidth;
        return result;
      });
      if (!subdivisions.length) subdivisions = fallbackSubdivisions(row, x, width);
    } else if (d3?.canView && d3.typeCode === d2.typeCode && d3.subtype === d2.subtype) {
      const configurations = d3.configurations.filter(configuration => configuration.holdId === row.name && aircraftD3ConfigurationStatus(configuration) === "configured");
      const selected = configurations.find(configuration => configuration.description?.trim().toUpperCase() === "DEFAULT")
        ?? configurations.find(configuration => configuration.code.trim().toUpperCase() === "DEFAULT") ?? configurations[0];
      const bays = selected?.rows.filter(position => position.rowType === "POSITION")
        .sort((a, b) => (b.balanceCentroid ?? 0) - (a.balanceCentroid ?? 0)) ?? [];
      subdivisions = bays.map((position, index) => ({ kind: "BAY", id: position.positionId, compartmentId: position.compartmentId!, uldType: position.uldType,
        maxWeight: position.maxWeight, maxVolume: position.volume, x: x + width * index / bays.length, width: width / bays.length }));
      if (!subdivisions.length) subdivisions = fallbackSubdivisions(row, x, width);
    } else {
      subdivisions = fallbackSubdivisions(row, x, width);
    }
    return { ...row, balanceFrom: arms.from, balanceTo: arms.to, x, width, subdivisions };
  });
  const sameAircraft = d2.typeCode === d4.typeCode && d2.subtype === d4.subtype;
  // D4 must be configured, and each applicable hold must have its own door.
  const doorsIncluded = d4.canView && sameAircraft && aircraftD4Status(d4) === "configured" && holds.every(h => d4.doors.some(d => d.holdId === h.name));
  const doors: LayoutDoor[] = [];
  if (doorsIncluded) for (const hold of holds) {
    const door = d4.doors.find(d => d.holdId === hold.name)!;
    const from = door.forwardArm!, to = door.aftArm!;
    // A door provides access to its associated hold, but the opening does not
    // have to lie inside that hold's D2 balance-arm limits. Keep the geometric
    // checks to the calibrated aircraft outline and let D4 own range validity.
    if (from >= to || holdLayoutX(to, aircraft) < aircraft.cropLeft || holdLayoutX(from, aircraft) > aircraft.cropRight)
      throw new Error(`Door ${hold.name}: its D4 Start/End values fall outside the calibrated aircraft view. Check D4 before viewing the layout.`);
    doors.push({ holdId: hold.name, deckCode: hold.deckCode, x: holdLayoutX(to, aircraft), width: holdLayoutX(from, aircraft) - holdLayoutX(to, aircraft), orientation: door.orientation! });
  }
  return { typeCode: d2.typeCode, subtype: d2.subtype, holds, doors, doorsIncluded, usesGlobalHoldBoundaries,
    decks: [...new Set(holds.map(h => h.deckCode))].map(code => ({ code, name: d2.deckTypes.find(d => d.code === code)?.name ?? code })) };
}
