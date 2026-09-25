export const densityFields=[{key:"baggage",label:"Checked Baggage"},{key:"cargo",label:"General Cargo"},{key:"mail",label:"General Mail"}] as const;
export type DensityValues=Record<typeof densityFields[number]["key"],string>;
export type DensitySnapshot={canView:boolean;canEdit:boolean;exists:boolean;weightUnit:string;volumeUnit:string;revision:string;values:DensityValues;defaults?:DensityValues};
export class DensityInvalid extends Error {}
export class DensityDenied extends Error {}
export class DensityConflict extends Error {}
export function validateDensities(input:unknown):DensityValues{
 if(!input||typeof input!=="object")throw new DensityInvalid("Check the density values.");
 const result={} as DensityValues;
 for(const {key,label} of densityFields){const value=(input as DensityValues)[key];
  if(typeof value!=="string")throw new DensityInvalid("Check the density values.");
  const trimmed=value.trim();
  if(!trimmed||!/^\d+(\.\d+)?([eE][+-]?\d+)?$/.test(trimmed)||!Number.isFinite(Number(trimmed))||Number(trimmed)<=0)throw new DensityInvalid(`${label} density is required and must be a positive number.`);
  result[key]=trimmed;
 }
 return result;
}

export function suggestedDensityValues(snapshot:DensitySnapshot):DensityValues {
 const values={...snapshot.values};
 if(snapshot.weightUnit&&snapshot.volumeUnit)for(const {key} of densityFields)if(!values[key].trim())values[key]=snapshot.defaults?.[key]??"";
 return values;
}
export function hasSuggestedDensities(snapshot:DensitySnapshot):boolean {
 return !!snapshot.weightUnit&&!!snapshot.volumeUnit&&densityFields.some(({key})=>!snapshot.values[key].trim()&&!!snapshot.defaults?.[key]);
}
