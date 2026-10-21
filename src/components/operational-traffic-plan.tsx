import type{ReactNode}from"react";
import type{OperationalPassengerBooking}from"@/domain/operational-passengers";
import type{OperationalFreightPlanning}from"@/ports/operational-flight-repository";

const kg=(value:number|null|undefined)=>value===null||value===undefined?"—":`${Math.round(value).toLocaleString()} KG`;
const volume=(value:number|null|undefined,unit:"M3"|"FT3"|undefined)=>value===null||value===undefined?"—":`${value.toLocaleString(undefined,{maximumFractionDigits:0})} ${unit==="FT3"?"CU FT":"m³"}`;

export function OperationalTrafficPlan({passengers,planning,children}:{passengers:OperationalPassengerBooking;planning:OperationalFreightPlanning;children:ReactNode}){
 const passengerSplit=passengers.classes.filter(row=>row.booked>0).map(row=>`${row.code}${row.booked.toLocaleString()}`).join(" · ")||"—";
 const baggageSplit=(planning.baggageClasses??[]).filter(row=>row.plannedPieces>0||row.plannedWeight>0).map(row=>row.commodityCode).filter((value,index,rows)=>rows.indexOf(value)===index).join(" · ")||"B";
 const baggageUlds=planning.baggageAccommodation?.contents.filter(row=>row.kind==="ULD").reduce<Record<string,number>>((totals,row)=>{const code=row.commodities?.map(item=>item.commodityCode).join("/")||row.commodityCode||"B";totals[code]=(totals[code]??0)+1;return totals},{});
 const baggageAllocation=baggageUlds&&Object.keys(baggageUlds).length?Object.entries(baggageUlds).map(([code,count])=>`${code} ${count} ${planning.uldCode??"ULD"}`).join(" · "):`${planning.plannedBaggageUldPositions??0} ${planning.uldCode??"ULD"}`;
 const cargoPositions=(planning.cargoUldAllocations??[]).map(row=>`${row.positionCount} ${row.uldCode}`).join(" · ")||"BULK";
 return <details className="operational-traffic-plan operational-collapsible">
  <summary className="operational-collapsible-summary">
   <div className="traffic-plan-title"><p className="eyebrow">TRAFFIC PLAN</p><h2>Traffic Plan</h2><p>Passenger and baggage planning</p></div>
   <div className="traffic-plan-summary-facts">
    <span><small>BOOKED PASSENGERS</small><strong>{passengerSplit}</strong><b>{passengers.totalBooked.toLocaleString()} PAX TOTAL</b><em>PLANNING WEIGHT</em><i>{kg(passengers.totalPassengerWeight)}</i></span>
    <span><small>FORECAST BAGGAGE</small><strong>{baggageSplit}</strong><b>FORECAST BY TYPE</b><em>ULD ALLOCATION</em><i>{baggageAllocation} · BULK (0)</i></span>
    <span className="remaining"><small>REMAINING PAYLOAD</small><strong>{kg(planning.remainingPayload)}</strong><em>MAXIMUM PAYLOAD</em><i>{kg(planning.maximumPayload)}</i></span>
    <span className="offer"><small>CARGO OFFER</small><strong>{kg(planning.cargoOfferWeight)} / {volume(planning.availableBulkVolume,planning.availableBulkVolumeUnit)}</strong><b>{cargoPositions}</b></span>
   </div>
  </summary>
  <div className="operational-traffic-plan-body">{children}</div>
 </details>;
}
