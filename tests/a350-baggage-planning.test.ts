import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { baggageContentsForUldCount, mixedBaggageContents, type OperationalBaggageClass } from "../src/domain/baggage-commodities";
import snapshot from "./fixtures/a350-hold-board.json";

const id="00000000-0000-4000-8000-000000000001";
const otherId="00000000-0000-4000-8000-000000000002";
const classes:OperationalBaggageClass[]=[
 ["F","First Class","BF",2],["C","Business Class","BJ",4],
 ["W","Premium Economy","BP",17],["Y","Economy","BY",120],
].map(([classCode,className,commodityCode,count])=>({classCode:String(classCode),className:String(className),commodityCode:commodityCode as OperationalBaggageClass["commodityCode"],passengers:Number(count),bagsPerPassenger:1,plannedPieces:Number(count),plannedWeight:Number(count)*15,weightPerPassenger:15,plannedVolume:Number(count)*0.08525}));
type Plan={ready:boolean;uldPositionCount:number;plannedBaggageUldPositions:number;availableUldPositions:number;baggageUldPieceTargets:number[];baggageClasses:OperationalBaggageClass[];baggagePlanningNotes:string[];baggageAccommodationNotes:string[];baggageProposalNotes:string[];baggageCapacityPositions:{id:string;bays:string[]}[];baggageCapacityReservation:{uldCount:number};cargoCapacityPositions:{pallets:{id:string;bays:string[]}[];containers:{id:string;bays:string[]}[];allContainerPositions:{id:string;bays:string[]}[];baggageContainerCount:number};cargoUldAllocations:{kind:string;uldCode:string;positionCount:number}[];cargoOfferWeight:number|null;remainingPayload:number;availableBulkVolume:number};
const base={applicable:true,operatingRole:"PASSENGER",ready:true,missing:[],uldCode:"AKE",uldPositionCount:38,
 plannedBaggageUldPositions:6,plannedBaggagePieces:143,plannedBaggageWeight:2145,baggagePiecesPerUld:50,
 baggageClasses:classes,holdSystem:"MIXED",remainingPayload:50000,holdWeightCapacity:65000,
 availableBulkWeight:4000,availableBulkVolume:17,cargoPlanningDensity:100,
 bulkHolds:[{maximumWeight:4000,volume:17}]};

