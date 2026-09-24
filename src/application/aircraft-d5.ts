import { aircraftC4Status } from "@/domain/aircraft-c4-status";
import {
  AircraftD5Conflict,
  AircraftD5Denied,
  type AircraftD5Snapshot,
  type CabinArea,
  type D5Section,
  validateExcludedRowsAgainstCabinAreas,
  validateD5Section,
} from "@/domain/aircraft-d5";
import type { IndexPerWeightUnitFormula } from "@/domain/index-per-weight-unit";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import type { AuthService } from "@/ports/auth-service";
import type { AircraftC4Repository } from "@/ports/aircraft-c4-repository";
import type { AircraftD5Repository } from "@/ports/aircraft-d5-repository";
import type { CarrierRepository } from "@/ports/carrier-repository";

export function createAircraftD5(
  auth: AuthService,
  carriers: CarrierRepository,
  repo: AircraftD5Repository,
  c4Repo: AircraftC4Repository,
) {
  async function check(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }

  async function context(iata: string, typeCode: string, subtype: string) {
    const [current, c4] = await Promise.all([
      repo.get(iata, typeCode, subtype),
      c4Repo.get(iata, typeCode, subtype),
    ]);
    const balanceFormula: IndexPerWeightUnitFormula | null =
      aircraftC4Status(c4) === "configured"
        ? { referenceArm: c4.values.referenceArm, constantC: c4.values.constantC }
        : null;
    return { current, balanceFormula };
  }

  const enrich = (
    snapshot: AircraftD5Snapshot,
    balanceFormula: IndexPerWeightUnitFormula | null,
  ): AircraftD5Snapshot => ({ ...snapshot, balanceFormula });

  return {
    async get(iata: string, typeCode: string, subtype: string) {
      await check(iata);
      const { current, balanceFormula } = await context(iata, typeCode, subtype);
      return enrich(current, balanceFormula);
    },
    async save(
      iata: string,
      typeCode: string,
      subtype: string,
      revision: string,
      section: D5Section,
      values: unknown,
    ) {
      await check(iata);
      const { current, balanceFormula } = await context(iata, typeCode, subtype);
      if (!current.canEdit) throw new AircraftD5Denied();
      if (current.revision !== revision) throw new AircraftD5Conflict();
      const validated = validateD5Section(section, values, balanceFormula);
      if(section === "excludedRows") validateExcludedRowsAgainstCabinAreas(validated as number[],current.cabinAreas);
      if(section === "cabinAreas") validateExcludedRowsAgainstCabinAreas(current.excludedRows,validated as CabinArea[]);
      const saved = await repo.save(
        iata,
        typeCode,
        subtype,
        revision,
        section,
        validated,
      );
      return enrich(saved, balanceFormula);
    },
  };
}
