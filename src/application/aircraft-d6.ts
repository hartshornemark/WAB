import { aircraftC4Status } from "@/domain/aircraft-c4-status";
import {
  AircraftD6Conflict,
  AircraftD6Denied,
  type AircraftD6Snapshot,
  type D6Section,
  validateD6Section,
} from "@/domain/aircraft-d6";
import type { IndexPerWeightUnitFormula } from "@/domain/index-per-weight-unit";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import type { AuthService } from "@/ports/auth-service";
import type { AircraftC4Repository } from "@/ports/aircraft-c4-repository";
import type { AircraftD6Repository } from "@/ports/aircraft-d6-repository";
import type { CarrierRepository } from "@/ports/carrier-repository";

export function createAircraftD6(
  auth: AuthService,
  carriers: CarrierRepository,
  repo: AircraftD6Repository,
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
    snapshot: AircraftD6Snapshot,
    balanceFormula: IndexPerWeightUnitFormula | null,
  ): AircraftD6Snapshot => ({ ...snapshot, balanceFormula });

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
      section: D6Section,
      applicable: boolean,
      values: unknown,
    ) {
      await check(iata);
      const { current, balanceFormula } = await context(iata, typeCode, subtype);
      if (!current.canEdit) throw new AircraftD6Denied();
      if (current.revision !== revision) throw new AircraftD6Conflict();
      const saved = await repo.save(
        iata,
        typeCode,
        subtype,
        revision,
        section,
        applicable,
        applicable ? validateD6Section(section, values, balanceFormula) : [],
      );
      return enrich(saved, balanceFormula);
    },
    async setApplicable(
      iata: string,
      typeCode: string,
      subtype: string,
      revision: string,
      section: D6Section,
      applicable: boolean,
    ) {
      await check(iata);
      const { current, balanceFormula } = await context(iata, typeCode, subtype);
      if (!current.canEdit) throw new AircraftD6Denied();
      if (current.revision !== revision) throw new AircraftD6Conflict();
      const saved = await repo.save(
        iata,
        typeCode,
        subtype,
        revision,
        section,
        applicable,
        [],
      );
      return enrich(saved, balanceFormula);
    },
  };
}
