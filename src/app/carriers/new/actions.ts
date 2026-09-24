"use server";
import{revalidatePath}from"next/cache";
import{redirect}from"next/navigation";
import{carrierAdministrationServices,logoServices}from"@/composition/services";
import{MAX_LOGO_BYTES}from"@/application/carrier-logos";
import{AuthenticationRequired,DataUnavailable}from"@/domain/models";
import{CarrierCreationDenied,CarrierIdentityExists,CarrierIdentityInvalid,type CarrierIdentityField}from"@/domain/carrier-onboarding";
export type NewCarrierFormState={error:string;fields:Record<CarrierIdentityField,string>;fieldErrors:Partial<Record<CarrierIdentityField,string>>};
const value=(form:FormData,key:string)=>{const x=form.get(key);return typeof x==="string"?x:""};
export async function createCarrierAction(_previous:NewCarrierFormState,form:FormData):Promise<NewCarrierFormState>{
  const fields={iata:value(form,"iata"),name:value(form,"name"),icao:value(form,"icao")},logo=form.get("logo");
  if(logo instanceof File&&logo.size){
    if(logo.size>MAX_LOGO_BYTES)return{error:"Choose a logo up to 2 MB.",fields,fieldErrors:{}};
    if(!["image/png","image/jpeg","image/webp"].includes(logo.type))return{error:"Choose a PNG, JPEG or WebP logo.",fields,fieldErrors:{}};
  }
  let carrier;
  try{carrier=await(await carrierAdministrationServices()).create(fields)}catch(error){
    if(error instanceof CarrierIdentityInvalid)return{error:"",fields,fieldErrors:{[error.field]:error.message}};
    if(error instanceof CarrierIdentityExists){const key=error.field==="duplicate"?undefined:error.field;return{error:key?"":"That carrier identity already exists.",fields,fieldErrors:key?{[key]:`This ${key.toUpperCase()} value is already in use.`}:{}}}
    if(error instanceof AuthenticationRequired)return{error:"Your session has ended. Sign in again before creating the carrier.",fields,fieldErrors:{}};
    if(error instanceof CarrierCreationDenied)return{error:"Only a Solution Administrator can create a carrier.",fields,fieldErrors:{}};
    return{error:error instanceof DataUnavailable?"The carrier could not be created. Refresh the page and try again.":"The carrier could not be created.",fields,fieldErrors:{}};
  }
  let logoRetry=false;
  if(logo instanceof File&&logo.size){try{await(await logoServices()).upload(carrier.iata,new Uint8Array(await logo.arrayBuffer()),logo.type)}catch{logoRetry=true}}
  revalidatePath("/carriers");revalidatePath(`/carrier/${encodeURIComponent(carrier.iata)}`);
  redirect(`/carrier/${encodeURIComponent(carrier.iata)}?created=1${logoRetry?"&logo=retry":""}`);
}
