export type FuelConfigurationOption={code:string;description:string};
export type FuelConfigurationOverride={
 configurationCode:string;
 maxWeight?:number|null;maxVolume?:number|null;volume?:number|null;
 balanceCentroid?:number|null;balanceFrom?:number|null;balanceTo?:number|null;
 indexPerWeightUnit?:number|null;
};
export type FuelConfigurationScoped={configurationCodes?:string[];configurationOverrides?:FuelConfigurationOverride[]};

const code=(value:unknown)=>String(value??"").trim().toUpperCase();
const optionalNumber=(value:unknown,label:string)=>{
 if(value===null||value===undefined||value==="")return null;
 const result=typeof value==="number"?value:Number(value);
 if(!Number.isFinite(result)||Math.abs(result)>1e9)throw new Error(`Enter a valid ${label}.`);
 return result;
};
export function validateFuelConfigurationScope<T extends FuelConfigurationScoped>(value:T,options:FuelConfigurationOption[]):T{
 const available=new Set(options.map(item=>item.code));
 const configurationCodes=[...new Set((value.configurationCodes??[]).map(code).filter(Boolean))].sort();
 const unknown=configurationCodes.find(item=>!available.has(item));
 if(unknown)throw new Error(`Fuel configuration ${unknown} is not defined on E1.2.`);
 const seen=new Set<string>();
 const configurationOverrides=(value.configurationOverrides??[]).map((raw,index)=>{
  const configurationCode=code(raw.configurationCode);
  if(!available.has(configurationCode))throw new Error(`Override ${index+1}: select a fitted fuel configuration defined on E1.2.`);
  if(seen.has(configurationCode))throw new Error(`Fuel configuration ${configurationCode} has more than one override.`);
  seen.add(configurationCode);
  const result:FuelConfigurationOverride={configurationCode};
  for(const [key,label] of [["maxWeight","Maximum Weight"],["maxVolume","Maximum Volume"],["volume","Volume"],["balanceCentroid","Balance Arm Centroid"],["balanceFrom","Balance Arm From"],["balanceTo","Balance Arm To"],["indexPerWeightUnit","Index Per Weight Unit"]] as const){
   const parsed=optionalNumber(raw[key],label);if(parsed!==null)result[key]=parsed;
  }
  if(result.maxWeight!==undefined&&result.maxWeight!<=0)throw new Error(`${configurationCode}: Maximum Weight must be positive.`);
  if(result.maxVolume!==undefined&&result.maxVolume!<=0)throw new Error(`${configurationCode}: Maximum Volume must be positive.`);
  if(result.volume!==undefined&&result.volume!<=0)throw new Error(`${configurationCode}: Volume must be positive.`);
  if((result.balanceFrom===undefined)!==(result.balanceTo===undefined))throw new Error(`${configurationCode}: complete both Balance Arm From and To overrides.`);
  if(result.balanceFrom!==undefined&&(result.balanceFrom!>result.balanceTo!||(result.balanceCentroid!==undefined&&(result.balanceCentroid!<result.balanceFrom!||result.balanceCentroid!>result.balanceTo!))))throw new Error(`${configurationCode}: override Balance Arms must be ordered From, Centroid, To.`);
  return result;
 });
 return{...value,configurationCodes,configurationOverrides};
}
export function appliesToFuelConfiguration(value:FuelConfigurationScoped,configurationCode:string|null|undefined){
 if(!configurationCode)return true;
 const scope=value.configurationCodes??[];
 return scope.length===0||scope.includes(configurationCode);
}
export function applyFuelConfigurationOverride<T extends FuelConfigurationScoped>(value:T,configurationCode:string|null|undefined):T{
 if(!configurationCode)return value;
 const override=value.configurationOverrides?.find(item=>item.configurationCode===configurationCode);
 return override?{...value,...Object.fromEntries(Object.entries(override).filter(([key,item])=>key!=="configurationCode"&&item!==null&&item!==undefined))}:value;
}
export function fuelConfigurationScopeLabel(value:FuelConfigurationScoped){return value.configurationCodes?.length?value.configurationCodes.join(" + "):"ALL CONFIGURATIONS"}