async function fixture(){
 const db=new PGlite();
 await db.exec(`
 create schema "Basic_Carrier_Record";create schema private;create schema auth;create schema test;
 create role anon;create role authenticated;
 create function auth.uid() returns uuid language sql stable as $$ select case when current_setting('test.anonymous',true)='yes' then null else '${id}'::uuid end $$;
 create function private.has_carrier_permission(text,text) returns boolean language sql stable as $$ select current_setting('test.denied',true) is distinct from 'yes' $$;
 create function private.has_global_permission(text) returns boolean language sql immutable as $$ select false $$;
 create table "Basic_Carrier_Record"."Operational_Flights"("Carrier_IATA" text,"Operational_Flight_ID" uuid,"Aircraft_Type_IATA" text,"Aircraft_Series_Subtype" text);
 create table "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA" text,"Aircraft_Type_IATA" text,"Aircraft_Series_Subtype" text,"ULD_ID" text,"Master_ULD_ID" text,"ULD_Type" text,"ULD_Tare_Weight" numeric,"ULD_Max_Weight" numeric,"ULD_Baggage_Max_Pieces" integer,"ULD_Baggage_Default" boolean,"ULD_Default" boolean);
 create table "Basic_Carrier_Record"."MASTER_ULD_List"("ULD_ID" text,"ULD_Volume" double precision);
 create table "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"("Carrier_IATA" text,"Aircraft_Type_IATA" text,"Aircraft_Series_Subtype" text,"Weight_Unit" text,"Volume_Unit" text);
 create table "Basic_Carrier_Record"."Carrier_ULD_Positions"("Carrier_IATA" text,"Aircraft_Type_IATA" text,"Aircraft_Series_Subtype" text,"ULD_Position_UUID" uuid,"ULD_Configuration_Code" text,"ULD_Row_Type" text,"ULD_Type" text,"ULD_Code" text,"Hold_Name_ID" text,"ULD_Position_Max_Weight" double precision);
 create table "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy"("Carrier_IATA" text,"Aircraft_Type_IATA" text,"Aircraft_Series_Subtype" text,"ULD_Position_UUID" uuid,"ULD_Configuration_Code" text,"Atomic_Bay_ID" text);
 create table "Basic_Carrier_Record"."Operational_Baggage_Accommodation"("Carrier_IATA" text,"Operational_Flight_ID" uuid,"Version" integer,"ULD_Count" integer,"ULD_Net_Weight" numeric,"Bulk_Net_Weight" numeric,"Planned_Contents" jsonb,"Accepted_By" uuid,"Accepted_At" timestamptz default now(),primary key("Carrier_IATA","Operational_Flight_ID"));
 create table test.plans(id uuid,planning jsonb);
 create function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) returns jsonb language sql stable as $$ select planning from test.plans where id=$2 $$;
 create function "Basic_Carrier_Record".get_operational_baggage_accommodation(text,uuid) returns jsonb language sql stable as $$ select to_jsonb(a) from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" a where "Operational_Flight_ID"=$2 $$;
 insert into "Basic_Carrier_Record"."Operational_Flights" values('ZZ','${id}','359','900'),('ZZ','${otherId}','763','300');
 insert into "Basic_Carrier_Record"."Carrier_ULD_Specifications" values('ZZ','359','900','AKE',null,'LD3',100,1588,50,true,true),('ZZ','359','900','PAG',null,'LD7',110,4626,null,false,false);
 insert into "Basic_Carrier_Record"."MASTER_ULD_List" values('AKE',4.3),('PAG',11.5);
 insert into "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" values('ZZ','359','900','KG','M3');
 `);
 await db.query("insert into test.plans values($1,$3),($2,$3)",[id,otherId,JSON.stringify(base)]);
 let sequence=0;
 for(const config of snapshot.d3.configurations)for(const row of config.rows){
  if(row.rowType!=="POSITION")continue;
  const uuid=`00000000-0000-4000-9000-${String(++sequence).padStart(12,"0")}`;
  await db.query('insert into "Basic_Carrier_Record"."Carrier_ULD_Positions" values(\'ZZ\',\'359\',\'900\',$1,$2,$3,$4,$5,$6,$7)',[uuid,config.code,row.rowType,row.uldType,row.uldCode,config.holdId,row.maxWeight]);
  for(const bay of row.occupiedBayIds)await db.query('insert into "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" values(\'ZZ\',\'359\',\'900\',$1,$2,$3)',[uuid,config.code,bay]);
 }
 // Install the real faulty allocation wrapper and existing save validation.
 await db.exec(readFileSync("supabase/migrations/20261019181500_passenger_cargo_uld_allocation.sql","utf8"));
 const saves=readFileSync("supabase/migrations/20261014070000_separate_bulk_baggage_categories.sql","utf8");
 await db.exec(saves.slice(saves.indexOf('create or replace function'),saves.indexOf('create or replace function "Basic_Carrier_Record".save_operational_final_traffic')));
 return db;
}
const planning=async(db:PGlite,flight=id)=>(await db.query<{result:Plan}>('select "Basic_Carrier_Record".get_operational_freight_planning(\'ZZ\',$1) result',[flight])).rows[0].result;
const contentsOf=(p:Plan,count=p.plannedBaggageUldPositions)=>baggageContentsForUldCount(p.baggageClasses,count,"AKE",50,p.baggageUldPieceTargets);
const inputOf=(contents:ReturnType<typeof contentsOf>)=>({uldCount:contents.filter(row=>row.kind==="ULD").length,uldNetWeight:contents.filter(row=>row.kind==="ULD").reduce((n,row)=>n+row.netWeight,0),bulkNetWeight:contents.filter(row=>row.kind==="BULK").reduce((n,row)=>n+row.netWeight,0),contents});
const save=(db:PGlite,input:ReturnType<typeof inputOf>,version=0)=>db.query('select "Basic_Carrier_Record".save_operational_baggage_accommodation(\'ZZ\',$1,$2,$3)',[id,version,JSON.stringify(input)]);

