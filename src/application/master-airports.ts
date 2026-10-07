import{AuthenticationRequired}from"@/domain/models";
import{MasterAirportDenied,validateMasterAirport}from"@/domain/master-airports";
import type{AuthService}from"@/ports/auth-service";
import type{MasterAirportRepository}from"@/ports/master-airport-repository";
export function createMasterAirports(auth:AuthService,repository:MasterAirportRepository){
 const user=async()=>{const value=await auth.currentUser();if(!value)throw new AuthenticationRequired();return value};
 return{
  async get(){const current=await user();try{return{user:current,...await repository.get()}}catch(error){if(error instanceof MasterAirportDenied)return{user:current,airports:[],timeZones:[],denied:true as const};throw error}},
  async save(originalIata:string|null,value:unknown){await user();const input=validateMasterAirport(value);if(originalIata&&originalIata.trim().toUpperCase()!==input.iata)throw new MasterAirportDenied("The IATA identity cannot be changed.");return repository.save(originalIata,input)}
 };
}
