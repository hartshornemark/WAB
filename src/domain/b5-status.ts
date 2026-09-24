import type{ConfigurationStatus,DisplayConfigurationStatus}from"@/domain/configuration-status";
import{validateUlds,type UldSnapshot}from"@/domain/uld-specifications";
export type B5Completion={page:DisplayConfigurationStatus;specifications:DisplayConfigurationStatus;inventory:DisplayConfigurationStatus};
export function b5Completion(snapshot:UldSnapshot):B5Completion{
 if(!snapshot.utilisesUlds)return{page:"skipped",specifications:"skipped",inventory:"skipped"};
 if(!snapshot.weightUnit||!snapshot.volumeUnit||snapshot.rows.length===0)return{page:"incomplete",specifications:"incomplete",inventory:"configured"};
 let specifications:ConfigurationStatus="configured";try{validateUlds(snapshot.rows,snapshot);}catch{specifications="partial";}
 const inventory:ConfigurationStatus=specifications==="partial"?"partial":"configured";return{page:specifications,specifications,inventory};
}
