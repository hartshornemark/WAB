import assert from"node:assert/strict";
import test from"node:test";
import{operationalFlightLabel,operationalWeightBasis,validServiceDate,validUuid,OperationalFlightInvalid}from"../src/domain/operational-flights";
test("operational flight identity accepts a real service date and UUID",()=>{assert.equal(validServiceDate("2026-10-08"),"2026-10-08");assert.equal(validUuid("aaad9d7d-54a4-4613-bbbb-e74d211b6849"),"aaad9d7d-54a4-4613-bbbb-e74d211b6849")});
test("operational flight identity rejects invalid values",()=>{assert.throws(()=>validServiceDate("08/10/2026"),OperationalFlightInvalid);assert.throws(()=>validUuid("flight-1"),OperationalFlightInvalid)});
test("workflow status labels are readable",()=>{assert.equal(operationalFlightLabel("LOADSHEET_PRELIMINARY"),"Loadsheet Preliminary");assert.equal(operationalFlightLabel("LOAD_PLANNING"),"Load Planning")});
test("freighter operations never retain passenger or baggage weight methods",()=>{assert.equal(operationalWeightBasis("FREIGHTER","STANDARD"),null);assert.equal(operationalWeightBasis("PASSENGER","STANDARD"),"STANDARD")});
