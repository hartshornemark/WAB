export type OperationalPassengerClass={code:string;name:string;booked:number;planningWeight:number|null;passengerWeight:number|null};
export type OperationalPassengerBooking={applicable:boolean;operatingRole:string;canEdit:boolean;version:number;status:"EMPTY"|"BOOKED";weightBasis:string|null;flightVariation:string|null;classes:OperationalPassengerClass[];totalBooked:number;totalPassengerWeight:number;ready:boolean;missing:string[];updatedAt:string|null};
export type OperationalPassengerBookingInput={classes:Array<{code:string;booked:number}>};
export class OperationalPassengerInvalid extends Error{}
export function passengerPlanningWeight(values:{adult:number|null;male:number|null;female:number|null;handBaggage:number|null;includesHandBaggage:boolean}){
 const passenger=values.adult??(values.male!==null&&values.female!==null?(values.male+values.female)/2:null);
 return passenger===null?null:passenger+(values.includesHandBaggage?0:values.handBaggage??0);
}
export function validateOperationalPassengerBooking(input:unknown):OperationalPassengerBookingInput{
 if(!input||typeof input!=="object"||!Array.isArray((input as {classes?:unknown}).classes))throw new OperationalPassengerInvalid("Enter the booked passenger load by class.");
 const seen=new Set<string>();
 const classes=(input as {classes:unknown[]}).classes.map(value=>{
  if(!value||typeof value!=="object")throw new OperationalPassengerInvalid("Check the booked passenger entries.");
  const row=value as Record<string,unknown>,code=String(row.code??"").trim().toUpperCase(),booked=Number(row.booked);
  if(!/^[A-Z]$/.test(code)||seen.has(code))throw new OperationalPassengerInvalid("Each configured class may be entered once.");
  if(!Number.isSafeInteger(booked)||booked<0||booked>999)throw new OperationalPassengerInvalid("Booked passengers must be a whole number between 0 and 999.");
  seen.add(code);return{code,booked};
 });
 if(classes.length<1||classes.length>4)throw new OperationalPassengerInvalid("Enter one to four configured classes.");
 return{classes};
}
