import type { Carrier } from "@/domain/models";
import type { NewCarrierInput } from "@/domain/carrier-onboarding";
export interface CarrierAdministrationRepository {
  canCreate():Promise<boolean>;
  create(input:NewCarrierInput):Promise<Carrier>;
}
