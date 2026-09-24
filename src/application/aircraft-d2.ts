import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { AircraftD2Conflict, AircraftD2Denied, validateAircraftD2Section, type AircraftD2Section, type AircraftD2Snapshot } from "@/domain/aircraft-d2";
import { aircraftC4Status } from "@/domain/aircraft-c4-status";
import type { IndexPerWeightUnitFormula } from "@/domain/index-per-weight-unit";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { AircraftD2Repository } from "@/ports/aircraft-d2-repository";
import type { AircraftC4Repository } from "@/ports/aircraft-c4-repository";

export function createAircraftD2(auth: AuthService, carriers: CarrierRepository, repo: AircraftD2Repository, c4Repo: AircraftC4Repository) {
  async function check(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  async function context(iata: string, typeCode: string, subtype: string) {
    const [current, c4] = await Promise.all([repo.get(iata, typeCode, subtype), c4Repo.get(iata, typeCode, subtype)]);
    const balanceFormula: IndexPerWeightUnitFormula | null = aircraftC4Status(c4) === "configured" ? { referenceArm: c4.values.referenceArm, constantC: c4.values.constantC } : null;
    return { current, balanceFormula };
  }
  const enrich = (snapshot: AircraftD2Snapshot, balanceFormula: IndexPerWeightUnitFormula | null): AircraftD2Snapshot => ({ ...snapshot, balanceFormula });
  return {
    async get(iata: string, typeCode: string, subtype: string) {
      await check(iata);
      const { current, balanceFormula } = await context(iata, typeCode, subtype);
      return enrich(current, balanceFormula);
    },
    async save(iata: string, typeCode: string, subtype: string, revision: string, section: AircraftD2Section, values: unknown) {
      await check(iata);
      const { current, balanceFormula } = await context(iata, typeCode, subtype);
      if (!current.canEdit) throw new AircraftD2Denied();
      if (current.revision !== revision) throw new AircraftD2Conflict();
      return enrich(await repo.save(iata, typeCode, subtype, revision, section, validateAircraftD2Section(section, values, current.deckTypes)), balanceFormula);
    },
  };
}
