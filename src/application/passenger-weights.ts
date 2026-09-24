import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { PassengerDenied, PassengerInvalid, validatePassengerValues, validatePassengerRows, validateVariations, type PassengerSection } from "@/domain/passenger-weights";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { PassengerRepository } from "@/ports/passenger-repository";
export function createPassengerWeights(auth: AuthService, carriers: CarrierRepository, repository: PassengerRepository) {
  async function check(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!iata || iata.length > 32 || !await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  return {
    async get(iata: string) { await check(iata); return repository.get(iata); },
    async save(iata: string, revision: string, section: PassengerSection, input: unknown) {
      await check(iata);
      const current = await repository.get(iata);
      if (!current.canEdit) throw new PassengerDenied();
      if (!["default","classes","variations"].includes(section)) throw new PassengerInvalid("Unknown section.");
      if (section !== "variations" && !current.unit) throw new PassengerInvalid("Save the weight unit on B1 first.");
      const values = section === "variations" ? validateVariations(input) : section === "classes" ? validatePassengerRows(input,current) : validatePassengerValues(input);
      return repository.save(iata,revision,section,values);
    },
  };
}
