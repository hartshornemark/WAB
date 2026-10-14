import type{AuthService}from"@/ports/auth-service";
import type{CarrierRepository}from"@/ports/carrier-repository";
import type{OperationalTimelineRepository}from"@/ports/operational-timeline-repository";
import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";
import{OperationalTimelineDenied,OperationalTimelineInvalid,validateOperationalTimeline}from"@/domain/operational-timeline";
export function createOperationalTimeline(auth:AuthService,carriers:CarrierRepository,repository:OperationalTimelineRepository){
 const access=async(iata:string)=>{const user=await auth.currentUser();if(!user)throw new AuthenticationRequired();const carrier=await carriers.findAuthorised(iata);if(!carrier)throw new CarrierUnavailable();return{user,carrier}};
 const aircraftType=(value:unknown)=>{const type=String(value??"").trim().toUpperCase();if(!/^[A-Z0-9]{3}$/.test(type))throw new OperationalTimelineInvalid("Select a carrier aircraft type.");return type};
 return{
  async get(iata:string){const context=await access(iata);return{...context,timeline:await repository.get(iata)}},
  async resolve(iata:string,type:unknown){await access(iata);return repository.resolve(iata,aircraftType(type))},
  async save(iata:string,type:unknown,expectedRevision:unknown,input:unknown){await access(iata);const revision=Number(expectedRevision);if(!Number.isSafeInteger(revision)||revision<0)throw new OperationalTimelineInvalid("Reload the timeline before saving.");const current=await repository.get(iata);if(!current.canEdit)throw new OperationalTimelineDenied("You do not have permission to change the Load Control timeline.");const scope=String(type??"").trim()?aircraftType(type):null;return repository.save(iata,scope,revision,validateOperationalTimeline(input))},
  async remove(iata:string,type:unknown,expectedRevision:unknown){await access(iata);const revision=Number(expectedRevision);if(!Number.isSafeInteger(revision)||revision<1)throw new OperationalTimelineInvalid("Reload the timeline before removing this variation.");const current=await repository.get(iata);if(!current.canEdit)throw new OperationalTimelineDenied("You do not have permission to change the Load Control timeline.");return repository.remove(iata,aircraftType(type),revision)},
 }
}
