import test from"node:test";import assert from"node:assert/strict";import{aircraftF1Status}from"@/domain/aircraft-f1-status";import{validateF1Definitions,validateF1Rows,type AircraftF1Snapshot}from"@/domain/aircraft-f1";
const base:AircraftF1Snapshot={canView:true,canEdit:true,revision:"x",typeCode:"320",subtype:"200",weightUnit:"Kg",definitions:[{tableId:null,tableName:"ALL",limitCondition:null,limitConditionCode:null,limitFromDate:null,limitToDate:null,limitType:null,persisted:false},{tableId:null,tableName:"SPECIAL",limitCondition:null,limitConditionCode:null,limitFromDate:null,limitToDate:null,limitType:null,persisted:false}],rows:[],variantOptions:[{code:"200",label:"320-200"},{code:"216",label:"320-216"}],registrationOptions:[{registration:"ECHGZ",variantCode:"200"},{registration:"ECHQI",variantCode:"216"}],c5Source:{mzfw:61000,mlaw:64500,mtow:73500,mrw:73900}};
test("F1 proposed C5.1 values do not configure the page until saved",()=>{const proposed={...base,rows:[{rowId:null,tableName:"ALL",variantCode:"200",registration:null,zeroFuelWeight:61000,landingWeight:64500,takeOffWeight:73500,rampTaxiWeight:73900,remarks:null,persisted:false}]};assert.equal(aircraftF1Status(proposed),"incomplete")});
test("ALL applies to every registration in the selected variant",()=>{const rows=validateF1Rows([{tableName:"ALL",variantCode:"200",registration:null,zeroFuelWeight:61000,landingWeight:64500,takeOffWeight:73500,rampTaxiWeight:73900,remarks:null}],base);assert.equal(rows[0].registration,null);assert.equal(aircraftF1Status({...base,rows}),"configured")});
test("a named table requires a registration belonging to the selected variant",()=>{assert.throws(()=>validateF1Rows([{tableName:"SPECIAL",variantCode:"216",registration:"ECHGZ",zeroFuelWeight:61000,landingWeight:64500,takeOffWeight:73500,rampTaxiWeight:73900}],base));const rows=validateF1Rows([{tableName:"SPECIAL",variantCode:"216",registration:"ECHQI",zeroFuelWeight:61000,landingWeight:64500,takeOffWeight:73500,rampTaxiWeight:73900}],base);assert.equal(rows[0].registration,"ECHQI")});
test("the same ALL table can define different carrier variants",()=>{const rows=validateF1Rows([{tableName:"ALL",variantCode:"200",zeroFuelWeight:61000,landingWeight:64500,takeOffWeight:73500,rampTaxiWeight:73900},{tableName:"ALL",variantCode:"216",zeroFuelWeight:61000,landingWeight:64500,takeOffWeight:73500,rampTaxiWeight:73900}],base);assert.equal(rows.length,2)});
test("weight hierarchy is enforced",()=>assert.throws(()=>validateF1Rows([{tableName:"ALL",variantCode:"200",zeroFuelWeight:65000,landingWeight:64500,takeOffWeight:73500,rampTaxiWeight:73900}],base)));
test("the default ALL table remains present",()=>{assert.throws(()=>validateF1Definitions([{tableName:"WINTER"}]));assert.equal(validateF1Definitions([{tableName:"ALL",limitFromDate:"2026-01-01",limitToDate:"2026-12-31"}])[0].tableName,"ALL")});

import {newF1RegistrationException} from '../src/domain/aircraft-f1';
const defaults={rowId:null,tableName:'ALL',variantCode:'200',registration:null,zeroFuelWeight:61000,landingWeight:64500,takeOffWeight:75500,rampTaxiWeight:75800,remarks:null,persisted:true};
test('F1 retains lower registration exceptions alongside ALL defaults',()=>{
 const exception={...defaults,registration:'ECHGZ',takeOffWeight:73500,rampTaxiWeight:73900};
 const rows=validateF1Rows([defaults,exception],base);
 assert.equal(rows[1].registration,'ECHGZ');assert.equal(rows[0].takeOffWeight,75500);
 assert.equal(Math.max(...rows.map(r=>r.takeOffWeight!)),75500);
});
test('F1 rejects exceptions without matching defaults, over defaults, duplicates and wrong variants',()=>{
 const exception={...defaults,registration:'ECHGZ'};
 assert.throws(()=>validateF1Rows([exception],base),/ALL defaults/);
 assert.throws(()=>validateF1Rows([defaults,{...exception,rampTaxiWeight:76000}],base),/cannot exceed/);
 assert.throws(()=>validateF1Rows([defaults,exception,exception],base),/duplicated/);
 assert.throws(()=>validateF1Rows([defaults,{...exception,registration:'ECHQI'}],base),/valid Registration/);
});
test('F1 exception drafts copy defaults and do not modify or duplicate existing entries',()=>{
 const row=newF1RegistrationException([defaults],base.registrationOptions)!;
 assert.equal(row.registration,'ECHGZ');assert.equal(row.takeOffWeight,75500);assert.equal(row.persisted,false);
 assert.equal(defaults.registration,null);
 assert.equal(newF1RegistrationException([defaults,row],base.registrationOptions),null);
});

test('minimum table can apply to all registrations and specify only applicable columns',()=>{
 const s={...base,definitions:[...base.definitions,{...base.definitions[1],tableName:'MINIMUM',limitType:'MINIMUM',persisted:true}]};
 const rows=validateF1Rows([defaults,{...defaults,tableName:'MINIMUM',zeroFuelWeight:null,landingWeight:null,takeOffWeight:40000,rampTaxiWeight:null}],s);
 assert.equal(rows[1].registration,null);assert.equal(rows[1].takeOffWeight,40000);assert.equal(rows[1].zeroFuelWeight,null);
 assert.equal(aircraftF1Status({...s,rows}),'configured');
 assert.equal(aircraftF1Status({...s,rows:[defaults]}),'partial');
 assert.throws(()=>validateF1Rows([{...rows[1],takeOffWeight:null}],s),/at least one/);
});
test('additional limiting tables require explicit minimum or maximum type',()=>{
 assert.throws(()=>validateF1Definitions([{tableName:'ALL'},{tableName:'MINIMUM'}]),/Minimum or Maximum/);
 assert.equal(validateF1Definitions([{tableName:'ALL'},{tableName:'MINIMUM',limitType:'MINIMUM'}])[1].limitType,'MINIMUM');
});
