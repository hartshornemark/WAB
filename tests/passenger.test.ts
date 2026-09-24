import test from "node:test";
import assert from "node:assert/strict";
import { validatePassengerValues, validatePassengerRows, validateVariations, passengerDraft, PassengerInvalid, type PassengerSnapshot } from "../src/domain/passenger-weights";
const values={adult:84,male:93,female:75,child:35,infant:0,handBaggage:null,includesHandBaggage:true,remarks:""};
const snapshot:PassengerSnapshot={canView:true,canEdit:true,revision:"r",unit:"KG",defaultWeights:values,rows:[],variations:[{code:"DOM",description:"Domestic"}],masterVariations:[],classes:[{code:"F",description:"First"}],variationsReviewed:true,classWeightsReviewed:false};
test("passenger default drafts preserve zero and optional adult",()=>{
 assert.deepEqual(validatePassengerValues(passengerDraft(values)),values);
 assert.equal(validatePassengerValues({...passengerDraft(values),adult:""}).adult,null);
 assert.equal(passengerDraft(values).infant,"0");
});
test("separate hand baggage required; inclusion retains entered weight",()=>{
 assert.throws(()=>validatePassengerValues({...values,includesHandBaggage:false}),PassengerInvalid);
 assert.equal(validatePassengerValues({...values,includesHandBaggage:false,handBaggage:0}).handBaggage,0);
 assert.equal(validatePassengerValues({...values,handBaggage:5}).handBaggage,5);
});
test("passenger weight validation rejects negatives, fractions and missing required values",()=>{
 for(const invalid of [{male:0},{female:null},{child:1.5},{infant:-1},{adult:0},{male:""},{handBaggage:-1},{male:2147483648},{includesHandBaggage:"true"},{remarks:"x".repeat(2001)}])
 assert.throws(()=>validatePassengerValues({...values,...invalid}),PassengerInvalid);
});
test("flight variations normalise codes, reject duplicate descriptions and invalid values",()=>{
 assert.deepEqual(validateVariations([{code:"dom",description:" Domestic "}]),[{code:"DOM",description:"Domestic"}]);
 for(const list of [[{code:"DO",description:"Domestic"}],[{code:"DOM",description:""}],[{code:"DOM",description:"Domestic"},{code:"INT",description:"domestic"}],[{code:"DOM",description:"A"},{code:"dom",description:"B"}]])
 assert.throws(()=>validateVariations(list),PassengerInvalid);
 assert.deepEqual(validateVariations([]),[]);
});
test("class weights use saved classes and adopted variations; pairs must be unique",()=>{
 const row={...values,id:null,classCode:"F",variation:null};
 assert.equal(validatePassengerRows([row],snapshot).length,1);
 for(const rows of [[{...row,classCode:"Q"}],[{...row,variation:"INT"}],[row,row],[{...row,id:"someone-elses-row"}]])
 assert.throws(()=>validatePassengerRows(rows,snapshot),PassengerInvalid);
 assert.equal(validatePassengerRows([row,{...row,variation:"DOM"}],snapshot).length,2);
});
test("a named variation may define passenger weights for all classes",()=>{
 const row={...values,id:null,classCode:null,variation:"DOM"};
 assert.equal(validatePassengerRows([row],snapshot)[0].classCode,null);
 assert.throws(()=>validatePassengerRows([{...row,variation:null}],snapshot),PassengerInvalid);
 assert.throws(()=>validatePassengerRows([row,row],snapshot),PassengerInvalid);
});
