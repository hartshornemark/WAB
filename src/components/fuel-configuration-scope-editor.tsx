"use client";
import{SaveInput}from"@/components/save-feedback";
import{fuelConfigurationScopeLabel,type FuelConfigurationOption,type FuelConfigurationScoped}from"@/domain/fuel-configuration-scope";

type OverrideField="maxWeight"|"maxVolume"|"volume"|"balanceCentroid"|"balanceFrom"|"balanceTo"|"indexPerWeightUnit";
const labels:Record<OverrideField,string>={maxWeight:"Maximum Weight",maxVolume:"Maximum Volume",volume:"Volume",balanceCentroid:"Balance Arm Centroid",balanceFrom:"Balance Arm From",balanceTo:"Balance Arm To",indexPerWeightUnit:"Index Per Weight Unit"};
export function FuelConfigurationScopeEditor<T extends FuelConfigurationScoped>({value,options,editing,onChange,overrideFields=[]}:{value:T;options:FuelConfigurationOption[];editing:boolean;onChange:(value:T)=>void;overrideFields?:OverrideField[]}){
 if(options.length===0)return null;
 if(!options.length)return null;
 const selected=value.configurationCodes??[],overrides=value.configurationOverrides??[];
 const setCodes=(configurationCodes:string[])=>onChange({...value,configurationCodes} as T);
 const setOverride=(configurationCode:string,field:OverrideField,raw:string)=>{
  const current=overrides.find(item=>item.configurationCode===configurationCode)??{configurationCode};
  const next={...current,[field]:raw.trim()===""?undefined:Number(raw)};
  const hasValue=overrideFields.some(key=>next[key]!==undefined&&next[key]!==null);
  onChange({...value,configurationOverrides:hasValue?[...overrides.filter(item=>item.configurationCode!==configurationCode),next]:overrides.filter(item=>item.configurationCode!==configurationCode)} as T);
 };
 if(!editing)return <div className="fuel-config-scope-view"><strong>{fuelConfigurationScopeLabel(value)}</strong>{overrides.length>0&&<span>{overrides.length} configuration override{overrides.length===1?"":"s"}</span>}</div>;
 return <fieldset className="fuel-config-scope"><legend>Fitted fuel configuration</legend><p>Leave ALL selected when this item is common to every fitted configuration.</p><div className="fuel-config-scope-options"><label><SaveInput type="checkbox" checked={selected.length===0} onChange={()=>setCodes([])}/><span>ALL</span></label>{options.map(option=><label key={option.code}><SaveInput type="checkbox" checked={selected.includes(option.code)} onChange={event=>setCodes(event.target.checked?[...selected,option.code]:selected.filter(code=>code!==option.code))}/><span>{option.code}</span></label>)}</div>{overrideFields.length>0&&<div className="fuel-config-overrides">{options.filter(option=>selected.length===0||selected.includes(option.code)).map(option=>{const override=overrides.find(item=>item.configurationCode===option.code);return <details key={option.code}><summary>{option.code} overrides</summary><div>{overrideFields.map(field=><label key={field}><span>{labels[field]}</span><SaveInput type="text" inputMode="decimal" value={override?.[field]??""} onChange={event=>setOverride(option.code,field,event.target.value)}/></label>)}</div></details>})}</div>}</fieldset>;
}
