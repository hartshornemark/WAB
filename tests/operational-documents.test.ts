import test from "node:test";
import assert from "node:assert/strict";
import { notocReadyForLoadsheet, operationalLoadsheetDistribution, operationalNotocDetailComplete, operationalNotocDisplayStatus, OperationalDocumentInvalid, orderOperationalNotocRows, seedOperationalNotocDetails, validateOperationalNotocDetails, type OperationalNotocRow } from "../src/domain/operational-documents";
import type { FreightLoadItem, FreightSpecialLoadOption } from "../src/domain/freight-acceptance";
import type { LoadPlanningProblem } from "../src/domain/load-planning-solver";

const options:FreightSpecialLoadOption[]=[{code:"RMD",description:"Miscellaneous dangerous goods",dangerousGoods:true,cargoAircraftOnly:false,classes:["9"]},{code:"AVI",description:"Live animals",dangerousGoods:false,cargoAircraftOnly:false}];
const item:FreightLoadItem={lineId:"load-1",loadType:"ULD",uldId:"AKE12345ZZ",grossWeight:500,netWeight:433,planningWeight:500,unloadingStation:"BKK",destination:null,commodity:"CARGO",pieces:1,volume:null,specialHandlingCodes:["AVI"],includedLoads:[{code:"RMD",weight:10,dangerousGoods:true}],dangerousGoods:true,remarks:null,source:"MANUAL",sourceReference:null,uldResolution:null};

test("code-only NOTOC data can be saved as preliminary",()=>{
 const rows=seedOperationalNotocDetails([item],options);
 assert.equal(rows.length,2);
 assert.equal(rows.find(row=>row.code==="RMD")?.classDivision,"9");
 assert.doesNotThrow(()=>validateOperationalNotocDetails(rows,[item],options,false));
});

test("final dangerous-goods NOTOC requires regulatory detail",()=>{
 const rows=seedOperationalNotocDetails([item],options);
 assert.throws(()=>validateOperationalNotocDetails(rows,[item],options,true),OperationalDocumentInvalid);
 const completed=rows.map(row=>row.category==="DANGEROUS_GOODS"?{...row,airwayBillNumber:"123-12345675",properShippingName:"Environmentally hazardous substance, liquid, n.o.s.",unIdNumber:"UN3082",classDivision:"9",numberOfPackages:1,netQuantityPerPackage:"10 KG",ergCode:"9L"}:row);
 assert.equal(operationalNotocDetailComplete(rows.find(row=>row.code==="RMD")!),false);
 assert.equal(operationalNotocDetailComplete(completed.find(row=>row.code==="RMD")!),true);
 assert.doesNotThrow(()=>validateOperationalNotocDetails(completed,[item],options,true));
});

test("loadsheet readiness requires a final NOTOC whenever special load data exist",()=>{
 assert.equal(notocReadyForLoadsheet([item],"DRAFT"),false);
 assert.equal(notocReadyForLoadsheet([item],"NOT_REQUIRED"),false);
 assert.equal(notocReadyForLoadsheet([item],"FINAL"),true);
 assert.equal(notocReadyForLoadsheet([{...item,dangerousGoods:false,includedLoads:[],specialHandlingCodes:[]}],"NOT_REQUIRED"),true);
});

test("a complete non-dangerous special load is shown as a required printable NOTOC",()=>{
 const specialItem={...item,dangerousGoods:false,includedLoads:[],specialHandlingCodes:["AVI"]};
 const rows=seedOperationalNotocDetails([specialItem],options);
 assert.equal(rows.length,1);
 assert.equal(rows[0].category,"SPECIAL_LOAD");
 assert.equal(operationalNotocDetailComplete(rows[0]),true);
 assert.equal(operationalNotocDisplayStatus(true,"EMPTY",true,0),"REQUIRED · READY");
});

test("printed NOTOC rows follow operational offload order and then position",()=>{
 const detail=seedOperationalNotocDetails([item],options)[0],row=(loadId:string,stationOfUnloading:string,position:string):OperationalNotocRow=>({...detail,key:`${loadId}:RMD`,loadId,stationOfUnloading,position,uldId:"AKE12345ZZ"}),rows=[row("later-a10","AAA","A10"),row("first","ZZZ","A1"),row("later-a2","AAA","A2")],load=(id:string,unloadOrder:number)=>({id,description:id,loadType:"ULD" as const,weightKg:500,volumeLitres:null,uldCode:"AKE",unloadOrder,lockedPositionId:null,specialLoadCodes:["RMD"],dangerousGoodsClasses:["9"]}),problem:LoadPlanningProblem={version:1,timeLimitSeconds:2,idealTrimIndexScaled:null,loads:[load("later-a10",1),load("first",0),load("later-a2",1)],positions:[],incompatiblePairs:[],specialLoadLimits:[]};
 assert.deepEqual(orderOperationalNotocRows(rows,problem).map(entry=>entry.loadId),["first","later-a2","later-a10"]);
});

test("loadsheet distribution aggregates bays into ordered hold totals",()=>{
 const load=(id:string,weightKg:number)=>({id,description:id,loadType:"ULD" as const,weightKg,volumeLitres:null,uldCode:"AKE",unloadOrder:0,lockedPositionId:null,specialLoadCodes:[],specialLoadDetails:[],dangerousGoodsClasses:[],emptyUld:false}),position=(id:string,locationRef:string,holdId:string)=>({id,description:id,loadType:"ULD" as const,acceptedUldCodes:["AKE"],maximumWeightKg:5000,maximumVolumeLitres:null,occupiedBayIds:[id],handlingRank:0,simplicityGroup:`ULD:LOWER:${holdId}`,indexPerKgScaled:0,holdId,locationRef,segregationGroup:id,balanceArm:0,deckCode:"LOWER"}),problem:LoadPlanningProblem={version:1,timeLimitSeconds:2,idealTrimIndexScaled:null,loads:[load("a",720),load("b",450),load("c",900)],positions:[position("p12","12","1"),position("p13","13","1"),position("p21","21","2"),position("p31","31","3")],incompatiblePairs:[],specialLoadLimits:[]},solution={status:"FEASIBLE" as const,assignments:[{loadId:"a",positionId:"p13"},{loadId:"b",positionId:"p12"},{loadId:"c",positionId:"p21"}],sequencePenalty:0,usedSimplicityGroups:3,trimDeviationScaled:0,engine:"TEST",solveMilliseconds:1,messages:[]};
 assert.deepEqual(operationalLoadsheetDistribution(problem,solution),[{location:"1",weight:1170},{location:"2",weight:900},{location:"3",weight:0}]);
});
