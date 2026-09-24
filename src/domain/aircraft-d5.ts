export type CabinArea = {
  id: string;
  deck: string;
  startRow: number | null;
  endRow: number | null;
  centroid: number | null;
  startArm: number | null;
  endArm: number | null;
  index: number | null;
};

export type CrewLocation = {
  id: string;
  description: string;
  seats: number | null;
  centroid: number | null;
  index: number | null;
};

import {
  balanceArmFromIndexPerWeightUnit,
  validIndexPerWeightUnitFormula,
  type IndexPerWeightUnitFormula,
} from "@/domain/index-per-weight-unit";

export type AircraftD5Snapshot = {
  canView: boolean;
  canEdit: boolean;
  revision: string;
  typeCode: string;
  subtype: string;
  excludedRows: number[];
  cabinAreas: CabinArea[];
  flightDeckLocations: CrewLocation[];
  cabinCrewLocations: CrewLocation[];
  balanceFormula?: IndexPerWeightUnitFormula | null;
};

export type D5Section = "excludedRows" | "cabinAreas" | "flightDeckLocations" | "cabinCrewLocations";

export class AircraftD5Invalid extends Error {}
export class AircraftD5Denied extends Error {}
export class AircraftD5Conflict extends Error {}

const text = (value: unknown, label: string, max: number) => {
  const result = String(value ?? "").trim().toUpperCase();
  if (!result || result.length > max) {
    throw new AircraftD5Invalid(`Enter a valid ${label}.`);
  }
  return result;
};

const optionalNum = (value: unknown, label: string) => {
  if (value === null || value === undefined || value === "") return null;
  return num(value, label);
};

const num = (value: unknown, label: string, positive = false) => {
  const result = typeof value === "number" ? value : Number(value);
  if (
    value === null ||
    value === "" ||
    typeof value === "boolean" ||
    !Number.isFinite(result) ||
    Math.abs(result) > 1e9 ||
    (positive && result <= 0)
  ) {
    throw new AircraftD5Invalid(`Enter a valid ${label}.`);
  }
  return result;
};

export function validateExcludedRowsAgainstCabinAreas(excludedRows:number[],areas:CabinArea[]){
  for(const rowNumber of excludedRows){
    if(!areas.some(area=>area.startRow!==null&&area.endRow!==null&&rowNumber>=area.startRow&&rowNumber<=area.endRow)){
      throw new AircraftD5Invalid(`Excluded Row ${rowNumber} is outside every Cabin Area range.`);
    }
  }
  for(const area of areas){
    if(area.startRow!==null&&area.endRow!==null&&Array.from({length:area.endRow-area.startRow+1},(_,i)=>area.startRow!+i).every(row=>excludedRows.includes(row))){
      throw new AircraftD5Invalid(`Cabin Area ${area.id} must retain at least one row.`);
    }
  }
}

export function validateD5Section(
  section: D5Section,
  input: unknown,
  formula?: IndexPerWeightUnitFormula | null,
) {
  if (section === "excludedRows") {
    if (!Array.isArray(input)) throw new AircraftD5Invalid("Check the excluded row numbers.");
    const rows = input.map((value, index) => {
      const rowNumber = num(value, `Excluded Row Number at row ${index + 1}`, true);
      if (!Number.isInteger(rowNumber) || rowNumber > 99) {
        throw new AircraftD5Invalid("Excluded Row Numbers must be whole numbers from 1 to 99.");
      }
      return rowNumber;
    });
    if (new Set(rows).size !== rows.length) {
      throw new AircraftD5Invalid("An Excluded Row Number is entered more than once.");
    }
    return rows.sort((a, b) => a - b);
  }

  if (!Array.isArray(input) || input.length < 1) {
    throw new AircraftD5Invalid("Add at least one complete row.");
  }

  if (section === "cabinAreas") {
    const rows = input.map((value, index) => {
      const row = value as Partial<CabinArea>;
      const startRow = num(row.startRow, `Start Row at row ${index + 1}`, true);
      const endRow = num(row.endRow, `End Row at row ${index + 1}`, true);
      const startArm = optionalNum(row.startArm, `Balance Arm From at row ${index + 1}`);
      const endArm = optionalNum(row.endArm, `Balance Arm To at row ${index + 1}`);
      const indexPerWeightUnit = optionalNum(
        row.index,
        `Index per Weight Unit at row ${index + 1}`,
      );

      if (!Number.isInteger(startRow) || !Number.isInteger(endRow) || startRow > endRow) {
        throw new AircraftD5Invalid(`Row ${index + 1}: enter a valid row range.`);
      }
      if (indexPerWeightUnit === null) {
        throw new AircraftD5Invalid(
          `Row ${index + 1}: enter Index per Weight Unit.`,
        );
      }
      if (!validIndexPerWeightUnitFormula(formula)) {
        throw new AircraftD5Invalid(
          `Row ${index + 1}: configure C4 before calculating Balance Arm Centroid.`,
        );
      }
      const centroid = balanceArmFromIndexPerWeightUnit(indexPerWeightUnit, formula);
      if ((startArm === null) !== (endArm === null)) {
        throw new AircraftD5Invalid(
          `Row ${index + 1}: complete both Balance Arm From and To, or leave both blank.`,
        );
      }
      if (startArm !== null && endArm !== null && (startArm > centroid || centroid > endArm)) {
        throw new AircraftD5Invalid(
          `Row ${index + 1}: Balance Arm must follow From ≤ Centroid ≤ To.`,
        );
      }

      return {
        id: text(row.id, `Area ID at row ${index + 1}`, 2),
        deck: text(row.deck, `Deck at row ${index + 1}`, 5),
        startRow,
        endRow,
        centroid,
        startArm,
        endArm,
        index: indexPerWeightUnit,
      };
    });

    const areaIds = new Set<string>();
    for (const row of rows) {
      if (areaIds.has(row.id)) {
        throw new AircraftD5Invalid(`Cabin Area ${row.id} is entered more than once.`);
      }
      areaIds.add(row.id);
    }

    const byStartRow = [...rows].sort((a, b) => a.startRow - b.startRow);
    for (let index = 1; index < byStartRow.length; index += 1) {
      if (byStartRow[index].startRow <= byStartRow[index - 1].endRow) {
        throw new AircraftD5Invalid(
          "Cabin Area row ranges must not overlap. Missing row numbers are permitted.",
        );
      }
    }

    return rows;
  }

  return input.map((value, index) => {
    const row = value as Partial<CrewLocation>;
    const seats = num(row.seats, `Number of Seats at row ${index + 1}`, true);
    if (!Number.isInteger(seats)) {
      throw new AircraftD5Invalid(`Row ${index + 1}: Number of Seats must be a whole number.`);
    }
    const description = String(row.description ?? "").trim().slice(0, 64);
    if (!description) {
      throw new AircraftD5Invalid(`Enter a Description at row ${index + 1}.`);
    }
    const indexPerWeightUnit = num(
      row.index,
      `Index per Weight Unit at row ${index + 1}`,
    );
    if (!validIndexPerWeightUnitFormula(formula)) {
      throw new AircraftD5Invalid(
        `Row ${index + 1}: configure C4 before calculating Balance Arm Centroid.`,
      );
    }
    return {
      id: text(row.id, `Location ID at row ${index + 1}`, 3),
      description,
      seats,
      centroid: balanceArmFromIndexPerWeightUnit(indexPerWeightUnit, formula),
      index: indexPerWeightUnit,
    };
  });
}
