import type{ReactNode}from"react";
import type{OperationalPassengerBooking}from"@/domain/operational-passengers";
import type{OperationalFreightPlanning}from"@/ports/operational-flight-repository";

const kg=(value:number|null|undefined)=>value===null||value===undefined?"—":`${Math.round(value).toLocaleString()} KG`;
const volume=(value:number|null|undefined,unit:"M3"|"FT3"|undefined)=>value===null||value===undefined?"—":`${value.toLocaleString(undefined,{maximumFractionDigits:0})} ${unit==="FT3"?"CU FT":"m³"}`;

export function OperationalTrafficPlan({passengers,planning,children}:{passengers:OperationalPassengerBooking;planning:OperationalFreightPlanning;children:ReactNode}){
 const freighter=planning.operatingRole==="FREIGHTER";
 const passengerSplit=passengers.classes.filter(row=>row.booked>0).map(row=>`${row.code}${row.booked.toLocaleString()}`).join(" · ")||"—";
 const baggageSplit=(planning.baggageClasses??[]).filter(row=>row.plannedPieces>0||row.plannedWeight>0).map(row=>row.commodityCode).filter((value,index,rows)=>rows.indexOf(value)===index).join(" · ")||"B";
 const baggageUlds=planning.baggageAccommodation?.contents.filter(row=>row.kind==="ULD").reduce<Record<string,number>>((totals,row)=>{const code=row.commodities?.map(item=>item.commodityCode).join("/")||row.commodityCode||"B";totals[code]=(totals[code]??0)+1;return totals},{});
 const baggageAllocation=baggageUlds&&Object.keys(baggageUlds).length?Object.entries(baggageUlds).map(([code,count])=>`${code} ${count} ${planning.uldCode??"ULD"}`).join(" · "):`${planning.plannedBaggageUldPositions??0} ${planning.uldCode??"ULD"}`;
 const cargoPositions=(planning.cargoUldAllocations??[]).map(row=>`${row.positionCount} ${row.uldCode}`).join(" · ")||"BULK";
 return <details className={`operational-traffic-plan operational-collapsible${freighter?" traffic-plan-freighter":""}`}>
  <summary className="operational-collapsible-summary">
   <div className="traffic-plan-title"><p className="eyebrow">{freighter?"TRAFFIC PLAN · FREIGHTER":"TRAFFIC PLAN"}</p><h2>{freighter?"Freight Traffic Plan":"Traffic Plan"}</h2><p>{freighter?"Cargo capacity and position planning for the operating aircraft.":"Passenger and baggage planning"}</p></div>
   <div className="traffic-plan-summary-facts">
    {freighter?<>
     <span><small>PLANNING AIRCRAFT WEIGHT</small><strong>{kg(planning.planningAircraftWeight)}</strong><em>OPERATING BASIS</em><i>{planning.weightBasis==="FLEET_WEIGHT"?"FLEET WEIGHT":planning.registration??"—"}</i></span>
     <span><small>STRUCTURAL CAPACITY</small><strong>{kg(planning.structuralCapacity)}</strong><em>MZFW</em><i>{kg(planning.mzfw)}</i></span>
     <span className="remaining"><small>SPACE WEIGHT CAPACITY</small><strong>{kg(planning.spaceWeightCapacity)}</strong><em>LIMITING FACTOR</em><i>{planning.ready?planning.limitingFactor.replaceAll("_"," "):"INCOMPLETE"}</i></span>
     <span className="offer"><small>CARGO OFFER</small><strong>{kg(planning.cargoOfferWeight)}</strong><b>{planning.ready?"AVAILABLE FOR UPLIFT · READY":"COMPLETE THE MISSING AIRCRAFT DATA"}</b></span>
    </>:<>
     <span><small>BOOKED PASSENGERS</small><strong>{passengerSplit}</strong><b>{passengers.totalBooked.toLocaleString()} PAX TOTAL</b><em>PLANNING WEIGHT</em><i>{kg(passengers.totalPassengerWeight)}</i></span>
     <span><small>FORECAST BAGGAGE</small><strong>{baggageSplit}</strong><b>FORECAST BY TYPE</b><em>ULD ALLOCATION</em><i>{baggageAllocation} · BULK (0)</i></span>
     <span className="remaining"><small>REMAINING PAYLOAD</small><strong>{kg(planning.remainingPayload)}</strong><em>MAXIMUM PAYLOAD</em><i>{kg(planning.maximumPayload)}</i></span>
     <span className="offer"><small>CARGO OFFER</small><strong>{kg(planning.cargoOfferWeight)} / {volume(planning.availableBulkVolume,planning.availableBulkVolumeUnit)}</strong><b>{cargoPositions}</b></span>
    </>}
   </div>
  </summary>
  <div className={`operational-traffic-plan-body${freighter?" freighter":""}`}>{children}</div>
 </details>;
}
