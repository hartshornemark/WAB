import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { CommodityDenied, validateCommodities } from "@/domain/commodity-codes";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { CommodityRepository } from "@/ports/commodity-repository";
export function createCommodityCodes(auth: AuthService, carriers: CarrierRepository, repository: CommodityRepository) {
  async function check(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!iata || iata.length > 32 || !await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  return {
    async get(iata: string) { await check(iata); return repository.get(iata); },
    async save(iata: string, revision: string, input: unknown) {
      await check(iata);
      if (!(await repository.get(iata)).canEdit) throw new CommodityDenied();
      return repository.save(iata, revision, validateCommodities(input));
    },
  };
}
