import {AuthenticationRequired} from "@/domain/models";
import {CarrierCreationDenied,validateNewCarrier,type NewCarrierInput} from "@/domain/carrier-onboarding";
import type{AuthService}from"@/ports/auth-service";
import type{CarrierAdministrationRepository}from"@/ports/carrier-administration-repository";
export function createCarrierAdministration(auth:AuthService,repo:CarrierAdministrationRepository){
  async function requireUser(){const user=await auth.currentUser();if(!user)throw new AuthenticationRequired();return user}
  return{
    async access(){const user=await requireUser();return{user,canCreate:await repo.canCreate()}},
    async create(input:NewCarrierInput){await requireUser();if(!await repo.canCreate())throw new CarrierCreationDenied();return repo.create(validateNewCarrier(input))}
  };
}
