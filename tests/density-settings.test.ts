import test from 'node:test';
import assert from 'node:assert/strict';
import {validateDensities,DensityInvalid,DensityDenied,DensityConflict,type DensitySnapshot} from '../src/domain/density-settings';
import {createDensitySettings} from '../src/application/density-settings';
import type {AuthService} from '../src/ports/auth-service';
import type {CarrierRepository} from '../src/ports/carrier-repository';
const values={baggage:'176',cargo:'212',mail:'212'};
test('density validation requires all three values and supports positive decimals',()=>{
 assert.deepEqual(validateDensities({...values,baggage:' 176.25 '}),{baggage:'176.25',cargo:'212',mail:'212'});
 assert.throws(()=>validateDensities({...values,mail:''}),DensityInvalid);
});
test('density rejects zero, negatives, non-finite and invalid types',()=>{for(const bad of ['0','-1','NaN','Infinity','1e999','abc',null,{},1])assert.throws(()=>validateDensities({...values,baggage:bad}));});
test('density preserves precise conversion values',()=>{assert.equal(validateDensities({...values,baggage:'10.987654321'}).baggage,'10.987654321');});
test('density application rejects unauthorised and stale saves',async()=>{
 let writes=0;let snapshot:DensitySnapshot={canView:true,canEdit:false,exists:true,weightUnit:'KG',volumeUnit:'m3',revision:'now',values};
 const app=createDensitySettings({currentUser:async()=>({id:'user'})} as AuthService,{findAuthorised:async()=>({iata:'ZZ'})} as unknown as CarrierRepository,{get:async()=>snapshot,save:async()=>{writes++;return snapshot;}});
 await assert.rejects(()=>app.save('ZZ','now',values),DensityDenied);snapshot={...snapshot,canEdit:true};await assert.rejects(()=>app.save('ZZ','old',values),DensityConflict);assert.equal(writes,0);await app.save('ZZ','now',values);assert.equal(writes,1);
});
