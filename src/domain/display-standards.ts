/**
 * Global Column Heading Register.
 *
 * User-facing tables must obtain shared headings from this register. Database
 * column names and stored unit codes are deliberately independent of it.
 */
export type NumericRule="integer"|"index"|"indexPerWeightUnit"|"twoDecimals"|"threeDecimals"|"text";
export type ColumnAlignment="left"|"center"|"right";

export type ColumnHeadingDefinition={
  label:string;
  alignment:ColumnAlignment;
  numericRule:NumericRule;
  unit:"none"|"weight"|"length"|"volume";
  group?:string;
  note?:string;
};

export const columnHeadingRegister={
  index:{label:"Index",alignment:"right",numericRule:"index",unit:"none"},
  indexPerWeightUnit:{label:"Index Per Weight Unit",alignment:"right",numericRule:"indexPerWeightUnit",unit:"none"},
  balanceArm:{label:"Balance Arm",alignment:"center",numericRule:"text",unit:"none"},
  balanceArmCentroid:{label:"Balance Arm Centroid",alignment:"right",numericRule:"threeDecimals",unit:"length",group:"Balance Arm"},
  balanceArmFrom:{label:"From",alignment:"right",numericRule:"threeDecimals",unit:"length",group:"Balance Arm"},
  balanceArmTo:{label:"To",alignment:"right",numericRule:"threeDecimals",unit:"length",group:"Balance Arm"},
  maxWeight:{label:"Max Weight",alignment:"right",numericRule:"integer",unit:"weight"},
  weight:{label:"Weight",alignment:"right",numericRule:"integer",unit:"weight"},
  fuelWeight:{label:"Fuel Weight",alignment:"right",numericRule:"integer",unit:"weight"},
  taxiFuel:{label:"Taxi Fuel",alignment:"right",numericRule:"integer",unit:"weight"},
  fuelStandardHorizontalArm:{label:"H-Arm",alignment:"right",numericRule:"threeDecimals",unit:"length",note:"Approved specifically for C8 Standard Fuel Loading Schedule."},
  specificGravity:{label:"Specific Gravity",alignment:"right",numericRule:"threeDecimals",unit:"none"},
  volume:{label:"Volume",alignment:"right",numericRule:"twoDecimals",unit:"volume"},
  maximumVolume:{label:"Maximum Volume",alignment:"right",numericRule:"integer",unit:"volume"},
  maxSeats:{label:"Max Seats",alignment:"center",numericRule:"integer",unit:"none"},
  totalSeats:{label:"Total Seats",alignment:"center",numericRule:"integer",unit:"none"},
}as const satisfies Record<string,ColumnHeadingDefinition>;

export type ColumnHeadingKey=keyof typeof columnHeadingRegister;

export function displayUnit(unit:string|null|undefined){
  if(unit==="KG")return"Kg";
  return unit??"";
}

export function columnHeading(key:ColumnHeadingKey,unit?:string|null){
  const label=columnHeadingRegister[key].label;
  const shownUnit=displayUnit(unit);
  return shownUnit?`${label} (${shownUnit})`:label;
}

export type IndexDecimalPlaces=1|2;
export function formatNumeric(value:number|null|undefined,rule:NumericRule,indexDecimalPlaces?:IndexDecimalPlaces):string;
export function formatNumeric(rule:"maxWeight"|"balanceArm"|"index",value:number|null|undefined,indexDecimalPlaces?:IndexDecimalPlaces):string;
export function formatNumeric(valueOrRule:number|null|undefined|"maxWeight"|"balanceArm"|"index",ruleOrValue:NumericRule|number|null|undefined,indexDecimalPlaces:IndexDecimalPlaces=1){
  const keyed=typeof valueOrRule==="string",value=keyed?ruleOrValue as number|null|undefined:valueOrRule,rule=keyed?({maxWeight:"integer",balanceArm:"threeDecimals",index:"index"}as const)[valueOrRule]:ruleOrValue as NumericRule;
  if(value===null||value===undefined||!Number.isFinite(value))return"—";
  if(rule==="integer")return value.toFixed(0);
  if(rule==="index")return value.toFixed(indexDecimalPlaces);
  if(rule==="indexPerWeightUnit")return value.toFixed(5);
  if(rule==="twoDecimals")return value.toFixed(2);
  if(rule==="threeDecimals")return value.toFixed(3);
  return String(value);
}
