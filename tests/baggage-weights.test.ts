import test from 'node:test';
import assert from 'node:assert/strict';
import {validateBaggage,newBaggageRecord,BaggageConflict,BaggageDenied,type BaggageRecord,type BaggageSnapshot} from '../src/domain/baggage-weights';
import {createBaggageWeights} from '../src/application/baggage-weights';
import type {AuthService} from '../src/ports/auth-service';
import type {CarrierRepository} from '../src/ports/carrier-repository';
const baseline:BaggageRecord={id:'baseline',baseline:true,values:{...newBaggageRecord('weights').values,passengerMethod:'UNSET'}};
const snapshot:BaggageSnapshot={canView:true,canEdit:true,revision:'v1',unit:'KG',volumeUnit:'m3',operationMode:'STANDARD',defaultPerPiece:true,checkedBaggageDensity:'176',classes:[{code:'F',description:'First'}],variations:[{code:'DOM',description:'Domestic'}],variationMethods:{},defaults:null,weights:[baseline],planning:[]};
test('B4 preserves the legacy fixed baseline but does not allow identity changes',()=>{
 const input=structuredClone(baseline);assert.equal(validateBaggage('weights',input,snapshot).baseline,true);
 input.values.classCode='F';assert.throws(()=>validateBaggage('weights',input,snapshot),/identity/);
});
test('B4 separate Standard tables require a whole-number Weight per Bag',()=>{
 for(const value of ['', '-1','1.2','2147483648','NaN']){const input=newBaggageRecord('weights');input.values.variation='DOM';input.values.piece=value;assert.throws(()=>validateBaggage('weights',input,snapshot));}
 const input=newBaggageRecord('weights');Object.assign(input.values,{variation:'DOM',piece:'15',passengerMethod:'STANDARD',passenger:'99'});const saved=validateBaggage('weights',input,snapshot);assert.equal(saved.values.piece,'15');assert.equal(saved.values.passengerMethod,'UNSET');assert.equal(saved.values.passenger,'');
});
test('B4 rejects duplicate scope and unknown class or variation',()=>{
 const input=newBaggageRecord('weights');input.values.piece='15';assert.throws(()=>validateBaggage('weights',input,snapshot),/Choose a Class/);
 input.values.classCode='Q';assert.throws(()=>validateBaggage('weights',input,snapshot),/B1/);
 input.values.classCode='F';input.values.variation='BAD';assert.throws(()=>validateBaggage('weights',input,snapshot),/B3/);
});
test('B4 planning accepts precise decimal averages and preserves unknown volume',()=>{
 const input=newBaggageRecord('planning');Object.assign(input.values,{bags:'1.25',weight:'18.75',volume:''});assert.equal(validateBaggage('planning',input,snapshot).values.volume,'');
 input.values.volume='0.045';assert.equal(validateBaggage('planning',input,snapshot).values.volume,'0.045');
 for(const value of ['-1','1.12345','Infinity','100000000']){input.values.volume=value;assert.throws(()=>validateBaggage('planning',input,snapshot));}
});
test('B4 permission and stale revision checks prevent repository writes',async()=>{
 let writes=0;let current=snapshot;
 const service=createBaggageWeights({currentUser:async()=>({id:'user'})} as AuthService,{findAuthorised:async()=>({iata:'ZZ'})} as unknown as CarrierRepository,{get:async()=>current,save:async()=>{writes++;},saveOperationMode:async()=>{writes++;},saveApplicability:async()=>{writes++;},saveVariationMethod:async()=>{writes++;}});
 current={...snapshot,canEdit:false};await assert.rejects(()=>service.save('ZZ','v1','weights',baseline),BaggageDenied);
 current=snapshot;await assert.rejects(()=>service.save('ZZ','old','weights',baseline),BaggageConflict);
 await assert.rejects(()=>service.save('ZZ','v1','weights',baseline,true),/cannot be removed/);
 assert.equal(writes,0);
});
