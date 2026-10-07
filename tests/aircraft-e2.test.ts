import test from"node:test";import assert from"node:assert/strict";import{aircraftE2Status,e2CrewStatus,e2PantryStatus}from"@/domain/aircraft-e2-status";import{validateE2Crew,validateE2Pantry,type AircraftE2Snapshot}from"@/domain/aircraft-e2";
const base:AircraftE2Snapshot={canView:true,canEdit:true,revision:"x",typeCode:"319",subtype:"100",startWeightPrinciple:"BASIC_WEIGHT",crewRows:[],pantryRows:[],flightDeckLocations:[{id:"XFD",description:"Flight Deck"}],cabinCrewLocations:[{id:"XLA",description:"Cabin Crew"}],holds:[{id:"1",description:"Hold 1"}]};
const crew={crewCode:"A",flightDeckLocationId:"XFD",flightDeckSeats:2,cabinCrewLocationId:"XLA",cabinCrewSeats:2,flightDeckBaggageLocation:null,cabinCrewBaggageLocation:null,isBase:false,weightAdjustment:null,indexAdjustment:null};
const pantry={pantryCode:"A",adjustmentMethod:"BY_GALLEY" as const,galleyLocations:"G1/100Kg G4/100Kg",totalWeight:200,balanceArm:18.037,index:.2,isBase:false,weightAdjustment:null,indexAdjustment:null};
test("E2 accepts complete crew rows without baggage",()=>assert.equal(e2CrewStatus({...base,crewRows:[crew]}),"configured"));
test("E2 requires a crew and pantry row",()=>{assert.equal(e2PantryStatus(base),"incomplete");assert.equal(aircraftE2Status({...base,crewRows:[crew],pantryRows:[pantry]}),"configured")});
test("E2 accepts only saved D2 holds when baggage is present",()=>{assert.doesNotThrow(()=>validateE2Crew([{...crew,flightDeckBaggageLocation:"1"}],base.flightDeckLocations,base.cabinCrewLocations,base.holds));assert.throws(()=>validateE2Crew([{...crew,flightDeckBaggageLocation:"9"}],base.flightDeckLocations,base.cabinCrewLocations,base.holds))});
test("E2 preserves decimal Pantry Index values",()=>{const[row]=validateE2Pantry([{...pantry,index:"3.2"}]);assert.equal(row.index,3.2)});

test("DOW/DOI crew and pantry codes require one zero base and signed deviations",()=>{
 const dow={...base,startWeightPrinciple:"DRY_OPERATING_WEIGHT" as const};
 const baseCrew={...crew,isBase:true,weightAdjustment:0,indexAdjustment:0};
 const alternateCrew={...crew,crewCode:"B",isBase:false,weightAdjustment:-50,indexAdjustment:-.25};
 const basePantry={...pantry,isBase:true,weightAdjustment:0,indexAdjustment:0};
 const alternatePantry={...pantry,pantryCode:"B",isBase:false,weightAdjustment:100,indexAdjustment:.4};
 assert.doesNotThrow(()=>validateE2Crew([baseCrew,alternateCrew],base.flightDeckLocations,base.cabinCrewLocations,base.holds,"DRY_OPERATING_WEIGHT"));
 assert.doesNotThrow(()=>validateE2Pantry([basePantry,alternatePantry],"DRY_OPERATING_WEIGHT"));
 assert.equal(aircraftE2Status({...dow,crewRows:[baseCrew,alternateCrew],pantryRows:[basePantry,alternatePantry]}),"configured");
 assert.throws(()=>validateE2Pantry([alternatePantry],"DRY_OPERATING_WEIGHT"),/exactly one base/);
 assert.throws(()=>validateE2Pantry([{...basePantry,weightAdjustment:1}],"DRY_OPERATING_WEIGHT"),/must have zero/);
 const oneLine={...alternatePantry,adjustmentMethod:"ONE_LINE" as const,galleyLocations:"ALL",totalWeight:0,balanceArm:0,index:0};
 assert.doesNotThrow(()=>validateE2Pantry([basePantry,oneLine],"DRY_OPERATING_WEIGHT"));
 assert.throws(()=>validateE2Pantry([{...basePantry,adjustmentMethod:"ONE_LINE"},alternatePantry],"DRY_OPERATING_WEIGHT"),/base pantry code must be defined by galley/);
});

test("one crew code may distribute its complement across several locations with one aggregate deviation",()=>{
 const cabin=[...base.cabinCrewLocations,{id:"XLB",description:"Rear Cabin"}];
 const forward={...crew,isBase:true,weightAdjustment:0,indexAdjustment:0,cabinCrewSeats:4};
 const rear={...forward,cabinCrewLocationId:"XLB",flightDeckSeats:0,cabinCrewSeats:6};
 const rows=validateE2Crew([forward,rear],base.flightDeckLocations,cabin,base.holds,"DRY_OPERATING_WEIGHT");
 assert.equal(rows.reduce((total,row)=>total+(row.flightDeckSeats??0),0),2);
 assert.equal(rows.reduce((total,row)=>total+(row.cabinCrewSeats??0),0),10);
 assert.throws(()=>validateE2Crew([forward,{...rear,isBase:false}],base.flightDeckLocations,cabin,base.holds,"DRY_OPERATING_WEIGHT"),/same base selection and DOW\/DOI adjustments/);
});

test("E2 pantry totals exceed crew seat limit and reject missing weights",()=>{
 assert.equal(validateE2Pantry([{...pantry,totalWeight:1403}])[0].totalWeight,1403);
 assert.throws(()=>validateE2Pantry([{...pantry,totalWeight:null}]));
 assert.throws(()=>validateE2Crew([{...crew,flightDeckSeats:1000}],base.flightDeckLocations,base.cabinCrewLocations,base.holds));
});

test("E2 flight-deck-only crew needs no cabin location and is configured",()=>{
 const [row]=validateE2Crew([{...crew,cabinCrewSeats:0,cabinCrewLocationId:""}],base.flightDeckLocations,[],base.holds);
 assert.equal(row.cabinCrewLocationId,"");assert.equal(row.cabinCrewSeats,0);
 assert.equal(e2CrewStatus({...base,crewRows:[row],cabinCrewLocations:[]}),"configured");
 assert.throws(()=>validateE2Crew([{...row,cabinCrewSeats:1}],base.flightDeckLocations,[],base.holds),/crew locations/);
 assert.equal(e2CrewStatus({...base,crewRows:[{...row,cabinCrewSeats:1}]}),"partial");
 const [cleared]=validateE2Crew([{...crew,cabinCrewSeats:0,cabinCrewBaggageLocation:"1"}],base.flightDeckLocations,base.cabinCrewLocations,base.holds);
 assert.equal(cleared.cabinCrewLocationId,"");assert.equal(cleared.cabinCrewBaggageLocation,null);
 assert.throws(()=>validateE2Crew([{...row,cabinCrewSeats:null}],base.flightDeckLocations,[],base.holds));
});
