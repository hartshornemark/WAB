import test from "node:test";
import assert from "node:assert/strict";
import { balancePointWithinEnvelope, calculateFinalPayloadCapability, calculateOperationalFuelEffect, fuelIndexAtWeight, operationalEnvelopeBoundary, operationalEnvelopeConfigured, operationalEnvelopeSelection, validateOperationalFuelInput } from "../src/domain/operational-fuel";

const formula={datum:0,referenceArm:0,constantK:0,constantC:1000,macRcLength:10,lemacLerc:0};
const curve=[{fuelWeight:0,indexValue:0},{fuelWeight:5000,indexValue:2},{fuelWeight:10000,indexValue:5}];

test("operational fuel validates preliminary and final inputs",()=>{
 assert.deepEqual(validateOperationalFuelInput({configurationCode:"2act",specificGravity:.8,blockFuel:9000,taxiFuel:300,tripFuel:6000,finalise:false}),{configurationCode:"2ACT",specificGravity:.8,blockFuel:9000,taxiFuel:300,tripFuel:6000,finalise:false});
 assert.throws(()=>validateOperationalFuelInput({configurationCode:null,specificGravity:.8,blockFuel:9000,taxiFuel:300,tripFuel:9000,finalise:true}),/Trip fuel/);
});

test("fuel curve interpolation calculates ramp TOW and LAW independently of load-plan edition",()=>{
 assert.equal(fuelIndexAtWeight(curve,7500),3.5);
 const result=calculateOperationalFuelEffect({zfw:{weight:50000,indexValue:45,macValue:9},blockFuel:9000,taxiFuel:500,tripFuel:6000,curve,formula});
 assert.equal(result.takeOffFuel,8500);assert.equal(result.landingFuel,2500);
 assert.deepEqual([result.ramp.weight,result.takeOff.weight,result.landing.weight],[59000,58500,52500]);
 assert.ok(result.takeOff.indexValue>result.landing.indexValue);
});

test("conditional TOW and LAW envelopes are selected by the applicable fuel quantity",()=>{
 const boundary={fwd:[{weight:50000,indexValue:40,macValue:null},{weight:70000,indexValue:45,macValue:null}],aft:[{weight:50000,indexValue:70,macValue:null},{weight:70000,indexValue:75,macValue:null}]};
 const values={maximumWeights:{mrw:71000,tow:70000,law:65000,zfw:60000},envelopes:{tow:boundary,law:boundary,zfw:boundary},envelopeModes:{tow:"CONDITIONAL",law:"STANDARD",zfw:"STANDARD"},conditionalEnvelopes:{tow:[{id:"1",code:"LOW",conditionBasis:"TAKE_OFF_FUEL",conditionDescription:"",lowerBound:0,lowerInclusive:true,upperBound:10000,upperInclusive:true,boundary}],law:[],zfw:[]}} as never;
 assert.equal(operationalEnvelopeBoundary(values,"tow",8500,null),boundary);
 assert.equal(operationalEnvelopeSelection(values,"tow",8500,null)?.code,"LOW");
 assert.equal(balancePointWithinEnvelope({weight:58500,indexValue:50,macValue:20},boundary),true);
 assert.equal(balancePointWithinEnvelope({weight:58500,indexValue:80,macValue:40},boundary),false);
});

test("an absent LAW envelope is unresolved rather than outside the envelope",()=>{
 const boundary={fwd:[{weight:50000,indexValue:40,macValue:null},{weight:80000,indexValue:45,macValue:null}],aft:[{weight:50000,indexValue:70,macValue:null},{weight:80000,indexValue:75,macValue:null}]};
 const values={maximumWeights:{mrw:81000,tow:80000,law:75000,zfw:70000},envelopes:{tow:boundary,law:{fwd:[],aft:[]},zfw:boundary},envelopeModes:{tow:"STANDARD",law:"STANDARD",zfw:"STANDARD"}} as never;
 assert.equal(operationalEnvelopeBoundary(values,"law",4500,null),null);
 assert.equal(operationalEnvelopeConfigured(values,"law"),false);
 assert.equal(balancePointWithinEnvelope({weight:70000,indexValue:60,macValue:25},operationalEnvelopeBoundary(values,"tow",12000,null)),true);
});

test("the saved A321P2F landing point is within the fallback TOW envelope",()=>{
 const tow={
  fwd:[{weight:47500,indexValue:27.96,macValue:null},{weight:71000,indexValue:15.15,macValue:null},{weight:83000,indexValue:27.75,macValue:null},{weight:89000,indexValue:25.87,macValue:null},{weight:91500,indexValue:30.84,macValue:null},{weight:93000,indexValue:38.22,macValue:null}],
  aft:[{weight:47500,indexValue:41.78,macValue:null},{weight:79200,indexValue:84.05,macValue:null},{weight:81800,indexValue:87.51,macValue:null},{weight:93000,indexValue:81.19,macValue:null}],
 };
 assert.equal(balancePointWithinEnvelope({weight:73037,indexValue:60.64,macValue:28},tow),true);
 assert.equal(balancePointWithinEnvelope({weight:80837,indexValue:62.04,macValue:28.1},tow),true);
});

test("final payload capability applies the most restrictive fuel-related structural limit",()=>{
 const result=calculateFinalPayloadCapability({dryOperatingWeight:46000,acceptedCargoWeight:22465,nonCargoTrafficWeight:0,takeOffFuel:11700,landingFuel:5000,maximumWeights:{mrw:77000,tow:76000,law:71000,zfw:73800}});
 assert.deepEqual(result,{maximumAllowableTrafficLoad:18300,allowedTrafficLoad:18300,acceptedCargoWeight:22465,actualTrafficLoad:22465,operationalUnderload:-4165,limitingFactor:"MTOW"});
});

test("actual traffic load includes passenger traffic without capping ATL to the Cargo Offer",()=>{
 const result=calculateFinalPayloadCapability({dryOperatingWeight:45000,acceptedCargoWeight:3000,nonCargoTrafficWeight:12000,takeOffFuel:9700,landingFuel:4000,maximumWeights:{mrw:77000,tow:76000,law:71000,zfw:73800}});
 assert.equal(result.maximumAllowableTrafficLoad,21300);
 assert.equal(result.allowedTrafficLoad,21300);
 assert.equal(result.actualTrafficLoad,15000);
 assert.equal(result.operationalUnderload,6300);
});
