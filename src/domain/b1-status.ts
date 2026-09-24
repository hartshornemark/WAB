import {aggregateConfigurationStatuses,type ConfigurationStatus} from "@/domain/configuration-status";
import type {DetailsSnapshot} from "@/domain/carrier-details";
import type {DensitySnapshot} from "@/domain/density-settings";
import type {ClassSnapshot} from "@/domain/class-codes";
import type {CommoditySnapshot} from "@/domain/commodity-codes";

export function b1UnitsStatus(details:Pick<DetailsSnapshot,"values">):ConfigurationStatus{
  const values=[details.values.weightUnit,details.values.volumeUnit,details.values.weightMethod,details.values.indexDecimalPlaces];
  if(values.every(value=>!value))return "incomplete";
  return ["KG","LB"].includes(values[0])&&["m3","ft3"].includes(values[1])&&["BASIC","DRY_OPERATING"].includes(values[2])&&["1","2"].includes(values[3])?"configured":"partial";
}

export function b1DensityStatus(snapshot:DensitySnapshot):ConfigurationStatus{
  if(!snapshot.weightUnit||!snapshot.volumeUnit)return "incomplete";
  const values=Object.values(snapshot.values).map(value=>value.trim());
  if(values.every(value=>!value))return "incomplete";
  const valid=values.every(value=>value!==""&&Number.isFinite(Number(value))&&Number(value)>0);
  return valid?"configured":"partial";
}

export function b1ClassStatus(snapshot:Pick<ClassSnapshot,"rows">):ConfigurationStatus{
  if(snapshot.rows.length===0)return "incomplete";
  const codes=new Set<string>(),priorities=new Set<number>();
  const valid=snapshot.rows.length<=4&&snapshot.rows.every(row=>{
    const code=row.code.trim().toUpperCase(),description=row.description.trim();
    if(!/^[A-Z]$/.test(code)||!Number.isInteger(row.priority)||row.priority<1||row.priority>4||!description||[...description].length>64||codes.has(code)||priorities.has(row.priority))return false;
    codes.add(code);priorities.add(row.priority);return true;
  });
  return valid?"configured":"partial";
}

export function b1CommodityStatus(snapshot:Pick<CommoditySnapshot,"rows">):ConfigurationStatus{
  if(snapshot.rows.length===0)return "incomplete";
  const codes=new Set<string>();
  const valid=snapshot.rows.length<=200&&snapshot.rows.every(row=>{
    const code=row.code.trim().toUpperCase(),description=row.description.trim();
    if(!/^[A-Z0-9]{1,2}$/.test(code)||!description||[...description].length>64||codes.has(code))return false;
    codes.add(code);return true;
  });
  return valid?"configured":"partial";
}

export function b1Statuses(details:DetailsSnapshot,density:DensitySnapshot,classes:ClassSnapshot,commodities:CommoditySnapshot){
  const units=b1UnitsStatus(details),densities=b1DensityStatus(density),classCodes=b1ClassStatus(classes),commodityCodes=b1CommodityStatus(commodities);
  return{units,densities,classCodes,commodityCodes,page:aggregateConfigurationStatuses([units,densities,classCodes,commodityCodes])};
}
