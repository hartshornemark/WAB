import test from "node:test";
import assert from "node:assert/strict";
import {b1Statuses,b1DensityStatus} from "../src/domain/b1-status";
import {emptyDetails,type DetailsSnapshot} from "../src/domain/carrier-details";
import type {DensitySnapshot} from "../src/domain/density-settings";

const details:DetailsSnapshot={canView:true,canEdit:true,exists:true,revision:"d",values:{...emptyDetails,weightUnit:"KG",volumeUnit:"m3",weightMethod:"DRY_OPERATING"}};
const density:DensitySnapshot={canView:true,canEdit:true,exists:true,weightUnit:"KG",volumeUnit:"m3",revision:"x",values:{baggage:"176",cargo:"212",mail:"212"}};
const classes={canView:true,canEdit:true,revision:"c",rows:[{code:"Y",priority:1,description:"Economy"}],defaults:[]};
const commodities={canView:true,canEdit:true,revision:"m",rows:[{code:"B",description:"Baggage"}],defaults:[]};

test("B1 is configured when all four saved sections satisfy their rules",()=>{
 const status=b1Statuses(details,density,classes,commodities);
 assert.deepEqual(status,{units:"configured",densities:"configured",classCodes:"configured",commodityCodes:"configured",page:"configured"});
});

test("Index display precision is required and accepts one or two decimal places",()=>{
 assert.equal(b1Statuses({...details,values:{...details.values,indexDecimalPlaces:""}},density,classes,commodities).units,"partial");
 assert.equal(b1Statuses({...details,values:{...details.values,indexDecimalPlaces:"2"}},density,classes,commodities).units,"configured");
});

test("blank densities are incomplete and a partial set remains partial",()=>{
 const blank={...density,exists:false,values:{baggage:"",cargo:"",mail:""}};
 assert.equal(b1DensityStatus(blank),"incomplete");
 assert.equal(b1DensityStatus({...blank,values:{baggage:"176",cargo:"",mail:""}}),"partial");
});

test("all three positive density values configure the section",()=>{
 assert.equal(b1DensityStatus(density),"configured");
 assert.equal(b1Statuses(details,density,classes,commodities).page,"configured");
});

test("missing saved class or commodity rows prevents B1 from being configured",()=>{
 assert.equal(b1Statuses(details,density,{...classes,rows:[]},commodities).page,"partial");
 assert.equal(b1Statuses(details,density,{...classes,rows:[]},{...commodities,rows:[]}).page,"partial");
});

test("B1 does not require Passenger Class Codes for an all-Freighter carrier",()=>{
 const status=b1Statuses(details,density,{...classes,rows:[]},commodities,false);
 assert.equal(status.classCodes,"not_required");
 assert.equal(status.page,"configured");
});
