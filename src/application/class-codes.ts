import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { ClassDenied, validateClasses } from "@/domain/class-codes";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { ClassRepository } from "@/ports/class-repository";
export function createClassCodes(auth: AuthService, carriers: CarrierRepository, repository: ClassRepository) {
  async function check(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!iata || iata.length > 32 || !await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  return {
    async get(iata: string) { await check(iata); return repository.get(iata); },
    async save(iata: string, revision: string, input: unknown) {
      await check(iata);
      if (!(await repository.get(iata)).canEdit) throw new ClassDenied();
      return repository.save(iata, revision, validateClasses(input));
    },
  };
}
