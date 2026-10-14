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

test("one ULD can retain several individually expressed baggage commodities",()=>{
 const rows=baggageContentsForUldCount(classes,3,"AKE",47);
 assert.deepEqual(rows.map(row=>[row.kind,row.pieces,row.commodities.map(item=>`${item.commodityCode}/${item.pieces}`)]),[
  ["ULD",47,["BJ/16","BY/31"]],
  ["ULD",47,["BY/47"]],
  ["ULD",47,["BY/47"]],
  ["BULK",10,["BY/10"]],
 ]);
 assert.equal(rows.reduce((sum,row)=>sum+row.netWeight,0),2265);
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
