import"server-only";
import type{CarrierAdministrationRepository}from"@/ports/carrier-administration-repository";
import{CarrierCreationDenied,CarrierIdentityExists,CarrierIdentityInvalid,type CarrierIdentityField}from"@/domain/carrier-onboarding";
import{DataUnavailable,type Carrier}from"@/domain/models";
import type{RequestClient}from"./server";
type DbError={code?:string;details?:string};
const field=(details?:string):CarrierIdentityField|"duplicate"=>details==="iata"||details==="name"||details==="icao"?details:"duplicate";
export function createCarrierAdministrationAdapter(client:RequestClient):CarrierAdministrationRepository{
  const schema=()=>client.schema("Basic_Carrier_Record");
  return{
    async canCreate(){const{data,error}=await schema().rpc("can_create_carrier",{});if(error)throw new DataUnavailable("Unable to check carrier creation permissions.");return data===true},
    async create(input){const{data,error}=await schema().rpc("create_carrier",{p_iata:input.iata,p_name:input.name,p_icao:input.icao});if(error){const e=error as DbError;if(e.code==="42501")throw new CarrierCreationDenied();if(e.code==="23505")throw new CarrierIdentityExists(field(e.details));if(e.code==="22023")throw new CarrierIdentityInvalid(field(e.details)==="duplicate"?"name":field(e.details) as CarrierIdentityField,"Check the carrier identity and try again.");throw new DataUnavailable("Unable to create the carrier.")}return data as unknown as Carrier}
  };
}
