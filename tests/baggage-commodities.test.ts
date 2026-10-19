import test from"node:test";
import assert from"node:assert/strict";
import{baggageContentsForUldCount,defaultBaggageCommodityCode,mixedBaggageContents,type OperationalBaggageClass}from"../src/domain/baggage-commodities";

const classes:OperationalBaggageClass[]=[
 {classCode:"C",className:"Business",commodityCode:"BJ",passengers:16,bagsPerPassenger:1,plannedPieces:16,weightPerPassenger:15,plannedWeight:240,plannedVolume:null},
 {classCode:"Y",className:"Economy",commodityCode:"BY",passengers:135,bagsPerPassenger:1,plannedPieces:135,weightPerPassenger:15,plannedWeight:2025,plannedVolume:null},
];

test("baggage commodities default across four passenger cabins",()=>{
 assert.equal(defaultBaggageCommodityCode("F","First"),"BF");
 assert.equal(defaultBaggageCommodityCode("C","Business"),"BJ");
 assert.equal(defaultBaggageCommodityCode("W","Premium Economy"),"BP");
 assert.equal(defaultBaggageCommodityCode("Y","Economy"),"BY");
 assert.equal(defaultBaggageCommodityCode("R","Regional"),"B");
});

test("the proposed plan keeps each baggage commodity in its own ULD",()=>{
 const rows=baggageContentsForUldCount(classes,3,"AKE",47);
 assert.deepEqual(rows.map(row=>[row.kind,row.pieces,row.commodities.map(item=>`${item.commodityCode}/${item.pieces}`)]),[
  ["ULD",16,["BJ/16"]],
  ["ULD",47,["BY/47"]],
  ["ULD",47,["BY/47"]],
  ["BULK",41,["BY/41"]],
 ]);
 assert.equal(rows.reduce((sum,row)=>sum+row.netWeight,0),2265);
});

test("PE901 proposes one BJ DPE and seven BY DPEs at the carrier limit",()=>{
 const rows=baggageContentsForUldCount([
  {...classes[0],plannedPieces:10,plannedWeight:200},
  {...classes[1],plannedPieces:195,plannedWeight:3900},
 ],8,"DPE",30);
 assert.deepEqual(rows.map(row=>[row.kind,row.pieces,row.commodities.map(item=>`${item.commodityCode}/${item.pieces}`)]),[
  ["ULD",10,["BJ/10"]],
  ["ULD",30,["BY/30"]],["ULD",30,["BY/30"]],["ULD",30,["BY/30"]],
  ["ULD",30,["BY/30"]],["ULD",30,["BY/30"]],["ULD",30,["BY/30"]],
  ["ULD",15,["BY/15"]],
 ]);
});

test("manual ULD totals redistribute class baggage and leave one mixed Bulk balance",()=>{
 const manualClasses=[{...classes[0],plannedPieces:12,plannedWeight:180},{...classes[1],plannedPieces:108,plannedWeight:1620}];
 const rows=mixedBaggageContents(manualClasses,[40,40,30],"AKE");
 assert.deepEqual(rows.map(row=>[row.kind,row.pieces,row.commodities.map(item=>`${item.commodityCode}/${item.pieces}`)]),[
  ["ULD",40,["BJ/12","BY/28"]],
  ["ULD",40,["BY/40"]],
  ["ULD",30,["BY/30"]],
  ["BULK",10,["BY/10"]],
 ]);
 assert.equal(rows.reduce((sum,row)=>sum+row.netWeight,0),1800);
});

test("Bulk-only baggage remains one load item per baggage category",()=>{
 const rows=baggageContentsForUldCount([{...classes[0],plannedPieces:12,plannedWeight:180},{...classes[1],plannedPieces:90,plannedWeight:1350}],0,null,null);
 assert.deepEqual(rows.map(row=>[row.loadId,row.commodityCode,row.pieces,row.netWeight]),[
  ["PLANNED_BAGGAGE:BJ:BULK","BJ",12,180],
  ["PLANNED_BAGGAGE:BY:BULK","BY",90,1350],
 ]);
});
