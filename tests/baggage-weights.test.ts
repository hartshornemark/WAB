import test from 'node:test';
import assert from 'node:assert/strict';
import {validateBaggage,newBaggageRecord,BaggageConflict,BaggageDenied,type BaggageRecord,type BaggageSnapshot} from '../src/domain/baggage-weights';
import {createBaggageWeights} from '../src/application/baggage-weights';
import type {AuthService} from '../src/ports/auth-service';
import type {CarrierRepository} from '../src/ports/carrier-repository';
const baseline:BaggageRecord={id:'baseline',baseline:true,values:{...newBaggageRecord('weights').values,passengerMethod:'UNSET'}};
const snapshot:BaggageSnapshot={canView:true,canEdit:true,revision:'v1',unit:'KG',volumeUnit:'m3',operationMode:'STANDARD',defaultPerPiece:true,checkedBaggageDensity:'176',classes:[{code:'F',description:'First'}],variations:[{code:'DOM',description:'Domestic'}],standardVariations:[],defaults:null,weights:[baseline],planning:[]};
test('B4 fixed baseline allows administrator weight edits but no identity changes',()=>{
 const input=structuredClone(baseline);input.values.passengerMethod='STANDARD';input.values.passenger='15';assert.equal(validateBaggage('weights',input,snapshot).values.passenger,'15');
 input.values.classCode='F';assert.throws(()=>validateBaggage('weights',input,snapshot),/identity/);
});
test('B4 rejects missing, negative, fractional and overflowing standard weights',()=>{
 for(const value of ['', '-1','1.2','2147483648','NaN']){const input=structuredClone(baseline);input.values.passengerMethod='STANDARD';input.values.passenger=value;assert.throws(()=>validateBaggage('weights',input,snapshot));}
});
test('B4 rejects duplicate scope and unknown class or variation',()=>{
 const input=newBaggageRecord('weights');input.values.passenger='15';assert.throws(()=>validateBaggage('weights',input,snapshot),/already exists/);
 input.values.classCode='Q';assert.throws(()=>validateBaggage('weights',input,snapshot),/B1/);
 input.values.classCode='F';input.values.variation='BAD';assert.throws(()=>validateBaggage('weights',input,snapshot),/B3/);
});
test('B4 planning accepts precise decimal averages and preserves unknown volume',()=>{
 const input=newBaggageRecord('planning');Object.assign(input.values,{bags:'1.25',weight:'18.75',volume:''});assert.equal(validateBaggage('planning',input,snapshot).values.volume,'');
 input.values.volume='0.045';assert.equal(validateBaggage('planning',input,snapshot).values.volume,'0.045');
 for(const value of ['-1','1.12345','Infinity','100000000']){input.values.volume=value;assert.throws(()=>validateBaggage('planning',input,snapshot));}
});
test('B4 actual mode retains inactive standard values; unset restricted to baseline',()=>{
 const input=structuredClone(baseline);input.values.passengerMethod='ACTUAL';input.values.passenger='15';assert.equal(validateBaggage('weights',input,snapshot).values.passenger,'15');
 input.id=null;input.baseline=false;input.values.classCode='F';input.values.passengerMethod='UNSET';assert.throws(()=>validateBaggage('weights',input,snapshot));
});
test('B4 permission and stale revision checks prevent repository writes',async()=>{
 let writes=0;let current=snapshot;
 const service=createBaggageWeights({currentUser:async()=>({id:'user'})} as AuthService,{findAuthorised:async()=>({iata:'ZZ'})} as unknown as CarrierRepository,{get:async()=>current,save:async()=>{writes++;},saveOperationMode:async()=>{writes++;},saveApplicability:async()=>{writes++;},saveVariationStandard:async()=>{writes++;}});
 current={...snapshot,canEdit:false};await assert.rejects(()=>service.save('ZZ','v1','weights',baseline),BaggageDenied);
 current=snapshot;await assert.rejects(()=>service.save('ZZ','old','weights',baseline),BaggageConflict);
 await assert.rejects(()=>service.save('ZZ','v1','weights',baseline,true),/cannot be removed/);
 assert.equal(writes,0);
});
