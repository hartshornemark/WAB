import test from"node:test";import assert from"node:assert/strict";import{aircraftE2Status,e2CrewStatus,e2PantryStatus}from"@/domain/aircraft-e2-status";import{validateE2Crew,validateE2Pantry,type AircraftE2Snapshot}from"@/domain/aircraft-e2";
const base:AircraftE2Snapshot={canView:true,canEdit:true,revision:"x",typeCode:"319",subtype:"100",crewRows:[],pantryRows:[],flightDeckLocations:[{id:"XFD",description:"Flight Deck"}],cabinCrewLocations:[{id:"XLA",description:"Cabin Crew"}],holds:[{id:"1",description:"Hold 1"}]};
const crew={crewCode:"A",flightDeckLocationId:"XFD",flightDeckSeats:2,cabinCrewLocationId:"XLA",cabinCrewSeats:2,flightDeckBaggageLocation:null,cabinCrewBaggageLocation:null};
const pantry={pantryCode:"A",galleyLocations:"G1/100Kg G4/100Kg",totalWeight:200,balanceArm:18.037,index:.2};
test("E2 accepts complete crew rows without baggage",()=>assert.equal(e2CrewStatus({...base,crewRows:[crew]}),"configured"));
test("E2 requires a crew and pantry row",()=>{assert.equal(e2PantryStatus(base),"incomplete");assert.equal(aircraftE2Status({...base,crewRows:[crew],pantryRows:[pantry]}),"configured")});
test("E2 accepts only saved D2 holds when baggage is present",()=>{assert.doesNotThrow(()=>validateE2Crew([{...crew,flightDeckBaggageLocation:"1"}],base.flightDeckLocations,base.cabinCrewLocations,base.holds));assert.throws(()=>validateE2Crew([{...crew,flightDeckBaggageLocation:"9"}],base.flightDeckLocations,base.cabinCrewLocations,base.holds))});
test("E2 preserves decimal Pantry Index values",()=>{const[row]=validateE2Pantry([{...pantry,index:"3.2"}]);assert.equal(row.index,3.2)});

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
