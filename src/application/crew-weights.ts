import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { CrewDenied, CrewInvalid, crewBodyValues, validateCrewHold } from "@/domain/crew-weights";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { CrewRepository } from "@/ports/crew-repository";
export function createCrewWeights(auth: AuthService, carriers: CarrierRepository, repository: CrewRepository) {
  async function check(iata: string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!iata || iata.length > 32 || !await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  return {
    async saveHold(iata:string,revision:string,code:string|null,input:unknown){
      await check(iata);const current=await repository.get(iata);
      if(!current.canEdit)throw new CrewDenied();
      if(!current.unit)throw new CrewInvalid("Choose and save the carrier’s weight unit on B1 first.");
      if(code!==null&&!current.variations?.some(v=>v.code===code))throw new CrewInvalid("This variation is no longer available. Reload B2.");
      return repository.saveHold(iata,revision,code,validateCrewHold(input,code));
    },
    async get(iata: string) { await check(iata); return repository.get(iata); },
    async save(iata: string, revision: string, input: unknown) {
      await check(iata);
      const current = await repository.get(iata);
      if (!current.canEdit) throw new CrewDenied();
      if (!current.unit) throw new CrewInvalid("Choose and save the carrier’s weight unit on B1 first.");
      const clean=crewBodyValues(input);
      if(current.exists&&(current.values.allFlights||current.values.longhaul||current.values.shorthaul)){
        for(const key of ["allFlights","longhaul","shorthaul","flightDeckOther","cabinOther","flightDeckLong","cabinLong","flightDeckShort","cabinShort"] as const)Object.assign(clean,{[key]:current.values[key]});
      }
      return repository.save(iata, revision, clean);
    },
  };
}
