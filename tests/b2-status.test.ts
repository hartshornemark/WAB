import test from "node:test";
import assert from "node:assert/strict";
import {b2Statuses} from "../src/domain/b2-status";
import type {CrewSnapshot,CrewValues} from "../src/domain/crew-weights";

const values:CrewValues={
  includesHandBaggage:true,allFlights:true,longhaul:false,shorthaul:false,
  flightDeckMale:85,flightDeckFemale:85,cabinMale:75,cabinFemale:75,
  flightDeckHand:null,cabinHand:null,
  flightDeckLong:null,flightDeckShort:null,flightDeckOther:0,
  cabinLong:null,cabinShort:null,cabinOther:0,
};
const snapshot:CrewSnapshot={canView:true,canEdit:true,exists:true,revision:"1",unit:"KG",values};

test("B2 is configured when crew, hand baggage and selected hold baggage rules pass",()=>{
 assert.deepEqual(b2Statuses(snapshot),{crewWeights:"configured",handBaggage:"configured",holdBaggage:"configured",page:"configured"});
});

test("B2 remains partial while hold baggage flight applicability is unselected",()=>{
 const result=b2Statuses({...snapshot,values:{...values,allFlights:false,flightDeckOther:0,cabinOther:0}});
 assert.deepEqual(result,{crewWeights:"configured",handBaggage:"configured",holdBaggage:"incomplete",page:"partial"});
});

test("separate hand baggage and each selected hold category require both nonnegative whole values",()=>{
 const hand=b2Statuses({...snapshot,values:{...values,includesHandBaggage:false,flightDeckHand:5,cabinHand:null}});
 assert.equal(hand.handBaggage,"partial");
 const hold=b2Statuses({...snapshot,values:{...values,allFlights:false,longhaul:true,flightDeckLong:12,cabinLong:null}});
 assert.equal(hold.holdBaggage,"partial");
});

test("a missing B1 weight unit is a blocking B2 prerequisite",()=>{
 const result=b2Statuses({...snapshot,unit:null});
 assert.equal(result.crewWeights,"incomplete");
 assert.equal(result.page,"incomplete");
});

test("an absent B2 record leaves crew and hand baggage incomplete",()=>{
 const result=b2Statuses({...snapshot,exists:false,values:{...values,allFlights:false}});
 assert.equal(result.crewWeights,"incomplete");
 assert.equal(result.handBaggage,"incomplete");
 assert.equal(result.holdBaggage,"incomplete");
 assert.equal(result.page,"incomplete");
});

test("B2 Standard plus variations requires each variation decision",()=>{
 const standard={code:null,mode:"SEPARATE" as const,flightDeck:0,cabin:0};
 const s={...snapshot,holdRows:[standard],variations:[{code:"LHL",description:"Longhaul"}]};
 assert.equal(b2Statuses(s).holdBaggage,"partial");
 assert.equal(b2Statuses({...s,holdRows:[standard,{code:"LHL",mode:"STANDARD",flightDeck:null,cabin:null}]}).page,"configured");
 assert.equal(b2Statuses({...s,holdRows:[standard,{code:"LHL",mode:"SEPARATE",flightDeck:20,cabin:15}]}).page,"configured");
 assert.equal(b2Statuses({...s,holdRows:[]}).holdBaggage,"incomplete");
});
