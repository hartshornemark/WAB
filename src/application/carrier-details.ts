import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { DetailsDenied, validateDetails, type DetailValues } from "@/domain/carrier-details";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { CarrierDetailsRepository } from "@/ports/carrier-details-repository";
export function createCarrierDetails(auth: AuthService, carriers: CarrierRepository, details: CarrierDetailsRepository) {
  async function requireCarrier(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!iata || iata.length > 32 || !await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  return {
    async get(iata: string) { await requireCarrier(iata); return details.get(iata); },
    async save(iata: string, revision: string, input: DetailValues) {
      await requireCarrier(iata);
      if (!(await details.get(iata)).canEdit) throw new DetailsDenied();
      return details.save(iata, revision, validateDetails(input));
    },
  };
}
