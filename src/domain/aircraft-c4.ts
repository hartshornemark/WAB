export type AircraftC4Values={datum:number;referenceArm:number;constantK:number;constantC:number;macRcLength:number;lemacLerc:number};
export type AircraftC4Snapshot={canView:boolean;canEdit:boolean;exists:boolean;revision:string;typeCode:string;subtype:string;lengthUnit:string;values:AircraftC4Values};
export class AircraftC4Invalid extends Error{}
export class AircraftC4Denied extends Error{}
export class AircraftC4Conflict extends Error{}

function finite(value:unknown,label:string,{positive=false,integer=false}:{positive?:boolean;integer?:boolean}={}){
  if(value===""||value===null||value===undefined||typeof value==="boolean")throw new AircraftC4Invalid(`Enter a valid ${label}.`);
  const number=typeof value==="number"?value:Number(value);
  if(!Number.isFinite(number)||Math.abs(number)>1_000_000_000||(positive?number<=0:false)||(integer&&!Number.isInteger(number)))throw new AircraftC4Invalid(`Enter a valid ${label}.`);
  return number;
}

export function validateAircraftC4(input:unknown):AircraftC4Values{
  const value=input as Record<string,unknown>;
  return{
    datum:finite(value?.datum,"Datum"),
    referenceArm:finite(value?.referenceArm,"Reference Arm"),
    constantK:finite(value?.constantK,"K Constant",{integer:true}),
    constantC:finite(value?.constantC,"C Constant",{positive:true}),
    macRcLength:finite(value?.macRcLength,"MAC/RC Length",{positive:true}),
    lemacLerc:finite(value?.lemacLerc,"LEMAC/LERC")
  };
}
