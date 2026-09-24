import test from "node:test";
import assert from "node:assert/strict";
import {b3Statuses} from "../src/domain/b3-status";
import type {PassengerSnapshot} from "../src/domain/passenger-weights";

const values={adult:84,male:93,female:75,child:35,infant:0,handBaggage:7,includesHandBaggage:false,remarks:""};
const base:PassengerSnapshot={canView:true,canEdit:true,revision:"r",unit:"KG",defaultWeights:values,rows:[],variations:[],masterVariations:[],classes:[{code:"F",description:"First"}],variationsReviewed:false,classWeightsReviewed:false};

test("B3 mandatory standard weights block the page",()=>{
  assert.deepEqual(b3Statuses({...base,defaultWeights:null}),{standard:"incomplete",variations:"incomplete",classWeights:"incomplete",page:"incomplete"});
});

test("included hand baggage still permits separate variation passenger tables",()=>{
  const included={...values,handBaggage:null,includesHandBaggage:true};
  assert.deepEqual(b3Statuses({...base,defaultWeights:included,variationsReviewed:true,classWeightsReviewed:true}),{standard:"configured",variations:"configured",classWeights:"configured",page:"configured"});
});

test("review confirms that standard passenger weights cover all variations when no overrides are needed",()=>{
  assert.deepEqual(b3Statuses({...base,variationsReviewed:true,classWeightsReviewed:true}),{standard:"configured",variations:"configured",classWeights:"configured",page:"configured"});
});

test("valid populated optionals are configured without relying on review metadata",()=>{
  const snapshot={...base,variations:[{code:"DOM",description:"Domestic"}],rows:[{...values,id:"1",classCode:"F",variation:"DOM"}]};
  assert.deepEqual(b3Statuses(snapshot),{standard:"configured",variations:"configured",classWeights:"configured",page:"configured"});
});

test("an unreviewed empty optional section makes an otherwise valid page partial",()=>{
  assert.equal(b3Statuses({...base,variations:[{code:"DOM",description:"Domestic"}]}).page,"partial");
});

test("an all-class variation table is configured",()=>{
  const snapshot={...base,variations:[{code:"DOM",description:"Domestic"}],rows:[{...values,id:"1",classCode:null,variation:"DOM"}]};
  assert.equal(b3Statuses(snapshot).classWeights,"configured");
});