test("A350 baggage planning uses real D3 alternatives and enforces the packing contract",async t=>{
 const db=await fixture();
 try{
  const broken=await planning(db),otherBefore=await planning(db,otherId);
  assert.equal(broken.uldPositionCount,0,"reproduce the live all-AKE-excluded failure");
  assert.equal(broken.plannedBaggageUldPositions,0);
  // An existing all-bulk accommodation must survive the migration and all reads.
  const oldContents=baggageContentsForUldCount(classes,0,null,null);
  await db.query('insert into "Basic_Carrier_Record"."Operational_Baggage_Accommodation" values(\'ZZ\',$1,1,0,0,2145,$2,$1,now())',[id,JSON.stringify(oldContents)]);
  const savedBefore=await db.query('select * from "Basic_Carrier_Record"."Operational_Baggage_Accommodation"');
  await db.exec(readFileSync("supabase/migrations/20261022163520_a350_baggage_capacity_and_shared_premium_uld.sql","utf8"));
  await db.exec(readFileSync("supabase/migrations/20261022163956_a350_baggage_volume_argument_cast.sql","utf8"));
  await db.exec(readFileSync("supabase/migrations/20261022165656_a350_pallet_first_cargo_offer.sql","utf8"));
  assert.deepEqual(await planning(db,otherId),otherBefore,"other aircraft remain byte-for-byte equivalent");
  const savedPlanning=await planning(db);
  assert.equal(savedPlanning.plannedBaggageUldPositions,5);
  assert.equal(savedPlanning.baggageCapacityReservation.uldCount,0,"a valid saved all-bulk choice reserves no ULD slots");
  assert.deepEqual((await db.query('select * from "Basic_Carrier_Record"."Operational_Baggage_Accommodation"')).rows,savedBefore.rows);
  await db.exec('delete from "Basic_Carrier_Record"."Operational_Baggage_Accommodation"');
  const proposed=await planning(db);
  assert.equal(proposed.ready,true,JSON.stringify(proposed.baggagePlanningNotes));
  assert.equal(proposed.uldPositionCount,34);
  assert.equal(proposed.plannedBaggageUldPositions,5);
  assert.ok(proposed.availableUldPositions>=0);
  const claimed=proposed.baggageCapacityPositions.flatMap(row=>row.bays);
  assert.equal(new Set(claimed).size,claimed.length,"capacity witness never reuses an atomic bay");
  assert.deepEqual(proposed.baggageUldPieceTargets,[6,17,50,50,20]);
  assert.deepEqual(proposed.cargoUldAllocations,[{kind:"PALLET",uldCode:"PAG",uldType:"LD7",positionCount:7},{kind:"CONTAINER",uldCode:"AKE",uldType:"LD3",positionCount:3}]);
  const cargoWitness=proposed.cargoCapacityPositions;
  assert.equal(cargoWitness.allContainerPositions.length,8);
  assert.equal(cargoWitness.baggageContainerCount,5);
  const cargoBays=[...cargoWitness.pallets,...cargoWitness.allContainerPositions].flatMap(row=>row.bays);
  assert.equal(new Set(cargoBays).size,cargoBays.length,"pallets, cargo containers and baggage reserve are simultaneously compatible");
  assert.equal(proposed.remainingPayload,49500,"reserve five baggage ULD tares once");

  const rejects=async(fn:()=>Promise<unknown>,message:RegExp)=>{await db.exec('savepoint expected_failure');try{await assert.rejects(fn,message)}finally{await db.exec('rollback to savepoint expected_failure;release savepoint expected_failure')}};
  const run=async(name:string,fn:()=>Promise<void>)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback')}});

  await run("BF/BJ share one ULD, with all pieces, net weight and category identities conserved",async()=>{
   const contents=contentsOf(proposed);
   assert.deepEqual(contents.map(row=>row.pieces),[6,17,50,50,20]);
   assert.deepEqual(contents[0].commodities.map(row=>[row.commodityCode,row.pieces,row.netWeight]),[["BF",2,30],["BJ",4,60]]);
   assert.equal(contents.reduce((n,row)=>n+row.netWeight,0),2145);
   await save(db,inputOf(contents));
   await rejects(()=>save(db,inputOf(contents)),/changed\. Reload/);
  });
  await run("a smaller operator-selected count leaves a reconciled Bulk remainder",async()=>{
   const contents=contentsOf(proposed,4);
   assert.deepEqual(contents.at(-1)?.commodities.map(row=>[row.commodityCode,row.pieces]),[["BY",20]]);
   await save(db,inputOf(contents));
   const p=await planning(db);assert.equal(p.baggageCapacityReservation.uldCount,4);assert.equal(p.remainingPayload,49600);
  });
  await run("an operator's larger valid ULD allocation reserves actual slots and tares",async()=>{
   const contents=mixedBaggageContents(classes,[6,17,30,30,30,30],"AKE");
   await save(db,inputOf(contents));
   const p=await planning(db);assert.equal(p.plannedBaggageUldPositions,5);assert.equal(p.baggageCapacityReservation.uldCount,6);assert.equal(p.remainingPayload,49400);
  });
  await run("changed forecasts flag stale saved baggage without rewriting it, and allow explicit correction",async()=>{
   await save(db,inputOf(contentsOf(proposed)));
   const before=await db.query('select * from "Basic_Carrier_Record"."Operational_Baggage_Accommodation"');
   await db.exec(`update test.plans set planning=jsonb_set(jsonb_set(planning,'{baggageClasses,3,plannedPieces}','121'),'{plannedBaggagePieces}','144')`);
   const p=await planning(db);assert.equal(p.ready,false);assert.equal(p.cargoOfferWeight,null);assert.match(p.baggageAccommodationNotes[0],/Review the saved baggage/);
   assert.deepEqual((await db.query('select * from "Basic_Carrier_Record"."Operational_Baggage_Accommodation"')).rows,before.rows);
   await save(db,inputOf(contentsOf(p)),1);
   assert.equal((await planning(db)).ready,true);
  });
  await run("an intentional all-bulk override is allowed only if it fits Bulk capacity",async()=>{
   await save(db,inputOf(contentsOf(proposed,0)));
   await db.exec(`update test.plans set planning=jsonb_set(planning,'{bulkHolds}','[{"maximumWeight":4000,"volume":1}]')`);
   await rejects(()=>save(db,inputOf(contentsOf(proposed,0)),1),/Bulk weight or volume/);
  });
  await run("manual reallocation cannot hide an overloaded ULD inside reconciled totals",async()=>{
   const contents=contentsOf(proposed);
   contents[0].netWeight+=1400;contents[0].commodities[0].netWeight+=1400;
   contents[2].netWeight-=700;contents[2].commodities[0].netWeight-=700;
   contents[3].netWeight-=700;contents[3].commodities[0].netWeight-=700;
   await rejects(()=>save(db,inputOf(contents)),/maximum gross weight or forecast volume/);
  });
  await run("manual contents cannot exceed forecast volume even below the piece and gross limits",async()=>{
   await db.exec(`update test.plans set planning=jsonb_set(planning,'{baggageClasses,3,plannedVolume}','18')`);
   await rejects(()=>save(db,inputOf(contentsOf(proposed))),/maximum gross weight or forecast volume/);
  });
  await run("manual ULD contents must use the default code and preserve each category",async()=>{
   const contents=contentsOf(proposed);contents[0].uldCode="PAG";
   await rejects(()=>save(db,inputOf(contents)),/Default Baggage ULD/);
   contents[0].uldCode="AKE";contents[0].commodities[0].classCode="Y";
   await rejects(()=>save(db,inputOf(contents)),/forecast class/);
  });
  await run("missing D3 footprints produce a visible configuration note",async()=>{
   await db.exec('delete from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" where "ULD_Position_UUID"=(select "ULD_Position_UUID" from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "ULD_Code"=\'AKE\' limit 1)');
   const p=await planning(db);assert.equal(p.ready,false);assert.match(p.baggagePlanningNotes[0],/occupancy mapping/);assert.equal(p.cargoOfferWeight,null);
  });
  await run("unknown limits never silently turn all baggage into Bulk",async()=>{
   await db.exec('update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_Baggage_Max_Pieces"=null');
   const p=await planning(db);assert.equal(p.ready,false);assert.match(p.baggagePlanningNotes[0],/limits/);
   await rejects(()=>save(db,inputOf(contentsOf(proposed))),/limits/);
  });
  await run("ambiguous configurations and unvalidated units cannot produce a ready proposal",async()=>{
   await db.exec('update "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" set "Volume_Unit"=\'FT3\'');
   let p=await planning(db);assert.equal(p.ready,false);assert.match(p.baggagePlanningNotes[0],/KG\/M3/);
   await db.exec('update "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" set "Volume_Unit"=\'M3\';update "Basic_Carrier_Record"."Carrier_ULD_Positions" set "ULD_Configuration_Code"=\'B\' where "ULD_Position_UUID"=(select "ULD_Position_UUID" from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "ULD_Code"=\'AKE\' limit 1)');
   p=await planning(db);assert.equal(p.ready,false);assert.match(p.baggagePlanningNotes[0],/one complete D3/);
  });
  await run("capacity shortfall uses Bulk only within its real capacity",async()=>{
   await db.exec('delete from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "ULD_Code"=\'AKE\' and "ULD_Position_UUID" not in(select "ULD_Position_UUID" from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "ULD_Code"=\'AKE\' order by "ULD_Position_UUID" limit 2)');
   const p=await planning(db);assert.equal(p.plannedBaggageUldPositions,2);assert.equal(p.ready,true);assert.ok(p.availableBulkVolume<17);
   await db.exec(`update test.plans set planning=jsonb_set(planning,'{bulkHolds}','[{"maximumWeight":100,"volume":1}]')`);
   const failed=await planning(db);assert.equal(failed.ready,false);assert.match(failed.baggageProposalNotes[0],/Bulk weight or volume/);
  });
  await run("anonymous and unauthorised calls retain access controls",async()=>{
   await db.exec("set local test.anonymous='yes'");await rejects(()=>planning(db),/access denied/);
   await db.exec("set local test.anonymous='no';set local test.denied='yes'");await rejects(()=>save(db,inputOf(contentsOf(proposed))),/operation denied/);
  });
  await run("packing respects exact boundaries and each independent limit",async()=>{
   const pack=async(rows:OperationalBaggageClass[],pieces=50,net=1488,volume=4.3)=>(await db.query<{targets:number[]}>('select private.a350_baggage_piece_targets($1,$2,$3,$4) targets',[JSON.stringify(rows),pieces,net,volume])).rows[0].targets;
   const premium=classes.slice(0,2).map(row=>({...row,plannedPieces:20,plannedWeight:300,plannedVolume:1.7}));
   assert.deepEqual(await pack(premium),[40]);
   assert.deepEqual(await pack(premium,50,600,3.4),[40],"exact weight/volume boundary fits");
   assert.deepEqual(await pack(premium,50,599,4.3),[20,20],"combined net weight fails");
   assert.deepEqual(await pack(premium,50,1488,3.39),[20,20],"combined volume fails");
   assert.deepEqual(await pack(premium,39),[20,20],"configured piece limit is additional");
   assert.deepEqual(await pack([{...classes[3],plannedPieces:100,plannedWeight:2000,plannedVolume:8}],999,600,10),[30,30,30,10]);
   assert.deepEqual(await pack([{...classes[3],plannedPieces:100,plannedWeight:1000,plannedVolume:10}],999,1488,2.5),[25,25,25,25]);
   await rejects(()=>pack([{...classes[0],plannedVolume:null}]),/volume forecast/);
   assert.deepEqual(await pack(classes.map(row=>({...row,plannedPieces:0,plannedWeight:0,plannedVolume:0}))),[]);
  });
  await run("compatible-set search agrees with exhaustive enumeration of conflicting alternatives",async()=>{
   for(let scenario=1;scenario<=12;scenario++){
    const positions=Array.from({length:8},(_,i)=>({id:String(i),bays:[`own:${i}`]}));
    for(let a=0;a<8;a++)for(let b=a+1;b<8;b++)if((a*17+b*13+scenario*7)%5<2){const bay=`edge:${a}:${b}`;positions[a].bays.push(bay);positions[b].bays.push(bay)}
    let maximum=0;
    for(let mask=0;mask<256;mask++){const bays=positions.filter((_,i)=>mask&(1<<i)).flatMap(row=>row.bays);if(new Set(bays).size===bays.length)maximum=Math.max(maximum,positions.filter((_,i)=>mask&(1<<i)).length)}
    const selected=(await db.query<{selected:{id:string;bays:string[]}[]}>('select private.compatible_baggage_positions($1) selected',[JSON.stringify(positions)])).rows[0].selected;
    assert.equal(selected.length,maximum);
    const bays=selected.flatMap(row=>row.bays);assert.equal(new Set(bays).size,bays.length);
   }
  });
  await run("pallet priority preserves baggage and fills leftover container space",async()=>{
   const containers=Array.from({length:4},(_,i)=>({id:`C${i}`,bays:[String(i)],netWeightCapacity:1000}));
   const pallets=[{id:"P1",bays:["0","1"],netWeightCapacity:2000},{id:"P2",bays:["1","2","3"],netWeightCapacity:2500}];
   const calculate=async(reserve:number)=>(await db.query<{result:{pallets:{id:string}[];containers:{id:string}[]}}> ('select private.a350_pallet_first_capacity($1,$2,$3) result',[JSON.stringify(pallets),JSON.stringify(containers),reserve])).rows[0].result;
   let result=await calculate(1);assert.deepEqual(result.pallets.map(p=>p.id),["P1"]);assert.equal(result.containers.length,2,"maximise residual containers after pallet priority");
   result=await calculate(2);assert.equal(result.pallets.length,1);assert.equal(result.containers.length,2);
   result=await calculate(3);assert.equal(result.pallets.length,0);assert.equal(result.containers.length,4,"never trade reserved baggage capacity for a pallet");
   await rejects(()=>calculate(5),/preserves the baggage/);
  });
 }finally{await db.close()}
});
